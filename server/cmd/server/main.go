// Command server is the Beizx reader backend.
//
// It replaces the previous JVM/Kotlin proxy service with a single Go binary
// that offers two things:
//
//  1. a validated HTTP proxy pool (scraped from public lists and re-checked
//     locally) so clients can reach sources that are slow or blocked;
//  2. a translation gateway that signs Youdao v3 requests server-side, so the
//     App ID / secret never has to live on a phone.
//
// Configuration is entirely environment based, which keeps the binary usable
// from Docker, systemd or a plain `go run`.
package main

import (
	"context"
	"errors"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"strconv"
	"syscall"
	"time"

	"github.com/beizx/reader-server/internal/gateway"
	"github.com/beizx/reader-server/internal/httpapi"
	"github.com/beizx/reader-server/internal/proxypool"
)

// version is reported by /healthz.
const version = "1.1.0"

func main() {
	logger := slog.New(slog.NewTextHandler(os.Stdout, &slog.HandlerOptions{
		Level: logLevel(os.Getenv("LOG_LEVEL")),
	}))
	slog.SetDefault(logger)

	cfg := loadConfig()
	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()

	var pool *proxypool.Pool
	if cfg.ProxyEnabled {
		pool = proxypool.New(proxypool.Config{
			Target:       cfg.ProxyTarget,
			CheckURL:     cfg.ProxyCheckURL,
			CheckTimeout: cfg.ProxyCheckTimeout,
			Sources: []proxypool.Source{
				proxypool.NewScdnSource(os.Getenv("PROXY_SCDN_ENDPOINT")),
				proxypool.NewIP89Source(os.Getenv("PROXY_IP89_ENDPOINT")),
			},
		}, nil)

		go runRefillLoop(ctx, pool, cfg.ProxyRefreshInterval)
	}

	var translator gateway.Translator = gateway.NewYoudao(cfg.YoudaoAppKey, cfg.YoudaoSecret)
	if cfg.YoudaoAppKey == "" || cfg.YoudaoSecret == "" {
		// The route stays registered so clients get a clear 503 instead of a
		// confusing 404, and it starts working as soon as env vars are set.
		logger.Warn("youdao credentials missing: /v1/translate will return 503")
	}

	// Repeated chunks are the norm (re-reading a chapter, two devices on one
	// gateway), so successful translations are cached in-process.
	cache := gateway.NewCachedTranslator(translator, gateway.CacheConfig{
		Entries: cfg.CacheEntries,
		TTL:     cfg.CacheTTL,
	})
	if cache.Enabled() {
		logger.Info("translate cache enabled", "entries", cfg.CacheEntries, "ttl", cfg.CacheTTL)
	}

	handler := httpapi.NewRouter(httpapi.Options{
		Pool:      poolStore(pool),
		Translate: translateHandler(cache),
		Cache:     cacheStore(cache),
		Token:     cfg.GatewayToken,
		Version:   version,
	})

	server := &http.Server{
		Addr:              cfg.Addr,
		Handler:           handler,
		ReadHeaderTimeout: 10 * time.Second,
		ReadTimeout:       30 * time.Second,
		WriteTimeout:      90 * time.Second,
		IdleTimeout:       120 * time.Second,
	}

	go func() {
		logger.Info("listening", "addr", cfg.Addr, "proxyPool", cfg.ProxyEnabled)
		if err := server.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			logger.Error("server failed", "err", err)
			stop()
		}
	}()

	<-ctx.Done()
	logger.Info("shutting down")

	shutdownCtx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	if err := server.Shutdown(shutdownCtx); err != nil {
		logger.Error("graceful shutdown failed", "err", err)
	}
}

func runRefillLoop(ctx context.Context, pool *proxypool.Pool, interval time.Duration) {
	refill := func() {
		refillCtx, cancel := context.WithTimeout(ctx, 3*time.Minute)
		defer cancel()
		stats, err := pool.Refill(refillCtx)
		if err != nil {
			slog.Warn("proxy refill failed", "err", err, "size", pool.Size())
			return
		}
		slog.Info(
			"proxy refill",
			"fetched", stats.Fetched,
			"checked", stats.Checked,
			"added", stats.Added,
			"size", pool.Size(),
		)
	}

	refill()
	ticker := time.NewTicker(interval)
	defer ticker.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			refill()
		}
	}
}

func poolStore(pool *proxypool.Pool) httpapi.ProxyStore {
	if pool == nil {
		return nil
	}
	return pool
}

func cacheStore(cache *gateway.CachedTranslator) httpapi.TranslateCache {
	if cache == nil || !cache.Enabled() {
		return nil
	}
	return cache
}

func translateHandler(translator gateway.Translator) http.Handler {
	if translator == nil {
		return nil
	}
	return gateway.NewTranslateHandler(translator, gateway.MaxTextRunes)
}

type config struct {
	Addr                 string
	GatewayToken         string
	YoudaoAppKey         string
	YoudaoSecret         string
	CacheEntries         int
	CacheTTL             time.Duration
	ProxyEnabled         bool
	ProxyTarget          int
	ProxyCheckURL        string
	ProxyCheckTimeout    time.Duration
	ProxyRefreshInterval time.Duration
}

func loadConfig() config {
	return config{
		Addr:                 ":" + envString("PORT", "8080"),
		GatewayToken:         os.Getenv("GATEWAY_TOKEN"),
		YoudaoAppKey:         os.Getenv("YOUDAO_APP_KEY"),
		YoudaoSecret:         os.Getenv("YOUDAO_APP_SECRET"),
		CacheEntries:         envInt("GATEWAY_CACHE_ENTRIES", 512),
		CacheTTL:             time.Duration(envInt("GATEWAY_CACHE_TTL_SECONDS", 3600)) * time.Second,
		ProxyEnabled:         envBool("PROXY_ENABLED", true),
		ProxyTarget:          envInt("PROXY_TARGET", 20),
		ProxyCheckURL:        envString("PROXY_CHECK_URL", proxypool.DefaultCheckURL),
		ProxyCheckTimeout:    time.Duration(envInt("PROXY_CHECK_TIMEOUT_MS", 4000)) * time.Millisecond,
		ProxyRefreshInterval: time.Duration(envInt("PROXY_REFRESH_SECONDS", 300)) * time.Second,
	}
}

func envString(key, fallback string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return fallback
}

func envInt(key string, fallback int) int {
	raw := os.Getenv(key)
	if raw == "" {
		return fallback
	}
	value, err := strconv.Atoi(raw)
	if err != nil {
		return fallback
	}
	return value
}

func envBool(key string, fallback bool) bool {
	raw := os.Getenv(key)
	if raw == "" {
		return fallback
	}
	value, err := strconv.ParseBool(raw)
	if err != nil {
		return fallback
	}
	return value
}

func logLevel(raw string) slog.Level {
	switch raw {
	case "debug":
		return slog.LevelDebug
	case "warn":
		return slog.LevelWarn
	case "error":
		return slog.LevelError
	default:
		return slog.LevelInfo
	}
}

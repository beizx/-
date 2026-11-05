package httpapi

import (
	"context"
	"crypto/subtle"
	"encoding/json"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/beizx/reader-server/internal/gateway"
	"github.com/beizx/reader-server/internal/proxypool"
)

// ProxyStore is the slice of the pool the API needs.
type ProxyStore interface {
	Size() int
	Stats() proxypool.Stats
	Snapshot(limit int) []proxypool.Proxy
	Take() (proxypool.Proxy, bool)
	Refill(ctx context.Context) (proxypool.Stats, error)
}

// TranslateCache reports the translate cache counters for /healthz.
type TranslateCache interface {
	Stats() gateway.CacheStats
}

// Options configures the router.
type Options struct {
	// Pool backs the /v1/proxies endpoints. Optional.
	Pool ProxyStore
	// Translate handles POST /v1/translate. Optional.
	Translate http.Handler
	// Cache, when set, is reported by /healthz.
	Cache TranslateCache
	// Token, when set, must be presented as `Authorization: Bearer <token>`
	// or `X-API-Token: <token>`.
	Token string
	// Version is reported by /healthz.
	Version string
}

// NewRouter wires every endpoint.
func NewRouter(opts Options) http.Handler {
	mux := http.NewServeMux()

	mux.HandleFunc("GET /healthz", func(w http.ResponseWriter, r *http.Request) {
		payload := map[string]any{
			"status": "ok",
			"time":   time.Now().UTC().Format(time.RFC3339),
		}
		if opts.Version != "" {
			payload["version"] = opts.Version
		}
		if opts.Pool != nil {
			payload["proxyPoolSize"] = opts.Pool.Size()
		}
		if opts.Cache != nil {
			payload["translateCache"] = opts.Cache.Stats()
		}
		writeJSON(w, http.StatusOK, payload)
	})

	if opts.Translate != nil {
		mux.Handle("POST /v1/translate", opts.Translate)
	}

	if opts.Pool != nil {
		mux.HandleFunc("GET /v1/proxies", func(w http.ResponseWriter, r *http.Request) {
			limit := parseInt(r.URL.Query().Get("limit"), 20)
			proxies := opts.Pool.Snapshot(limit)
			items := make([]string, 0, len(proxies))
			for _, proxy := range proxies {
				items = append(items, proxy.String())
			}
			writeJSON(w, http.StatusOK, map[string]any{
				"size":    opts.Pool.Size(),
				"proxies": items,
				"stats":   opts.Pool.Stats(),
			})
		})

		mux.HandleFunc("POST /v1/proxies/take", func(w http.ResponseWriter, r *http.Request) {
			proxy, ok := opts.Pool.Take()
			if !ok {
				writeJSON(w, http.StatusServiceUnavailable, map[string]any{
					"error": "proxy pool is empty",
				})
				return
			}
			writeJSON(w, http.StatusOK, map[string]any{"proxy": proxy.String()})
		})

		mux.HandleFunc("POST /v1/proxies/refresh", func(w http.ResponseWriter, r *http.Request) {
			stats, err := opts.Pool.Refill(r.Context())
			status := http.StatusOK
			payload := map[string]any{
				"size":  opts.Pool.Size(),
				"stats": stats,
			}
			if err != nil {
				status = http.StatusBadGateway
				payload["error"] = err.Error()
			}
			writeJSON(w, status, payload)
		})
	}

	return withRecovery(withCORS(withAuth(opts.Token, mux)))
}

func withAuth(token string, next http.Handler) http.Handler {
	if strings.TrimSpace(token) == "" {
		return next
	}
	expected := []byte(token)
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/healthz" {
			next.ServeHTTP(w, r)
			return
		}
		provided := strings.TrimSpace(strings.TrimPrefix(r.Header.Get("Authorization"), "Bearer "))
		if provided == "" {
			provided = strings.TrimSpace(r.Header.Get("X-API-Token"))
		}
		if subtle.ConstantTimeCompare([]byte(provided), expected) != 1 {
			writeJSON(w, http.StatusUnauthorized, map[string]any{"error": "unauthorized"})
			return
		}
		next.ServeHTTP(w, r)
	})
}

func withCORS(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Access-Control-Allow-Origin", "*")
		w.Header().Set("Access-Control-Allow-Headers", "Content-Type, Authorization, X-API-Token")
		w.Header().Set("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
		if r.Method == http.MethodOptions {
			w.WriteHeader(http.StatusNoContent)
			return
		}
		next.ServeHTTP(w, r)
	})
}

func withRecovery(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		defer func() {
			if recovered := recover(); recovered != nil {
				writeJSON(w, http.StatusInternalServerError, map[string]any{
					"error": "internal error",
				})
			}
		}()
		next.ServeHTTP(w, r)
	})
}

func parseInt(raw string, fallback int) int {
	if raw == "" {
		return fallback
	}
	value, err := strconv.Atoi(raw)
	if err != nil || value <= 0 {
		return fallback
	}
	return value
}

func writeJSON(w http.ResponseWriter, status int, payload any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(payload)
}

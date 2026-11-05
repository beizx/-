package httpapi

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/beizx/reader-server/internal/gateway"
	"github.com/beizx/reader-server/internal/proxypool"
)

type fakePool struct {
	queue []proxypool.Proxy
	stats proxypool.Stats
	err   error
}

func (f *fakePool) Size() int { return len(f.queue) }

func (f *fakePool) Stats() proxypool.Stats { return f.stats }

func (f *fakePool) Snapshot(limit int) []proxypool.Proxy {
	if limit <= 0 || limit > len(f.queue) {
		limit = len(f.queue)
	}
	return append([]proxypool.Proxy(nil), f.queue[:limit]...)
}

func (f *fakePool) Take() (proxypool.Proxy, bool) {
	if len(f.queue) == 0 {
		return proxypool.Proxy{}, false
	}
	proxy := f.queue[0]
	f.queue = f.queue[1:]
	return proxy, true
}

func (f *fakePool) Refill(context.Context) (proxypool.Stats, error) {
	f.stats = proxypool.Stats{Fetched: 2, Added: 1}
	return f.stats, f.err
}

func doRequest(t *testing.T, handler http.Handler, method, path, body string) *httptest.ResponseRecorder {
	t.Helper()
	var reader *strings.Reader
	if body == "" {
		reader = strings.NewReader("")
	} else {
		reader = strings.NewReader(body)
	}
	request := httptest.NewRequest(method, path, reader)
	recorder := httptest.NewRecorder()
	handler.ServeHTTP(recorder, request)
	return recorder
}

func TestHealthzIsPublic(t *testing.T) {
	handler := NewRouter(Options{
		Pool:    &fakePool{queue: []proxypool.Proxy{{Host: "1.2.3.4", Port: 8080}}},
		Token:   "secret-token",
		Version: "1.0.0",
	})

	recorder := doRequest(t, handler, http.MethodGet, "/healthz", "")
	if recorder.Code != http.StatusOK {
		t.Fatalf("unexpected status %d", recorder.Code)
	}
	var payload map[string]any
	if err := json.Unmarshal(recorder.Body.Bytes(), &payload); err != nil {
		t.Fatalf("decode: %v", err)
	}
	if payload["status"] != "ok" {
		t.Fatalf("unexpected payload %+v", payload)
	}
	if payload["proxyPoolSize"] != float64(1) {
		t.Fatalf("unexpected pool size %+v", payload["proxyPoolSize"])
	}
}

func TestHealthzReportsTranslateCache(t *testing.T) {
	upstream := &stubCacheTranslator{result: gateway.Result{Text: "译文"}}
	cache := gateway.NewCachedTranslator(upstream, gateway.CacheConfig{
		Entries: 8,
		TTL:     time.Minute,
	})
	if _, err := cache.Translate(context.Background(), "hello", "en", "zh-CHS"); err != nil {
		t.Fatalf("translate: %v", err)
	}
	if _, err := cache.Translate(context.Background(), "hello", "en", "zh-CHS"); err != nil {
		t.Fatalf("translate: %v", err)
	}

	handler := NewRouter(Options{Cache: cache})
	recorder := doRequest(t, handler, http.MethodGet, "/healthz", "")
	if recorder.Code != http.StatusOK {
		t.Fatalf("unexpected status %d", recorder.Code)
	}
	var payload struct {
		TranslateCache gateway.CacheStats `json:"translateCache"`
	}
	if err := json.Unmarshal(recorder.Body.Bytes(), &payload); err != nil {
		t.Fatalf("decode: %v", err)
	}
	if payload.TranslateCache.Entries != 1 || payload.TranslateCache.Hits != 1 {
		t.Fatalf("unexpected cache stats %+v", payload.TranslateCache)
	}
}

type stubCacheTranslator struct {
	result gateway.Result
}

func (s *stubCacheTranslator) Translate(context.Context, string, string, string) (gateway.Result, error) {
	return s.result, nil
}

func TestProtectedEndpointsRequireToken(t *testing.T) {
	handler := NewRouter(Options{Pool: &fakePool{}, Token: "secret-token"})

	if recorder := doRequest(t, handler, http.MethodGet, "/v1/proxies", ""); recorder.Code != http.StatusUnauthorized {
		t.Fatalf("expected 401 without a token, got %d", recorder.Code)
	}

	request := httptest.NewRequest(http.MethodGet, "/v1/proxies", nil)
	request.Header.Set("Authorization", "Bearer secret-token")
	recorder := httptest.NewRecorder()
	handler.ServeHTTP(recorder, request)
	if recorder.Code != http.StatusOK {
		t.Fatalf("expected 200 with a token, got %d", recorder.Code)
	}
}

func TestProxiesEndpoints(t *testing.T) {
	pool := &fakePool{queue: []proxypool.Proxy{{Host: "1.2.3.4", Port: 8080}}}
	handler := NewRouter(Options{Pool: pool})

	recorder := doRequest(t, handler, http.MethodGet, "/v1/proxies?limit=5", "")
	if recorder.Code != http.StatusOK {
		t.Fatalf("unexpected status %d", recorder.Code)
	}
	var listed struct {
		Size    int      `json:"size"`
		Proxies []string `json:"proxies"`
	}
	if err := json.Unmarshal(recorder.Body.Bytes(), &listed); err != nil {
		t.Fatalf("decode: %v", err)
	}
	if listed.Size != 1 || len(listed.Proxies) != 1 {
		t.Fatalf("unexpected listing %+v", listed)
	}
	if listed.Proxies[0] != "http://1.2.3.4:8080" {
		t.Fatalf("unexpected proxy string %q", listed.Proxies[0])
	}

	recorder = doRequest(t, handler, http.MethodPost, "/v1/proxies/take", "")
	if recorder.Code != http.StatusOK {
		t.Fatalf("unexpected status %d", recorder.Code)
	}
	if pool.Size() != 0 {
		t.Fatal("take should drain the queue")
	}

	recorder = doRequest(t, handler, http.MethodPost, "/v1/proxies/take", "")
	if recorder.Code != http.StatusServiceUnavailable {
		t.Fatalf("expected 503 on an empty pool, got %d", recorder.Code)
	}
}

func TestProxyRefreshReportsStats(t *testing.T) {
	handler := NewRouter(Options{Pool: &fakePool{}})

	recorder := doRequest(t, handler, http.MethodPost, "/v1/proxies/refresh", "")
	if recorder.Code != http.StatusOK {
		t.Fatalf("unexpected status %d", recorder.Code)
	}
	var payload struct {
		Size  int             `json:"size"`
		Stats proxypool.Stats `json:"stats"`
	}
	if err := json.Unmarshal(recorder.Body.Bytes(), &payload); err != nil {
		t.Fatalf("decode: %v", err)
	}
	if payload.Stats.Fetched != 2 || payload.Stats.Added != 1 {
		t.Fatalf("unexpected stats %+v", payload.Stats)
	}
}

func TestRouterOmitsUnconfiguredEndpoints(t *testing.T) {
	handler := NewRouter(Options{})

	if recorder := doRequest(t, handler, http.MethodPost, "/v1/translate", "{}"); recorder.Code != http.StatusNotFound {
		t.Fatalf("expected 404 without a translator, got %d", recorder.Code)
	}
	if recorder := doRequest(t, handler, http.MethodGet, "/v1/proxies", ""); recorder.Code != http.StatusNotFound {
		t.Fatalf("expected 404 without a pool, got %d", recorder.Code)
	}
}

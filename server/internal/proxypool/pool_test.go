package proxypool

import (
	"context"
	"errors"
	"net/http"
	"net/http/httptest"
	"net/url"
	"strconv"
	"sync/atomic"
	"testing"
	"time"
)

type fakeSource struct {
	name     string
	proxies  []Proxy
	err      error
	requests atomic.Int32
}

func (s *fakeSource) Name() string { return s.name }

func (s *fakeSource) Fetch(context.Context, *http.Client) ([]Proxy, error) {
	s.requests.Add(1)
	if s.err != nil {
		return nil, s.err
	}
	return s.proxies, nil
}

// fakeProxy answers proxied GETs with 200 so validation succeeds without a
// real upstream proxy.
func fakeProxy(t *testing.T) *httptest.Server {
	t.Helper()
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
	}))
	t.Cleanup(server.Close)
	return server
}

func hostPortOf(t *testing.T, rawURL string) Proxy {
	t.Helper()
	parsed, err := url.Parse(rawURL)
	if err != nil {
		t.Fatalf("parse %q: %v", rawURL, err)
	}
	port, err := strconv.Atoi(parsed.Port())
	if err != nil {
		t.Fatalf("parse port of %q: %v", rawURL, err)
	}
	return Proxy{Host: parsed.Hostname(), Port: port}
}

func TestRefillAddsValidatedProxies(t *testing.T) {
	server := fakeProxy(t)
	proxy := hostPortOf(t, server.URL)
	source := &fakeSource{name: "fake", proxies: []Proxy{proxy}}

	pool := New(Config{
		Target:       3,
		CheckURL:     "http://example.test/check",
		CheckTimeout: 2 * time.Second,
		AllowPrivate: true,
		Sources:      []Source{source},
	}, nil)

	stats, err := pool.Refill(context.Background())
	if err != nil {
		t.Fatalf("refill failed: %v", err)
	}
	if stats.Added != 1 || stats.Checked != 1 {
		t.Fatalf("unexpected stats: %+v", stats)
	}
	if pool.Size() != 1 {
		t.Fatalf("expected 1 queued proxy, got %d", pool.Size())
	}

	taken, ok := pool.Take()
	if !ok || taken != proxy {
		t.Fatalf("take returned %+v, %v", taken, ok)
	}
	if _, ok := pool.Take(); ok {
		t.Fatal("expected the queue to be empty")
	}
}

func TestRefillRejectsUnreachableProxies(t *testing.T) {
	server := fakeProxy(t)
	deadURL := server.URL
	server.Close() // nothing listens there any more

	pool := New(Config{
		Target:       2,
		CheckURL:     "http://example.test/check",
		CheckTimeout: 300 * time.Millisecond,
		AllowPrivate: true,
		Sources: []Source{&fakeSource{
			name:    "fake",
			proxies: []Proxy{hostPortOf(t, deadURL)},
		}},
	}, nil)

	stats, err := pool.Refill(context.Background())
	if err != nil {
		t.Fatalf("refill should not fail when candidates die: %v", err)
	}
	if stats.Rejected != 1 || stats.Added != 0 {
		t.Fatalf("unexpected stats: %+v", stats)
	}
	if pool.Size() != 0 {
		t.Fatalf("expected an empty pool, got %d", pool.Size())
	}
}

func TestRefillReportsSourceFailures(t *testing.T) {
	pool := New(Config{
		Target:       1,
		CheckURL:     "http://example.test/check",
		AllowPrivate: true,
		Sources: []Source{&fakeSource{
			name: "broken",
			err:  errors.New("upstream down"),
		}},
	}, nil)

	if _, err := pool.Refill(context.Background()); err == nil {
		t.Fatal("expected the source error to surface when the pool stays empty")
	}
}

func TestRefillStopsAtTargetAndDeduplicates(t *testing.T) {
	server := fakeProxy(t)
	proxy := hostPortOf(t, server.URL)
	source := &fakeSource{
		name:    "fake",
		proxies: []Proxy{proxy, proxy, proxy},
	}
	pool := New(Config{
		Target:       1,
		CheckURL:     "http://example.test/check",
		CheckTimeout: 2 * time.Second,
		AllowPrivate: true,
		Sources:      []Source{source},
	}, nil)

	if _, err := pool.Refill(context.Background()); err != nil {
		t.Fatalf("refill failed: %v", err)
	}
	if pool.Size() != 1 {
		t.Fatalf("expected the pool to stop at the target, got %d", pool.Size())
	}

	// A second refill must not duplicate the queued proxy.
	if _, err := pool.Refill(context.Background()); err != nil {
		t.Fatalf("second refill failed: %v", err)
	}
	if pool.Size() != 1 {
		t.Fatalf("expected no duplicates, got %d", pool.Size())
	}
}

func TestSnapshotCopiesQueue(t *testing.T) {
	server := fakeProxy(t)
	proxy := hostPortOf(t, server.URL)
	pool := New(Config{
		Target:       5,
		CheckURL:     "http://example.test/check",
		CheckTimeout: 2 * time.Second,
		AllowPrivate: true,
		Sources:      []Source{&fakeSource{name: "fake", proxies: []Proxy{proxy}}},
	}, nil)
	if _, err := pool.Refill(context.Background()); err != nil {
		t.Fatalf("refill failed: %v", err)
	}

	snapshot := pool.Snapshot(10)
	if len(snapshot) != 1 {
		t.Fatalf("expected 1 proxy in the snapshot, got %d", len(snapshot))
	}
	snapshot[0] = Proxy{Host: "9.9.9.9", Port: 1}
	if pool.Snapshot(1)[0] != proxy {
		t.Fatal("snapshot must not expose the internal slice")
	}
}

package gateway

import (
	"context"
	"errors"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"testing"
	"time"
)

// countingTranslator records every upstream call and can block on demand so the
// single-flight behaviour is observable.
type countingTranslator struct {
	mu      sync.Mutex
	calls   int
	texts   []string
	gate    chan struct{}
	result  Result
	err     error
	started chan struct{}
}

func (c *countingTranslator) Translate(
	ctx context.Context,
	text, from, to string,
) (Result, error) {
	c.mu.Lock()
	c.calls++
	c.texts = append(c.texts, text)
	gate := c.gate
	started := c.started
	c.mu.Unlock()

	if started != nil {
		select {
		case started <- struct{}{}:
		default:
		}
	}
	if gate != nil {
		select {
		case <-gate:
		case <-ctx.Done():
			return Result{}, ctx.Err()
		}
	}
	if c.err != nil {
		return Result{}, c.err
	}
	return c.result, nil
}

func (c *countingTranslator) callCount() int {
	c.mu.Lock()
	defer c.mu.Unlock()
	return c.calls
}

func newTestCache(next Translator, entries int, ttl time.Duration, now func() time.Time) *CachedTranslator {
	return NewCachedTranslator(next, CacheConfig{Entries: entries, TTL: ttl, Now: now})
}

func TestCacheServesRepeatedChunksFromMemory(t *testing.T) {
	upstream := &countingTranslator{result: Result{Text: "译文"}}
	cache := newTestCache(upstream, 16, time.Minute, nil)
	ctx := context.Background()

	first, err := cache.Translate(ctx, "hello", "en", "zh-CHS")
	if err != nil {
		t.Fatalf("first translate: %v", err)
	}
	if first.Cached {
		t.Fatal("first answer must not be flagged as cached")
	}

	second, err := cache.Translate(ctx, " hello ", "en", "zh-CHS")
	if err != nil {
		t.Fatalf("second translate: %v", err)
	}
	if !second.Cached {
		t.Fatal("second answer should come from the cache")
	}
	if second.Text != "译文" {
		t.Fatalf("unexpected text %q", second.Text)
	}
	if upstream.callCount() != 1 {
		t.Fatalf("expected 1 upstream call, got %d", upstream.callCount())
	}

	stats := cache.Stats()
	if stats.Hits != 1 || stats.Misses != 1 || stats.Entries != 1 {
		t.Fatalf("unexpected stats %+v", stats)
	}
}

func TestCacheKeyIncludesLanguages(t *testing.T) {
	upstream := &countingTranslator{result: Result{Text: "译文"}}
	cache := newTestCache(upstream, 16, time.Minute, nil)
	ctx := context.Background()

	if _, err := cache.Translate(ctx, "hello", "en", "zh-CHS"); err != nil {
		t.Fatalf("translate: %v", err)
	}
	if _, err := cache.Translate(ctx, "hello", "en", "ja"); err != nil {
		t.Fatalf("translate: %v", err)
	}
	if upstream.callCount() != 2 {
		t.Fatalf("different targets must not share an entry, got %d calls", upstream.callCount())
	}
}

func TestCacheExpiresAfterTTL(t *testing.T) {
	upstream := &countingTranslator{result: Result{Text: "译文"}}
	current := time.Unix(1_700_000_000, 0)
	cache := newTestCache(upstream, 16, 30*time.Second, func() time.Time { return current })
	ctx := context.Background()

	if _, err := cache.Translate(ctx, "hello", "en", "zh-CHS"); err != nil {
		t.Fatalf("translate: %v", err)
	}
	current = current.Add(31 * time.Second)
	result, err := cache.Translate(ctx, "hello", "en", "zh-CHS")
	if err != nil {
		t.Fatalf("translate: %v", err)
	}
	if result.Cached {
		t.Fatal("entry must expire after the TTL")
	}
	if upstream.callCount() != 2 {
		t.Fatalf("expected a refresh call, got %d", upstream.callCount())
	}
	stats := cache.Stats()
	if stats.Expired != 1 {
		t.Fatalf("expected 1 expired entry, got %+v", stats)
	}
}

func TestCacheEvictsLeastRecentlyUsed(t *testing.T) {
	upstream := &countingTranslator{result: Result{Text: "译文"}}
	cache := newTestCache(upstream, 2, time.Minute, nil)
	ctx := context.Background()

	for _, text := range []string{"one", "two"} {
		if _, err := cache.Translate(ctx, text, "en", "zh-CHS"); err != nil {
			t.Fatalf("translate %s: %v", text, err)
		}
	}
	// Touch "one" so "two" becomes the least recently used entry.
	if _, err := cache.Translate(ctx, "one", "en", "zh-CHS"); err != nil {
		t.Fatalf("translate one: %v", err)
	}
	if _, err := cache.Translate(ctx, "three", "en", "zh-CHS"); err != nil {
		t.Fatalf("translate three: %v", err)
	}

	stats := cache.Stats()
	if stats.Entries != 2 || stats.Evictions != 1 {
		t.Fatalf("unexpected stats %+v", stats)
	}
	if _, err := cache.Translate(ctx, "one", "en", "zh-CHS"); err != nil {
		t.Fatalf("translate one: %v", err)
	}
	if upstream.callCount() != 3 {
		t.Fatalf("recently used entry must survive, got %d calls", upstream.callCount())
	}
	if _, err := cache.Translate(ctx, "two", "en", "zh-CHS"); err != nil {
		t.Fatalf("translate two: %v", err)
	}
	if upstream.callCount() != 4 {
		t.Fatalf("evicted entry must be fetched again, got %d calls", upstream.callCount())
	}
}

func TestCacheSingleFlightsConcurrentRequests(t *testing.T) {
	upstream := &countingTranslator{
		result:  Result{Text: "译文"},
		gate:    make(chan struct{}),
		started: make(chan struct{}, 8),
	}
	cache := newTestCache(upstream, 16, time.Minute, nil)
	ctx := context.Background()

	const workers = 6
	var wg sync.WaitGroup
	results := make([]Result, workers)
	errs := make([]error, workers)
	for i := 0; i < workers; i++ {
		wg.Add(1)
		go func(index int) {
			defer wg.Done()
			results[index], errs[index] = cache.Translate(ctx, "hello", "en", "zh-CHS")
		}(i)
	}

	<-upstream.started
	// Give the other goroutines time to join the in-flight request.
	time.Sleep(50 * time.Millisecond)
	close(upstream.gate)
	wg.Wait()

	for i := 0; i < workers; i++ {
		if errs[i] != nil {
			t.Fatalf("worker %d failed: %v", i, errs[i])
		}
		if results[i].Text != "译文" {
			t.Fatalf("worker %d got %q", i, results[i].Text)
		}
	}
	if upstream.callCount() != 1 {
		t.Fatalf("expected a single upstream call, got %d", upstream.callCount())
	}
}

func TestCacheDoesNotStoreFailures(t *testing.T) {
	upstream := &countingTranslator{err: errors.New("boom")}
	cache := newTestCache(upstream, 16, time.Minute, nil)
	ctx := context.Background()

	if _, err := cache.Translate(ctx, "hello", "en", "zh-CHS"); err == nil {
		t.Fatal("expected the upstream error")
	}
	upstream.err = nil
	upstream.result = Result{Text: "译文"}
	result, err := cache.Translate(ctx, "hello", "en", "zh-CHS")
	if err != nil {
		t.Fatalf("second translate: %v", err)
	}
	if result.Cached {
		t.Fatal("failures must never be cached")
	}
	if upstream.callCount() != 2 {
		t.Fatalf("expected 2 upstream calls, got %d", upstream.callCount())
	}
}

func TestCacheDisabledPassesThrough(t *testing.T) {
	upstream := &countingTranslator{result: Result{Text: "译文"}}
	cache := newTestCache(upstream, 0, time.Minute, nil)
	if cache.Enabled() {
		t.Fatal("zero entries must disable the cache")
	}
	ctx := context.Background()
	for i := 0; i < 2; i++ {
		if _, err := cache.Translate(ctx, "hello", "en", "zh-CHS"); err != nil {
			t.Fatalf("translate: %v", err)
		}
	}
	if upstream.callCount() != 2 {
		t.Fatalf("expected 2 upstream calls, got %d", upstream.callCount())
	}
	if stats := cache.Stats(); stats.Hits != 0 || stats.Entries != 0 {
		t.Fatalf("disabled cache must stay empty, got %+v", stats)
	}
}

func TestTranslateHandlerReportsCacheHeader(t *testing.T) {
	upstream := &countingTranslator{result: Result{Text: "译文"}}
	cache := newTestCache(upstream, 16, time.Minute, nil)
	server := httptest.NewServer(NewTranslateHandler(cache, 100))
	defer server.Close()

	post := func() *http.Response {
		response, err := http.Post(
			server.URL,
			"application/json",
			strings.NewReader(`{"text":"hello","from":"en","to":"zh-CHS"}`),
		)
		if err != nil {
			t.Fatalf("request failed: %v", err)
		}
		return response
	}

	first := post()
	first.Body.Close()
	if got := first.Header.Get("X-Cache"); got != "miss" {
		t.Fatalf("first request X-Cache = %q, want miss", got)
	}

	second := post()
	second.Body.Close()
	if got := second.Header.Get("X-Cache"); got != "hit" {
		t.Fatalf("second request X-Cache = %q, want hit", got)
	}
	if upstream.callCount() != 1 {
		t.Fatalf("expected 1 upstream call, got %d", upstream.callCount())
	}
}

func TestDiskCacheSurvivesNewTranslator(t *testing.T) {
	dir := t.TempDir()
	upstream := &countingTranslator{result: Result{Text: "译文", DetectedSource: "en", Target: "zh-CHS"}}
	first := NewCachedTranslator(upstream, CacheConfig{Entries: 8, TTL: time.Minute, Dir: dir})
	ctx := context.Background()
	if _, err := first.Translate(ctx, "hello", "en", "zh-CHS"); err != nil {
		t.Fatalf("first translate: %v", err)
	}
	if stats := first.Stats(); stats.DiskWrites != 1 || stats.DiskEntries != 1 {
		t.Fatalf("expected a disk write, got %+v", stats)
	}

	secondUpstream := &countingTranslator{result: Result{Text: "不应出现"}}
	second := NewCachedTranslator(secondUpstream, CacheConfig{Entries: 8, TTL: time.Minute, Dir: dir})
	got, err := second.Translate(ctx, "hello", "en", "zh-CHS")
	if err != nil {
		t.Fatalf("second translate: %v", err)
	}
	if !got.Cached || got.Text != "译文" || got.DetectedSource != "en" {
		t.Fatalf("disk hit = %+v", got)
	}
	if secondUpstream.callCount() != 0 {
		t.Fatalf("disk hit must not call upstream, got %d", secondUpstream.callCount())
	}
	if stats := second.Stats(); stats.DiskHits != 1 || stats.Misses != 0 {
		t.Fatalf("unexpected stats %+v", stats)
	}

	// The promoted entry is now in memory, so another read is a memory hit.
	if _, err := second.Translate(ctx, "hello", "en", "zh-CHS"); err != nil {
		t.Fatalf("third translate: %v", err)
	}
	if stats := second.Stats(); stats.Hits != 1 || stats.DiskHits != 1 {
		t.Fatalf("expected memory hit after promotion, got %+v", stats)
	}
}

func TestDiskCacheExpires(t *testing.T) {
	dir := t.TempDir()
	current := time.Unix(1_700_000_000, 0)
	now := func() time.Time { return current }
	upstream := &countingTranslator{result: Result{Text: "译文"}}
	first := NewCachedTranslator(upstream, CacheConfig{Entries: 4, TTL: 30 * time.Second, Dir: dir, Now: now})
	ctx := context.Background()
	if _, err := first.Translate(ctx, "hello", "en", "zh-CHS"); err != nil {
		t.Fatalf("translate: %v", err)
	}

	current = current.Add(31 * time.Second)
	secondUpstream := &countingTranslator{result: Result{Text: "新译文"}}
	second := NewCachedTranslator(secondUpstream, CacheConfig{Entries: 4, TTL: 30 * time.Second, Dir: dir, Now: now})
	got, err := second.Translate(ctx, "hello", "en", "zh-CHS")
	if err != nil {
		t.Fatalf("translate: %v", err)
	}
	if got.Cached || got.Text != "新译文" {
		t.Fatalf("expired disk entry must miss, got %+v", got)
	}
	if secondUpstream.callCount() != 1 {
		t.Fatalf("expected a refresh, got %d calls", secondUpstream.callCount())
	}
}

func TestDiskCacheEvictsOldestFile(t *testing.T) {
	dir := t.TempDir()
	upstream := &countingTranslator{result: Result{Text: "译文"}}
	cache := NewCachedTranslator(upstream, CacheConfig{Entries: 1, TTL: time.Minute, Dir: dir})
	ctx := context.Background()
	if _, err := cache.Translate(ctx, "one", "en", "zh-CHS"); err != nil {
		t.Fatalf("translate one: %v", err)
	}
	// ModTime resolution can collapse two immediate writes; push the first
	// file into the past so eviction order is deterministic.
	time.Sleep(20 * time.Millisecond)
	if _, err := cache.Translate(ctx, "two", "en", "zh-CHS"); err != nil {
		t.Fatalf("translate two: %v", err)
	}
	if stats := cache.Stats(); stats.DiskEntries != 1 {
		t.Fatalf("disk cap should keep one file, got %+v", stats)
	}

	restarted := NewCachedTranslator(&countingTranslator{result: Result{Text: "新"}}, CacheConfig{
		Entries: 1,
		TTL:     time.Minute,
		Dir:     dir,
	})
	got, err := restarted.Translate(ctx, "two", "en", "zh-CHS")
	if err != nil {
		t.Fatalf("translate two: %v", err)
	}
	if !got.Cached || got.Text != "译文" {
		t.Fatalf("newest disk entry should survive, got %+v", got)
	}
	got, err = restarted.Translate(ctx, "one", "en", "zh-CHS")
	if err != nil {
		t.Fatalf("translate one: %v", err)
	}
	if got.Cached {
		t.Fatalf("evicted disk entry must miss, got %+v", got)
	}
}

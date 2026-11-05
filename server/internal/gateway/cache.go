package gateway

import (
	"container/list"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"net/http"
	"os"
	"strings"
	"sync"
	"time"
)

// CacheStats is a snapshot of the translate cache counters, reported by
// /healthz so an operator can see whether the cache is paying off.
type CacheStats struct {
	Entries     int   `json:"entries"`
	Hits        int64 `json:"hits"`
	Misses      int64 `json:"misses"`
	Evictions   int64 `json:"evictions"`
	Expired     int64 `json:"expired"`
	DiskHits    int64 `json:"diskHits"`
	DiskWrites  int64 `json:"diskWrites"`
	DiskEntries int   `json:"diskEntries"`
}

// CacheConfig configures a CachedTranslator. A zero Entries or TTL disables
// caching and every request goes straight upstream.
type CacheConfig struct {
	Entries int
	TTL     time.Duration
	// Dir, when set, mirrors successful entries onto disk so a process
	// restart can still serve them. Empty disables the file layer.
	// The on-disk cap matches Entries.
	Dir string
	// Now is injectable so tests can move time forward without sleeping.
	Now func() time.Time
}

// CachedTranslator memoises a Translator behind a TTL + LRU cache.
//
// Two properties matter for a translation gateway:
//
//   - Readers re-open the same chapter and two devices often translate the same
//     book, so identical chunks are requested repeatedly. A hit costs one map
//     lookup instead of a Youdao round trip (and quota).
//   - Concurrent requests for the same chunk are single-flighted: the first
//     caller talks to Youdao and the rest wait for that answer, so a burst of
//     retries cannot multiply upstream traffic.
//
// Only successful translations are stored; errors are never cached so a rate
// limit or a network blip cannot poison the cache.
type CachedTranslator struct {
	next Translator
	ttl  time.Duration
	max  int
	now  func() time.Time
	disk *diskCache

	mu         sync.Mutex
	entries    map[string]*list.Element
	order      *list.List
	flights    map[string]*translationFlight
	hits       int64
	misses     int64
	evictions  int64
	expired    int64
	diskHits   int64
	diskWrites int64
}

type cacheEntry struct {
	key     string
	result  Result
	expires time.Time
}

type translationFlight struct {
	done   chan struct{}
	result Result
	err    error
}

// NewCachedTranslator wraps next with the cache described by cfg.
func NewCachedTranslator(next Translator, cfg CacheConfig) *CachedTranslator {
	now := cfg.Now
	if now == nil {
		now = time.Now
	}
	maxEntries := cfg.Entries
	if maxEntries < 0 {
		maxEntries = 0
	}
	cache := &CachedTranslator{
		next:    next,
		ttl:     cfg.TTL,
		max:     maxEntries,
		now:     now,
		entries: make(map[string]*list.Element),
		order:   list.New(),
		flights: make(map[string]*translationFlight),
	}
	if dir := strings.TrimSpace(cfg.Dir); dir != "" && maxEntries > 0 && cfg.TTL > 0 {
		if err := os.MkdirAll(dir, 0o755); err == nil {
			cache.disk = &diskCache{dir: dir, max: maxEntries, ttl: cfg.TTL, now: now}
		}
	}
	return cache
}

// Enabled reports whether the cache will actually be used.
func (c *CachedTranslator) Enabled() bool {
	return c != nil && c.max > 0 && c.ttl > 0
}

// Translate serves a cached translation when possible.
func (c *CachedTranslator) Translate(
	ctx context.Context,
	text, from, to string,
) (Result, error) {
	if c == nil || c.next == nil {
		return Result{}, &Error{
			Message:    "translator is not configured",
			StatusCode: http.StatusServiceUnavailable,
		}
	}
	if !c.Enabled() {
		return c.next.Translate(ctx, text, from, to)
	}

	key := cacheKey(text, from, to)
	if result, ok := c.lookupMemory(key); ok {
		if c.disk != nil {
			c.disk.Touch(key)
		}
		result.Cached = true
		return result, nil
	}
	if c.disk != nil {
		if result, ok := c.disk.Get(key); ok {
			c.mu.Lock()
			c.diskHits++
			c.remember(key, result)
			c.mu.Unlock()
			result.Cached = true
			return result, nil
		}
	}
	c.mu.Lock()
	c.misses++
	c.mu.Unlock()
	return c.translateOnce(ctx, key, text, from, to)
}

// Stats returns a snapshot of the counters.
func (c *CachedTranslator) Stats() CacheStats {
	if c == nil {
		return CacheStats{}
	}
	c.mu.Lock()
	defer c.mu.Unlock()
	diskEntries := 0
	if c.disk != nil {
		diskEntries = c.disk.Len()
	}
	return CacheStats{
		Entries:     c.order.Len(),
		Hits:        c.hits,
		Misses:      c.misses,
		Evictions:   c.evictions,
		Expired:     c.expired,
		DiskHits:    c.diskHits,
		DiskWrites:  c.diskWrites,
		DiskEntries: diskEntries,
	}
}

func (c *CachedTranslator) lookupMemory(key string) (Result, bool) {
	c.mu.Lock()
	defer c.mu.Unlock()

	element, ok := c.entries[key]
	if !ok {
		return Result{}, false
	}
	entry := element.Value.(*cacheEntry)
	if c.now().After(entry.expires) {
		c.order.Remove(element)
		delete(c.entries, key)
		c.expired++
		return Result{}, false
	}
	c.order.MoveToFront(element)
	c.hits++
	return entry.result, true
}

func (c *CachedTranslator) translateOnce(
	ctx context.Context,
	key, text, from, to string,
) (Result, error) {
	c.mu.Lock()
	if flight, ok := c.flights[key]; ok {
		c.mu.Unlock()
		select {
		case <-flight.done:
			return flight.result, flight.err
		case <-ctx.Done():
			return Result{}, ctx.Err()
		}
	}
	flight := &translationFlight{done: make(chan struct{})}
	c.flights[key] = flight
	c.mu.Unlock()

	result, err := c.next.Translate(ctx, text, from, to)

	var expires time.Time
	c.mu.Lock()
	delete(c.flights, key)
	if err == nil {
		c.remember(key, result)
		expires = c.now().Add(c.ttl)
	}
	disk := c.disk
	c.mu.Unlock()
	if err == nil && disk != nil {
		if putErr := disk.Put(key, result, expires); putErr == nil {
			c.mu.Lock()
			c.diskWrites++
			c.mu.Unlock()
		}
	}
	flight.result, flight.err = result, err
	close(flight.done)
	return result, err
}

// remember inserts or refreshes a memory entry. Callers must hold the lock.
// Disk persistence is handled by the caller so this lock does not cover IO.
func (c *CachedTranslator) remember(key string, result Result) {
	expires := c.now().Add(c.ttl)
	if element, ok := c.entries[key]; ok {
		entry := element.Value.(*cacheEntry)
		entry.result = result
		entry.expires = expires
		c.order.MoveToFront(element)
		return
	}

	element := c.order.PushFront(&cacheEntry{
		key:     key,
		result:  result,
		expires: expires,
	})
	c.entries[key] = element
	for c.order.Len() > c.max {
		oldest := c.order.Back()
		if oldest == nil {
			break
		}
		c.order.Remove(oldest)
		delete(c.entries, oldest.Value.(*cacheEntry).key)
		c.evictions++
	}
}

// cacheKey hashes the request so the map never holds whole chapters as keys.
func cacheKey(text, from, to string) string {
	normalized := strings.TrimSpace(text)
	sum := sha256.Sum256([]byte(from + "\x00" + to + "\x00" + normalized))
	return hex.EncodeToString(sum[:])
}

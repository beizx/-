package proxypool

import (
	"context"
	"errors"
	"fmt"
	"net/http"
	"net/url"
	"sync"
	"time"
)

// Config tunes the pool.
type Config struct {
	// Target is the queue length the pool tries to keep filled.
	Target int
	// CheckURL is fetched through each candidate to prove it works.
	CheckURL string
	// CheckTimeout bounds a single validation request.
	CheckTimeout time.Duration
	// Sources are consulted in order until Target is reached.
	Sources []Source
	// AllowPrivate keeps loopback and RFC1918 candidates. Only tests and
	// intranet deployments should set it.
	AllowPrivate bool
}

// DefaultCheckURL is a small, cache-friendly endpoint that returns 204.
const DefaultCheckURL = "https://www.baidu.com/robots.txt"

// Stats reports what the last refill did, which is useful for /v1/proxies.
type Stats struct {
	Fetched  int
	Checked  int
	Rejected int
	Added    int
}

// ErrNoProxy is returned when the queue is empty.
var ErrNoProxy = errors.New("proxypool: no proxy available")

// Pool keeps a queue of validated proxies and refills it from the sources.
type Pool struct {
	cfg    Config
	client *http.Client

	mu    sync.Mutex
	queue []Proxy
	stats Stats

	refillMu sync.Mutex
}

// New builds a pool. A nil client gets a sane default.
func New(cfg Config, client *http.Client) *Pool {
	if cfg.Target <= 0 {
		cfg.Target = 20
	}
	if cfg.CheckURL == "" {
		cfg.CheckURL = DefaultCheckURL
	}
	if cfg.CheckTimeout <= 0 {
		cfg.CheckTimeout = 4 * time.Second
	}
	if client == nil {
		client = &http.Client{Timeout: 15 * time.Second}
	}
	return &Pool{cfg: cfg, client: client}
}

// Size returns the number of queued proxies.
func (p *Pool) Size() int {
	p.mu.Lock()
	defer p.mu.Unlock()
	return len(p.queue)
}

// Stats returns a copy of the last refill statistics.
func (p *Pool) Stats() Stats {
	p.mu.Lock()
	defer p.mu.Unlock()
	return p.stats
}

// Snapshot copies up to limit queued proxies without removing them.
func (p *Pool) Snapshot(limit int) []Proxy {
	p.mu.Lock()
	defer p.mu.Unlock()
	if limit <= 0 || limit > len(p.queue) {
		limit = len(p.queue)
	}
	out := make([]Proxy, limit)
	copy(out, p.queue[:limit])
	return out
}

// Take removes and returns the head of the queue.
func (p *Pool) Take() (Proxy, bool) {
	p.mu.Lock()
	defer p.mu.Unlock()
	if len(p.queue) == 0 {
		return Proxy{}, false
	}
	proxy := p.queue[0]
	p.queue = p.queue[1:]
	return proxy, true
}

// Refill fetches, validates and enqueues proxies until Target is reached.
//
// It is safe to call concurrently; overlapping calls share one run so a burst
// of requests cannot fan out into a burst of upstream scrapes.
func (p *Pool) Refill(ctx context.Context) (Stats, error) {
	p.refillMu.Lock()
	defer p.refillMu.Unlock()

	stats := Stats{}
	var firstErr error

	for _, source := range p.cfg.Sources {
		if p.Size() >= p.cfg.Target {
			break
		}
		candidates, err := source.Fetch(ctx, p.client)
		if err != nil {
			if firstErr == nil {
				firstErr = err
			}
			continue
		}
		stats.Fetched += len(candidates)

		for _, candidate := range candidates {
			if p.Size() >= p.cfg.Target {
				break
			}
			if p.contains(candidate) {
				continue
			}
			stats.Checked++
			if err := p.Validate(ctx, candidate); err != nil {
				stats.Rejected++
				continue
			}
			p.enqueue(candidate)
			stats.Added++
		}
	}

	p.mu.Lock()
	p.stats = stats
	p.mu.Unlock()

	if p.Size() == 0 && firstErr != nil {
		return stats, firstErr
	}
	return stats, nil
}

// Validate performs a GET through the candidate proxy.
func (p *Pool) Validate(ctx context.Context, proxy Proxy) error {
	if p.cfg.AllowPrivate {
		if proxy.Host == "" || proxy.Port < 1 || proxy.Port > 65535 {
			return fmt.Errorf("proxypool: invalid proxy %s", proxy.Address())
		}
	} else if !proxy.Valid() {
		return fmt.Errorf("proxypool: invalid proxy %s", proxy.Address())
	}
	ctx, cancel := context.WithTimeout(ctx, p.cfg.CheckTimeout)
	defer cancel()

	client := &http.Client{
		Timeout: p.cfg.CheckTimeout,
		Transport: &http.Transport{
			Proxy:               http.ProxyURL(proxy.URL()),
			DisableKeepAlives:   true,
			TLSHandshakeTimeout: p.cfg.CheckTimeout,
		},
	}
	defer client.CloseIdleConnections()

	request, err := http.NewRequestWithContext(ctx, http.MethodGet, p.cfg.CheckURL, nil)
	if err != nil {
		return fmt.Errorf("proxypool: build check request: %w", err)
	}
	request.Header.Set("User-Agent", userAgentForUpstream)

	response, err := client.Do(request)
	if err != nil {
		var urlErr *url.Error
		if errors.As(err, &urlErr) {
			return fmt.Errorf("proxypool: proxy %s unreachable: %w", proxy.Address(), urlErr.Err)
		}
		return fmt.Errorf("proxypool: proxy %s unreachable: %w", proxy.Address(), err)
	}
	defer func() {
		_ = response.Body.Close()
	}()

	if response.StatusCode >= 400 {
		return fmt.Errorf("proxypool: proxy %s returned %d", proxy.Address(), response.StatusCode)
	}
	return nil
}

func (p *Pool) contains(proxy Proxy) bool {
	p.mu.Lock()
	defer p.mu.Unlock()
	for _, queued := range p.queue {
		if queued == proxy {
			return true
		}
	}
	return false
}

func (p *Pool) enqueue(proxy Proxy) {
	p.mu.Lock()
	defer p.mu.Unlock()
	if len(p.queue) >= p.cfg.Target {
		return
	}
	p.queue = append(p.queue, proxy)
}

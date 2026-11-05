package proxypool

import (
	"context"
	"fmt"
	"io"
	"net/http"
	"strings"
	"time"
)

// Format describes how a source serialises its proxy list.
type Format string

const (
	// FormatText is a plain-text body containing `ip:port` pairs.
	FormatText Format = "text"
	// FormatJSON is the `{"data":{"proxies":[...]}}` envelope.
	FormatJSON Format = "json"
)

// Source publishes candidate proxies. Implementations only fetch and parse;
// validation is the pool's job so every source gets the same treatment.
type Source interface {
	Name() string
	Fetch(ctx context.Context, client *http.Client) ([]Proxy, error)
}

// Default source endpoints, ported from the previous Kotlin/JVM service.
const (
	DefaultIP89Endpoint  = "https://api.89ip.cn/tqdl.html?api=1&num=40&port=&address=&isp="
	DefaultScdnEndpoint  = "https://proxy.scdn.io/api/get_proxy.php?protocol=https&count=20"
	defaultFetchTimeout  = 12 * time.Second
	maxSourceBodyBytes   = 2 << 20
	userAgentForUpstream = "beizx-reader-server/1.0 (+https://github.com/beizx)"
)

// HTTPSource is a generic HTTP-backed source.
type HTTPSource struct {
	name     string
	endpoint string
	format   Format
	timeout  time.Duration
}

// NewHTTPSource builds a source with an explicit name, endpoint and format.
func NewHTTPSource(name, endpoint string, format Format) *HTTPSource {
	return &HTTPSource{
		name:     name,
		endpoint: endpoint,
		format:   format,
		timeout:  defaultFetchTimeout,
	}
}

// NewIP89Source returns the 89ip.cn plain-text source.
func NewIP89Source(endpoint string) *HTTPSource {
	if strings.TrimSpace(endpoint) == "" {
		endpoint = DefaultIP89Endpoint
	}
	return NewHTTPSource("89ip", endpoint, FormatText)
}

// NewScdnSource returns the proxy.scdn.io JSON source.
func NewScdnSource(endpoint string) *HTTPSource {
	if strings.TrimSpace(endpoint) == "" {
		endpoint = DefaultScdnEndpoint
	}
	return NewHTTPSource("scdn", endpoint, FormatJSON)
}

func (s *HTTPSource) Name() string { return s.name }

// Fetch downloads and parses the source list.
func (s *HTTPSource) Fetch(ctx context.Context, client *http.Client) ([]Proxy, error) {
	if client == nil {
		client = &http.Client{Timeout: s.timeout}
	}
	ctx, cancel := context.WithTimeout(ctx, s.timeout)
	defer cancel()

	request, err := http.NewRequestWithContext(ctx, http.MethodGet, s.endpoint, nil)
	if err != nil {
		return nil, fmt.Errorf("proxypool: %s: build request: %w", s.name, err)
	}
	request.Header.Set("User-Agent", userAgentForUpstream)
	request.Header.Set("Accept", "*/*")

	response, err := client.Do(request)
	if err != nil {
		return nil, fmt.Errorf("proxypool: %s: fetch: %w", s.name, err)
	}
	defer func() {
		_ = response.Body.Close()
	}()

	if response.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("proxypool: %s: unexpected status %d", s.name, response.StatusCode)
	}

	body, err := io.ReadAll(io.LimitReader(response.Body, maxSourceBodyBytes))
	if err != nil {
		return nil, fmt.Errorf("proxypool: %s: read body: %w", s.name, err)
	}

	switch s.format {
	case FormatJSON:
		return ParseJSONList(body)
	default:
		return Parse(string(body)), nil
	}
}

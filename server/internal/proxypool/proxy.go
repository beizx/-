package proxypool

import (
	"encoding/json"
	"fmt"
	"net"
	"net/url"
	"regexp"
	"strconv"
	"strings"
)

// SchemeHTTP is the only scheme the pool hands out: the sources publish plain
// HTTP proxies that tunnel HTTPS targets through CONNECT.
const SchemeHTTP = "http"

// addressPattern matches the `1.2.3.4:8080` shape used by every public proxy
// list. Hostnames are rejected on purpose: a public pool of hostnames is far
// more likely to be a DNS rebinding trap than a usable proxy.
var addressPattern = regexp.MustCompile(`(\d{1,3}(?:\.\d{1,3}){3}):(\d{2,5})`)

// Proxy is one validated upstream HTTP proxy.
type Proxy struct {
	Host string
	Port int
}

// Address returns host:port as used by net.Dial and http.Transport.
func (p Proxy) Address() string {
	return net.JoinHostPort(p.Host, strconv.Itoa(p.Port))
}

// URL renders the proxy as an absolute URL for http.ProxyURL.
func (p Proxy) URL() *url.URL {
	return &url.URL{Scheme: SchemeHTTP, Host: p.Address()}
}

func (p Proxy) String() string {
	return SchemeHTTP + "://" + p.Address()
}

// Valid reports whether the address could plausibly be a public proxy.
func (p Proxy) Valid() bool {
	if net.ParseIP(p.Host) == nil {
		return false
	}
	if p.Port < 1 || p.Port > 65535 {
		return false
	}
	ip := net.ParseIP(p.Host)
	return !ip.IsLoopback() && !ip.IsPrivate() && !ip.IsUnspecified()
}

// Parse extracts every `ip:port` pair from free-form text, which is what the
// plain-text sources return.
func Parse(text string) []Proxy {
	matches := addressPattern.FindAllStringSubmatch(text, -1)
	proxies := make([]Proxy, 0, len(matches))
	for _, match := range matches {
		port, err := strconv.Atoi(match[2])
		if err != nil {
			continue
		}
		proxy := Proxy{Host: match[1], Port: port}
		if proxy.Valid() {
			proxies = append(proxies, proxy)
		}
	}
	return proxies
}

// scdnEnvelope mirrors the JSON shape returned by proxy.scdn.io.
type scdnEnvelope struct {
	Data struct {
		Proxies []string `json:"proxies"`
	} `json:"data"`
}

// ParseJSONList decodes the `{"data":{"proxies":["ip:port"]}}` payload.
func ParseJSONList(raw []byte) ([]Proxy, error) {
	trimmed := strings.TrimSpace(string(raw))
	if trimmed == "" {
		return nil, fmt.Errorf("proxypool: empty response")
	}
	var envelope scdnEnvelope
	if err := json.Unmarshal([]byte(trimmed), &envelope); err != nil {
		return nil, fmt.Errorf("proxypool: decode proxy list: %w", err)
	}
	proxies := make([]Proxy, 0, len(envelope.Data.Proxies))
	for _, entry := range envelope.Data.Proxies {
		for _, proxy := range Parse(entry) {
			proxies = append(proxies, proxy)
		}
	}
	return proxies, nil
}

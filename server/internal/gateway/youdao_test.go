package gateway

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"net/url"
	"strings"
	"testing"
	"time"
)

func newTestYoudao(t *testing.T, handler http.HandlerFunc) (*Youdao, *httptest.Server) {
	t.Helper()
	server := httptest.NewServer(handler)
	t.Cleanup(server.Close)

	client := NewYoudao("test-app-key", "test-secret")
	client.Endpoint = server.URL
	client.Now = func() time.Time { return time.Unix(1700000000, 0) }
	client.Salt = func() string { return "fixed-salt" }
	return client, server
}

func TestYoudaoTranslateSignsRequest(t *testing.T) {
	var gotForm url.Values
	client, _ := newTestYoudao(t, func(w http.ResponseWriter, r *http.Request) {
		if err := r.ParseForm(); err != nil {
			t.Errorf("parse form: %v", err)
		}
		gotForm = r.PostForm
		_ = json.NewEncoder(w).Encode(map[string]any{
			"errorCode":   "0",
			"translation": []string{"你好世界"},
			"l":           "en2zh-CHS",
		})
	})

	result, err := client.Translate(context.Background(), "  hello world  ", "auto", "zh-CHS")
	if err != nil {
		t.Fatalf("translate failed: %v", err)
	}
	if result.Text != "你好世界" {
		t.Fatalf("unexpected translation %q", result.Text)
	}
	if result.DetectedSource != "en" {
		t.Fatalf("unexpected detected source %q", result.DetectedSource)
	}

	if gotForm.Get("q") != "hello world" {
		t.Fatalf("text was not trimmed: %q", gotForm.Get("q"))
	}
	if gotForm.Get("signType") != "v3" {
		t.Fatalf("expected signType v3, got %q", gotForm.Get("signType"))
	}
	if gotForm.Get("curtime") != "1700000000" {
		t.Fatalf("unexpected curtime %q", gotForm.Get("curtime"))
	}
	want := Sign("test-app-key", "hello world", "fixed-salt", "1700000000", "test-secret")
	if gotForm.Get("sign") != want {
		t.Fatalf("unexpected signature %q, want %q", gotForm.Get("sign"), want)
	}
}

func TestYoudaoMapsUpstreamErrorCodes(t *testing.T) {
	client, _ := newTestYoudao(t, func(w http.ResponseWriter, r *http.Request) {
		_ = json.NewEncoder(w).Encode(map[string]any{"errorCode": "108"})
	})

	_, err := client.Translate(context.Background(), "hello", "auto", "zh-CHS")
	if err == nil {
		t.Fatal("expected an error")
	}
	apiErr, ok := err.(*Error)
	if !ok {
		t.Fatalf("expected *Error, got %T", err)
	}
	if apiErr.Code != "108" || apiErr.StatusCode != http.StatusUnauthorized {
		t.Fatalf("unexpected error mapping: %+v", apiErr)
	}
}

func TestYoudaoRequiresCredentials(t *testing.T) {
	client := NewYoudao("", "")
	if _, err := client.Translate(context.Background(), "hello", "auto", "zh"); err == nil {
		t.Fatal("expected a configuration error")
	}
}

func TestYoudaoRejectsEmptyText(t *testing.T) {
	client := NewYoudao("key", "secret")
	if _, err := client.Translate(context.Background(), "   ", "auto", "zh"); err == nil {
		t.Fatal("expected an error for empty text")
	}
}

func TestYoudaoTruncatesLongInput(t *testing.T) {
	var sent string
	client, _ := newTestYoudao(t, func(w http.ResponseWriter, r *http.Request) {
		if err := r.ParseForm(); err != nil {
			t.Errorf("parse form: %v", err)
		}
		sent = r.PostForm.Get("q")
		_ = json.NewEncoder(w).Encode(map[string]any{
			"errorCode":   "0",
			"translation": []string{"ok"},
			"l":           "zh2en",
		})
	})

	long := strings.Repeat("字", maxInputRunes+50)
	if _, err := client.Translate(context.Background(), long, "zh", "en"); err != nil {
		t.Fatalf("translate failed: %v", err)
	}
	if runes := []rune(sent); len(runes) != maxInputRunes {
		t.Fatalf("expected %d runes, got %d", maxInputRunes, len(runes))
	}
}

func TestSignMatchesGoldenDigest(t *testing.T) {
	// sha256("key" + "text" + "1" + "2" + "secret"), computed independently.
	const want = "331a1d32fe82ff8a622c7096f2c18bc8f3db5d8da4e48292bd51a0f302db2099"
	if got := Sign("key", "text", "1", "2", "secret"); got != want {
		t.Fatalf("unexpected signature %q, want %q", got, want)
	}
}

func TestSignInputFollowsV3Truncation(t *testing.T) {
	short := "hello world"
	if SignInput(short) != short {
		t.Fatalf("short queries must be signed verbatim, got %q", SignInput(short))
	}

	// Same first 10 runes, same length, same last 10 runes: the middle may
	// differ and the signature input must still match.
	a := "0123456789" + "AAAA" + "abcdefghij"
	b := "0123456789" + "ZZZZ" + "abcdefghij"
	if len([]rune(a)) != 24 {
		t.Fatalf("test fixture must be 24 runes, got %d", len([]rune(a)))
	}
	if SignInput(a) != SignInput(b) {
		t.Fatalf("expected identical signing input, got %q vs %q", SignInput(a), SignInput(b))
	}
	if want := "0123456789" + "24" + "abcdefghij"; SignInput(a) != want {
		t.Fatalf("unexpected signing input %q, want %q", SignInput(a), want)
	}
}

func TestYoudaoSignsWithTruncatedQuery(t *testing.T) {
	var gotForm url.Values
	client, _ := newTestYoudao(t, func(w http.ResponseWriter, r *http.Request) {
		if err := r.ParseForm(); err != nil {
			t.Errorf("parse form: %v", err)
		}
		gotForm = r.PostForm
		_ = json.NewEncoder(w).Encode(map[string]any{
			"errorCode":   "0",
			"translation": []string{"ok"},
			"l":           "zh2en",
		})
	})

	text := "0123456789" + "AAAA" + "abcdefghij"
	if _, err := client.Translate(context.Background(), text, "zh", "en"); err != nil {
		t.Fatalf("translate failed: %v", err)
	}
	if gotForm.Get("q") != text {
		t.Fatalf("the full text must be sent as q, got %q", gotForm.Get("q"))
	}
	want := Sign("test-app-key", SignInput(text), "fixed-salt", "1700000000", "test-secret")
	if gotForm.Get("sign") != want {
		t.Fatalf("signature must use the truncated query")
	}
}

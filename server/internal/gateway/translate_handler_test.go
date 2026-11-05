package gateway

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

type stubTranslator struct {
	result Result
	err    error
	calls  int
}

func (s *stubTranslator) Translate(context.Context, string, string, string) (Result, error) {
	s.calls++
	return s.result, s.err
}

func TestTranslateHandlerSuccess(t *testing.T) {
	translator := &stubTranslator{result: Result{Text: "译文", DetectedSource: "en", Target: "zh-CHS"}}
	server := httptest.NewServer(NewTranslateHandler(translator, 100))
	defer server.Close()

	response, err := http.Post(
		server.URL,
		"application/json",
		strings.NewReader(`{"text":"hello","from":"auto","to":"zh-CHS"}`),
	)
	if err != nil {
		t.Fatalf("request failed: %v", err)
	}
	defer response.Body.Close()

	if response.StatusCode != http.StatusOK {
		t.Fatalf("unexpected status %d", response.StatusCode)
	}
	var payload TranslateResponse
	if err := json.NewDecoder(response.Body).Decode(&payload); err != nil {
		t.Fatalf("decode: %v", err)
	}
	if payload.Text != "译文" || payload.DetectedSource != "en" {
		t.Fatalf("unexpected payload %+v", payload)
	}
	if translator.calls != 1 {
		t.Fatalf("expected 1 upstream call, got %d", translator.calls)
	}
}

func TestTranslateHandlerRejectsEmptyText(t *testing.T) {
	translator := &stubTranslator{}
	server := httptest.NewServer(NewTranslateHandler(translator, 100))
	defer server.Close()

	response, err := http.Post(server.URL, "application/json", strings.NewReader(`{"text":"   "}`))
	if err != nil {
		t.Fatalf("request failed: %v", err)
	}
	defer response.Body.Close()

	if response.StatusCode != http.StatusBadRequest {
		t.Fatalf("unexpected status %d", response.StatusCode)
	}
	if translator.calls != 0 {
		t.Fatal("upstream must not be called for invalid input")
	}
}

func TestTranslateHandlerRejectsOversizedText(t *testing.T) {
	translator := &stubTranslator{}
	server := httptest.NewServer(NewTranslateHandler(translator, 4))
	defer server.Close()

	body := `{"text":"` + strings.Repeat("字", 5) + `"}`
	response, err := http.Post(server.URL, "application/json", strings.NewReader(body))
	if err != nil {
		t.Fatalf("request failed: %v", err)
	}
	defer response.Body.Close()

	if response.StatusCode != http.StatusRequestEntityTooLarge {
		t.Fatalf("unexpected status %d", response.StatusCode)
	}
}

func TestTranslateHandlerPropagatesUpstreamStatus(t *testing.T) {
	translator := &stubTranslator{
		err: &Error{Code: "411", Message: "请求过于频繁", StatusCode: http.StatusTooManyRequests},
	}
	server := httptest.NewServer(NewTranslateHandler(translator, 100))
	defer server.Close()

	response, err := http.Post(server.URL, "application/json", strings.NewReader(`{"text":"hi"}`))
	if err != nil {
		t.Fatalf("request failed: %v", err)
	}
	defer response.Body.Close()

	if response.StatusCode != http.StatusTooManyRequests {
		t.Fatalf("unexpected status %d", response.StatusCode)
	}
	var payload errorResponse
	if err := json.NewDecoder(response.Body).Decode(&payload); err != nil {
		t.Fatalf("decode: %v", err)
	}
	if payload.Code != "411" {
		t.Fatalf("unexpected code %q", payload.Code)
	}
}

func TestTranslateHandlerRejectsWrongMethod(t *testing.T) {
	server := httptest.NewServer(NewTranslateHandler(&stubTranslator{}, 100))
	defer server.Close()

	response, err := http.Get(server.URL)
	if err != nil {
		t.Fatalf("request failed: %v", err)
	}
	defer response.Body.Close()

	if response.StatusCode != http.StatusMethodNotAllowed {
		t.Fatalf("unexpected status %d", response.StatusCode)
	}
}

func TestIsRetryable(t *testing.T) {
	if !IsRetryable(&Error{Code: "411"}) {
		t.Fatal("rate limits should be retryable")
	}
	if IsRetryable(&Error{Code: "108", StatusCode: http.StatusUnauthorized}) {
		t.Fatal("bad credentials are not retryable")
	}
	if IsRetryable(errors.New("boom")) {
		t.Fatal("plain errors are not retryable")
	}
}

package gateway

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"time"
)

// DefaultEndpoint is the Youdao text translation v3 endpoint.
const DefaultEndpoint = "https://openapi.youdao.com/api"

// maxInputRunes is the v3 API limit per request.
const maxInputRunes = 4800

// Error is an upstream failure with the provider's own code preserved so the
// client can distinguish "bad key" from "rate limited".
type Error struct {
	Code       string
	Message    string
	StatusCode int
}

func (e *Error) Error() string {
	if e.Code == "" {
		return "gateway: " + e.Message
	}
	return fmt.Sprintf("gateway: %s (code %s)", e.Message, e.Code)
}

// Result is a successful translation.
type Result struct {
	Text           string `json:"text"`
	DetectedSource string `json:"detectedSource,omitempty"`
	Target         string `json:"target,omitempty"`
	// Cached is set by CachedTranslator when the answer came from the cache.
	// It is not part of the JSON contract; the handler turns it into the
	// X-Cache response header.
	Cached bool `json:"-"`
}

// Translator is the seam used by the HTTP handler and by tests.
type Translator interface {
	Translate(ctx context.Context, text, from, to string) (Result, error)
}

// Youdao signs and executes requests against the Youdao open API.
type Youdao struct {
	AppKey   string
	Secret   string
	Endpoint string
	Client   *http.Client
	Now      func() time.Time
	Salt     func() string
}

// NewYoudao builds a client with production defaults.
func NewYoudao(appKey, secret string) *Youdao {
	return &Youdao{
		AppKey:   appKey,
		Secret:   secret,
		Endpoint: DefaultEndpoint,
		Client:   &http.Client{Timeout: 20 * time.Second},
		Now:      time.Now,
	}
}

// Translate sends one chunk of text to Youdao.
func (y *Youdao) Translate(ctx context.Context, text, from, to string) (Result, error) {
	trimmed := strings.TrimSpace(text)
	if trimmed == "" {
		return Result{}, &Error{Message: "text is empty", StatusCode: http.StatusBadRequest}
	}
	if y.AppKey == "" || y.Secret == "" {
		return Result{}, &Error{Message: "youdao credentials are not configured", StatusCode: http.StatusServiceUnavailable}
	}
	if from == "" {
		from = "auto"
	}
	if to == "" {
		to = "zh-CHS"
	}

	input := truncateRunes(trimmed, maxInputRunes)
	salt := y.salt()
	curtime := strconv.FormatInt(y.now().Unix(), 10)

	form := url.Values{}
	form.Set("q", input)
	form.Set("from", from)
	form.Set("to", to)
	form.Set("appKey", y.AppKey)
	form.Set("salt", salt)
	form.Set("sign", Sign(y.AppKey, SignInput(input), salt, curtime, y.Secret))
	form.Set("signType", "v3")
	form.Set("curtime", curtime)

	request, err := http.NewRequestWithContext(
		ctx,
		http.MethodPost,
		y.endpoint(),
		strings.NewReader(form.Encode()),
	)
	if err != nil {
		return Result{}, fmt.Errorf("gateway: build request: %w", err)
	}
	request.Header.Set("Content-Type", "application/x-www-form-urlencoded")

	client := y.Client
	if client == nil {
		client = http.DefaultClient
	}
	response, err := client.Do(request)
	if err != nil {
		return Result{}, &Error{
			Message:    "youdao request failed: " + err.Error(),
			StatusCode: http.StatusBadGateway,
		}
	}
	defer func() {
		_ = response.Body.Close()
	}()

	body, err := io.ReadAll(io.LimitReader(response.Body, 4<<20))
	if err != nil {
		return Result{}, &Error{
			Message:    "read youdao response: " + err.Error(),
			StatusCode: http.StatusBadGateway,
		}
	}
	if response.StatusCode != http.StatusOK {
		return Result{}, &Error{
			Message:    fmt.Sprintf("youdao returned status %d", response.StatusCode),
			StatusCode: http.StatusBadGateway,
		}
	}

	var payload struct {
		ErrorCode   string   `json:"errorCode"`
		Translation []string `json:"translation"`
		L           string   `json:"l"`
	}
	if err := json.Unmarshal(body, &payload); err != nil {
		return Result{}, &Error{
			Message:    "decode youdao response: " + err.Error(),
			StatusCode: http.StatusBadGateway,
		}
	}
	if payload.ErrorCode != "" && payload.ErrorCode != "0" {
		return Result{}, mapErrorCode(payload.ErrorCode)
	}
	if len(payload.Translation) == 0 {
		return Result{}, &Error{
			Message:    "youdao returned no translation",
			StatusCode: http.StatusBadGateway,
		}
	}

	detected := ""
	if parts := strings.Split(payload.L, "2"); len(parts) == 2 {
		detected = parts[0]
	}
	return Result{
		Text:           strings.Join(payload.Translation, "\n"),
		DetectedSource: detected,
		Target:         to,
	}, nil
}

func (y *Youdao) endpoint() string {
	if strings.TrimSpace(y.Endpoint) == "" {
		return DefaultEndpoint
	}
	return y.Endpoint
}

func (y *Youdao) now() time.Time {
	if y.Now != nil {
		return y.Now()
	}
	return time.Now()
}

func (y *Youdao) salt() string {
	if y.Salt != nil {
		return y.Salt()
	}
	return strconv.FormatInt(time.Now().UnixNano(), 10)
}

// Sign implements the Youdao v3 signature:
// sha256(appKey + input + salt + curtime + appSecret), hex encoded.
func Sign(appKey, input, salt, curtime, secret string) string {
	sum := sha256.Sum256([]byte(appKey + input + salt + curtime + secret))
	return hex.EncodeToString(sum[:])
}

// SignInput applies the v3 signing rule for the query: anything longer than 20
// characters is signed as first 10 runes + character count + last 10 runes.
// The `q` field itself still carries the full text.
func SignInput(query string) string {
	runes := []rune(query)
	if len(runes) <= 20 {
		return query
	}
	first := string(runes[:10])
	last := string(runes[len(runes)-10:])
	return first + strconv.Itoa(len(runes)) + last
}

// truncateRunes keeps the first n runes and never splits a UTF-8 sequence.
func truncateRunes(text string, n int) string {
	runes := []rune(text)
	if len(runes) <= n {
		return text
	}
	return string(runes[:n])
}

// IsRetryable reports whether the caller should retry later.
func IsRetryable(err error) bool {
	var apiErr *Error
	if !errors.As(err, &apiErr) {
		return false
	}
	return apiErr.Code == "411" || apiErr.Code == "401" || apiErr.StatusCode >= 500
}

func mapErrorCode(code string) error {
	switch code {
	case "108", "110":
		return &Error{
			Code:       code,
			Message:    "有道应用 ID 或密钥无效，请检查接口配置",
			StatusCode: http.StatusUnauthorized,
		}
	case "411", "412":
		return &Error{
			Code:       code,
			Message:    "请求过于频繁，请稍后重试",
			StatusCode: http.StatusTooManyRequests,
		}
	case "401":
		return &Error{
			Code:       code,
			Message:    "有道账号余额不足或服务未开通",
			StatusCode: http.StatusPaymentRequired,
		}
	default:
		return &Error{
			Code:       code,
			Message:    "有道返回错误码 " + code,
			StatusCode: http.StatusBadGateway,
		}
	}
}

package gateway

import (
	"encoding/json"
	"errors"
	"net/http"
	"strings"
)

// TranslateRequest is the JSON body accepted by the gateway.
type TranslateRequest struct {
	Text string `json:"text"`
	From string `json:"from"`
	To   string `json:"to"`
}

// TranslateResponse is the JSON body returned on success.
type TranslateResponse struct {
	Text           string `json:"text"`
	DetectedSource string `json:"detectedSource,omitempty"`
	Target         string `json:"target,omitempty"`
}

type errorResponse struct {
	Error   string `json:"error"`
	Code    string `json:"code,omitempty"`
	Details string `json:"details,omitempty"`
}

// MaxTextRunes bounds a single request so one client cannot burn the whole
// free quota in one call.
const MaxTextRunes = 20000

// NewTranslateHandler serves POST /v1/translate.
func NewTranslateHandler(translator Translator, maxRunes int) http.Handler {
	if maxRunes <= 0 {
		maxRunes = MaxTextRunes
	}
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost {
			w.Header().Set("Allow", http.MethodPost)
			writeJSON(w, http.StatusMethodNotAllowed, errorResponse{Error: "method not allowed"})
			return
		}

		var body TranslateRequest
		decoder := json.NewDecoder(http.MaxBytesReader(w, r.Body, 1<<20))
		decoder.DisallowUnknownFields()
		if err := decoder.Decode(&body); err != nil {
			writeJSON(w, http.StatusBadRequest, errorResponse{
				Error:   "invalid JSON body",
				Details: err.Error(),
			})
			return
		}

		text := strings.TrimSpace(body.Text)
		if text == "" {
			writeJSON(w, http.StatusBadRequest, errorResponse{Error: "text is required"})
			return
		}
		if len([]rune(text)) > maxRunes {
			writeJSON(w, http.StatusRequestEntityTooLarge, errorResponse{
				Error: "text is too long",
			})
			return
		}

		result, err := translator.Translate(r.Context(), text, body.From, body.To)
		if err != nil {
			var apiErr *Error
			if errors.As(err, &apiErr) {
				status := apiErr.StatusCode
				if status == 0 {
					status = http.StatusBadGateway
				}
				writeJSON(w, status, errorResponse{
					Error: apiErr.Message,
					Code:  apiErr.Code,
				})
				return
			}
			writeJSON(w, http.StatusBadGateway, errorResponse{Error: err.Error()})
			return
		}

		if result.Cached {
			w.Header().Set("X-Cache", "hit")
		} else {
			w.Header().Set("X-Cache", "miss")
		}
		writeJSON(w, http.StatusOK, TranslateResponse{
			Text:           result.Text,
			DetectedSource: result.DetectedSource,
			Target:         result.Target,
		})
	})
}

func writeJSON(w http.ResponseWriter, status int, payload any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.Header().Set("Cache-Control", "no-store")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(payload)
}

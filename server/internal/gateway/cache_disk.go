package gateway

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
	"sync"
	"time"
)

// diskCache is a small file-backed mirror of successful translations.
//
// Each entry is one JSON file named by the cache key. The directory is capped
// at [diskCache.max] files so a long-running gateway cannot fill the disk.
// Errors are ignored by the caller: a disk problem must not fail a translation
// that the memory cache (or upstream) already handled.
type diskCache struct {
	dir string
	max int
	ttl time.Duration
	now func() time.Time
	mu  sync.Mutex
}

type diskPayload struct {
	Text           string `json:"text"`
	DetectedSource string `json:"detectedSource,omitempty"`
	Target         string `json:"target,omitempty"`
	ExpiresUnix    int64  `json:"expiresUnix"`
}

var cacheFileName = regexp.MustCompile(`^[a-f0-9]{64}\.json$`)

func (d *diskCache) path(key string) string {
	name := key
	if !regexp.MustCompile(`^[a-f0-9]{64}$`).MatchString(name) {
		sum := sha256.Sum256([]byte(key))
		name = hex.EncodeToString(sum[:])
	}
	return filepath.Join(d.dir, name+".json")
}

// Get returns a non-expired entry. Expired or unreadable files are removed.
func (d *diskCache) Get(key string) (Result, bool) {
	if d == nil {
		return Result{}, false
	}
	d.mu.Lock()
	defer d.mu.Unlock()

	path := d.path(key)
	data, err := os.ReadFile(path)
	if err != nil {
		return Result{}, false
	}
	var payload diskPayload
	if err := json.Unmarshal(data, &payload); err != nil {
		_ = os.Remove(path)
		return Result{}, false
	}
	if !d.now().Before(time.Unix(payload.ExpiresUnix, 0)) {
		_ = os.Remove(path)
		return Result{}, false
	}
	return Result{
		Text:           payload.Text,
		DetectedSource: payload.DetectedSource,
		Target:         payload.Target,
	}, true
}

// Put writes one entry and evicts the oldest files when the directory is over
// capacity. The write is atomic via a temporary sibling file.
func (d *diskCache) Put(key string, result Result, expires time.Time) error {
	if d == nil {
		return nil
	}
	d.mu.Lock()
	defer d.mu.Unlock()

	if err := os.MkdirAll(d.dir, 0o755); err != nil {
		return err
	}
	body, err := json.Marshal(diskPayload{
		Text:           result.Text,
		DetectedSource: result.DetectedSource,
		Target:         result.Target,
		ExpiresUnix:    expires.Unix(),
	})
	if err != nil {
		return err
	}
	final := d.path(key)
	temporary := final + ".tmp"
	if err := os.WriteFile(temporary, body, 0o644); err != nil {
		return err
	}
	if err := os.Rename(temporary, final); err != nil {
		_ = os.Remove(temporary)
		return err
	}
	d.evictLocked()
	return nil
}

// Touch refreshes the file modification time so eviction keeps hot keys.
func (d *diskCache) Touch(key string) {
	if d == nil {
		return
	}
	d.mu.Lock()
	defer d.mu.Unlock()
	now := d.now()
	_ = os.Chtimes(d.path(key), now, now)
}

// Len counts JSON entries currently on disk.
func (d *diskCache) Len() int {
	if d == nil {
		return 0
	}
	d.mu.Lock()
	defer d.mu.Unlock()
	entries, err := os.ReadDir(d.dir)
	if err != nil {
		return 0
	}
	count := 0
	for _, entry := range entries {
		if !entry.IsDir() && cacheFileName.MatchString(entry.Name()) {
			count++
		}
	}
	return count
}

func (d *diskCache) evictLocked() {
	entries, err := os.ReadDir(d.dir)
	if err != nil {
		return
	}
	type item struct {
		path string
		mod  time.Time
	}
	files := make([]item, 0, len(entries))
	for _, entry := range entries {
		if entry.IsDir() || !strings.HasSuffix(entry.Name(), ".json") {
			continue
		}
		info, err := entry.Info()
		if err != nil {
			continue
		}
		files = append(files, item{
			path: filepath.Join(d.dir, entry.Name()),
			mod:  info.ModTime(),
		})
	}
	if len(files) <= d.max {
		return
	}
	sort.Slice(files, func(i, j int) bool { return files[i].mod.Before(files[j].mod) })
	extra := len(files) - d.max
	for i := 0; i < extra; i++ {
		_ = os.Remove(files[i].path)
	}
}

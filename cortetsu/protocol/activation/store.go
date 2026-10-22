// Package activation records explicit per-domain consent bound to one session.
// A second graphical session never inherits the first one's writer authority.
package activation

import (
	"bytes"
	"encoding/json"
	"errors"
	"github.com/DilanRC/Cortetsu/cortetsu/protocol/execv1"
	"os"
	"path/filepath"
	"regexp"
	"syscall"
	"time"
)

type Config struct {
	Schema    int               `json:"schema"`
	Owners    map[string]string `json:"owners"`
	Overrides map[string]int64  `json:"overrides"`
}
type Store struct{ Root string }

var sessionID = regexp.MustCompile(`^[A-Za-z0-9][A-Za-z0-9_.:-]{0,127}$`)

func ValidSession(session string) bool { return sessionID.MatchString(session) }

var Domains = map[string]bool{"notifications": true, "gamemode": true, "power": true, "display": true}

func DefaultStore() Store {
	config := os.Getenv("XDG_CONFIG_HOME")
	if config == "" {
		config = filepath.Join(os.Getenv("HOME"), ".config")
	}
	return Store{Root: filepath.Join(config, "cortetsu", "coordinator")}
}
func privateDir(path string) error {
	if !filepath.IsAbs(path) {
		return errors.New("PERMISSION_DENIED")
	}
	m, err := os.Lstat(path)
	if err != nil {
		return err
	}
	st, ok := m.Sys().(*syscall.Stat_t)
	if !m.IsDir() || m.Mode()&os.ModeSymlink != 0 || m.Mode().Perm() != 0700 || !ok || st.Uid != uint32(os.Getuid()) {
		return errors.New("PERMISSION_DENIED")
	}
	return nil
}
func (s Store) Read() (Config, error) {
	c := Config{Schema: 1, Owners: map[string]string{}, Overrides: map[string]int64{}}
	if err := privateDir(s.Root); err != nil {
		if errors.Is(err, os.ErrNotExist) {
			return c, nil
		}
		return c, err
	}
	path := filepath.Join(s.Root, "activation.json")
	fd, err := syscall.Open(path, syscall.O_RDONLY|syscall.O_NOFOLLOW|syscall.O_CLOEXEC, 0)
	if errors.Is(err, os.ErrNotExist) {
		return c, nil
	}
	if err != nil {
		return c, errors.New("PERMISSION_DENIED")
	}
	f := os.NewFile(uintptr(fd), path)
	defer f.Close()
	m, err := f.Stat()
	if err != nil || !m.Mode().IsRegular() || m.Mode().Perm() != 0600 || m.Size() > 65536 {
		return c, errors.New("INVALID_REQUEST")
	}
	raw := make([]byte, m.Size())
	if _, err = f.ReadAt(raw, 0); err != nil {
		return c, errors.New("INVALID_REQUEST")
	}
	if _, err = execv1.Canonicalize(raw); err != nil {
		return c, errors.New("INVALID_REQUEST")
	}
	decoder := json.NewDecoder(bytes.NewReader(raw))
	decoder.DisallowUnknownFields()
	if err = decoder.Decode(&c); err != nil || c.Schema != 1 || len(c.Owners) > 4 || len(c.Overrides) > 4 {
		return c, errors.New("INVALID_REQUEST")
	}
	for d, s := range c.Owners {
		if !Domains[d] || !sessionID.MatchString(s) {
			return c, errors.New("INVALID_REQUEST")
		}
	}
	for d, u := range c.Overrides {
		if !Domains[d] || u < 0 {
			return c, errors.New("INVALID_REQUEST")
		}
	}
	if c.Owners == nil {
		c.Owners = map[string]string{}
	}
	if c.Overrides == nil {
		c.Overrides = map[string]int64{}
	}
	return c, nil
}
func (s Store) update(fn func(*Config) error) error {
	if !filepath.IsAbs(s.Root) {
		return errors.New("PERMISSION_DENIED")
	}
	if err := os.MkdirAll(s.Root, 0700); err != nil {
		return err
	}
	if err := privateDir(s.Root); err != nil {
		return err
	}
	fd, err := syscall.Open(filepath.Join(s.Root, "activation.lock"), syscall.O_WRONLY|syscall.O_CREAT|syscall.O_NOFOLLOW|syscall.O_CLOEXEC, 0600)
	if err != nil {
		return err
	}
	f := os.NewFile(uintptr(fd), "activation.lock")
	defer f.Close()
	if err = syscall.Flock(fd, syscall.LOCK_EX); err != nil {
		return err
	}
	defer syscall.Flock(fd, syscall.LOCK_UN)
	c, err := s.Read()
	if err != nil {
		return err
	}
	if err = fn(&c); err != nil {
		return err
	}
	raw, err := json.Marshal(c)
	if err != nil {
		return err
	}
	tmp, err := os.CreateTemp(s.Root, ".activation-")
	if err != nil {
		return err
	}
	defer os.Remove(tmp.Name())
	if _, err = tmp.Write(append(raw, '\n')); err == nil {
		err = tmp.Sync()
	}
	closeErr := tmp.Close()
	if err == nil {
		err = closeErr
	}
	if err != nil {
		return err
	}
	if err = os.Rename(tmp.Name(), filepath.Join(s.Root, "activation.json")); err != nil {
		return err
	}
	dir, err := os.Open(s.Root)
	if err != nil {
		return err
	}
	defer dir.Close()
	return dir.Sync()
}
func (s Store) Set(domain, session string, enabled bool) error {
	if !Domains[domain] || !sessionID.MatchString(session) {
		return errors.New("INVALID_REQUEST")
	}
	return s.update(func(c *Config) error {
		if old, ok := c.Owners[domain]; ok && old != session {
			return errors.New("SESSION_MISMATCH")
		}
		if enabled {
			c.Owners[domain] = session
		} else {
			delete(c.Owners, domain)
		}
		return nil
	})
}

// Revoke removes only the authorization shown to the user. Checking the
// expected owner inside update's lock prevents a stale UI from revoking a
// different session that acquired the domain after that snapshot was read.
// It does not transfer ownership or discard an existing manual pause.
func (s Store) Revoke(domain, expectedOwner string) error {
	if !Domains[domain] || !ValidSession(expectedOwner) {
		return errors.New("INVALID_REQUEST")
	}
	return s.update(func(c *Config) error {
		if c.Owners[domain] != expectedOwner {
			return errors.New("SESSION_MISMATCH")
		}
		delete(c.Owners, domain)
		return nil
	})
}
func (s Store) Override(domain string, until int64) error {
	if !Domains[domain] || until < 0 || until > time.Now().Add(7*24*time.Hour).UnixMilli() {
		return errors.New("INVALID_REQUEST")
	}
	return s.update(func(c *Config) error { c.Overrides[domain] = until; return nil })
}

// OverrideForSession performs authorization and the pause update in the same
// critical section. Reading first in the CLI could authorize a former owner.
func (s Store) OverrideForSession(domain, session string, until int64) error {
	if !Domains[domain] || !ValidSession(session) || until < 0 || until > time.Now().Add(7*24*time.Hour).UnixMilli() {
		return errors.New("INVALID_REQUEST")
	}
	return s.update(func(c *Config) error {
		if owner := c.Owners[domain]; owner != "" && owner != session {
			return errors.New("SESSION_MISMATCH")
		}
		c.Overrides[domain] = until
		return nil
	})
}

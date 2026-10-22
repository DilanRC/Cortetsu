package activation

import (
	"os"
	"path/filepath"
	"testing"
	"time"
)

func TestConsentIsExplicitPrivateAndBoundToOneSession(t *testing.T) {
	s := Store{Root: filepath.Join(t.TempDir(), "coordinator")}
	initial, err := s.Read()
	if err != nil || len(initial.Owners) != 0 {
		t.Fatal(initial, err)
	}
	if _, err := os.Stat(s.Root); !os.IsNotExist(err) {
		t.Fatal("read created state")
	}
	if err := s.Set("notifications", "one", true); err != nil {
		t.Fatal(err)
	}
	c, err := s.Read()
	if err != nil || c.Owners["notifications"] != "one" {
		t.Fatal(c, err)
	}
	if err := s.Set("notifications", "two", false); err == nil {
		t.Fatal("other session disabled owner")
	}
	if err := s.Set("notifications", "two", true); err == nil {
		t.Fatal("other session stole owner")
	}
	if err := s.Set("notifications", "one", false); err != nil {
		t.Fatal(err)
	}
	if err := s.Set("notifications", "two", true); err != nil {
		t.Fatal(err)
	}
	m, _ := os.Stat(filepath.Join(s.Root, "activation.json"))
	if m.Mode().Perm() != 0600 {
		t.Fatal(m.Mode())
	}
}

func TestRevokeRequiresExactExpectedOwnerAndKeepsDomainDisabled(t *testing.T) {
	s := Store{Root: filepath.Join(t.TempDir(), "coordinator")}
	if err := s.Set("notifications", "expired-session", true); err != nil {
		t.Fatal(err)
	}
	if err := s.Set("power", "other-domain-session", true); err != nil {
		t.Fatal(err)
	}
	until := time.Now().Add(time.Hour).UnixMilli()
	if err := s.Override("notifications", until); err != nil {
		t.Fatal(err)
	}
	if err := s.Revoke("notifications", "different-session"); err == nil || err.Error() != "SESSION_MISMATCH" {
		t.Fatal(err)
	}
	c, err := s.Read()
	if err != nil || c.Owners["notifications"] != "expired-session" {
		t.Fatal(c, err)
	}
	if err := s.Revoke("notifications", "expired-session"); err != nil {
		t.Fatal(err)
	}
	c, err = s.Read()
	if err != nil || c.Owners["notifications"] != "" || c.Owners["power"] != "other-domain-session" || c.Overrides["notifications"] != until {
		t.Fatal(c, err)
	}
	// Revocation grants no authority to the caller; a separate enable is needed.
	if err := s.Set("notifications", "new-session", true); err != nil {
		t.Fatal(err)
	}
	if err := s.Revoke("notifications", "expired-session"); err == nil || err.Error() != "SESSION_MISMATCH" {
		t.Fatal(err)
	}
	c, err = s.Read()
	if err != nil || c.Owners["notifications"] != "new-session" {
		t.Fatal(c, err)
	}
}

func TestRevokeChecksCurrentOwnerInsideUpdateLock(t *testing.T) {
	s := Store{Root: filepath.Join(t.TempDir(), "coordinator")}
	if err := s.Set("power", "expired-session", true); err != nil {
		t.Fatal(err)
	}
	entered, release := make(chan struct{}), make(chan struct{})
	changed := make(chan error, 1)
	go func() {
		changed <- s.update(func(c *Config) error {
			c.Owners["power"] = "new-session"
			close(entered)
			<-release
			return nil
		})
	}()
	<-entered
	revoked := make(chan error, 1)
	go func() { revoked <- s.Revoke("power", "expired-session") }()
	select {
	case err := <-revoked:
		close(release)
		t.Fatalf("revoke bypassed update lock: %v", err)
	case <-time.After(30 * time.Millisecond):
	}
	close(release)
	if err := <-changed; err != nil {
		t.Fatal(err)
	}
	if err := <-revoked; err == nil || err.Error() != "SESSION_MISMATCH" {
		t.Fatal(err)
	}
	c, err := s.Read()
	if err != nil || c.Owners["power"] != "new-session" {
		t.Fatal(c, err)
	}
}

func TestRevokeRejectsInvalidDomainAndOwnerBeforeCreatingState(t *testing.T) {
	for _, pair := range [][2]string{{"shell.exec", "session"}, {"power", ""}, {"power", "../session"}, {"power", "--session"}} {
		s := Store{Root: filepath.Join(t.TempDir(), "coordinator")}
		if err := s.Revoke(pair[0], pair[1]); err == nil || err.Error() != "INVALID_REQUEST" {
			t.Fatal(pair, err)
		}
		if _, err := os.Stat(s.Root); !os.IsNotExist(err) {
			t.Fatal("invalid revoke created state", err)
		}
	}
}

func TestOverrideForSessionChecksOwnerInsideUpdateLock(t *testing.T) {
	s := Store{Root: filepath.Join(t.TempDir(), "coordinator")}
	if err := s.Set("power", "old-session", true); err != nil {
		t.Fatal(err)
	}
	until := time.Now().Add(time.Hour).UnixMilli()
	if err := s.OverrideForSession("power", "old-session", until); err != nil {
		t.Fatal(err)
	}
	entered, release := make(chan struct{}), make(chan struct{})
	changed := make(chan error, 1)
	go func() {
		changed <- s.update(func(c *Config) error {
			c.Owners["power"] = "new-session"
			close(entered)
			<-release
			return nil
		})
	}()
	<-entered
	overridden := make(chan error, 1)
	go func() { overridden <- s.OverrideForSession("power", "old-session", 0) }()
	select {
	case err := <-overridden:
		close(release)
		t.Fatalf("override bypassed update lock: %v", err)
	case <-time.After(30 * time.Millisecond):
	}
	close(release)
	if err := <-changed; err != nil {
		t.Fatal(err)
	}
	if err := <-overridden; err == nil || err.Error() != "SESSION_MISMATCH" {
		t.Fatal(err)
	}
	c, err := s.Read()
	if err != nil || c.Owners["power"] != "new-session" || c.Overrides["power"] != until {
		t.Fatal(c, err)
	}
	if err := s.OverrideForSession("power", "new-session", 0); err != nil {
		t.Fatal(err)
	}
	c, err = s.Read()
	if err != nil || c.Overrides["power"] != 0 {
		t.Fatal(c, err)
	}
}

func TestOverrideForSessionRejectsInvalidInputWithoutGrantingConsent(t *testing.T) {
	for _, input := range []struct {
		domain, session string
		until           int64
	}{
		{"shell.exec", "session", 0}, {"power", "", 0}, {"power", "../session", 0},
		{"power", "session", -1}, {"power", "session", time.Now().Add(8 * 24 * time.Hour).UnixMilli()},
	} {
		s := Store{Root: filepath.Join(t.TempDir(), "coordinator")}
		if err := s.OverrideForSession(input.domain, input.session, input.until); err == nil || err.Error() != "INVALID_REQUEST" {
			t.Fatal(input, err)
		}
		if _, err := os.Stat(s.Root); !os.IsNotExist(err) {
			t.Fatal("invalid override created state", err)
		}
	}
	s := Store{Root: filepath.Join(t.TempDir(), "coordinator")}
	if err := s.OverrideForSession("power", "new-session", 0); err != nil {
		t.Fatal(err)
	}
	c, err := s.Read()
	if err != nil || len(c.Owners) != 0 {
		t.Fatal("override granted consent", c, err)
	}
}
func TestUnknownDomainsAndSymlinkConfigRejected(t *testing.T) {
	s := Store{Root: filepath.Join(t.TempDir(), "coordinator")}
	if err := s.Set("shell.exec", "one", true); err == nil {
		t.Fatal("arbitrary executor enabled")
	}
	if err := os.Mkdir(s.Root, 0700); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(filepath.Join(t.TempDir(), "foreign"), filepath.Join(s.Root, "activation.json")); err != nil {
		t.Fatal(err)
	}
	if err := s.Set("power", "one", true); err == nil {
		t.Fatal("symlink followed")
	}
}

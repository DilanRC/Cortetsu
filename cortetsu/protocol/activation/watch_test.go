package activation

import (
	"context"
	"os"
	"path/filepath"
	"testing"
	"time"
)

func TestWatchDetectsConsentWithoutCreatingConfig(t *testing.T) {
	s := Store{Root: filepath.Join(t.TempDir(), "missing")}
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	changed := make(chan struct{}, 8)
	done := make(chan error, 1)
	go func() { done <- s.Watch(ctx, changed) }()
	if err := s.Set("notifications", "one", true); err != nil {
		t.Fatal(err)
	}
	select {
	case <-changed:
	case <-time.After(3 * time.Second):
		t.Fatal("consent was not observed")
	}
	cancel()
	select {
	case err := <-done:
		if err != nil {
			t.Fatal(err)
		}
	case <-time.After(time.Second):
		t.Fatal("watch did not cancel")
	}
}
func TestWatchReportsRemovalOfConsent(t *testing.T) {
	s := Store{Root: filepath.Join(t.TempDir(), "config")}
	if err := s.Set("notifications", "one", true); err != nil {
		t.Fatal(err)
	}
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	changed := make(chan struct{}, 1)
	done := make(chan error, 1)
	go func() { done <- s.Watch(ctx, changed) }()
	select {
	case <-changed:
	case <-time.After(time.Second):
		t.Fatal("watch was not armed")
	}
	if err := os.Remove(filepath.Join(s.Root, "activation.json")); err != nil {
		t.Fatal(err)
	}
	select {
	case <-changed:
	case <-time.After(time.Second):
		t.Fatal("deleting consent was not observed")
	}
	cancel()
	select {
	case <-done:
	case <-time.After(time.Second):
		t.Fatal("watch did not cancel")
	}
}

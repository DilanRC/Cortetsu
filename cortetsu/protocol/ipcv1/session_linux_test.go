//go:build linux

package ipcv1

import (
	"context"
	"encoding/json"
	"net"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func TestExplicitSessionReadOnlySnapshotAndPermissions(t *testing.T) {
	runtime := t.TempDir()
	if err := os.Chmod(runtime, 0700); err != nil {
		t.Fatal(err)
	}
	listener, err := OpenReadOnlySessionListener(runtime, "a", 18, func(domains []string) (any, error) {
		if len(domains) != 1 || domains[0] != "coordinator" {
			t.Fatalf("unexpected domains: %v", domains)
		}
		return map[string]any{"mode": "observe", "last_event_epoch": 0}, nil
	})
	if err != nil {
		t.Fatal(err)
	}
	if _, err := os.Lstat(filepath.Join(runtime, "cortetsu")); err != nil {
		t.Fatal(err)
	}
	ctx, cancel := context.WithCancel(context.Background())
	done := make(chan error, 1)
	go func() { done <- listener.Serve(ctx) }()
	defer func() {
		cancel()
		_ = listener.Close()
		select {
		case e := <-done:
			if e != nil {
				t.Error(e)
			}
		case <-time.After(time.Second * 2):
			t.Error("stuck socket server")
		}
	}()
	conn, err := net.Dial("unix", listener.Path())
	if err != nil {
		t.Fatal(err)
	}
	defer conn.Close()
	hello := strings.ReplaceAll(helloFixture, "wayland-1", "a")
	hello = strings.Replace(hello, `"session_epoch":1`, `"session_epoch":18`, 1)
	if _, err = conn.Write([]byte(hello + "\n")); err != nil {
		t.Fatal(err)
	}
	fr := NewFrameReader(conn)
	if _, err = fr.Read(); err != nil {
		t.Fatal(err)
	}
	req := strings.ReplaceAll(requestFixture, "wayland-1", "a")
	req = strings.Replace(req, `"session_epoch":1`, `"session_epoch":18`, 1)
	req = strings.Replace(req, `["power","display"]`, `["coordinator"]`, 1)
	if _, err = conn.Write([]byte(req + "\n")); err != nil {
		t.Fatal(err)
	}
	raw, err := fr.Read()
	if err != nil {
		t.Fatal(err)
	}
	var reply serverReply
	if err = json.Unmarshal(raw, &reply); err != nil {
		t.Fatal(err)
	}
	if reply.Outcome != "read" || reply.Error != nil {
		t.Fatal(reply)
	}
	// The production listener has the same mutation deny-list as the tests.
	forbidden := strings.Replace(req, `"snapshot.get"`, `"shell.exec"`, 1)
	if _, err = conn.Write([]byte(forbidden + "\n")); err != nil {
		t.Fatal(err)
	}
	raw, err = fr.Read()
	if err != nil {
		t.Fatal(err)
	}
	if err = json.Unmarshal(raw, &reply); err != nil {
		t.Fatal(err)
	}
	if reply.Outcome != "rejected" {
		t.Fatal(reply)
	}
	// Refuse a second listener in the same session, even from same uid.
	if _, err = OpenReadOnlySessionListener(runtime, "a", 19, nil); code(err) != "PERMISSION_DENIED" {
		t.Fatal(err)
	}
}

func TestReadOnlyListenerRefusesPublicRuntimeAndSymlink(t *testing.T) {
	root := t.TempDir()
	if err := os.Chmod(root, 0755); err != nil {
		t.Fatal(err)
	}
	if _, err := OpenReadOnlySessionListener(root, "a", 1, nil); code(err) != "PERMISSION_DENIED" {
		t.Fatal(err)
	}
	if err := os.Chmod(root, 0700); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(root, root+"-alias"); err != nil {
		t.Fatal(err)
	}
	if _, err := OpenReadOnlySessionListener(root+"-alias", "a", 1, nil); code(err) != "PERMISSION_DENIED" {
		t.Fatal(err)
	}
}

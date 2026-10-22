//go:build linux

package ipcv1

import (
	"context"
	"encoding/json"
	"net"
	"os"
	"strings"
	"testing"
	"time"
)

func startTestServer(t *testing.T, session string) (*TestListener, func()) {
	t.Helper()
	root := t.TempDir()
	if err := os.Chmod(root, 0700); err != nil {
		t.Fatal(err)
	}
	listener, err := OpenIsolatedListener(root, session, 1)
	if err != nil {
		t.Fatal(err)
	}
	ctx, cancel := context.WithCancel(context.Background())
	finished := make(chan error, 1)
	go func() { finished <- listener.Serve(ctx) }()
	return listener, func() {
		cancel()
		listener.Close()
		select {
		case err := <-finished:
			if err != nil {
				t.Error(err)
			}
		case <-time.After(2 * time.Second):
			t.Error("server did not stop")
		}
	}
}

func dialTestServer(t *testing.T, path string) *net.UnixConn {
	t.Helper()
	conn, err := net.DialUnix("unix", nil, &net.UnixAddr{Name: path, Net: "unix"})
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { conn.Close() })
	return conn
}

func TestSeparateUnixSessionsNoPrivilegeEscalation(t *testing.T) {
	first, stopFirst := startTestServer(t, "session-a")
	defer stopFirst()
	second, stopSecond := startTestServer(t, "session-b")
	defer stopSecond()
	if first.Path() == second.Path() {
		t.Fatal("sockets share path")
	}
	for _, tc := range []struct {
		session string
		path    string
	}{{"session-a", first.Path()}, {"session-b", second.Path()}} {
		conn := dialTestServer(t, tc.path)
		hello := strings.ReplaceAll(helloFixture, "wayland-1", tc.session)
		if _, err := conn.Write([]byte(hello + "\n")); err != nil {
			t.Fatal(err)
		}
		frame, err := NewFrameReader(conn).Read()
		if err != nil {
			t.Fatal(err)
		}
		var accepted Negotiated
		if err := json.Unmarshal(frame, &accepted); err != nil {
			t.Fatal(err)
		}
		if accepted.SessionID != tc.session {
			t.Fatal(accepted)
		}
		request := strings.ReplaceAll(requestFixture, "wayland-1", tc.session)
		if _, err := conn.Write([]byte(request + "\n")); err != nil {
			t.Fatal(err)
		}
		response, err := NewFrameReader(conn).Read()
		if err != nil {
			t.Fatal(err)
		}
		var reply serverReply
		if err := json.Unmarshal(response, &reply); err != nil {
			t.Fatal(err)
		}
		if reply.Outcome != "rejected" || reply.Error == nil || reply.Error.Code != "OWNER_UNAVAILABLE" {
			t.Fatal(reply)
		}
	}
}

func TestCannotImpersonateAnotherSession(t *testing.T) {
	server, stop := startTestServer(t, "session-a")
	defer stop()
	conn := dialTestServer(t, server.Path())
	if _, err := conn.Write([]byte(strings.ReplaceAll(helloFixture, "wayland-1", "session-b") + "\n")); err != nil {
		t.Fatal(err)
	}
	_ = conn.SetReadDeadline(time.Now().Add(time.Second))
	if _, err := NewFrameReader(conn).Read(); err == nil {
		t.Fatal("accepted cross-session hello")
	}
}

func TestSocketPermissionsAndSymlinks(t *testing.T) {
	root := t.TempDir()
	if err := os.Chmod(root, 0755); err != nil {
		t.Fatal(err)
	}
	if _, err := OpenIsolatedListener(root, "session-a", 1); code(err) != "PERMISSION_DENIED" {
		t.Fatal(err)
	}
	if err := os.Chmod(root, 0700); err != nil {
		t.Fatal(err)
	}
	s, err := OpenIsolatedListener(root, "session-a", 1)
	if err != nil {
		t.Fatal(err)
	}
	defer s.Close()
	meta, err := os.Stat(s.Path())
	if err != nil {
		t.Fatal(err)
	}
	if meta.Mode().Perm() != 0600 {
		t.Fatalf("mode %v", meta.Mode())
	}
	if _, err := OpenIsolatedListener(root, "session-a", 1); code(err) != "PERMISSION_DENIED" {
		t.Fatal("collision", err)
	}
	if _, err := OpenIsolatedListener(root, "../escape", 1); code(err) != "INVALID_REQUEST" {
		t.Fatal(err)
	}
}

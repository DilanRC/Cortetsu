//go:build linux

package observehypr

import (
	"encoding/json"
	"net"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func TestOwnerSnapshotWhitelistsCountsAndClosesConnections(t *testing.T) {
	path := filepath.Join(t.TempDir(), ".socket.sock")
	server, err := net.Listen("unix", path)
	if err != nil {
		t.Fatal(err)
	}
	defer server.Close()
	accepted := make(chan string, 3)
	go func() {
		for i := 0; i < 3; i++ {
			conn, e := server.Accept()
			if e != nil {
				return
			}
			_ = conn.SetDeadline(time.Now().Add(2 * time.Second))
			buf := make([]byte, 128)
			n, _ := conn.Read(buf)
			req := string(buf[:n])
			accepted <- req
			if req == "j/monitors" {
				_, _ = conn.Write([]byte(`[ {"name":"HDMI-A-1","disabled":false,"focused":false,"private":"WINDOW-SECRET"},{"name":"eDP-1","disabled":false,"focused":true}]`))
			} else if req == "j/workspaces" {
				_, _ = conn.Write([]byte(`[{"id":1,"name":"personal-secret"},{"id":2}]`))
			} else {
				_, _ = conn.Write([]byte(`{"fullscreen":2,"title":"DO-NOT-RETAIN","class":"personal-app","tags":["opaque*","game*"]}`))
			}
			conn.Close()
		}
	}()
	state, err := ReadOwner(path)
	if err != nil {
		t.Fatal(err)
	}
	if state.MonitorCount != 2 || state.WorkspaceCount != 2 || !state.FocusedMonitor || !state.FocusedFullscreen || !state.FocusedGame {
		t.Fatal(state)
	}
	data, err := json.Marshal(state)
	if err != nil {
		t.Fatal(err)
	}
	if strings.Contains(string(data), "WINDOW-SECRET") || strings.Contains(string(data), "personal-secret") || strings.Contains(string(data), "HDMI") || strings.Contains(string(data), "DO-NOT-RETAIN") {
		t.Fatal("raw private data leaked")
	}
	if <-accepted != "j/monitors" || <-accepted != "j/workspaces" || <-accepted != "j/activewindow" {
		t.Fatal("wrong read-only owner queries")
	}
}

func TestOwnerRejectsNonSocketAndSymlink(t *testing.T) {
	dir := t.TempDir()
	regular := filepath.Join(dir, ".socket.sock")
	if err := os.WriteFile(regular, []byte("j/monitors"), 0600); err != nil {
		t.Fatal(err)
	}
	if _, err := ReadOwner(regular); err == nil {
		t.Fatal("accepted non socket")
	}
	alias := filepath.Join(dir, ".socket2.sock")
	if err := os.Symlink(regular, alias); err != nil {
		t.Fatal(err)
	}
	if err := queryOwner(alias, "j/monitors", &struct{}{}); err == nil {
		t.Fatal("accepted symlink")
	}
	if _, err := CommandSocketFromEvent("/tmp/other.sock"); err == nil {
		t.Fatal("accepted unknown socket")
	}
	if p, err := CommandSocketFromEvent(alias); err != nil || p != regular {
		t.Fatal(p, err)
	}
}

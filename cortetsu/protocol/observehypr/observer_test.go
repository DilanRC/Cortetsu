package observehypr

import (
	"bytes"
	"context"
	"encoding/json"
	"net"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"
)

func TestWhitelistDropsTitlesAddressesAndPasswords(t *testing.T) {
	now := time.Unix(200, 0)
	good, ok := Normalize("openwindow>>0xABC,1,kitty,secret BANK password", "s1", 1, 2, now)
	if !ok || good.Type != "window_opened" || good.Session != "s1" || good.Sequence != 2 {
		t.Fatalf("unexpected: %+v", good)
	}
	raw, _ := json.Marshal(good)
	for _, token := range []string{"BANK", "secret", "0xABC", "kitty"} {
		if bytes.Contains(raw, []byte(token)) {
			t.Fatalf("leaked %s", token)
		}
	}
	for _, kind := range []string{"windowtitlev2>>secret", "submapsecret>>secret", "exec>>rm -rf /", "workspace", "\x00>>data"} {
		if _, ok := Normalize(kind, "s1", 1, 2, now); ok {
			t.Fatalf("accepted %q", kind)
		}
	}
}

func TestSocketPathRejectsTraversal(t *testing.T) {
	for _, tc := range []struct{ dir, sig string }{{"/tmp", "../evil"}, {"relative", "s1"}, {"/tmp", "a/b"}, {"/tmp", ""}} {
		if _, err := SocketPath(tc.dir, tc.sig); err == nil {
			t.Fatalf("accepted: %v", tc)
		}
	}
	if _, err := SocketPath("/run/user/1000", "s1-arch"); err != nil {
		t.Fatal(err)
	}
}

type syncOutput struct {
	mu sync.Mutex
	b  bytes.Buffer
}

func (o *syncOutput) Write(p []byte) (int, error) {
	o.mu.Lock()
	defer o.mu.Unlock()
	return o.b.Write(p)
}
func (o *syncOutput) String() string { o.mu.Lock(); defer o.mu.Unlock(); return o.b.String() }

func TestReconnectResyncAndNoRawPayload(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "socket2.sock")
	l, err := net.Listen("unix", path)
	if err != nil {
		t.Fatal(err)
	}
	defer l.Close()
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()
	var server sync.WaitGroup
	server.Add(1)
	go func() {
		defer server.Done()
		for n := 0; n < 2; n++ {
			c, err := l.Accept()
			if err != nil {
				return
			}
			_, _ = c.Write([]byte("openwindow>>secret title and password\nworkspacev2>>foo\n"))
			_ = c.Close()
		}
	}()
	out := &syncOutput{}
	result := make(chan error, 1)
	go func() {
		result <- (Observer{Session: "s1", Socket: path, ReconnectDelay: 10 * time.Millisecond}).Run(ctx, out)
	}()
	deadline := time.After(time.Second)
	for {
		if strings.Count(out.String(), `"type":"resync_required"`) >= 2 && strings.Count(out.String(), `"workspace_changed"`) >= 2 {
			cancel()
			break
		}
		select {
		case <-deadline:
			t.Fatalf("observer did not reconnect: %s", out.String())
		default:
			time.Sleep(time.Millisecond * 10)
		}
	}
	if err := <-result; err != nil {
		t.Fatal(err)
	}
	server.Wait()
	content := out.String()
	if strings.Contains(content, "password") || strings.Contains(content, "secret") || strings.Contains(content, "title") {
		t.Fatalf("leaked untrusted event: %s", content)
	}
	lines := strings.Split(strings.TrimSpace(content), "\n")
	var oldEpoch uint64
	for _, line := range lines {
		var o Output
		if err := json.Unmarshal([]byte(line), &o); err != nil {
			t.Fatal(err)
		}
		if o.Type == "resync_required" {
			if o.Epoch <= oldEpoch {
				t.Fatal("epoch did not advance")
			}
			oldEpoch = o.Epoch
		}
	}
	if oldEpoch < 2 {
		t.Fatalf("expected 2 epochs, got %d", oldEpoch)
	}
}

func TestSeparateSessionIdentity(t *testing.T) {
	at := time.Unix(200, 0)
	a, _ := Normalize("fullscreen>>1", "session_a", 1, 1, at)
	b, _ := Normalize("fullscreen>>1", "session_b", 1, 1, at)
	if a.Session == b.Session || a.Session != "session_a" || b.Session != "session_b" {
		t.Fatal("session identity collision")
	}
}

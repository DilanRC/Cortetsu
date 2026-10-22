//go:build linux

package ipcv1

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net"
	"os"
	"path/filepath"
	"syscall"
	"time"

	"github.com/DilanRC/Cortetsu/cortetsu/protocol/execclient"
	"github.com/DilanRC/Cortetsu/cortetsu/protocol/policy"
)

const (
	maxClients               = 8
	maxRequestsPerConnection = 32
	clientDeadline           = 30 * time.Second
)

// TestListener implements the first-party, read-only IPC adapter *only* for
// isolated tests. No systemd socket or production service launches it.
// It intentionally cannot invoke Rust, Hyprland or any privileged operation.
// SnapshotSource is a safe, bounded read-only observation source. It must never
// include window titles, secrets, addresses, or raw Hyprland event payloads.
type SnapshotSource func(domains []string) (any, error)

type TestListener struct {
	l        *net.UnixListener
	path     string
	session  string
	epoch    uint64
	snapshot SnapshotSource
	rules    []policy.Rule
	rust     *execclient.Client
}

// SetSnapshotSource configures the source before Serve starts. It must not be
// changed while Serve is running (it is intentionally not hot-swappable).
func (s *TestListener) SetSnapshotSource(source SnapshotSource) {
	if s != nil {
		s.snapshot = source
	}
}

// SetRules supplies a static, validated read-only policy catalog before the
// listener starts. The catalog is never mutated by IPC clients.
// SetVerifier enables only the read-only Rust system.verify operation.
// The executable is configured by a trusted startup option, never by IPC.
func (s *TestListener) SetVerifier(client *execclient.Client) error {
	if s == nil {
		return fail("INVALID_REQUEST")
	}
	if client != nil {
		if err := client.CheckBinary(); err != nil {
			return fail("OWNER_UNAVAILABLE")
		}
	}
	s.rust = client
	return nil
}

func (s *TestListener) SetRules(rules []policy.Rule) error {
	if s == nil || len(rules) > 128 {
		return fail("INVALID_REQUEST")
	}
	ids := map[string]bool{}
	for _, r := range rules {
		if err := r.Validate(); err != nil || ids[r.ID] {
			return fail("INVALID_REQUEST")
		}
		ids[r.ID] = true
	}
	s.rules = append([]policy.Rule(nil), rules...)
	return nil
}

func (s *TestListener) Path() string {
	if s == nil {
		return ""
	}
	return s.path
}

func OpenIsolatedListener(privateRoot, session string, epoch uint64) (*TestListener, error) {
	if !id.MatchString(session) || epoch == 0 {
		return nil, fail("INVALID_REQUEST")
	}
	meta, err := os.Lstat(privateRoot)
	if err != nil || !meta.IsDir() || meta.Mode()&os.ModeSymlink != 0 || meta.Mode().Perm()&0077 != 0 {
		return nil, fail("PERMISSION_DENIED")
	}
	stat, ok := meta.Sys().(*syscall.Stat_t)
	if !ok || stat.Uid != uint32(os.Getuid()) {
		return nil, fail("PERMISSION_DENIED")
	}
	name := filepath.Join(privateRoot, "cortetsu-"+session+".sock")
	if len(name) >= 104 {
		return nil, fail("INVALID_REQUEST")
	}
	if _, err := os.Lstat(name); !errors.Is(err, os.ErrNotExist) {
		return nil, fail("PERMISSION_DENIED")
	}
	addr := &net.UnixAddr{Name: name, Net: "unix"}
	listener, err := net.ListenUnix("unix", addr)
	if err != nil {
		return nil, fail("OWNER_UNAVAILABLE")
	}
	if err := os.Chmod(name, 0600); err != nil {
		listener.Close()
		return nil, fail("PERMISSION_DENIED")
	}
	return &TestListener{l: listener, path: name, session: session, epoch: epoch}, nil
}

func (s *TestListener) Close() error {
	if s == nil || s.l == nil {
		return nil
	}
	return s.l.Close()
}

func peerUID(conn *net.UnixConn) (uint32, error) {
	raw, err := conn.SyscallConn()
	if err != nil {
		return 0, err
	}
	var cred *syscall.Ucred
	var inner error
	if err := raw.Control(func(fd uintptr) {
		cred, inner = syscall.GetsockoptUcred(int(fd), syscall.SOL_SOCKET, syscall.SO_PEERCRED)
	}); err != nil {
		return 0, err
	}
	if inner != nil {
		return 0, inner
	}
	if cred == nil {
		return 0, errors.New("missing peer credentials")
	}
	return cred.Uid, nil
}

func (s *TestListener) Serve(ctx context.Context) error {
	if s == nil || s.l == nil {
		return fail("INVALID_REQUEST")
	}
	stop := context.AfterFunc(ctx, func() { _ = s.Close() })
	defer stop()
	permits := make(chan struct{}, maxClients)
	for {
		conn, err := s.l.AcceptUnix()
		if err != nil {
			if ctx.Err() != nil || errors.Is(err, net.ErrClosed) {
				return nil
			}
			return fmt.Errorf("socket accept failed: %w", err)
		}
		select {
		case permits <- struct{}{}:
			go func() { defer func() { <-permits }(); s.handle(conn) }()
		default:
			_ = conn.Close()
		}
	}
}

type serverReply struct {
	Protocol string  `json:"protocol"`
	Version  Version `json:"version"`
	Type     string  `json:"type"`
	ID       string  `json:"id"`
	Outcome  string  `json:"outcome"`
	Error    *Error  `json:"error,omitempty"`
	Body     any     `json:"body"`
}

func (s *TestListener) handle(conn *net.UnixConn) {
	defer conn.Close()
	uid, err := peerUID(conn)
	if err != nil || uid != uint32(os.Getuid()) {
		return
	}
	_ = conn.SetDeadline(time.Now().Add(clientDeadline))
	frames := NewFrameReader(conn)
	helloFrame, err := frames.Read()
	if err != nil {
		return
	}
	hello, err := ParseHello(helloFrame)
	if err != nil {
		return
	}
	accepted, err := Negotiate(hello, s.session, s.epoch)
	if err != nil {
		return
	}
	if err := WriteFrame(conn, accepted); err != nil {
		return
	}
	engine := policy.NewEngine()
	traces := map[string][]policy.Decision{}
	for i := 0; i < maxRequestsPerConnection; i++ {
		_ = conn.SetDeadline(time.Now().Add(clientDeadline))
		frame, err := frames.Read()
		if err != nil {
			return
		}
		request, err := ParseRequest(frame, accepted)
		if err != nil {
			// Do not echo untrusted request IDs or request data on error.
			_ = WriteFrame(conn, serverReply{Protocol: Protocol, Version: Version{Major: Major, Minor: Minor}, Type: "response", Outcome: "rejected", Error: &Error{Code: "INVALID_REQUEST"}, Body: map[string]any{}})
			return
		}
		reply := serverReply{Protocol: Protocol, Version: Version{Major: Major, Minor: Minor}, Type: "response", ID: request.ID, Outcome: "rejected", Error: &Error{Code: "OWNER_UNAVAILABLE"}, Body: map[string]any{}}
		switch request.Op {
		case "system.verify":
			if s.rust != nil {
				body, err := s.rust.Verify(context.Background(), request.ID, time.Duration(request.DeadlineMs)*time.Millisecond)
				if err == nil {
					reply.Outcome = "read"
					reply.Error = nil
					reply.Body = body
				}
			}
		case "snapshot.get":
			if s.snapshot != nil {
				var body struct {
					Domains []string `json:"domains"`
				}
				if json.Unmarshal(request.Body, &body) == nil {
					if result, err := s.snapshot(body.Domains); err == nil {
						reply.Outcome = "read"
						reply.Error = nil
						reply.Body = result
					}
				}
			}
		case "policy.list":
			reply.Outcome = "read"
			reply.Error = nil
			records := append([]policy.Rule(nil), s.rules...)
			reply.Body = map[string]any{"rules": records}
		case "policy.simulate":
			var body struct {
				AtUnixMs  int64                   `json:"at_unix_ms"`
				Event     policy.Event            `json:"event"`
				Rules     []policy.Rule           `json:"rules"`
				Overrides []policy.ManualOverride `json:"overrides"`
			}
			if err := json.Unmarshal(request.Body, &body); err == nil {
				decisions, err := engine.Evaluate(body.AtUnixMs, body.Event, body.Rules, body.Overrides)
				if err == nil {
					reply.Outcome = "simulated"
					reply.Error = nil
					// Keep at most 16 bounded traces per connection; never
					// persist raw event metadata or unbounded policy details.
					if len(decisions) <= 64 {
						if len(traces) >= 16 {
							traces = map[string][]policy.Decision{}
						}
						traces[request.ID] = append([]policy.Decision(nil), decisions...)
					}
					reply.Body = map[string]any{"trace_id": request.ID, "decisions": decisions}
				}
			}
		case "explain.get":
			var args struct {
				TraceID string `json:"trace_id"`
			}
			if json.Unmarshal(request.Body, &args) == nil {
				if decisions, ok := traces[args.TraceID]; ok {
					reply.Outcome = "read"
					reply.Error = nil
					reply.Body = map[string]any{"trace_id": args.TraceID, "decisions": decisions}
				}
			}
		}
		if err := WriteFrame(conn, reply); err != nil {
			return
		}
	}
}

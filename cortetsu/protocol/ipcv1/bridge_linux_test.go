//go:build linux

package ipcv1

import (
	"context"
	"encoding/json"
	"fmt"
	"net"
	"os"
	"testing"
	"time"

	"github.com/DilanRC/Cortetsu/cortetsu/protocol/execclient"
	"github.com/DilanRC/Cortetsu/cortetsu/protocol/policy"
)

func TestReadOnlyBridgeCatalogSimulationAndExplanation(t *testing.T) {
	dir := t.TempDir()
	if err := os.Chmod(dir, 0700); err != nil {
		t.Fatal(err)
	}
	listener, err := OpenIsolatedListener(dir, "session-a", 73)
	if err != nil {
		t.Fatal(err)
	}
	listener.SetSnapshotSource(func(domains []string) (any, error) {
		if len(domains) > 0 && domains[0] != "coordinator" {
			return nil, fmt.Errorf("denied")
		}
		return map[string]any{"mode": "observe", "authoritative": false, "stream_stale": true}, nil
	})
	rules := []policy.Rule{{ID: "r1", Enabled: true, Mode: "simulate", Domain: "hyprland", EventType: "workspace_changed", Resource: "power", Operation: "power.profile.set", Priority: 4, TTLms: 10000}}
	if err := listener.SetRules(rules); err != nil {
		t.Fatal(err)
	}
	ctx, cancel := context.WithCancel(context.Background())
	ended := make(chan error, 1)
	go func() { ended <- listener.Serve(ctx) }()
	defer func() { cancel(); _ = listener.Close(); <-ended }()
	c, err := net.Dial("unix", listener.Path())
	if err != nil {
		t.Fatal(err)
	}
	defer c.Close()
	if err := c.SetDeadline(time.Now().Add(3 * time.Second)); err != nil {
		t.Fatal(err)
	}
	if err := WriteFrame(c, map[string]any{"type": "hello", "protocol": Protocol, "version": Version{Major: 1}, "client": "cortetsu-shell", "client_version": "2.0", "session_id": "session-a", "session_epoch": 73, "capabilities": []string{"snapshot", "policy.observe", "policy.simulate", "explain"}}); err != nil {
		t.Fatal(err)
	}
	frames := NewFrameReader(c)
	first, err := frames.Read()
	if err != nil {
		t.Fatal(err)
	}
	var ack Negotiated
	if err := json.Unmarshal(first, &ack); err != nil {
		t.Fatal(err)
	}
	if ack.SessionEpoch != 73 {
		t.Fatal(ack)
	}
	request := func(op string, body any, id string) map[string]any {
		return map[string]any{"type": "request", "protocol": Protocol, "version": Version{Major: 1}, "id": id, "op": op, "session_id": "session-a", "session_epoch": 73, "deadline_ms": 5000, "body": body}
	}
	send := func(req map[string]any) map[string]any {
		t.Helper()
		if err := WriteFrame(c, req); err != nil {
			t.Fatal(err)
		}
		raw, err := frames.Read()
		if err != nil {
			t.Fatal(err)
		}
		var reply map[string]any
		if err := json.Unmarshal(raw, &reply); err != nil {
			t.Fatal(err)
		}
		if reply["protocol"] != Protocol {
			t.Fatalf("unversioned response: %v", reply)
		}
		return reply
	}
	const firstID = "123e4567-e89b-12d3-a456-426614174000"
	const traceID = "123e4567-e89b-12d3-a456-426614174001"
	snap := send(request("snapshot.get", map[string]any{"domains": []string{"coordinator"}}, firstID))
	if snap["outcome"] != "read" {
		t.Fatalf("missing snapshot: %v", snap)
	}
	list := send(request("policy.list", map[string]any{}, firstID))
	cat := list["body"].(map[string]any)["rules"].([]any)
	if list["outcome"] != "read" || len(cat) != 1 {
		t.Fatalf("bad catalog: %v", list)
	}
	sim := send(request("policy.simulate", map[string]any{"at_unix_ms": 1100, "event": map[string]any{"domain": "hyprland", "type": "workspace_changed", "emitted_at_unix_ms": 1000}, "rules": rules}, traceID))
	if sim["outcome"] != "simulated" {
		t.Fatalf("not simulated: %v", sim)
	}
	explanation := send(request("explain.get", map[string]any{"trace_id": traceID}, firstID))
	if explanation["outcome"] != "read" {
		t.Fatalf("trace unavailable: %v", explanation)
	}
	// A mutation is never added to the read-only request allowlist.
	blocked := send(request("display.profile.preview", map[string]any{}, firstID))
	if blocked["outcome"] != "rejected" {
		t.Fatalf("mutation allowed: %v", blocked)
	}
}

func TestRuleCatalogNeverAcceptsDuplicateOrUnsupportedOwners(t *testing.T) {
	root := t.TempDir()
	if err := os.Chmod(root, 0700); err != nil {
		t.Fatal(err)
	}
	l, err := OpenIsolatedListener(root, "a", 1)
	if err != nil {
		t.Fatal(err)
	}
	defer l.Close()
	valid := policy.Rule{ID: "r1", Mode: "simulate", Domain: "hyprland", EventType: "workspace_changed", Resource: "power", Operation: "power.profile.set", TTLms: 1000}
	if err := l.SetRules([]policy.Rule{valid, valid}); err == nil {
		t.Fatal("duplicate accepted")
	}
	bad := valid
	bad.ID = "other"
	bad.Operation = "shell.exec"
	if err := l.SetRules([]policy.Rule{bad}); err == nil {
		t.Fatal("command accepted")
	}
}

func TestReadOnlyRustVerificationIsOptIn(t *testing.T) {
	root := t.TempDir()
	if err := os.Chmod(root, 0700); err != nil {
		t.Fatal(err)
	}
	binary := root + "/trusted-rescue"
	const requestID = "00000000-0000-0000-0000-000000000012"
	body := `{"protocol":"cortetsu.exec","version":{"major":1,"minor":0},"request_id":"` + requestID + `","outcome":"read","verified":true,"body":{"revision":"test","shell":"test"}}`
	if err := os.WriteFile(binary, []byte("#!/bin/sh\nprintf '%s\\n' '"+body+"'\n"), 0700); err != nil {
		t.Fatal(err)
	}
	server, err := OpenIsolatedListener(root, "test", 1)
	if err != nil {
		t.Fatal(err)
	}
	if err := server.SetVerifier(&execclient.Client{Binary: binary}); err != nil {
		t.Fatal(err)
	}
	ctx, cancel := context.WithCancel(context.Background())
	stopped := make(chan error, 1)
	go func() { stopped <- server.Serve(ctx) }()
	defer func() { cancel(); server.Close(); <-stopped }()
	conn, err := net.Dial("unix", server.Path())
	if err != nil {
		t.Fatal(err)
	}
	defer conn.Close()
	_ = conn.SetDeadline(time.Now().Add(3 * time.Second))
	if err := WriteFrame(conn, map[string]any{"type": "hello", "protocol": Protocol, "version": Version{Major: 1}, "client": "test", "client_version": "1", "session_id": "test", "session_epoch": 1, "capabilities": []string{"system.verify"}}); err != nil {
		t.Fatal(err)
	}
	frames := NewFrameReader(conn)
	if _, err := frames.Read(); err != nil {
		t.Fatal(err)
	}
	if err := WriteFrame(conn, map[string]any{"type": "request", "protocol": Protocol, "version": Version{Major: 1}, "id": requestID, "op": "system.verify", "session_id": "test", "session_epoch": 1, "deadline_ms": 5000, "body": map[string]any{}}); err != nil {
		t.Fatal(err)
	}
	raw, err := frames.Read()
	if err != nil {
		t.Fatal(err)
	}
	var reply map[string]any
	if err := json.Unmarshal(raw, &reply); err != nil {
		t.Fatal(err)
	}
	if reply["outcome"] != "read" || reply["body"].(map[string]any)["revision"] != "test" {
		t.Fatalf("Rust read adapter failed: %s", raw)
	}
}

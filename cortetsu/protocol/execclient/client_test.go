package execclient

import (
	"context"
	"encoding/json"
	"fmt"
	"github.com/DilanRC/Cortetsu/cortetsu/protocol/execv1"
	"io"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

const requestID = "00000000-0000-0000-0000-000000000001"

func child(t *testing.T, body string) Client {
	t.Helper()
	dir := t.TempDir()
	path := filepath.Join(dir, "trusted-rescue")
	if err := os.WriteFile(path, []byte("#!/bin/sh\nprintf '%s\\n' '"+body+"'\n"), 0700); err != nil {
		t.Fatal(err)
	}
	return Client{Binary: path}
}

func TestTypedMutationRequiresVerifiedMatchingOutcome(t *testing.T) {
	revision := uint64(0)
	r := execv1.Request{Protocol: execv1.Protocol, Version: execv1.Version{Major: 1}, RequestID: requestID,
		Operation: "notifications.dnd.set", DeadlineMs: 1000, ExpectedRevision: &revision,
		IdempotencyKey: "00000000-0000-4000-8000-000000000009", Arguments: json.RawMessage(`{"enabled":true}`)}
	client := child(t, fmt.Sprintf(`{"protocol":"cortetsu.exec","version":{"major":1,"minor":0},"request_id":"%s","outcome":"applied","verified":true,"body":{"dnd":true,"revision":1}}`, requestID))
	result, err := client.Execute(context.Background(), r)
	if err != nil || result.Outcome != "applied" {
		t.Fatalf("typed mutation not executed: %v", err)
	}
}

func TestPinnedReadOnlyRustExecutor(t *testing.T) {
	reply := fmt.Sprintf(`{"protocol":"cortetsu.exec","version":{"major":1,"minor":0},"request_id":"%s","outcome":"read","verified":true,"body":{"revision":"test"}}`, requestID)
	client := child(t, reply)
	body, err := client.Verify(context.Background(), requestID, 2*time.Second)
	if err != nil || !strings.Contains(string(body), `"revision":"test"`) {
		t.Fatalf("read: %q %v", body, err)
	}
}

func TestRejectsUnverifiedSuccessAndWrongRequestID(t *testing.T) {
	for name, reply := range map[string]string{
		"false-success": fmt.Sprintf(`{"protocol":"cortetsu.exec","version":{"major":1,"minor":0},"request_id":"%s","outcome":"read","verified":false,"body":{}}`, requestID),
		"mismatched-id": `{"protocol":"cortetsu.exec","version":{"major":1,"minor":0},"request_id":"00000000-0000-0000-0000-000000000002","outcome":"read","verified":true,"body":{}}`,
		"garbage":       `NOT_JSON`,
	} {
		t.Run(name, func(t *testing.T) {
			if _, err := child(t, reply).Verify(context.Background(), requestID, 2*time.Second); err == nil {
				t.Fatal("accepted")
			}
		})
	}
}

func TestDeniesNonPinnedBinary(t *testing.T) {
	if err := (Client{Binary: "echo"}).CheckBinary(); err == nil {
		t.Fatal("relative path accepted")
	}
	dir := t.TempDir()
	target := child(t, "{}")
	link := filepath.Join(dir, "rescue")
	if err := os.Symlink(target.Binary, link); err != nil {
		t.Fatal(err)
	}
	if err := (Client{Binary: link}).CheckBinary(); err == nil {
		t.Fatal("symlink accepted")
	}
	world := filepath.Join(dir, "world")
	if err := os.WriteFile(world, []byte("#!/bin/sh\n"), 0777); err != nil {
		t.Fatal(err)
	}
	if err := os.Chmod(world, 0777); err != nil {
		t.Fatal(err)
	}
	if err := (Client{Binary: world}).CheckBinary(); err == nil {
		t.Fatal("world writable accepted")
	}
}

func scriptClient(t *testing.T, script string) Client {
	t.Helper()
	path := filepath.Join(t.TempDir(), "trusted-rescue")
	if err := os.WriteFile(path, []byte("#!/bin/sh\n"+script+"\n"), 0700); err != nil {
		t.Fatal(err)
	}
	return Client{Binary: path}
}
func TestDeadlineDoesNotWaitForDetachedInheritedStdout(t *testing.T) {
	client := scriptClient(t, "setsid sh -c 'sleep 2' &\nexit 0")
	start := time.Now()
	if _, err := client.Verify(context.Background(), requestID, 60*time.Millisecond); err == nil {
		t.Fatal("empty reply accepted")
	}
	if elapsed := time.Since(start); elapsed > 500*time.Millisecond {
		t.Fatal("inherited stdout defeated request deadline", elapsed)
	}
}
func TestCancellationAllowsOwnerCleanupBeforeKill(t *testing.T) {
	client := scriptClient(t, `trap 'touch "$(dirname "$0")/cleaned"; exit 0' TERM
while :; do sleep 1; done`)
	if _, err := client.Verify(context.Background(), requestID, 100*time.Millisecond); err == nil {
		t.Fatal("timeout reported success")
	}
	if _, err := os.Stat(filepath.Join(filepath.Dir(client.Binary), "cleaned")); err != nil {
		t.Fatal("owner did not receive a cleanup grace period", err)
	}
}

func TestCopyCannotBypassOutputLimitThroughReaderFrom(t *testing.T) {
	cancelled := false
	output := &boundedOutput{cancel: func() { cancelled = true }}
	input := io.LimitReader(strings.NewReader(strings.Repeat("x", 4*MaxWireBytes)), 4*MaxWireBytes)
	if _, err := io.Copy(output, input); err != nil {
		t.Fatal(err)
	}
	if !cancelled || !output.exceeded || output.Len() > MaxWireBytes+1 {
		t.Fatal("io.Copy bypassed the output limit", output.Len(), cancelled)
	}
}

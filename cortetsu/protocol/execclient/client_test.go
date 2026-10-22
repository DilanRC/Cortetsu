package execclient

import (
	"context"
	"fmt"
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

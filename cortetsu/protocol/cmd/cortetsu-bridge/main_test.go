package main

import (
	"encoding/json"
	"os"
	"path/filepath"
	"testing"
)

func TestMetadataSecureLifecycle(t *testing.T) {
	dir := t.TempDir()
	cleanup, err := publishMetadata(dir, "session-a", 42, filepath.Join(dir, "cortetsu-session-a.sock"))
	if err != nil {
		t.Fatal(err)
	}
	metaPath := filepath.Join(dir, "bridge-session-a.json")
	info, err := os.Lstat(metaPath)
	if err != nil {
		t.Fatal(err)
	}
	if info.Mode().Perm() != 0600 {
		t.Fatalf("permissions = %v", info.Mode())
	}
	data, err := os.ReadFile(metaPath)
	if err != nil {
		t.Fatal(err)
	}
	var m metadata
	if json.Unmarshal(data, &m) != nil || m.SessionEpoch != 42 || m.Protocol != "cortetsu.ipc" {
		t.Fatal("bad metadata")
	}
	cleanup()
	if _, err := os.Lstat(metaPath); !os.IsNotExist(err) {
		t.Fatal("metadata not removed")
	}
}
func TestMetadataRefusesSymlink(t *testing.T) {
	dir := t.TempDir()
	destination := filepath.Join(dir, "bridge-session-a.json")
	if err := os.Symlink(filepath.Join(dir, "foreign"), destination); err != nil {
		t.Fatal(err)
	}
	if _, err := publishMetadata(dir, "session-a", 42, "/socket"); err == nil {
		t.Fatal("accepted symlink")
	}
}

package main

import (
	"encoding/json"
	"os"
	"path/filepath"
	"testing"

	"github.com/DilanRC/Cortetsu/cortetsu/protocol/activation"
)

func TestRevokeCLIRequiresExpectedOwnerAndSeparateEnable(t *testing.T) {
	t.Setenv("XDG_CONFIG_HOME", t.TempDir())
	t.Setenv("HYPRLAND_INSTANCE_SIGNATURE", "new-session")
	store := activation.DefaultStore()
	if err := store.Set("power", "expired-session", true); err != nil {
		t.Fatal(err)
	}
	output, err := os.CreateTemp(t.TempDir(), "stdout-")
	if err != nil {
		t.Fatal(err)
	}
	old := os.Stdout
	os.Stdout = output
	defer func() { os.Stdout = old; output.Close() }()
	if err := run([]string{"revoke", "power", "expired-session"}); err != nil {
		t.Fatal(err)
	}
	raw, err := os.ReadFile(output.Name())
	if err != nil {
		t.Fatal(err)
	}
	var reply map[string]any
	if err := json.Unmarshal(raw, &reply); err != nil {
		t.Fatal(err)
	}
	if reply["domain"] != "power" || reply["enabled"] != false || reply["owner_session"] != "" ||
		reply["revoked_owner_session"] != "expired-session" || reply["session_id"] != "new-session" {
		t.Fatal(reply)
	}
	c, err := store.Read()
	if err != nil || c.Owners["power"] != "" {
		t.Fatal(c, err)
	}
	if err := run([]string{"enable", "power"}); err != nil {
		t.Fatal(err)
	}
	if err := run([]string{"revoke", "power", "expired-session"}); err == nil || err.Error() != "SESSION_MISMATCH" {
		t.Fatal(err)
	}
	c, err = store.Read()
	if err != nil || c.Owners["power"] != "new-session" {
		t.Fatal(c, err)
	}
}

func TestRevokeCLIValidatesArgumentsBeforeAnyMutation(t *testing.T) {
	for _, args := range [][]string{{"revoke"}, {"revoke", "power"}, {"revoke", "power", "old", "extra"}, {"revoke", "shell.exec", "old"}, {"revoke", "power", ""}, {"revoke", "power", "old;touch"}} {
		t.Run(filepath.Join(args...), func(t *testing.T) {
			t.Setenv("XDG_CONFIG_HOME", t.TempDir())
			t.Setenv("HYPRLAND_INSTANCE_SIGNATURE", "new-session")
			if err := run(args); err == nil {
				t.Fatal("invalid revoke succeeded", args)
			}
			if _, err := os.Stat(activation.DefaultStore().Root); !os.IsNotExist(err) {
				t.Fatal("invalid revoke created state", err)
			}
		})
	}
	t.Setenv("XDG_CONFIG_HOME", t.TempDir())
	t.Setenv("HYPRLAND_INSTANCE_SIGNATURE", "../not-a-session")
	if err := run([]string{"revoke", "power", "old-session"}); err == nil {
		t.Fatal("invalid caller session accepted")
	}
	if _, err := os.Stat(activation.DefaultStore().Root); !os.IsNotExist(err) {
		t.Fatal("invalid caller created state", err)
	}
}

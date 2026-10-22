// cortetsu-policy changes only explicit coordinator consent/configuration.
// Device writes remain typed requests to the Rust transaction owners.
package main

import (
	"encoding/json"
	"fmt"
	"os"
	"strconv"
	"time"

	"github.com/DilanRC/Cortetsu/cortetsu/protocol/activation"
	"github.com/DilanRC/Cortetsu/cortetsu/protocol/coordinator"
)

func run(args []string) error {
	if len(args) == 0 {
		return fmt.Errorf("usage: cortetsu-policy status|rules|enable DOMAIN|disable DOMAIN|revoke DOMAIN EXPECTED_OWNER|override DOMAIN SECONDS")
	}
	s := activation.DefaultStore()
	session := os.Getenv("HYPRLAND_INSTANCE_SIGNATURE")
	switch args[0] {
	case "status":
		if len(args) != 1 {
			return fmt.Errorf("INVALID_REQUEST")
		}
		c, err := s.Read()
		if err != nil {
			return err
		}
		return json.NewEncoder(os.Stdout).Encode(map[string]any{"session_id": session, "config": c})
	case "rules":
		if len(args) != 1 {
			return fmt.Errorf("INVALID_REQUEST")
		}
		rules, err := coordinator.LoadRules("")
		if err != nil {
			return err
		}
		return json.NewEncoder(os.Stdout).Encode(map[string]any{"rules": rules})
	case "enable", "disable":
		if len(args) != 2 || !activation.ValidSession(session) {
			return fmt.Errorf("SESSION_MISMATCH")
		}
		if err := s.Set(args[1], session, args[0] == "enable"); err != nil {
			return err
		}
		return json.NewEncoder(os.Stdout).Encode(map[string]any{"domain": args[1], "enabled": args[0] == "enable", "session_id": session})
	case "revoke":
		if len(args) != 3 {
			return fmt.Errorf("INVALID_REQUEST")
		}
		if !activation.ValidSession(session) {
			return fmt.Errorf("SESSION_MISMATCH")
		}
		if err := s.Revoke(args[1], args[2]); err != nil {
			return err
		}
		return json.NewEncoder(os.Stdout).Encode(map[string]any{"domain": args[1], "enabled": false, "owner_session": "", "revoked_owner_session": args[2], "session_id": session})
	case "override":
		if len(args) != 3 || !activation.ValidSession(session) {
			return fmt.Errorf("INVALID_REQUEST")
		}
		seconds, err := strconv.ParseInt(args[2], 10, 32)
		if err != nil || seconds < 0 || seconds > 7*24*3600 {
			return fmt.Errorf("INVALID_REQUEST")
		}
		until := int64(0)
		if seconds > 0 {
			until = time.Now().Add(time.Duration(seconds) * time.Second).UnixMilli()
		}
		if err := s.OverrideForSession(args[1], session, until); err != nil {
			return err
		}
		return json.NewEncoder(os.Stdout).Encode(map[string]any{"domain": args[1], "manual_override_until_unix_ms": until})
	default:
		return fmt.Errorf("INVALID_REQUEST")
	}
}
func main() {
	if err := run(os.Args[1:]); err != nil {
		fmt.Fprintln(os.Stderr, "cortetsu-policy:", err)
		os.Exit(1)
	}
}

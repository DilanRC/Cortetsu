package coordinator

import (
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"syscall"

	"github.com/DilanRC/Cortetsu/cortetsu/protocol/policy"
	"github.com/DilanRC/Cortetsu/cortetsu/protocol/shadow"
)

// DefaultRules describe available automation; none may execute until the user
// enables the affected domain for this exact graphical session.
func DefaultRules() []policy.Rule {
	rule := func(id, domain, resource, operation string, conditions []policy.Condition, args string, priority int) policy.Rule {
		return policy.Rule{ID: id, Enabled: true, Mode: "active", Domain: domain, EventType: "state.changed", Conditions: conditions, Resource: resource, Operation: operation, Priority: priority, CooldownMs: 2000, HysteresisMs: 400, TTLms: 5000, Arguments: json.RawMessage(args)}
	}
	return []policy.Rule{
		rule("fullscreen-dnd-on", "hyprland", "notifications", "notifications.dnd.set", []policy.Condition{{Field: "focused_fullscreen", Equals: "true"}}, `{"enabled":true}`, 10),
		rule("fullscreen-dnd-off", "hyprland", "notifications", "notifications.dnd.set", []policy.Condition{{Field: "focused_fullscreen", Equals: "false"}}, `{"enabled":false}`, 10),
		// Game mode needs a fullscreen window tagged "game": a fullscreen video
		// or browser only gets do-not-disturb.
		rule("fullscreen-gamemode-on", "hyprland", "gamemode", "gamemode.set", []policy.Condition{{Field: "focused_fullscreen", Equals: "true"}, {Field: "focused_game", Equals: "true"}}, `{"enabled":true}`, 10),
		rule("fullscreen-gamemode-off", "hyprland", "gamemode", "gamemode.set", []policy.Condition{{Field: "focused_fullscreen", Equals: "false"}}, `{"enabled":false}`, 10),
		rule("non-game-gamemode-off", "hyprland", "gamemode", "gamemode.set", []policy.Condition{{Field: "focused_game", Equals: "false"}}, `{"enabled":false}`, 10),
		rule("battery-low-power", "power", "power", "power.profile.set", []policy.Condition{{Field: "ac_online", Equals: "false"}, {Field: "percentage_band", Equals: "low"}}, `{"profile":"power-saver"}`, 20),
		rule("ac-balanced-power", "power", "power", "power.profile.set", []policy.Condition{{Field: "ac_online", Equals: "true"}}, `{"profile":"balanced"}`, 10),
	}
}
func RulesPath() string {
	config := os.Getenv("XDG_CONFIG_HOME")
	if config == "" {
		config = filepath.Join(os.Getenv("HOME"), ".config")
	}
	return filepath.Join(config, "cortetsu", "coordinator", "rules.json")
}
func LoadRules(path string) ([]policy.Rule, error) {
	if path == "" {
		path = RulesPath()
	}
	m, err := os.Lstat(path)
	if errors.Is(err, os.ErrNotExist) {
		return DefaultRules(), nil
	}
	if err != nil {
		return nil, errors.New("cannot inspect policy catalog")
	}
	owner, ok := m.Sys().(*syscall.Stat_t)
	if !m.Mode().IsRegular() || m.Mode().Perm()&0022 != 0 || m.Size() > shadow.MaxLineBytes || !ok || (owner.Uid != uint32(os.Getuid()) && owner.Uid != 0) {
		return nil, errors.New("policy catalog must be a trusted regular file")
	}
	content, err := os.ReadFile(path)
	if err != nil {
		return nil, errors.New("cannot read policy catalog")
	}
	rules, err := shadow.ReadRules(content)
	if err != nil || len(rules) > 128 {
		return nil, errors.New("invalid policy catalog")
	}
	return rules, nil
}

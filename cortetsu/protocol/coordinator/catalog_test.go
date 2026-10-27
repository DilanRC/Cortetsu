package coordinator

import (
	"testing"

	"github.com/DilanRC/Cortetsu/cortetsu/protocol/policy"
)

// Game mode follows a fullscreen window tagged "game"; a fullscreen video
// keeps do-not-disturb only.
func TestDefaultGameModeNeedsFullscreenGame(t *testing.T) {
	cases := []struct {
		name, fullscreen, game string
		want                   string // gamemode rule selected, "" for none
	}{
		{"video fullscreen", "true", "false", "non-game-gamemode-off"},
		{"game fullscreen", "true", "true", "fullscreen-gamemode-on"},
		{"game windowed", "false", "true", "fullscreen-gamemode-off"},
		{"desktop", "false", "false", "fullscreen-gamemode-off"},
	}
	for _, c := range cases {
		ev := policy.Event{Producer: "hyprland", Session: "s", Epoch: 1, Sequence: 1, EmittedAtUnixMs: 900, Domain: "hyprland", Type: "state.changed",
			Fields: map[string]string{"focused_fullscreen": c.fullscreen, "focused_game": c.game}}
		rules := DefaultRules()
		for i := range rules {
			rules[i].HysteresisMs = 0
		}
		decisions, err := policy.NewEngine().EvaluateAuthorized(1000, ev, rules, nil, map[string]bool{"gamemode": true, "notifications": true})
		if err != nil {
			t.Fatal(c.name, err)
		}
		got := ""
		for _, d := range decisions {
			if d.Resource == "gamemode" && d.Outcome == "SELECTED" {
				got = d.RuleID
			}
		}
		if got != c.want {
			t.Errorf("%s: gamemode rule %q, want %q (%v)", c.name, got, c.want, decisions)
		}
	}
}

package policy

import "testing"

func TestActiveSelectionRequiresVerifiedDomainAndKeepsPriority(t *testing.T) {
	event := Event{Producer: "hyprland", Session: "one", Epoch: 1, Sequence: 1, EmittedAtUnixMs: 1000, Domain: "hyprland", Type: "fullscreen_changed"}
	rules := []Rule{{ID: "dnd", Enabled: true, Mode: "active", Domain: "hyprland", EventType: "fullscreen_changed", Resource: "notifications", Operation: "notifications.dnd.set", TTLms: 1000}}
	blocked, err := NewEngine().Evaluate(1000, event, rules, nil)
	if err != nil {
		t.Fatal(err)
	}
	if len(blocked) != 1 || blocked[0].Outcome != "BLOCKED" {
		t.Fatal(blocked)
	}
	selected, err := NewEngine().EvaluateAuthorized(1000, event, rules, nil, map[string]bool{"notifications": true})
	if err != nil || len(selected) != 1 || selected[0].Outcome != "SELECTED" {
		t.Fatalf("%v %v", selected, err)
	}
}

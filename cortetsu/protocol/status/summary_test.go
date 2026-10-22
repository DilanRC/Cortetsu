package status

import (
	"encoding/json"
	"strings"
	"testing"

	"github.com/DilanRC/Cortetsu/cortetsu/protocol/observehypr"
	"github.com/DilanRC/Cortetsu/cortetsu/protocol/policy"
)

func TestReadOnlyStatusCannotExposePrivateDataOrPretendSnapshot(t *testing.T) {
	s := NewStore()
	s.Apply(observehypr.Output{Type: "resync_required", Epoch: 1, Session: "a"})
	s.Apply(observehypr.Output{Type: "event", Epoch: 1, Session: "a", Event: &policy.Event{
		Session: "a", Epoch: 1, Type: "focus_changed", Fields: map[string]string{"private_title": "SECRET_ACCESS_TOKEN"},
	}})
	value, err := s.Snapshot([]string{"coordinator"})
	if err != nil {
		t.Fatal(err)
	}
	b, err := json.Marshal(value)
	if err != nil {
		t.Fatal(err)
	}
	if strings.Contains(string(b), "SECRET") {
		t.Fatal("leaked event payload")
	}
	var data Summary
	if err = json.Unmarshal(b, &data); err != nil {
		t.Fatal(err)
	}
	if data.Authoritative || !data.StreamStale || data.Seen != 1 || data.LastType != "focus_changed" {
		t.Fatalf("unexpected observation: %+v", data)
	}
	for _, domain := range []string{"secret", "network", "notifications"} {
		if _, err := s.Snapshot([]string{domain}); err == nil {
			t.Fatalf("exposed %s", domain)
		}
	}
	s.Apply(observehypr.Output{Type: "resync_required", Epoch: 2, Session: "a"})
	state, _ := s.Snapshot(nil)
	if state.(Summary).Seen != 0 || state.(Summary).LastType != "" {
		t.Fatal("stale event crossed epoch")
	}
}

func TestOwnerSnapshotIsInvalidatedAcrossEpoch(t *testing.T) {
	store := NewStore()
	store.SetOwner(observehypr.OwnerState{ObservedUnixMs: 25})
	got, err := store.Snapshot([]string{"hyprland"})
	if err != nil || !got.(Summary).Authoritative || got.(Summary).Owner == nil {
		t.Fatalf("owner snapshot missing: %#v / %v", got, err)
	}
	store.Apply(observehypr.Output{Type: "resync_required", Epoch: 5, Session: "a"})
	got, err = store.Snapshot([]string{"coordinator"})
	if err != nil || got.(Summary).Owner != nil || got.(Summary).Authoritative || !got.(Summary).StreamStale {
		t.Fatalf("stale owner survived reconnect: %#v / %v", got, err)
	}
	store.SetOwner(observehypr.OwnerState{ObservedUnixMs: 26})
	store.MarkOwnerUnavailable()
	got, _ = store.Snapshot(nil)
	if got.(Summary).Owner != nil || got.(Summary).Authoritative {
		t.Fatal("owner failure kept an authoritative snapshot")
	}
}

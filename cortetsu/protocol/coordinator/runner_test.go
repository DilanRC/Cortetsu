package coordinator

import (
	"context"
	"encoding/json"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/DilanRC/Cortetsu/cortetsu/protocol/activation"
	"github.com/DilanRC/Cortetsu/cortetsu/protocol/execv1"
	"github.com/DilanRC/Cortetsu/cortetsu/protocol/policy"
)

type ownerStub struct {
	writes       int
	enabled      bool
	revision     uint64
	override     int64
	unverifiable bool
}

func (s *ownerStub) Execute(_ context.Context, r execv1.Request) (*execv1.Response, error) {
	outcome := "read"
	if r.Operation == "notifications.dnd.set" {
		if r.ExpectedRevision == nil || *r.ExpectedRevision != s.revision || r.IdempotencyKey == "" {
			panic("unsafe mutation")
		}
		var args struct {
			Enabled bool `json:"enabled"`
		}
		json.Unmarshal(r.Arguments, &args)
		s.enabled = args.Enabled
		s.revision++
		s.writes++
		outcome = "applied"
	}
	body, _ := json.Marshal(map[string]any{"dnd": s.enabled, "revision": s.revision, "manual_override_until_unix_ms": s.override})
	return &execv1.Response{Protocol: execv1.Protocol, Version: execv1.Version{Major: 1}, RequestID: r.RequestID, Outcome: outcome, Verified: !s.unverifiable, Body: body}, nil
}
func fixture(t *testing.T) (*Runner, *ownerStub, activation.Store, policy.Event) {
	t.Helper()
	root := t.TempDir()
	store := activation.Store{Root: filepath.Join(root, "config")}
	audit := filepath.Join(root, "audit")
	if err := os.Mkdir(audit, 0700); err != nil {
		t.Fatal(err)
	}
	owner := &ownerStub{}
	r, err := New("one", []policy.Rule{{ID: "dnd", Enabled: true, Mode: "active", Domain: "hyprland", EventType: "state.changed", Resource: "notifications", Operation: "notifications.dnd.set", Arguments: json.RawMessage(`{"enabled":true}`), TTLms: 5000}}, store, owner, audit)
	if err != nil {
		t.Fatal(err)
	}
	ev := policy.Event{Producer: "hyprland", Session: "one", Epoch: 2, Sequence: 1, EmittedAtUnixMs: time.Now().UnixMilli(), Domain: "hyprland", Type: "state.changed", Fields: map[string]string{"focused_fullscreen": "true"}}
	return r, owner, store, ev
}
func TestExplicitConsentCASReadbackAndNoReplay(t *testing.T) {
	r, owner, store, ev := fixture(t)
	if _, err := r.Handle(context.Background(), ev); err != nil {
		t.Fatal(err)
	}
	if owner.writes != 0 {
		t.Fatal("mutated without consent")
	}
	if err := store.Set("notifications", "one", true); err != nil {
		t.Fatal(err)
	}
	ev.Sequence++
	ev.EmittedAtUnixMs = time.Now().UnixMilli()
	decisions, err := r.Handle(context.Background(), ev)
	if err != nil || len(decisions) != 1 || decisions[0].Outcome != "APPLIED" || owner.writes != 1 {
		t.Fatal(decisions, owner.writes, err)
	}
	if _, err := r.Handle(context.Background(), ev); err != nil {
		t.Fatal(err)
	}
	if owner.writes != 1 {
		t.Fatal("replayed event")
	}
	ev.Sequence++
	decisions, err = r.Handle(context.Background(), ev)
	if err != nil || decisions[0].Reason != "ALREADY_SATISFIED" || owner.writes != 1 {
		t.Fatal(decisions, owner.writes, err)
	}
}
func TestManualOverrideForeignSessionAndUnverifiedOwnerNeverWrite(t *testing.T) {
	r, owner, store, ev := fixture(t)
	if err := store.Set("notifications", "one", true); err != nil {
		t.Fatal(err)
	}
	owner.override = time.Now().Add(time.Hour).UnixMilli()
	d, err := r.Handle(context.Background(), ev)
	if err != nil || d[0].Reason != "MANUAL_OVERRIDE" || owner.writes != 0 {
		t.Fatal(d, err)
	}
	ev.Sequence++
	owner.override = 0
	owner.unverifiable = true
	d, err = r.Handle(context.Background(), ev)
	if err != nil || d[0].Outcome != "BLOCKED" || owner.writes != 0 {
		t.Fatal(d, err)
	}
	ev.Session = "two"
	ev.Sequence++
	if _, err = r.Handle(context.Background(), ev); err == nil || owner.writes != 0 {
		t.Fatal("foreign session admitted")
	}
}
func TestAuditFailurePreventsMutation(t *testing.T) {
	r, owner, store, ev := fixture(t)
	if err := store.Set("notifications", "one", true); err != nil {
		t.Fatal(err)
	}
	if err := os.Chmod(r.audit.Root, 0755); err != nil {
		t.Fatal(err)
	}
	d, err := r.Handle(context.Background(), ev)
	if err != nil || d[0].Reason != "AUDIT_UNAVAILABLE" || owner.writes != 0 {
		t.Fatal(d, err)
	}
}

func TestSharedBusEpochInvalidatesEveryDomainHysteresis(t *testing.T) {
	r, owner, store, ev := fixture(t)
	if err := store.Set("notifications", "one", true); err != nil {
		t.Fatal(err)
	}
	r.rules[0].Domain = "connectivity"
	r.rules[0].HysteresisMs = 5
	ev.Producer = "dbus"
	ev.Domain = "connectivity"
	decisions, err := r.Handle(context.Background(), ev)
	if err != nil || len(decisions) != 1 || decisions[0].Reason != "STABILIZING" {
		t.Fatal(decisions, err)
	}
	time.Sleep(10 * time.Millisecond)
	ev.Epoch++
	ev.Sequence++
	ev.Domain = "power"
	ev.EmittedAtUnixMs = time.Now().UnixMilli()
	if _, err := r.Handle(context.Background(), ev); err != nil {
		t.Fatal(err)
	}
	ev.Domain = "connectivity"
	ev.Sequence++
	decisions, err = r.Handle(context.Background(), ev)
	if err != nil || len(decisions) != 1 || decisions[0].Reason != "STABILIZING" || owner.writes != 0 {
		t.Fatal("new bus connection reused old stability", decisions, owner.writes, err)
	}
}

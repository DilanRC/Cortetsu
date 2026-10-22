package policy

import (
	"reflect"
	"testing"
)

func sampleRule(id, mode string, priority int) Rule {
	return Rule{ID: id, Enabled: true, Mode: mode, Domain: "power", EventType: "battery.changed", Resource: "power", Operation: "power.profile.set", Priority: priority, TTLms: 60000, CooldownMs: 1000, Conditions: []Condition{{Field: "level", Equals: "low"}}}
}

func TestDisabledAndModeAlwaysReadOnly(t *testing.T) {
	e := NewEngine()
	r := sampleRule("low.battery", "active", 5)
	ev := Event{Domain: "power", Type: "battery.changed", EmittedAtUnixMs: 1000, Fields: map[string]string{"level": "low"}}
	out, err := e.Evaluate(1000, ev, []Rule{r}, nil)
	if err != nil || len(out) != 1 || out[0].Outcome != "BLOCKED" || out[0].Reason != "NO_VERIFIED_RUST_OWNER" {
		t.Fatalf("active bypass: %+v / %v", out, err)
	}
	r.Mode = "simulate"
	out, err = e.Evaluate(1001, ev, []Rule{r}, nil)
	if err != nil || len(out) != 1 || out[0].Outcome != "SIMULATED" {
		t.Fatalf("simulate: %+v / %v", out, err)
	}
	r.Enabled = false
	out, err = e.Evaluate(1002, ev, []Rule{r}, nil)
	if err != nil || len(out) != 0 {
		t.Fatalf("disabled rule: %+v / %v", out, err)
	}
}

func TestDeterministicTieBreakAndCooldown(t *testing.T) {
	ev := Event{Domain: "power", Type: "battery.changed", EmittedAtUnixMs: 1000, Fields: map[string]string{"level": "low"}}
	z := sampleRule("z", "simulate", 9)
	a := sampleRule("a", "simulate", 9)
	e := NewEngine()
	first, err := e.Evaluate(1000, ev, []Rule{z, a}, nil)
	if err != nil || len(first) != 2 || first[0].RuleID != "a" || first[0].Outcome != "SIMULATED" || first[1].Reason != "LOWER_PRIORITY" {
		t.Fatalf("tie: %+v / %v", first, err)
	}
	second, err := e.Evaluate(1100, ev, []Rule{z, a}, nil)
	if err != nil || second[0].Reason != "COOLDOWN" || second[1].Outcome != "SIMULATED" {
		t.Fatalf("cooldown: %+v / %v", second, err)
	}
}

func TestManualOverrideAndValidation(t *testing.T) {
	ev := Event{Domain: "power", Type: "battery.changed", EmittedAtUnixMs: 100, Fields: map[string]string{"level": "low"}}
	e := NewEngine()
	o, err := e.Evaluate(100, ev, []Rule{sampleRule("r", "simulate", 1)}, []ManualOverride{{Resource: "power", UntilUnixMs: 101}})
	if err != nil || o[0].Reason != "MANUAL_OVERRIDE" {
		t.Fatalf("manual override: %+v %v", o, err)
	}
	o, err = e.Evaluate(101, ev, []Rule{sampleRule("r", "simulate", 1)}, []ManualOverride{{Resource: "power", UntilUnixMs: 101}})
	if err != nil || o[0].Outcome != "SIMULATED" {
		t.Fatalf("override expiry: %+v %v", o, err)
	}
	invalid := sampleRule("bad", "active", 1)
	invalid.Operation = "arbitrary.command"
	if _, err = e.Evaluate(200, ev, []Rule{invalid}, nil); err == nil {
		t.Fatal("arbitrary command accepted")
	}
	if _, err = e.Evaluate(200, ev, []Rule{sampleRule("dup", "observe", 1), sampleRule("dup", "observe", 2)}, nil); err == nil {
		t.Fatal("duplicate rule accepted")
	}
}

func TestObserverRejectsGapsAndEpochChange(t *testing.T) {
	o := NewObserver()
	event := Event{Producer: "hypr", Session: "sess", Epoch: 1, Sequence: 11, Domain: "window", Type: "focus"}
	if result, err := o.Accept(event); err != nil || result != "RESYNC_REQUIRED" {
		t.Fatalf("unknown producer: %s %v", result, err)
	}
	if err := o.Snapshot("hypr", Cursor{Session: "sess", Epoch: 1, Sequence: 10}); err != nil {
		t.Fatal(err)
	}
	if result, _ := o.Accept(event); result != "APPLIED_OBSERVATION" {
		t.Fatalf("expected accepted: %s", result)
	}
	if result, _ := o.Accept(event); result != "DUPLICATE" {
		t.Fatalf("duplicate: %s", result)
	}
	event.Sequence = 13
	if result, _ := o.Accept(event); result != "RESYNC_REQUIRED" {
		t.Fatalf("gap: %s", result)
	}
	cursor, _ := o.Cursor("hypr")
	if !cursor.Stale {
		t.Fatal("gap failed to mark stale")
	}
	event.Sequence = 12
	if result, _ := o.Accept(event); result != "RESYNC_REQUIRED" {
		t.Fatalf("stale stream accepted: %s", result)
	}
	if err := o.Snapshot("hypr", Cursor{Session: "sess", Epoch: 2, Sequence: 20}); err != nil {
		t.Fatal(err)
	}
	event.Epoch, event.Sequence = 2, 21
	if result, _ := o.Accept(event); result != "APPLIED_OBSERVATION" {
		t.Fatalf("new snapshot failed: %s", result)
	}
}

func TestSimulationDeterministicAcrossFreshEngines(t *testing.T) {
	ev := Event{Domain: "power", Type: "battery.changed", EmittedAtUnixMs: 1000, Fields: map[string]string{"level": "low"}}
	rules := []Rule{sampleRule("b", "simulate", 3), sampleRule("a", "observe", 4)}
	a, err := NewEngine().Evaluate(1000, ev, append([]Rule(nil), rules...), nil)
	if err != nil {
		t.Fatal(err)
	}
	b, err := NewEngine().Evaluate(1000, ev, append([]Rule(nil), rules...), nil)
	if err != nil || !reflect.DeepEqual(a, b) {
		t.Fatalf("nondeterministic: %v / %v", a, b)
	}
}

func TestPolicyEventTTLAndPrivacy(t *testing.T) {
	e := NewEngine()
	r := sampleRule("low.ttl", "simulate", 5)
	ev := Event{Domain: "power", Type: "battery.changed", EmittedAtUnixMs: 1000, Fields: map[string]string{"level": "low"}}
	got, err := e.Evaluate(1000+r.TTLms+1, ev, []Rule{r}, nil)
	if err != nil || got[0].Reason != "EVENT_EXPIRED" {
		t.Fatalf("expired: %+v %v", got, err)
	}
	got, err = e.Evaluate(999, ev, []Rule{r}, nil)
	if err != nil || got[0].Reason != "EVENT_IN_FUTURE" {
		t.Fatalf("clock skew: %+v %v", got, err)
	}
	ev.Fields["wifi_password"] = "secret"
	if _, err = e.Evaluate(1000, ev, []Rule{r}, nil); err == nil {
		t.Fatal("secret-bearing key accepted")
	}
}

func TestObserverSeparateSessionsAndSnapshotMonotonicity(t *testing.T) {
	o := NewObserver()
	for _, session := range []string{"session-a", "session-b"} {
		if err := o.Snapshot("hypr", Cursor{Session: session, Epoch: 1, Sequence: 10}); err != nil {
			t.Fatal(err)
		}
		got, err := o.Accept(Event{Producer: "hypr", Session: session, Epoch: 1, Sequence: 11, Domain: "display", Type: "changed"})
		if err != nil || got != "APPLIED_OBSERVATION" {
			t.Fatalf("%s %s %v", session, got, err)
		}
	}
	if _, ok := o.Cursor("hypr"); ok {
		t.Fatal("ambiguous legacy cursor")
	}
	if c, ok := o.CursorFor("hypr", "session-a"); !ok || c.Sequence != 11 {
		t.Fatal(c, ok)
	}
	if err := o.Snapshot("hypr", Cursor{Session: "session-a", Epoch: 1, Sequence: 3}); err == nil {
		t.Fatal("old snapshot accepted")
	}
	if c, ok := o.CursorFor("hypr", "session-b"); !ok || c.Sequence != 11 {
		t.Fatal("other session affected", c)
	}
}

func TestHysteresisPerSessionAndNoUnexpectedAction(t *testing.T) {
	e := NewEngine()
	r := sampleRule("low", "simulate", 1)
	r.HysteresisMs = 1500
	r.CooldownMs = 0
	ev := Event{Session: "session-a", Domain: "power", Type: "battery.changed", EmittedAtUnixMs: 1000, Fields: map[string]string{"level": "low"}}
	decide := func(at int64, event Event) Decision {
		t.Helper()
		got, err := e.Evaluate(at, event, []Rule{r}, nil)
		if err != nil || len(got) != 1 {
			t.Fatalf("evaluation: %v %v", got, err)
		}
		return got[0]
	}
	if got := decide(1000, ev); got.Reason != "STABILIZING" {
		t.Fatal(got)
	}
	if got := decide(2000, ev); got.Reason != "STABILIZING" {
		t.Fatal(got)
	}
	if got := decide(2500, ev); got.Outcome != "SIMULATED" {
		t.Fatal(got)
	}
	// A new Wayland session must never inherit the old session's hysteresis.
	ev.Session = "session-b"
	if got := decide(2600, ev); got.Reason != "STABILIZING" {
		t.Fatal(got)
	}
	ev.Fields["level"] = "normal"
	got, err := e.Evaluate(3000, ev, []Rule{r}, nil)
	if err != nil || len(got) != 0 {
		t.Fatal(got, err)
	}
	ev.Fields["level"] = "low"
	if got := decide(3100, ev); got.Reason != "STABILIZING" {
		t.Fatal(got)
	}
	// Even a high-priority active rule cannot bypass missing Rust owner.
	r.Mode = "active"
	if got := decide(4700, ev); got.Reason != "NO_VERIFIED_RUST_OWNER" {
		t.Fatal(got)
	}
}

func TestRulesRejectNonWhitelistedCondition(t *testing.T) {
	r := sampleRule("unsafe", "observe", 0)
	r.Conditions = []Condition{{Field: "ssid", Equals: "private_wifi"}}
	if err := r.Validate(); err == nil {
		t.Fatal("secret condition key accepted")
	}
	r = sampleRule("unsafe", "observe", 0)
	r.HysteresisMs = 25 * 3600 * 1000
	if err := r.Validate(); err == nil {
		t.Fatal("unbounded hysteresis accepted")
	}
}

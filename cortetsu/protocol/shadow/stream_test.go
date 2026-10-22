package shadow

import (
	"bytes"
	"encoding/json"
	"strings"
	"testing"

	"github.com/DilanRC/Cortetsu/cortetsu/protocol/policy"
)

const testTrace = `{"type":"snapshot","producer":"hypr","cursor":{"session":"wayland-1","epoch":1,"sequence":0}}
{"type":"event","event":{"producer":"hypr","session":"wayland-1","epoch":1,"sequence":1,"domain":"power","type":"battery.changed","emitted_at_unix_ms":1000,"fields":{"level":"low"}},"now_unix_ms":1001}
{"type":"event","event":{"producer":"hypr","session":"wayland-1","epoch":1,"sequence":1,"domain":"power","type":"battery.changed","emitted_at_unix_ms":1000,"fields":{"level":"low"}},"now_unix_ms":1002}
{"type":"event","event":{"producer":"hypr","session":"wayland-1","epoch":1,"sequence":3,"domain":"power","type":"battery.changed","emitted_at_unix_ms":1000,"fields":{"level":"low"}},"now_unix_ms":1003}
`

func TestReplayReadOnlyAndResnapshot(t *testing.T) {
	rules := []policy.Rule{{ID: "low", Enabled: true, Mode: "simulate", Domain: "power", EventType: "battery.changed", Resource: "power", Operation: "power.profile.set", Priority: 1, CooldownMs: 1000, TTLms: 60000, Conditions: []policy.Condition{{Field: "level", Equals: "low"}}}}
	var output bytes.Buffer
	if err := Run(strings.NewReader(testTrace), &output, rules); err != nil {
		t.Fatal(err)
	}
	var lines []Result
	for _, line := range strings.Split(strings.TrimSpace(output.String()), "\n") {
		var result Result
		if err := json.Unmarshal([]byte(line), &result); err != nil {
			t.Fatal(err)
		}
		lines = append(lines, result)
	}
	if len(lines) != 4 || lines[0].Status != "SNAPSHOT_SET" || lines[1].Status != "APPLIED_OBSERVATION" || lines[2].Status != "DUPLICATE" || lines[3].Status != "RESYNC_REQUIRED" {
		t.Fatal(lines)
	}
	if len(lines[1].Decisions) != 1 || lines[1].Decisions[0].Outcome != "SIMULATED" {
		t.Fatal(lines)
	}
	if strings.Contains(output.String(), "battery.changed") || strings.Contains(output.String(), "\"level\"") {
		t.Fatal("event data leaked")
	}
}

func TestActiveRulesBlockedAndMalformedRejected(t *testing.T) {
	rules := []policy.Rule{{ID: "bad", Enabled: true, Mode: "active", Domain: "power", EventType: "battery.changed", Resource: "power", Operation: "power.profile.set", Priority: 10, TTLms: 60000}}
	var output bytes.Buffer
	if err := Run(strings.NewReader(testTrace[:strings.Index(testTrace, "\n")+1]+strings.Split(testTrace, "\n")[1]+"\n"), &output, rules); err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(output.String(), "NO_VERIFIED_RUST_OWNER") {
		t.Fatal(output.String())
	}
	if _, err := ReadRules([]byte(`[ {"id":"x","operation":"shell.exec"}]`)); err == nil {
		t.Fatal("invalid rule accepted")
	}
	if err := Run(strings.NewReader(`{"type":"snapshot","producer":"hypr","cursor":{"session":"x","epoch":1,"sequence":0},"password":"abc"}`+"\n"), &output, nil); err == nil {
		t.Fatal("secret-bearing input accepted")
	}
	if err := Run(strings.NewReader(`{"type":"snapshot","type":"event"}`+"\n"), &output, nil); err == nil {
		t.Fatal("duplicate key accepted")
	}
}

func TestReadRulesRejectsSurrogateAndOversize(t *testing.T) {
	if _, err := ReadRules([]byte(`[{"id":"\ud800"}]`)); err == nil {
		t.Fatal("bad utf16 accepted")
	}
	if _, err := ReadRules([]byte(strings.Repeat(" ", MaxLineBytes+1))); err == nil {
		t.Fatal("oversize accepted")
	}
}

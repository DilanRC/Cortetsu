package shadow

import (
	"bytes"
	"os"
	"path/filepath"
	"testing"

	"github.com/DilanRC/Cortetsu/cortetsu/protocol/policy"
	"github.com/DilanRC/Cortetsu/cortetsu/protocol/policyaudit"
)

func TestTraceIsRedactedAndOptIn(t *testing.T) {
	dir := filepath.Join(t.TempDir(), "audit")
	if err := os.Mkdir(dir, 0700); err != nil {
		t.Fatal(err)
	}
	audit := &policyaudit.Ledger{Root: dir}
	rules := []policy.Rule{{ID: "critical", Enabled: true, Mode: "simulate", Domain: "power", EventType: "battery.changed", Resource: "power", Operation: "power.profile.set", TTLms: 60000}}
	input := `{"type":"snapshot","producer":"logind","cursor":{"session":"a","epoch":1,"sequence":2}}
{"type":"event","event":{"producer":"logind","session":"a","epoch":1,"sequence":3,"domain":"power","type":"battery.changed","emitted_at_unix_ms":1000,"fields":{"level":"critical"}},"now_unix_ms":1001}
`
	var out bytes.Buffer
	if err := RunWithAudit(bytes.NewBufferString(input), &out, rules, audit); err != nil {
		t.Fatal(err)
	}
	records, err := audit.Read()
	if err != nil {
		t.Fatal(err)
	}
	if len(records) != 1 || records[0].Outcome != "SIMULATED" {
		t.Fatalf("unexpected decisions: %+v", records)
	}
	raw, err := os.ReadFile(filepath.Join(dir, "policy-decisions-v1.jsonl"))
	if err != nil {
		t.Fatal(err)
	}
	if bytes.Contains(raw, []byte("critical\"")) && bytes.Contains(raw, []byte("level")) {
		t.Fatal("event payload logged")
	}
	if !bytes.Contains(out.Bytes(), []byte("SIMULATED")) {
		t.Fatal("result was not emitted")
	}
}

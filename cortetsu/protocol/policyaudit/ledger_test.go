package policyaudit

import (
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"

	"github.com/DilanRC/Cortetsu/cortetsu/protocol/policy"
)

func record(t *testing.T) Record {
	t.Helper()
	r, err := NewRecord(policy.Event{Producer: "logind", Session: "session-a", Epoch: 5, Sequence: 8}, policy.Decision{RuleID: "battery", Resource: "power", Operation: "power.profile.set", Outcome: "SIMULATED", Reason: "NO_MUTATION"}, 1234)
	if err != nil {
		t.Fatal(err)
	}
	return r
}
func TestOptInRedactedConcurrentLedger(t *testing.T) {
	root := filepath.Join(t.TempDir(), "private")
	if err := os.Mkdir(root, 0700); err != nil {
		t.Fatal(err)
	}
	l := Ledger{Root: root}
	r := record(t)
	var wg sync.WaitGroup
	errCh := make(chan error, 24)
	for i := 0; i < 24; i++ {
		wg.Add(1)
		go func() { defer wg.Done(); errCh <- l.Append(r) }()
	}
	wg.Wait()
	close(errCh)
	for err := range errCh {
		if err != nil {
			t.Fatal(err)
		}
	}
	content, err := os.ReadFile(filepath.Join(root, "policy-decisions-v1.jsonl"))
	if err != nil {
		t.Fatal(err)
	}
	if strings.Contains(string(content), "secret") {
		t.Fatal("private content leaked")
	}
	entries, err := l.Read()
	if err != nil {
		t.Fatal(err)
	}
	if len(entries) != 24 {
		t.Fatalf("got %d audit records", len(entries))
	}
	if entries[0].RuleID != "battery" {
		t.Fatal("unexpected record")
	}
}
func TestRejectsUnsafeFilesAndCorruption(t *testing.T) {
	dir := t.TempDir()
	secret := filepath.Join(dir, "secret")
	os.WriteFile(secret, []byte("do-not-change"), 0600)
	priv := filepath.Join(dir, "private")
	os.Mkdir(priv, 0700)
	l := Ledger{Root: priv}
	r := record(t)
	if err := os.Symlink(secret, filepath.Join(priv, "policy-decisions-v1.jsonl")); err != nil {
		t.Fatal(err)
	}
	if l.Append(r) == nil {
		t.Fatal("followed symlink")
	}
	if stringMust(os.ReadFile(secret)) != "do-not-change" {
		t.Fatal("target corrupted")
	}
	os.Remove(filepath.Join(priv, "policy-decisions-v1.jsonl"))
	if err := os.WriteFile(filepath.Join(priv, "policy-decisions-v1.jsonl"), []byte("{broken\n"), 0600); err != nil {
		t.Fatal(err)
	}
	if _, err := l.Read(); err == nil {
		t.Fatal("accepted malformed ledger")
	}
	os.Chmod(priv, 0755)
	if l.Append(r) == nil {
		t.Fatal("accepted public audit dir")
	}
}
func stringMust(b []byte, e error) string {
	if e != nil {
		panic(e)
	}
	return string(b)
}
func TestRejectsUntrustedMetadata(t *testing.T) {
	r := record(t)
	r.RuleID = "../evil"
	if r.Validate() == nil {
		t.Fatal("allowed unsafe rule id")
	}
	r = record(t)
	r.Reason = "secret value"
	if r.Validate() == nil {
		t.Fatal("allowed free-form log text")
	}
}

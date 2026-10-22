package execv1

import (
	"os"
	"testing"
)

func TestDNDSharedFixture(t *testing.T) {
	raw, err := os.ReadFile("../../contracts/exec/v1/fixtures/notifications-dnd-set.json")
	if err != nil {
		t.Fatal(err)
	}
	request, err := ParseRequest(raw)
	if err != nil {
		t.Fatalf("typed DND must be admitted: %v", err)
	}
	if _, err := FingerprintRequest(request, "notifications"); err != nil {
		t.Fatal(err)
	}
}

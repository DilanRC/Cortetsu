package execv1

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func errorCode(t *testing.T, err error) string {
	t.Helper()
	if err == nil {
		return ""
	}
	e, ok := err.(*Error)
	if !ok {
		t.Fatalf("untyped error: %T: %v", err, err)
	}
	return e.Code
}

func TestRequestGoldenFixtures(t *testing.T) {
	cases := []struct{ file, code string }{
		{"valid-read.json", ""},
		{"valid-write.json", ""},
		{"duplicate-key.json", "INVALID_REQUEST"},
		{"negative-zero.json", "INVALID_REQUEST"},
		{"unsupported-major.json", "INCOMPATIBLE_PROTOCOL"},
		{"unsupported-minor.json", "UNSUPPORTED_CAPABILITY"},
		{"unknown-operation.json", "UNSUPPORTED_CAPABILITY"},
		{"missing-idempotency.json", "INVALID_REQUEST"},
		{"secret-argument.json", "INVALID_REQUEST"},
		{"truncated.json", "INVALID_REQUEST"},
	}
	for _, tc := range cases {
		t.Run(tc.file, func(t *testing.T) {
			b, err := os.ReadFile(filepath.Join("..", "..", "contracts", "exec", "v1", "fixtures", tc.file))
			if err != nil {
				t.Fatal(err)
			}
			r, err := ParseRequest(b)
			if got := errorCode(t, err); got != tc.code {
				t.Fatalf("expected %q, got %q", tc.code, got)
			}
			if tc.code == "" && r == nil {
				t.Fatal("no request")
			}
		})
	}
}

func TestMalformedAndFrameLimits(t *testing.T) {
	base := `{"protocol":"cortetsu.exec","version":{"major":1,"minor":0},"request_id":"123e4567-e89b-12d3-a456-426614174000","operation":"gamemode.status","deadline_ms":5000,"arguments":{}}`
	cases := []string{
		base + base,
		strings.Replace(base, `"deadline_ms":5000`, `"deadline_ms":true`, 1),
		strings.Replace(base, `"deadline_ms":5000`, `"deadline_ms":0`, 1),
		strings.Replace(base, `"deadline_ms":5000`, `"deadline_ms":999999`, 1),
		strings.Replace(base, `"arguments":{}`, `"arguments":{"unexpected":"\ud800"}`, 1),
		strings.Replace(base, `"arguments":{}`, `"arguments":null`, 1),
		strings.Replace(base, `"arguments":{}`, `"arguments":{"password":"secret"}`, 1),
		strings.Replace(base, `"request_id":"123e4567-e89b-12d3-a456-426614174000"`, `"request_id":"bad"`, 1),
		`true`,
		`[]`,
		`{}`,
		`{"bad":true}`,
		`{"x":-0e-3}`,
		`{"x":-0.00001e-999}`,
		`{"x":1e999}`,
		strings.Replace(base, `"arguments":{}`, `"arguments":{"value":"\ud800"}`, 1),
	}
	for _, c := range cases {
		if _, err := ParseRequest([]byte(c)); err == nil {
			t.Fatalf("accepted %q", c)
		}
	}
	oversized := []byte(strings.Repeat(" ", MaxBytes+1))
	if got := errorCode(t, func() error { _, err := ParseRequest(oversized); return err }()); got != "FRAME_TOO_LARGE" {
		t.Fatalf("oversize: %s", got)
	}
	if _, err := ParseRequest([]byte{0xff, 0xfe}); err == nil {
		t.Fatal("accepted invalid UTF8")
	}
}

func TestResponseRequiresVerifiedReadback(t *testing.T) {
	ok := `{"protocol":"cortetsu.exec","version":{"major":1,"minor":0},"request_id":"123e4567-e89b-12d3-a456-426614174000","outcome":"applied","verified":true,"body":{}}`
	if _, err := ParseResponse([]byte(ok)); err != nil {
		t.Fatal(err)
	}
	bad := strings.Replace(ok, `"verified":true`, `"verified":false`, 1)
	if _, err := ParseResponse([]byte(bad)); err == nil {
		t.Fatal("success without readback")
	}
	rej := `{"protocol":"cortetsu.exec","version":{"major":1,"minor":0},"request_id":"123e4567-e89b-12d3-a456-426614174000","outcome":"rejected","verified":false,"error":{"code":"STATE_STALE","retryable":true},"body":{}}`
	if _, err := ParseResponse([]byte(rej)); err != nil {
		t.Fatal(err)
	}
	rejNoErr := strings.Replace(rej, `"error":{"code":"STATE_STALE","retryable":true},`, "", 1)
	if _, err := ParseResponse([]byte(rejNoErr)); err == nil {
		t.Fatal("rejected without code")
	}
	var result Response
	if err := json.Unmarshal([]byte(rej), &result); err != nil {
		t.Fatal(err)
	}
	if result.Error.Code != "STATE_STALE" {
		t.Fatal(result.Error)
	}
}

func TestSystemVerifyIsReadOnlyWithEmptyArguments(t *testing.T) {
	good, readErr := os.ReadFile("../../contracts/exec/v1/fixtures/system-verify.json")
	if readErr != nil {
		t.Fatal(readErr)
	}
	if _, err := ParseRequest(good); err != nil {
		t.Fatalf("valid: %v", err)
	}
	bad := []byte(`{"protocol":"cortetsu.exec","version":{"major":1,"minor":0},"request_id":"00000000-0000-0000-0000-000000000001","operation":"system.verify","deadline_ms":5000,"arguments":{"command":"systemctl reboot"}}`)
	if _, err := ParseRequest(bad); err == nil {
		t.Fatal("accepted an arbitrary command field")
	}
}

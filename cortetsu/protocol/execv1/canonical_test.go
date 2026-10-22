package execv1

import (
	"bytes"
	"encoding/hex"
	"strings"
	"testing"
)

func TestCanonicalizeRFCAndUTF16Order(t *testing.T) {
	data := []byte(`{"z":-1.0,"numbers":[333333333.3333333,1e30,4.50,2e-3,1e-27],"string":"€$\u000f\nA'B\"\\\"/","\ue000":1,"\ud83d\ude00":2}`)
	want := `{"numbers":[333333333.3333333,1e+30,4.5,0.002,1e-27],"string":"€$\u000f\nA'B\"\\\"/","z":-1,"😀":2,"":1}`
	got, err := Canonicalize(data)
	if err != nil {
		t.Fatal(err)
	}
	if string(got) != want {
		t.Fatalf("got: %q\nwant:%q", got, want)
	}
	repeated, err := Canonicalize(got)
	if err != nil || !bytes.Equal(got, repeated) {
		t.Fatalf("not idempotent: %s, %v", repeated, err)
	}
}

func TestRejectInvalidJCS(t *testing.T) {
	for _, value := range []string{
		`{"x":1,"x":2}`, `{"nested":{"a":1,"a":0}}`,
		`{"s":"\ud800"}`, `{"s":"\udc00"}`, `{"s":"\ud800a"}`,
		`{"s":"\ud800\u0041"}`, `{"s":"\udc00\ud800"}`,
		`{"n":-0}`, `{"n":-0e-800}`, `{"n":1e500}`, `{} {}`,
	} {
		if b, err := Canonicalize([]byte(value)); err == nil {
			t.Errorf("accepted invalid %q as %q", value, b)
		}
	}
	if _, err := Canonicalize([]byte(strings.Repeat(" ", MaxBytes+1))); err == nil {
		t.Fatal("oversized accepted")
	}
	if _, err := Canonicalize([]byte{0xff}); err == nil {
		t.Fatal("invalid UTF-8 accepted")
	}
}

func TestJCSNumbers(t *testing.T) {
	pairs := map[string]string{
		"0.000001": "0.000001", "1e-7": "1e-7", "1e21": "1e+21",
		"100000000000000000000": "100000000000000000000", "-0.0": "",
		"-42.0": "-42", "1e-8": "1e-8", "3.141592653589793": "3.141592653589793",
	}
	for raw, expected := range pairs {
		result, err := Canonicalize([]byte(raw))
		if expected == "" {
			if err == nil {
				t.Errorf("accepted %s", raw)
			}
			continue
		}
		if err != nil || string(result) != expected {
			t.Errorf("%s: %s / %v, want %s", raw, result, err, expected)
		}
	}
}

func TestFingerprintStableAcrossReconnect(t *testing.T) {
	first, err := ParseRequest([]byte(`{"protocol":"cortetsu.exec","version":{"major":1,"minor":0},"request_id":"123e4567-e89b-12d3-a456-426614174000","operation":"gamemode.set","deadline_ms":1000,"expected_revision":7,"idempotency_key":"123e4567-e89b-12d3-a456-426614174001","arguments":{"enabled":true}}`))
	if err != nil {
		t.Fatal(err)
	}
	hash, err := FingerprintRequest(first, "gamemode")
	if err != nil || hash == [32]byte{} {
		t.Fatalf("%x: %v", hash, err)
	}
	t.Logf("fingerprint: %s", hex.EncodeToString(hash[:]))
	first.RequestID = "123e4567-e89b-12d3-a456-426614174002"
	first.DeadlineMs = 1500
	second, err := FingerprintRequest(first, "gamemode")
	if err != nil || second != hash {
		t.Fatal("request id/deadline changed fingerprint")
	}
	third, err := FingerprintRequest(first, "gamemode_other")
	if err != nil || third == hash {
		t.Fatal("resource identity did not affect fingerprint")
	}
	*first.ExpectedRevision = 8
	fourth, err := FingerprintRequest(first, "gamemode")
	if err != nil || fourth == hash {
		t.Fatal("revision did not affect fingerprint")
	}
}

package ipcv1

import (
	"bytes"
	"errors"
	"io"
	"reflect"
	"strings"
	"testing"
)

const helloFixture = `{"type":"hello","protocol":"cortetsu.ipc","version":{"major":1,"minor":0},"client":"cortetsu-shell","client_version":"2.0","session_id":"wayland-1","session_epoch":1,"capabilities":["snapshot","events","policy.simulate","policy.observe","explain"]}`
const requestFixture = `{"type":"request","protocol":"cortetsu.ipc","version":{"major":1,"minor":0},"id":"123e4567-e89b-12d3-a456-426614174000","op":"snapshot.get","session_id":"wayland-1","session_epoch":1,"deadline_ms":5000,"body":{"domains":["power","display"]}}`

func code(err error) string {
	if err == nil {
		return ""
	}
	var e *Error
	if errors.As(err, &e) {
		return e.Code
	}
	return "UNEXPECTED_ERROR_TYPE"
}

func sessionFor(t *testing.T, session string, epoch uint64) *Negotiated {
	t.Helper()
	h, err := ParseHello([]byte(strings.ReplaceAll(helloFixture, "wayland-1", session)))
	if err != nil {
		t.Fatal(err)
	}
	n, err := Negotiate(h, session, epoch)
	if err != nil {
		t.Fatal(err)
	}
	return n
}

func TestHelloAndSessionNegotiation(t *testing.T) {
	h, err := ParseHello([]byte(helloFixture))
	if err != nil {
		t.Fatal(err)
	}
	if _, err := Negotiate(h, "another-session", 1); code(err) != "SESSION_MISMATCH" {
		t.Fatal(err)
	}
	if _, err := Negotiate(h, "wayland-1", 2); code(err) != "SESSION_MISMATCH" {
		t.Fatal(err)
	}
	accepted, err := Negotiate(h, "wayland-1", 1)
	if err != nil {
		t.Fatal(err)
	}
	if accepted.Type != "hello_ack" || accepted.MaxFrameBytes != MaxFrameBytes || len(accepted.Capabilities) != 5 {
		t.Fatal(accepted)
	}
	if !reflect.DeepEqual(accepted.Capabilities, []string{"events", "explain", "policy.observe", "policy.simulate", "snapshot"}) {
		t.Fatal(accepted.Capabilities)
	}
}

func TestStrictHelloSecurity(t *testing.T) {
	bad := map[string]string{
		"wrong-major":             strings.Replace(helloFixture, `"major":1`, `"major":2`, 1),
		"new-minor":               strings.Replace(helloFixture, `"minor":0`, `"minor":9`, 1),
		"unrecognized-capability": strings.Replace(helloFixture, `"events"`, `"shell.exec"`, 1),
		"duplicate-capability":    strings.Replace(helloFixture, `"events"`, `"snapshot"`, 1),
		"duplicate-json-key":      strings.Replace(helloFixture, `"client_version":"2.0"`, `"client_version":"2.0","client":"evil"`, 1),
		"invalid-session-id":      strings.ReplaceAll(helloFixture, "wayland-1", "../other-user"),
		"zero-epoch":              strings.Replace(helloFixture, `"session_epoch":1`, `"session_epoch":0`, 1),
		"extra-field":             strings.Replace(helloFixture, `"session_epoch":1`, `"session_epoch":1,"password":"leak"`, 1),
		"negative-zero":           strings.Replace(helloFixture, `"session_epoch":1`, `"session_epoch":-0e-3`, 1),
		"broken-utf16":            strings.Replace(helloFixture, `"client":"cortetsu-shell"`, `"client":"\ud800"`, 1),
	}
	for name, s := range bad {
		t.Run(name, func(t *testing.T) {
			if _, err := ParseHello([]byte(s)); err == nil {
				t.Fatalf("accepted %s", s)
			}
		})
	}
}

func TestRequestReadOnlyContracts(t *testing.T) {
	s := sessionFor(t, "wayland-1", 1)
	req, err := ParseRequest([]byte(requestFixture), s)
	if err != nil || req.Op != "snapshot.get" {
		t.Fatalf("%+v %v", req, err)
	}
	for name, sample := range map[string]string{
		"wrong-session":      strings.ReplaceAll(requestFixture, "wayland-1", "wayland-2"),
		"wrong-epoch":        strings.Replace(requestFixture, `"session_epoch":1`, `"session_epoch":2`, 1),
		"mutating-operation": strings.Replace(requestFixture, `"op":"snapshot.get"`, `"op":"display.profile.preview"`, 1),
		"command-injection":  strings.Replace(requestFixture, `"op":"snapshot.get"`, `"op":"shell.exec"`, 1),
		"bad-arguments":      strings.Replace(requestFixture, `"domains":["power","display"]`, `"secret":"credential"`, 1),
		"truncated":          requestFixture[:len(requestFixture)-2],
	} {
		t.Run(name, func(t *testing.T) {
			if _, err := ParseRequest([]byte(sample), s); err == nil {
				t.Fatal("request accepted")
			}
		})
	}
	if _, err := ParseRequest([]byte(strings.Repeat(" ", MaxFrameBytes+1)), s); code(err) != "FRAME_TOO_LARGE" {
		t.Fatal(err)
	}
}

func TestSessionIsolation(t *testing.T) {
	first := sessionFor(t, "wayland-1", 1)
	second := sessionFor(t, "wayland-2", 1)
	sameRequest := []byte(requestFixture)
	if _, err := ParseRequest(sameRequest, first); err != nil {
		t.Fatal(err)
	}
	if _, err := ParseRequest(sameRequest, second); code(err) != "SESSION_MISMATCH" {
		t.Fatal(err)
	}
	// A new login epoch cannot accidentally reuse a stale request id.
	secondEpoch := *first
	secondEpoch.SessionEpoch = 2
	if _, err := ParseRequest(sameRequest, &secondEpoch); code(err) != "SESSION_MISMATCH" {
		t.Fatal(err)
	}
}

func TestSimulateAllowedButNeverExecute(t *testing.T) {
	s := sessionFor(t, "wayland-1", 1)
	valid := `{"type":"request","protocol":"cortetsu.ipc","version":{"major":1,"minor":0},"id":"123e4567-e89b-12d3-a456-426614174000","op":"policy.simulate","session_id":"wayland-1","session_epoch":1,"deadline_ms":5000,"body":{"at_unix_ms":123456,"event":{"domain":"power","type":"battery.changed","emitted_at_unix_ms":123456,"fields":{"level":"low"}},"rules":[{"id":"low","enabled":true,"mode":"simulate","domain":"power","event_type":"battery.changed","resource":"power","operation":"power.profile.set","priority":3,"cooldown_ms":1000,"ttl_ms":60000}]}}`
	if _, err := ParseRequest([]byte(valid), s); err != nil {
		t.Fatal(err)
	}
	denied := strings.Replace(valid, `"mode":"simulate"`, `"mode":"active","operation":"arbitrary.command"`, 1)
	if _, err := ParseRequest([]byte(denied), s); err == nil {
		t.Fatal("arbitrary operation passed")
	}
}

func TestReadAndWriteFraming(t *testing.T) {
	var output bytes.Buffer
	msg := map[string]string{"msg": "ábol \n"}
	if err := WriteFrame(&output, msg); err != nil {
		t.Fatal(err)
	}
	original := output.String()
	out, err := NewFrameReader(strings.NewReader(original)).Read()
	if err != nil || string(out) != strings.TrimSuffix(original, "\n") {
		t.Fatalf("%q %v", out, err)
	}
	out, err = NewFrameReader(strings.NewReader(original)).Read()
	if err != nil || len(out) == 0 {
		t.Fatal(err)
	}
	if _, err = NewFrameReader(strings.NewReader(`{"msg":"partial"}`)).Read(); code(err) != "INVALID_REQUEST" {
		t.Fatal(err)
	}
	if _, err = NewFrameReader(strings.NewReader(strings.Repeat("X", MaxFrameBytes+1) + "\n")).Read(); code(err) != "FRAME_TOO_LARGE" {
		t.Fatal(err)
	}
	if _, err = NewFrameReader(strings.NewReader("")).Read(); !errors.Is(err, io.EOF) {
		t.Fatal(err)
	}
}

func FuzzIPCFrame(f *testing.F) {
	f.Add([]byte(helloFixture))
	f.Add([]byte(requestFixture))
	f.Add([]byte(`{"type":"hello","type":"request"}`))
	f.Fuzz(func(t *testing.T, payload []byte) {
		if len(payload) > MaxFrameBytes+100 {
			t.Skip()
		}
		_, _ = ParseHello(payload)
		_, _ = ParseRequest(payload, &Negotiated{SessionID: "wayland-1", SessionEpoch: 1, Capabilities: []string{"snapshot"}})
	})
}

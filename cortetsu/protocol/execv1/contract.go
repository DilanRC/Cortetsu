// Package execv1 validates the proposed Cortetsu helper wire contract.
// This package performs no I/O or mutations; adapters remain disabled until
// capability, readback, idempotency journal and recovery gates are complete.
package execv1

import (
	"bytes"
	"encoding/json"
	"errors"
	"io"
	"math"
	"regexp"
	"strconv"
	"unicode/utf8"
)

const (
	maxSafeInteger uint64 = 9007199254740991
	Protocol              = "cortetsu.exec"
	Major                 = 1
	Minor                 = 0
	MaxBytes              = 64 * 1024
	MaxDeadlineMs         = 60_000
)

// Error code is a stable, safe value: never include the submitted payload.
type Error struct{ Code string }

func (e *Error) Error() string { return e.Code }
func invalid() error           { return &Error{Code: "INVALID_REQUEST"} }

var uuid = regexp.MustCompile(`(?i)^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$`)

// Version is intentionally separate from the Cortetsu product version.
type Version struct {
	Major uint32 `json:"major"`
	Minor uint32 `json:"minor"`
}

type Request struct {
	Protocol         string          `json:"protocol"`
	Version          Version         `json:"version"`
	RequestID        string          `json:"request_id"`
	Operation        string          `json:"operation"`
	DeadlineMs       int64           `json:"deadline_ms"`
	ExpectedRevision *uint64         `json:"expected_revision,omitempty"`
	IdempotencyKey   string          `json:"idempotency_key,omitempty"`
	Arguments        json.RawMessage `json:"arguments"`
}

type Response struct {
	Protocol      string          `json:"protocol"`
	Version       Version         `json:"version"`
	RequestID     string          `json:"request_id"`
	Outcome       string          `json:"outcome"`
	Verified      bool            `json:"verified"`
	TransactionID string          `json:"transaction_id,omitempty"`
	Error         *Failure        `json:"error,omitempty"`
	Body          json.RawMessage `json:"body"`
}

type Failure struct {
	Code      string `json:"code"`
	Retryable bool   `json:"retryable"`
}

var failureCodes = map[string]bool{
	"INCOMPATIBLE_PROTOCOL": true, "UNSUPPORTED_CAPABILITY": true,
	"INVALID_REQUEST": true, "FRAME_TOO_LARGE": true, "RATE_LIMITED": true,
	"STATE_STALE": true, "SESSION_MISMATCH": true, "POLICY_CONFLICT": true,
	"USER_CONFIRMATION_REQUIRED": true, "OWNER_UNAVAILABLE": true,
	"PERMISSION_DENIED": true, "DEADLINE_EXCEEDED": true,
	"IDEMPOTENCY_CONFLICT": true, "APPLY_FAILED": true,
	"APPLY_VERIFICATION_FAILED": true, "ROLLBACK_FAILED": true,
	"RECOVERY_REQUIRED": true, "SECRET_TRANSPORT_DENIED": true,
	"INTERNAL_REDACTED": true,
}

// checkValue walks every object, detecting duplicate keys including in nested
// arguments. JSON number tokens are interpreted as IEEE-754 binary64, as
// required before RFC 8785 canonicalisation, rejecting negative zero.
func checkValue(d *json.Decoder) error {
	token, err := d.Token()
	if err != nil {
		return invalid()
	}
	switch v := token.(type) {
	case json.Delim:
		switch v {
		case '{':
			seen := map[string]bool{}
			for d.More() {
				keyToken, err := d.Token()
				if err != nil {
					return invalid()
				}
				key, ok := keyToken.(string)
				if !ok || seen[key] {
					return invalid()
				}
				seen[key] = true
				if err := checkValue(d); err != nil {
					return err
				}
			}
			end, err := d.Token()
			if err != nil || end != json.Delim('}') {
				return invalid()
			}
		case '[':
			for d.More() {
				if err := checkValue(d); err != nil {
					return err
				}
			}
			end, err := d.Token()
			if err != nil || end != json.Delim(']') {
				return invalid()
			}
		default:
			return invalid()
		}
	case json.Number:
		number, err := strconv.ParseFloat(string(v), 64)
		if err != nil || math.IsInf(number, 0) || math.IsNaN(number) || (number == 0 && math.Signbit(number)) {
			return invalid()
		}
	}
	return nil
}

// strictDecode enforces frame limits, a single JSON value, valid UTF-8,
// duplicate-free objects, finite binary64 numbers and no unknown struct keys.
func strictDecode(data []byte, result any) error {
	if len(data) > MaxBytes {
		return &Error{Code: "FRAME_TOO_LARGE"}
	}
	if len(bytes.TrimSpace(data)) == 0 || !utf8.Valid(data) || !validEscapedSurrogates(data) {
		return invalid()
	}
	d := json.NewDecoder(bytes.NewReader(data))
	d.UseNumber()
	if err := checkValue(d); err != nil {
		return err
	}
	if _, err := d.Token(); !errors.Is(err, io.EOF) {
		return invalid()
	}
	d = json.NewDecoder(bytes.NewReader(data))
	d.DisallowUnknownFields()
	if err := d.Decode(result); err != nil {
		return invalid()
	}
	if _, err := d.Token(); !errors.Is(err, io.EOF) {
		return invalid()
	}
	return nil
}

func checkVersion(protocol string, v Version) error {
	if protocol != Protocol || v.Major != Major {
		return &Error{Code: "INCOMPATIBLE_PROTOCOL"}
	}
	if v.Minor > Minor {
		return &Error{Code: "UNSUPPORTED_CAPABILITY"}
	}
	return nil
}

func checkObject(raw json.RawMessage, target any) error {
	if trimmed := bytes.TrimSpace(raw); len(trimmed) == 0 || trimmed[0] != '{' {
		return invalid()
	}
	return strictDecode(raw, target)
}

// ParseRequest validates the envelope and operation-specific argument shape.
// A valid mutating request is NOT permission to execute: capability checks,
// lock, journal, readback and transaction owner remain mandatory in Rust.
func ParseRequest(data []byte) (*Request, error) {
	if len(data) > MaxBytes {
		return nil, &Error{Code: "FRAME_TOO_LARGE"}
	}
	if first := bytes.TrimSpace(data); len(first) == 0 || first[0] != '{' {
		return nil, invalid()
	}
	var r Request
	if err := strictDecode(data, &r); err != nil {
		return nil, err
	}
	if err := checkVersion(r.Protocol, r.Version); err != nil {
		return nil, err
	}
	if !uuid.MatchString(r.RequestID) || r.DeadlineMs <= 0 || r.DeadlineMs > MaxDeadlineMs {
		return nil, invalid()
	}
	if r.IdempotencyKey != "" && !uuid.MatchString(r.IdempotencyKey) {
		return nil, invalid()
	}
	var mutation bool
	var argument any
	switch r.Operation {
	case "gamemode.status", "power.status", "display.status", "system.verify":
		argument = &struct{}{}
	case "gamemode.set":
		mutation = true
		argument = &struct {
			Enabled *bool `json:"enabled"`
		}{}
	case "power.profile.set":
		mutation = true
		argument = &struct {
			Profile string `json:"profile"`
		}{}
	case "display.profile.preview":
		mutation = true
		argument = &struct {
			Monitor string `json:"monitor"`
			Profile string `json:"profile"`
		}{}
	default:
		return nil, &Error{Code: "UNSUPPORTED_CAPABILITY"}
	}
	if err := checkObject(r.Arguments, argument); err != nil {
		return nil, err
	}
	if r.ExpectedRevision != nil && *r.ExpectedRevision > maxSafeInteger {
		return nil, invalid()
	}
	if mutation && (r.ExpectedRevision == nil || r.IdempotencyKey == "") {
		return nil, invalid()
	}
	switch args := argument.(type) {
	case *struct {
		Enabled *bool `json:"enabled"`
	}:
		if args.Enabled == nil {
			return nil, invalid()
		}
	case *struct {
		Profile string `json:"profile"`
	}:
		if args.Profile != "balanced" && args.Profile != "power-saver" && args.Profile != "performance" {
			return nil, invalid()
		}
	case *struct {
		Monitor string `json:"monitor"`
		Profile string `json:"profile"`
	}:
		if args.Monitor == "" || len(args.Monitor) > 128 || args.Profile == "" || len(args.Profile) > 128 {
			return nil, invalid()
		}
	}
	return &r, nil
}

// ParseResponse rejects a nominal success without explicit verification.
// No contract consumer should equate process exit code 0 with an applied write.
func ParseResponse(data []byte) (*Response, error) {
	if first := bytes.TrimSpace(data); len(first) == 0 || first[0] != '{' {
		return nil, invalid()
	}
	var r Response
	if err := strictDecode(data, &r); err != nil {
		return nil, err
	}
	if err := checkVersion(r.Protocol, r.Version); err != nil {
		return nil, err
	}
	if !uuid.MatchString(r.RequestID) {
		return nil, invalid()
	}
	if err := checkObject(r.Body, &map[string]json.RawMessage{}); err != nil {
		return nil, err
	}
	if r.TransactionID != "" && !uuid.MatchString(r.TransactionID) {
		return nil, invalid()
	}
	switch r.Outcome {
	case "read", "applied":
		if !r.Verified || r.Error != nil {
			return nil, invalid()
		}
	case "rejected", "unknown":
		if r.Verified || r.Error == nil || !failureCodes[r.Error.Code] {
			return nil, invalid()
		}
	default:
		return nil, invalid()
	}
	return &r, nil
}

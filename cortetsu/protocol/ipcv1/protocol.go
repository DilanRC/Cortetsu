// Package ipcv1 validates the local, read-only Cortetsu IPC v1 contract.
// It does not create a socket or execute an operation: enabling a listener
// requires the session/ownership ADR and physical two-session gate.
package ipcv1

import (
	"bufio"
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"regexp"
	"slices"

	"github.com/DilanRC/Cortetsu/cortetsu/protocol/execv1"
	"github.com/DilanRC/Cortetsu/cortetsu/protocol/policy"
)

const (
	Protocol      = "cortetsu.ipc"
	Major         = 1
	Minor         = 0
	MaxFrameBytes = 64 * 1024
	MaxDeadlineMs = 60000
)

var id = regexp.MustCompile(`^[a-zA-Z0-9][a-zA-Z0-9._:-]{0,127}$`)
var uuid = regexp.MustCompile(`(?i)^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$`)

var supportedCapabilities = []string{"snapshot", "events", "policy.observe", "policy.simulate", "explain", "system.verify"}

// Error never includes request bodies or session identifiers in its message.
type Error struct {
	Code      string `json:"code"`
	Retryable bool   `json:"retryable"`
}

func (e *Error) Error() string { return e.Code }
func fail(code string) error   { return &Error{Code: code} }

type Version struct {
	Major uint32 `json:"major"`
	Minor uint32 `json:"minor"`
}

type Hello struct {
	Type          string   `json:"type"`
	Protocol      string   `json:"protocol"`
	Version       Version  `json:"version"`
	Client        string   `json:"client"`
	ClientVersion string   `json:"client_version"`
	SessionID     string   `json:"session_id"`
	SessionEpoch  uint64   `json:"session_epoch"`
	Capabilities  []string `json:"capabilities"`
}

type Negotiated struct {
	Type          string   `json:"type"`
	Protocol      string   `json:"protocol"`
	Version       Version  `json:"version"`
	SessionID     string   `json:"session_id"`
	SessionEpoch  uint64   `json:"session_epoch"`
	Capabilities  []string `json:"capabilities"`
	MaxFrameBytes int      `json:"max_frame_bytes"`
}

type Request struct {
	Type         string          `json:"type"`
	Protocol     string          `json:"protocol"`
	Version      Version         `json:"version"`
	ID           string          `json:"id"`
	Op           string          `json:"op"`
	SessionID    string          `json:"session_id"`
	SessionEpoch uint64          `json:"session_epoch"`
	DeadlineMs   int64           `json:"deadline_ms"`
	Body         json.RawMessage `json:"body"`
}

func checkVersion(protocol string, v Version) error {
	if protocol != Protocol || v.Major != Major {
		return fail("INCOMPATIBLE_PROTOCOL")
	}
	if v.Minor > Minor {
		return fail("UNSUPPORTED_CAPABILITY")
	}
	return nil
}

// decode rejects duplicate keys anywhere, ambiguous Unicode, non-finite
// numbers, oversized requests and unexpected fields before using the data.
func decode(data []byte, target any) error {
	if len(data) > MaxFrameBytes {
		return fail("FRAME_TOO_LARGE")
	}
	if _, err := execv1.Canonicalize(data); err != nil {
		var contract *execv1.Error
		if errors.As(err, &contract) && contract.Code == "FRAME_TOO_LARGE" {
			return fail("FRAME_TOO_LARGE")
		}
		return fail("INVALID_REQUEST")
	}
	decoder := json.NewDecoder(bytes.NewReader(data))
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(target); err != nil {
		return fail("INVALID_REQUEST")
	}
	if _, err := decoder.Token(); !errors.Is(err, io.EOF) {
		return fail("INVALID_REQUEST")
	}
	return nil
}

func ParseHello(data []byte) (*Hello, error) {
	var h Hello
	if err := decode(data, &h); err != nil {
		return nil, err
	}
	if err := checkVersion(h.Protocol, h.Version); err != nil {
		return nil, err
	}
	if h.Type != "hello" || !id.MatchString(h.Client) || len(h.ClientVersion) == 0 || len(h.ClientVersion) > 128 ||
		!id.MatchString(h.SessionID) || h.SessionEpoch == 0 || len(h.Capabilities) > len(supportedCapabilities) {
		return nil, fail("INVALID_REQUEST")
	}
	seen := map[string]bool{}
	for _, cap := range h.Capabilities {
		if seen[cap] || !slices.Contains(supportedCapabilities, cap) {
			return nil, fail("UNSUPPORTED_CAPABILITY")
		}
		seen[cap] = true
	}
	return &h, nil
}

func Negotiate(h *Hello, expectedSession string, expectedEpoch uint64) (*Negotiated, error) {
	if h == nil || h.SessionID != expectedSession || h.SessionEpoch != expectedEpoch || expectedEpoch == 0 {
		return nil, fail("SESSION_MISMATCH")
	}
	caps := slices.Clone(h.Capabilities)
	slices.Sort(caps)
	return &Negotiated{Type: "hello_ack", Protocol: Protocol, Version: Version{Major: Major, Minor: Minor},
		SessionID: h.SessionID, SessionEpoch: h.SessionEpoch, Capabilities: caps, MaxFrameBytes: MaxFrameBytes}, nil
}

func checkBody(raw json.RawMessage, dest any) error {
	if len(raw) == 0 || raw[0] != '{' {
		return fail("INVALID_REQUEST")
	}
	return decode(raw, dest)
}

func ParseRequest(data []byte, session *Negotiated) (*Request, error) {
	if session == nil {
		return nil, fail("SESSION_MISMATCH")
	}
	var r Request
	if err := decode(data, &r); err != nil {
		return nil, err
	}
	if err := checkVersion(r.Protocol, r.Version); err != nil {
		return nil, err
	}
	if r.Type != "request" || !uuid.MatchString(r.ID) || r.DeadlineMs <= 0 || r.DeadlineMs > MaxDeadlineMs {
		return nil, fail("INVALID_REQUEST")
	}
	if r.SessionID != session.SessionID || r.SessionEpoch != session.SessionEpoch {
		return nil, fail("SESSION_MISMATCH")
	}
	switch r.Op {
	case "system.verify":
		if !slices.Contains(session.Capabilities, "system.verify") {
			return nil, fail("UNSUPPORTED_CAPABILITY")
		}
		if err := checkBody(r.Body, &struct{}{}); err != nil {
			return nil, err
		}
	case "snapshot.get":
		if !slices.Contains(session.Capabilities, "snapshot") {
			return nil, fail("UNSUPPORTED_CAPABILITY")
		}
		var args struct {
			Domains []string `json:"domains"`
		}
		if err := checkBody(r.Body, &args); err != nil {
			return nil, err
		}
		if len(args.Domains) > 32 {
			return nil, fail("INVALID_REQUEST")
		}
		for _, domain := range args.Domains {
			if !id.MatchString(domain) {
				return nil, fail("INVALID_REQUEST")
			}
		}
	case "policy.list":
		if !slices.Contains(session.Capabilities, "policy.observe") {
			return nil, fail("UNSUPPORTED_CAPABILITY")
		}
		if err := checkBody(r.Body, &struct{}{}); err != nil {
			return nil, err
		}
	case "explain.get":
		if !slices.Contains(session.Capabilities, "explain") {
			return nil, fail("UNSUPPORTED_CAPABILITY")
		}
		var args struct {
			TraceID string `json:"trace_id"`
		}
		if err := checkBody(r.Body, &args); err != nil {
			return nil, err
		}
		if !uuid.MatchString(args.TraceID) {
			return nil, fail("INVALID_REQUEST")
		}
	case "policy.simulate":
		if !slices.Contains(session.Capabilities, "policy.simulate") {
			return nil, fail("UNSUPPORTED_CAPABILITY")
		}
		var args struct {
			AtUnixMs  int64                   `json:"at_unix_ms"`
			Event     policy.Event            `json:"event"`
			Rules     []policy.Rule           `json:"rules"`
			Overrides []policy.ManualOverride `json:"overrides"`
		}
		if err := checkBody(r.Body, &args); err != nil {
			return nil, err
		}
		if args.AtUnixMs <= 0 || len(args.Rules) > 128 || len(args.Overrides) > 128 {
			return nil, fail("INVALID_REQUEST")
		}
		if _, err := policy.NewEngine().Evaluate(args.AtUnixMs, args.Event, args.Rules, args.Overrides); err != nil {
			return nil, fail("INVALID_REQUEST")
		}
	default:
		// Neither shell/exec nor any mutating operation is admitted by this
		// phase. F8 may add typed mutations only after a durable Rust journal.
		return nil, fail("UNSUPPORTED_CAPABILITY")
	}
	return &r, nil
}

// FrameReader bounds each newline-delimited message without reading a byte at
// a time from the UNIX socket. A partial frame at EOF is always invalid.
// The buffered reader must be reused for a whole client connection.
type FrameReader struct{ reader *bufio.Reader }

func NewFrameReader(source io.Reader) *FrameReader {
	if source == nil {
		return &FrameReader{}
	}
	return &FrameReader{reader: bufio.NewReaderSize(source, 4096)}
}

func (r *FrameReader) Read() ([]byte, error) {
	if r == nil || r.reader == nil {
		return nil, fail("INVALID_REQUEST")
	}
	frame := make([]byte, 0, 4096)
	for {
		part, err := r.reader.ReadSlice('\n')
		if len(frame)+len(part) > MaxFrameBytes+1 {
			return nil, fail("FRAME_TOO_LARGE")
		}
		frame = append(frame, part...)
		if err == nil {
			frame = frame[:len(frame)-1]
			if len(frame) == 0 || len(frame) > MaxFrameBytes {
				return nil, fail("INVALID_REQUEST")
			}
			return frame, nil
		}
		if errors.Is(err, bufio.ErrBufferFull) {
			continue
		}
		if errors.Is(err, io.EOF) && len(frame) == 0 {
			return nil, io.EOF
		}
		return nil, fail("INVALID_REQUEST")
	}
}

func WriteFrame(w io.Writer, v any) error {
	data, err := json.Marshal(v)
	if err != nil {
		return fmt.Errorf("cannot encode frame: %w", err)
	}
	if len(data) > MaxFrameBytes {
		return fail("FRAME_TOO_LARGE")
	}
	data = append(data, '\n')
	for len(data) > 0 {
		n, err := w.Write(data)
		if err != nil {
			return err
		}
		if n == 0 {
			return io.ErrShortWrite
		}
		data = data[n:]
	}
	return nil
}

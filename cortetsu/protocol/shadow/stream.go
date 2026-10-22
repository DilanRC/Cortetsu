// Package shadow provides a no-side-effect, NDJSON event trace evaluator.
// Only snapshots from a trusted source can clear a stale producer; neither
// this library nor its CLI connects to Hyprland or applies an operation.
package shadow

import (
	"bufio"
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"io"

	"github.com/DilanRC/Cortetsu/cortetsu/protocol/execv1"
	"github.com/DilanRC/Cortetsu/cortetsu/protocol/policy"
	"github.com/DilanRC/Cortetsu/cortetsu/protocol/policyaudit"
)

const MaxLineBytes = 64 * 1024

type Input struct {
	Type      string                  `json:"type"`
	Producer  string                  `json:"producer,omitempty"`
	Cursor    *policy.Cursor          `json:"cursor,omitempty"`
	Event     *policy.Event           `json:"event,omitempty"`
	NowUnixMs int64                   `json:"now_unix_ms,omitempty"`
	Overrides []policy.ManualOverride `json:"overrides,omitempty"`
}

type Result struct {
	Type      string            `json:"type"`
	Status    string            `json:"status"`
	Decisions []policy.Decision `json:"decisions,omitempty"`
}

func decode(raw []byte, target any) error {
	if len(raw) > MaxLineBytes {
		return errors.New("FRAME_TOO_LARGE")
	}
	if _, err := execv1.Canonicalize(raw); err != nil {
		return errors.New("INVALID_REQUEST")
	}
	d := json.NewDecoder(bytes.NewReader(raw))
	d.DisallowUnknownFields()
	if err := d.Decode(target); err != nil {
		return errors.New("INVALID_REQUEST")
	}
	if _, err := d.Token(); !errors.Is(err, io.EOF) {
		return errors.New("INVALID_REQUEST")
	}
	return nil
}

// Run consumes user-supplied trace events and writes only decisions. It never
// emits event payloads, secrets or the raw input to stdout/stderr.
func Run(input io.Reader, output io.Writer, rules []policy.Rule) error {
	return RunWithAudit(input, output, rules, nil)
}

// RunWithAudit optionally persists redacted decisions, but never actions.
func RunWithAudit(input io.Reader, output io.Writer, rules []policy.Rule, audit *policyaudit.Ledger) error {
	if input == nil || output == nil {
		return errors.New("missing stream")
	}
	if len(rules) > 1024 {
		return errors.New("too many rules")
	}
	observer := policy.NewObserver()
	engine := policy.NewEngine()
	scanner := bufio.NewScanner(input)
	scanner.Buffer(make([]byte, 4096), MaxLineBytes+2)
	for scanner.Scan() {
		raw := scanner.Bytes()
		if len(raw) > MaxLineBytes {
			return errors.New("FRAME_TOO_LARGE")
		}
		var next Input
		if err := decode(raw, &next); err != nil {
			return err
		}
		var result Result
		switch next.Type {
		case "snapshot":
			if next.Event != nil || next.Cursor == nil || next.NowUnixMs != 0 || len(next.Overrides) != 0 {
				return errors.New("INVALID_REQUEST")
			}
			if err := observer.Snapshot(next.Producer, *next.Cursor); err != nil {
				return errors.New("INVALID_REQUEST")
			}
			result = Result{Type: "cursor", Status: "SNAPSHOT_SET"}
		case "event":
			if next.Cursor != nil || next.Event == nil || next.Producer != "" || next.NowUnixMs <= 0 {
				return errors.New("INVALID_REQUEST")
			}
			status, err := observer.Accept(*next.Event)
			if err != nil {
				return errors.New("INVALID_REQUEST")
			}
			result = Result{Type: "observation", Status: status}
			if status == "APPLIED_OBSERVATION" {
				decisions, err := engine.Evaluate(next.NowUnixMs, *next.Event, rules, next.Overrides)
				if err != nil {
					return errors.New("INVALID_REQUEST")
				}
				result.Decisions = decisions
				if audit != nil {
					for _, d := range decisions {
						record, err := policyaudit.NewRecord(*next.Event, d, next.NowUnixMs)
						if err != nil {
							return err
						}
						if err := audit.Append(record); err != nil {
							return err
						}
					}
				}
			}
		default:
			return errors.New("INVALID_REQUEST")
		}
		b, err := json.Marshal(result)
		if err != nil {
			return errors.New("ENCODE_ERROR")
		}
		if _, err := fmt.Fprintln(output, string(b)); err != nil {
			return err
		}
	}
	if err := scanner.Err(); err != nil {
		if errors.Is(err, bufio.ErrTooLong) {
			return errors.New("FRAME_TOO_LARGE")
		}
		return errors.New("INVALID_REQUEST")
	}
	return nil
}

func ReadRules(raw []byte) ([]policy.Rule, error) {
	if len(raw) > MaxLineBytes {
		return nil, errors.New("FRAME_TOO_LARGE")
	}
	var rules []policy.Rule
	if err := decode(raw, &rules); err != nil {
		return nil, err
	}
	if len(rules) > 1024 {
		return nil, errors.New("too many rules")
	}
	for _, r := range rules {
		if err := r.Validate(); err != nil {
			return nil, errors.New("INVALID_REQUEST")
		}
	}
	return rules, nil
}

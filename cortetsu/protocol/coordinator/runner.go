// Package coordinator connects trusted observations to typed Rust owners.
// The policy engine remains pure; this boundary requires per-domain consent,
// fresh owner revisions and a durable, redacted intent before every mutation.
package coordinator

import (
	"context"
	"crypto/rand"
	"crypto/sha256"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"sync"
	"time"

	"github.com/DilanRC/Cortetsu/cortetsu/protocol/activation"
	"github.com/DilanRC/Cortetsu/cortetsu/protocol/execv1"
	"github.com/DilanRC/Cortetsu/cortetsu/protocol/policy"
	"github.com/DilanRC/Cortetsu/cortetsu/protocol/policyaudit"
)

type Executor interface {
	Execute(context.Context, execv1.Request) (*execv1.Response, error)
}
type cursor struct{ epoch, sequence uint64 }
type snapshot struct {
	Revision *uint64 `json:"revision"`
	Override int64   `json:"manual_override_until_unix_ms"`
	Dnd      *bool   `json:"dnd"`
	Enabled  *bool   `json:"enabled"`
	Profile  string  `json:"profile"`
}
type Runner struct {
	mu      sync.Mutex
	lastMu  sync.RWMutex
	session string
	rules   []policy.Rule
	config  activation.Store
	owner   Executor
	audit   policyaudit.Ledger
	engine  *policy.Engine
	cursors map[string]cursor
	last    []policy.Decision
}

func New(session string, rules []policy.Rule, config activation.Store, owner Executor, auditRoot string) (*Runner, error) {
	if session == "" || len(rules) > 128 || owner == nil {
		return nil, errors.New("INVALID_REQUEST")
	}
	seen := map[string]bool{}
	for _, r := range rules {
		if err := r.Validate(); err != nil || seen[r.ID] {
			return nil, errors.New("INVALID_REQUEST")
		}
		seen[r.ID] = true
		if r.Mode == "active" {
			revision := uint64(0)
			probe := request("00000000-0000-4000-8000-000000000001", r.Operation, r.Arguments)
			probe.ExpectedRevision = &revision
			probe.IdempotencyKey = probe.RequestID
			raw, _ := json.Marshal(probe)
			if _, err := execv1.ParseRequest(raw); err != nil {
				return nil, errors.New("INVALID_REQUEST")
			}
		}
	}
	return &Runner{session: session, rules: append([]policy.Rule(nil), rules...), config: config, owner: owner, audit: policyaudit.Ledger{Root: auditRoot}, engine: policy.NewEngine(), cursors: map[string]cursor{}}, nil
}
func uuidFrom(b []byte) string {
	return fmt.Sprintf("%x-%x-%x-%x-%x", b[0:4], b[4:6], b[6:8], b[8:10], b[10:16])
}
func RandomID() (string, error) {
	var raw [16]byte
	if _, err := rand.Read(raw[:]); err != nil {
		return "", err
	}
	raw[6] = (raw[6] & 15) | 64
	raw[8] = (raw[8] & 63) | 128
	return uuidFrom(raw[:]), nil
}
func request(id, op string, args json.RawMessage) execv1.Request {
	return execv1.Request{Protocol: execv1.Protocol, Version: execv1.Version{Major: 1}, RequestID: id, Operation: op, DeadlineMs: 5000, Arguments: args}
}
func (r *Runner) read(ctx context.Context, domain string) (snapshot, error) {
	id, err := RandomID()
	if err != nil {
		return snapshot{}, err
	}
	reply, err := r.owner.Execute(ctx, request(id, domain+".status", json.RawMessage(`{}`)))
	var s snapshot
	if err != nil || reply == nil || reply.RequestID != id || reply.Outcome != "read" || !reply.Verified || reply.Error != nil {
		return s, errors.New("OWNER_UNAVAILABLE")
	}
	if err = json.Unmarshal(reply.Body, &s); err != nil || s.Revision == nil || *s.Revision > 9007199254740991 || s.Override < 0 {
		return snapshot{}, errors.New("OWNER_UNAVAILABLE")
	}
	switch domain {
	case "notifications":
		if s.Dnd == nil {
			return snapshot{}, errors.New("OWNER_UNAVAILABLE")
		}
	case "gamemode":
		if s.Enabled == nil {
			return snapshot{}, errors.New("OWNER_UNAVAILABLE")
		}
	case "power":
		if s.Profile != "power-saver" && s.Profile != "balanced" && s.Profile != "performance" {
			return snapshot{}, errors.New("OWNER_UNAVAILABLE")
		}
	}
	return s, nil
}
func satisfied(s snapshot, r policy.Rule) bool {
	switch r.Operation {
	case "notifications.dnd.set", "gamemode.set":
		var a struct {
			Enabled bool `json:"enabled"`
		}
		if json.Unmarshal(r.Arguments, &a) != nil {
			return false
		}
		current := s.Enabled
		if r.Resource == "notifications" {
			current = s.Dnd
		}
		return current != nil && *current == a.Enabled
	case "power.profile.set":
		var a struct {
			Profile string `json:"profile"`
		}
		return json.Unmarshal(r.Arguments, &a) == nil && s.Profile == a.Profile
	}
	return false
}
func (r *Runner) record(ev policy.Event, d policy.Decision, now int64) error {
	// No user state is created by a simulation. Only an explicitly active
	// domain reaches this journal, and a non-private existing root is refused.
	if err := os.MkdirAll(r.audit.Root, 0700); err != nil {
		return err
	}
	entry, err := policyaudit.NewRecord(ev, d, now)
	if err != nil {
		return err
	}
	return r.audit.Append(entry)
}
func (r *Runner) Last() []policy.Decision {
	r.lastMu.RLock()
	defer r.lastMu.RUnlock()
	return append([]policy.Decision(nil), r.last...)
}
func (r *Runner) setLast(d []policy.Decision) {
	r.lastMu.Lock()
	defer r.lastMu.Unlock()
	r.last = append([]policy.Decision(nil), d...)
}

// Handle accepts an authoritative current observation, never a replay supplied
// by an IPC client. Duplicate cursors, foreign sessions and stale observations
// cannot become mutations. The event contains only redacted, allowed fields.
func (r *Runner) Handle(ctx context.Context, ev policy.Event) ([]policy.Decision, error) {
	r.mu.Lock()
	defer r.mu.Unlock()
	now := time.Now().UnixMilli()
	if ev.Session != r.session || ev.Epoch == 0 || ev.Sequence == 0 || ev.EmittedAtUnixMs <= 0 || ev.EmittedAtUnixMs > now || now-ev.EmittedAtUnixMs > 5000 {
		return nil, errors.New("STATE_STALE")
	}
	stream := ev.Producer + "\x00" + ev.Domain
	old := r.cursors[stream]
	if old.epoch == ev.Epoch && old.sequence >= ev.Sequence {
		return nil, nil
	}
	if old.epoch != ev.Epoch {
		r.engine.InvalidateStability(ev.Session, ev.Domain, r.rules)
	}
	r.cursors[stream] = cursor{ev.Epoch, ev.Sequence}
	if ev.Fields["state"] == "unavailable" {
		r.engine.InvalidateStability(ev.Session, ev.Domain, r.rules)
		return nil, nil
	}
	config, err := r.config.Read()
	if err != nil {
		return nil, err
	}
	owners := map[string]bool{}
	snapshots := map[string]snapshot{}
	var overrides []policy.ManualOverride
	relevant := map[string]bool{}
	for _, rule := range r.rules {
		if rule.Enabled && rule.Mode == "active" && rule.Domain == ev.Domain && rule.EventType == ev.Type {
			relevant[rule.Resource] = true
		}
	}
	for domain, session := range config.Owners {
		if session != r.session || !relevant[domain] {
			continue
		}
		s, err := r.read(ctx, domain)
		if err != nil {
			continue
		}
		owners[domain] = true
		snapshots[domain] = s
		until := s.Override
		if config.Overrides[domain] > until {
			until = config.Overrides[domain]
		}
		overrides = append(overrides, policy.ManualOverride{Resource: domain, UntilUnixMs: until})
	}
	decisions, err := r.engine.EvaluateAuthorized(now, ev, r.rules, overrides, owners)
	if err != nil {
		return nil, err
	}
	byID := map[string]policy.Rule{}
	for _, rule := range r.rules {
		byID[rule.ID] = rule
	}
	for i := range decisions {
		d := &decisions[i]
		if d.Outcome != "SELECTED" {
			continue
		}
		rule := byID[d.RuleID]
		before := snapshots[d.Resource]
		if satisfied(before, rule) {
			d.Outcome = "UNCHANGED"
			d.Reason = "ALREADY_SATISFIED"
			continue
		}
		// Re-read revocation/override immediately before constructing the
		// request. Already in-flight transactions finish under the Rust lock.
		current, err := r.config.Read()
		if err != nil || current.Owners[d.Resource] != r.session || current.Overrides[d.Resource] > time.Now().UnixMilli() {
			d.Outcome = "BLOCKED"
			d.Reason = "CONSENT_REVOKED"
			continue
		}
		if time.Now().UnixMilli()-ev.EmittedAtUnixMs > rule.TTLms {
			d.Outcome = "BLOCKED"
			d.Reason = "EVENT_EXPIRED"
			continue
		}
		seed, _ := json.Marshal(struct {
			Session         string
			Epoch, Sequence uint64
			Rule            string
			Arguments       json.RawMessage
		}{r.session, ev.Epoch, ev.Sequence, rule.ID, rule.Arguments})
		hash := sha256.Sum256(seed)
		hash[6] = (hash[6] & 15) | 80
		hash[8] = (hash[8] & 63) | 128
		key := uuidFrom(hash[:16])
		req := request(key, rule.Operation, rule.Arguments)
		req.ExpectedRevision = before.Revision
		req.IdempotencyKey = key
		intent := *d
		intent.Outcome = "INTENT"
		intent.Reason = "OWNER_REVISION_VERIFIED"
		if err := r.record(ev, intent, now); err != nil {
			d.Outcome = "BLOCKED"
			d.Reason = "AUDIT_UNAVAILABLE"
			continue
		}
		reply, err := r.owner.Execute(ctx, req)
		if err != nil || reply == nil || reply.RequestID != key {
			d.Outcome = "UNKNOWN"
			d.Reason = "OWNER_UNAVAILABLE"
		} else if reply.Error != nil {
			d.Outcome = "BLOCKED"
			d.Reason = reply.Error.Code
		} else if reply.Outcome != "applied" || !reply.Verified {
			d.Outcome = "UNKNOWN"
			d.Reason = "APPLY_VERIFICATION_FAILED"
		} else {
			after, err := r.read(ctx, d.Resource)
			if err != nil || *after.Revision <= *before.Revision || (d.Resource != "display" && !satisfied(after, rule)) {
				d.Outcome = "UNKNOWN"
				d.Reason = "APPLY_VERIFICATION_FAILED"
			} else {
				d.Outcome = "APPLIED"
				d.Reason = "RUST_READBACK_VERIFIED"
			}
		}
		if err := r.record(ev, *d, time.Now().UnixMilli()); err != nil {
			d.Outcome = "UNKNOWN"
			d.Reason = "AUDIT_UNAVAILABLE"
		}
	}
	r.setLast(decisions)
	return decisions, nil
}

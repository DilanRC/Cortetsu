// Package policy is a pure, deterministic policy simulator. Nothing in this
// package talks to a compositor, runs a command, or writes to disk. Go is not
// required to keep Cortetsu's manual desktop functions available.
package policy

import (
	"errors"
	"regexp"
	"slices"
	"strings"
	"sync"
)

var name = regexp.MustCompile(`^[a-zA-Z0-9][a-zA-Z0-9._:-]{0,127}$`)

var allowedEventFields = map[string]bool{
	"level": true, "source": true, "profile": true, "ac_online": true,
	"percentage_band": true, "monitor_count": true,
	"focused_fullscreen": true, "connected": true,
	"state": true, "game_running": true,
}

var allowedOperations = map[string]string{
	"gamemode.set":            "gamemode",
	"power.profile.set":       "power",
	"display.profile.preview": "display",
}

// Event holds only explicitly whitelisted, non-secret metadata. Never include
// Wi-Fi keys, notification contents, tokens or clipboard contents in fields.
type Event struct {
	Producer        string            `json:"producer"`
	Session         string            `json:"session"`
	Epoch           uint64            `json:"epoch"`
	Sequence        uint64            `json:"sequence"`
	EmittedAtUnixMs int64             `json:"emitted_at_unix_ms"`
	Domain          string            `json:"domain"`
	Type            string            `json:"type"`
	Fields          map[string]string `json:"fields,omitempty"`
}

type Condition struct {
	Field  string `json:"field"`
	Equals string `json:"equals"`
}

type Rule struct {
	ID           string      `json:"id"`
	Enabled      bool        `json:"enabled"`
	Mode         string      `json:"mode"`
	Domain       string      `json:"domain"`
	EventType    string      `json:"event_type"`
	Conditions   []Condition `json:"conditions,omitempty"`
	Resource     string      `json:"resource"`
	Operation    string      `json:"operation"`
	Priority     int         `json:"priority"`
	CooldownMs   int64       `json:"cooldown_ms"`
	HysteresisMs int64       `json:"hysteresis_ms,omitempty"`
	TTLms        int64       `json:"ttl_ms"`
}

// ManualOverride blocks automation for a resource until UntilUnixMs.
// A zero or negative deadline is never a valid override.
type ManualOverride struct {
	Resource    string `json:"resource"`
	UntilUnixMs int64  `json:"until_unix_ms"`
}

type Decision struct {
	Resource  string `json:"resource"`
	RuleID    string `json:"rule_id"`
	Operation string `json:"operation,omitempty"`
	Outcome   string `json:"outcome"`
	Reason    string `json:"reason"`
}

type Engine struct {
	mu            sync.Mutex
	lastSelection map[string]int64
	stableSince   map[string]int64
}

func NewEngine() *Engine {
	return &Engine{lastSelection: map[string]int64{}, stableSince: map[string]int64{}}
}

func (r Rule) Validate() error {
	if !name.MatchString(r.ID) || !name.MatchString(r.Domain) || !name.MatchString(r.EventType) || !name.MatchString(r.Resource) {
		return errors.New("invalid rule identifier")
	}
	if r.Priority < -1000 || r.Priority > 1000 || r.CooldownMs < 0 || r.HysteresisMs < 0 || r.HysteresisMs > 24*3600*1000 || r.TTLms <= 0 || r.TTLms > 7*24*3600*1000 {
		return errors.New("invalid priority, cooldown or ttl")
	}
	if r.Mode != "observe" && r.Mode != "simulate" && r.Mode != "active" {
		return errors.New("invalid policy mode")
	}
	if domain, ok := allowedOperations[r.Operation]; !ok || domain != r.Resource {
		return errors.New("operation/resource combination not supported")
	}
	if len(r.Conditions) > 32 {
		return errors.New("too many conditions")
	}
	for _, c := range r.Conditions {
		if !name.MatchString(c.Field) || !allowedEventFields[c.Field] || len(c.Equals) > 256 || strings.ContainsAny(c.Equals, "\r\n") {
			return errors.New("invalid condition")
		}
	}
	return nil
}

// Evaluate returns explanatory decisions; in this milestone it NEVER applies
// them. Even active rules return BLOCKED until a verified Rust owner exists.
// Ties are resolved by priority then lexicographically by rule ID.
func (e *Engine) Evaluate(nowMs int64, event Event, rules []Rule, overrides []ManualOverride) ([]Decision, error) {
	if e == nil || nowMs <= 0 || event.EmittedAtUnixMs <= 0 || !name.MatchString(event.Domain) || !name.MatchString(event.Type) || len(event.Fields) > 32 {
		return nil, errors.New("invalid evaluation context")
	}
	// Keep model state bounded even if a client invents new rule identifiers.
	for key, value := range event.Fields {
		if !allowedEventFields[key] || len(value) > 64 || strings.ContainsAny(value, "\r\n") {
			return nil, errors.New("non-whitelisted event metadata")
		}
	}
	e.mu.Lock()
	defer e.mu.Unlock()
	if e.lastSelection == nil {
		e.lastSelection = make(map[string]int64)
	}
	if e.stableSince == nil {
		e.stableSince = make(map[string]int64)
	}
	if len(rules) > 1024 {
		return nil, errors.New("too many rules")
	}
	seen := make(map[string]bool, len(rules))
	for _, rule := range rules {
		if err := rule.Validate(); err != nil {
			return nil, err
		}
		if seen[rule.ID] {
			return nil, errors.New("duplicate rule id")
		}
		seen[rule.ID] = true
	}
	candidates := slices.Clone(rules)
	slices.SortFunc(candidates, func(a, b Rule) int {
		if a.Priority > b.Priority {
			return -1
		}
		if a.Priority < b.Priority {
			return 1
		}
		return strings.Compare(a.ID, b.ID)
	})
	locks := make(map[string]int64, len(overrides))
	for _, lock := range overrides {
		if !name.MatchString(lock.Resource) || lock.UntilUnixMs < 0 {
			return nil, errors.New("invalid manual override")
		}
		if lock.UntilUnixMs > locks[lock.Resource] {
			locks[lock.Resource] = lock.UntilUnixMs
		}
	}
	selected := map[string]bool{}
	var results []Decision
	for _, r := range candidates {
		if !r.Enabled || r.Domain != event.Domain || r.EventType != event.Type {
			continue
		}
		matches := true
		key := event.Session + "\x00" + r.ID
		for _, c := range r.Conditions {
			if event.Fields[c.Field] != c.Equals {
				matches = false
				break
			}
		}
		if !matches {
			delete(e.stableSince, key)
			continue
		}
		d := Decision{Resource: r.Resource, RuleID: r.ID, Operation: r.Operation}
		switch {
		case selected[r.Resource]:
			d.Outcome, d.Reason = "BLOCKED", "LOWER_PRIORITY"
		case event.EmittedAtUnixMs > 0 && event.EmittedAtUnixMs > nowMs:
			d.Outcome, d.Reason = "BLOCKED", "EVENT_IN_FUTURE"
		case event.EmittedAtUnixMs > 0 && nowMs-event.EmittedAtUnixMs > r.TTLms:
			d.Outcome, d.Reason = "BLOCKED", "EVENT_EXPIRED"
		case locks[r.Resource] > nowMs:
			d.Outcome, d.Reason = "BLOCKED", "MANUAL_OVERRIDE"
		case r.HysteresisMs > 0 && (e.stableSince[key] == 0 || nowMs < e.stableSince[key] || nowMs-e.stableSince[key] < r.HysteresisMs):
			if e.stableSince[key] == 0 || nowMs < e.stableSince[key] {
				e.stableSince[key] = nowMs
			}
			d.Outcome, d.Reason = "BLOCKED", "STABILIZING"
		case e.lastSelection[key] != 0 && nowMs >= e.lastSelection[key] && nowMs-e.lastSelection[key] < r.CooldownMs:
			d.Outcome, d.Reason = "BLOCKED", "COOLDOWN"
		case r.Mode == "observe":
			d.Outcome, d.Reason = "OBSERVED", "READ_ONLY"
		case r.Mode == "simulate":
			d.Outcome, d.Reason = "SIMULATED", "NO_MUTATION"
		default:
			d.Outcome, d.Reason = "BLOCKED", "NO_VERIFIED_RUST_OWNER"
		}
		if d.Outcome == "SIMULATED" || d.Outcome == "OBSERVED" {
			selected[r.Resource] = true
			if len(e.lastSelection) >= 8192 {
				// Old cooldown entries cannot authorize an action; clearing only
				// affects simulations. No actions are wired to this engine.
				e.lastSelection = map[string]int64{}
			}
			if len(e.stableSince) >= 8192 {
				e.stableSince = map[string]int64{}
			}
			e.lastSelection[key] = nowMs
		}
		results = append(results, d)
	}
	return results, nil
}

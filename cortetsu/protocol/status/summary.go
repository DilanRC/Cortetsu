// Package status holds a deliberately limited observer summary.
// It never stores Hyprland event payloads, window titles or resources.
package status

import (
	"errors"
	"sync"

	"github.com/DilanRC/Cortetsu/cortetsu/protocol/observehypr"
)

type Summary struct {
	Mode          string                  `json:"mode"`
	Capabilities  []string                `json:"capabilities"`
	Authoritative bool                    `json:"authoritative"`
	StreamStale   bool                    `json:"stream_stale"`
	Epoch         uint64                  `json:"epoch"`
	Seen          uint64                  `json:"events_seen"`
	LastType      string                  `json:"last_type,omitempty"`
	Owner         *observehypr.OwnerState `json:"owner,omitempty"`
}

type Store struct {
	mu    sync.RWMutex
	value Summary
}

func NewStore() *Store {
	return &Store{value: Summary{Mode: "observe", Capabilities: []string{"snapshot", "policy.simulate"}, Authoritative: false, StreamStale: true}}
}

// Apply consumes only redacted observer outputs; on new epoch the cache is
// invalidated and must not be treated as a snapshot of compositor state.
func (s *Store) Apply(output observehypr.Output) {
	if s == nil {
		return
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	switch output.Type {
	case "resync_required":
		s.value.StreamStale = true
		s.value.Authoritative = false
		s.value.Epoch = output.Epoch
		s.value.Seen = 0
		s.value.LastType = ""
		s.value.Owner = nil
	case "event":
		if output.Event == nil || output.Event.Epoch != s.value.Epoch || output.Event.Session != output.Session {
			s.value.StreamStale = true
			return
		}
		s.value.Seen++
		// Normalized events are an explicit enum, but don't trust arbitrary
		// test or future inputs to become telemetry sent to QML.
		switch output.Event.Type {
		case "workspace_changed", "focus_changed", "fullscreen_changed", "monitor_connected", "monitor_disconnected", "window_opened", "window_closed", "configuration_reloaded", "keybind_layer_changed":
			s.value.LastType = output.Event.Type
		default:
			s.value.LastType = ""
		}
	}
}

// SetOwner marks a fresh owner snapshot valid; in the case of a new event
// epoch, no event-only cache may silently clear staleness.
func (s *Store) SetOwner(owner observehypr.OwnerState) {
	if s == nil || owner.ObservedUnixMs <= 0 {
		return
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	s.value.Owner = &owner
	s.value.Authoritative = true
	s.value.StreamStale = false
}

// MarkOwnerUnavailable ensures clients never display the last known state as
// a current one when the compositor cannot be read.
func (s *Store) MarkOwnerUnavailable() {
	if s == nil {
		return
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	s.value.Authoritative = false
	s.value.StreamStale = true
	s.value.Owner = nil
}

// Snapshot implements ipcv1.SnapshotSource, enforcing that requests cannot
// access window details, network credentials or notification contents.
func (s *Store) Snapshot(domains []string) (any, error) {
	if s == nil || len(domains) > 2 {
		return nil, errors.New("unsupported")
	}
	for _, d := range domains {
		if d != "coordinator" && d != "hyprland" {
			return nil, errors.New("unsupported")
		}
	}
	s.mu.RLock()
	defer s.mu.RUnlock()
	// Clone the mutable slice rather than exposing backing storage.
	c := s.value
	c.Capabilities = append([]string(nil), s.value.Capabilities...)
	if s.value.Owner != nil {
		owner := *s.value.Owner
		c.Owner = &owner
	}
	return c, nil
}

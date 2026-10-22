package policy

import (
	"errors"
	"strings"
	"sync"
)

type Cursor struct {
	Session  string `json:"session"`
	Epoch    uint64 `json:"epoch"`
	Sequence uint64 `json:"sequence"`
	Stale    bool   `json:"stale"`
}

// Observer isolates producer/stream state by *session*. It is an in-memory
// cursor and never replays mutations or assumes ownership of external state.
// Snapshot must be sourced from a trusted adapter before this cache is valid.
type Observer struct {
	mu      sync.RWMutex
	streams map[string]Cursor
}

func NewObserver() *Observer                    { return &Observer{streams: map[string]Cursor{}} }
func cursorKey(producer, session string) string { return producer + "\x00" + session }

func (o *Observer) Snapshot(producer string, cursor Cursor) error {
	if o == nil || !name.MatchString(producer) || !name.MatchString(cursor.Session) || cursor.Epoch == 0 {
		return errors.New("invalid snapshot")
	}
	o.mu.Lock()
	defer o.mu.Unlock()
	if o.streams == nil {
		o.streams = map[string]Cursor{}
	}
	key := cursorKey(producer, cursor.Session)
	if previous, ok := o.streams[key]; ok && !previous.Stale && previous.Epoch == cursor.Epoch && previous.Sequence > cursor.Sequence {
		return errors.New("snapshot cannot roll back the producer sequence")
	}
	cursor.Stale = false
	o.streams[key] = cursor
	return nil
}

// Accept reports APPLIED_OBSERVATION, DUPLICATE or RESYNC_REQUIRED. Gaps and
// epoch changes cannot accidentally become a new clean session snapshot.
func (o *Observer) Accept(event Event) (string, error) {
	if o == nil || !name.MatchString(event.Producer) || !name.MatchString(event.Session) ||
		!name.MatchString(event.Domain) || !name.MatchString(event.Type) || event.Epoch == 0 || event.Sequence == 0 {
		return "", errors.New("invalid event")
	}
	o.mu.Lock()
	defer o.mu.Unlock()
	if o.streams == nil {
		o.streams = map[string]Cursor{}
	}
	key := cursorKey(event.Producer, event.Session)
	cursor, ok := o.streams[key]
	if !ok || cursor.Stale || event.Epoch != cursor.Epoch {
		cursor.Stale = true
		o.streams[key] = cursor
		return "RESYNC_REQUIRED", nil
	}
	if event.Sequence <= cursor.Sequence {
		return "DUPLICATE", nil
	}
	if event.Sequence-cursor.Sequence != 1 {
		cursor.Stale = true
		o.streams[key] = cursor
		return "RESYNC_REQUIRED", nil
	}
	cursor.Sequence = event.Sequence
	o.streams[key] = cursor
	return "APPLIED_OBSERVATION", nil
}

func (o *Observer) CursorFor(producer, session string) (Cursor, bool) {
	if o == nil {
		return Cursor{}, false
	}
	o.mu.RLock()
	defer o.mu.RUnlock()
	c, ok := o.streams[cursorKey(producer, session)]
	return c, ok
}

// Cursor is retained for existing one-session callers. It refuses to choose
// arbitrarily if the same producer is observed in multiple sessions.
func (o *Observer) Cursor(producer string) (Cursor, bool) {
	if o == nil {
		return Cursor{}, false
	}
	o.mu.RLock()
	defer o.mu.RUnlock()
	prefix := producer + "\x00"
	var found Cursor
	count := 0
	for k, c := range o.streams {
		if strings.HasPrefix(k, prefix) {
			found = c
			count++
		}
	}
	return found, count == 1
}

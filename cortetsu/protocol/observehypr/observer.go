// Package observehypr reads Hyprland's .socket2.sock event stream in shadow
// mode. It never sends requests to the compositor, executes commands or
// handles user titles, window addresses, clipboard data or notification text.
package observehypr

import (
	"bufio"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"time"

	"github.com/DilanRC/Cortetsu/cortetsu/protocol/policy"
)

const MaxEventBytes = 8 * 1024

var identifier = regexp.MustCompile(`^[A-Za-z0-9][A-Za-z0-9_.-]{0,127}$`)

// Event types are deliberately coarse. No event payload is kept because
// openwindow/windowtitle events contain application names and sensitive titles.
var allowed = map[string]string{
	"workspace": "workspace_changed", "workspacev2": "workspace_changed",
	"focusedmon": "focus_changed", "activewindow": "focus_changed", "activewindowv2": "focus_changed",
	"fullscreen": "fullscreen_changed", "fullscreenstate": "fullscreen_changed",
	"monitoradded": "monitor_connected", "monitoraddedv2": "monitor_connected",
	"monitorremoved": "monitor_disconnected", "monitorremovedv2": "monitor_disconnected",
	"openwindow": "window_opened", "closewindow": "window_closed",
	"configreloaded": "configuration_reloaded", "submap": "keybind_layer_changed",
}

// Normalize drops all untrusted payload bytes, including window titles and
// addresses, and produces explicitly whitelisted context only.
func Normalize(line, session string, epoch, seq uint64, at time.Time) (policy.Event, bool) {
	kind, _, ok := strings.Cut(strings.TrimSuffix(line, "\r"), ">>")
	if !ok || !identifier.MatchString(session) || epoch == 0 || seq == 0 {
		return policy.Event{}, false
	}
	normalized, ok := allowed[kind]
	if !ok {
		return policy.Event{}, false
	}
	return policy.Event{
		Producer: "hyprland", Session: session, Epoch: epoch, Sequence: seq,
		EmittedAtUnixMs: at.UnixMilli(), Domain: "hyprland", Type: normalized,
		Fields: map[string]string{"source": "hyprland"},
	}, true
}

// SocketPath resolves only the per-user Hyprland event endpoint. Path
// components are validated to avoid traversal via environment variables.
func SocketPath(runtimeDir, signature string) (string, error) {
	if runtimeDir == "" || !filepath.IsAbs(runtimeDir) || !identifier.MatchString(signature) {
		return "", errors.New("invalid runtime directory or instance signature")
	}
	path := filepath.Join(runtimeDir, "hypr", signature, ".socket2.sock")
	if len(path) >= 104 {
		return "", errors.New("Unix socket path too long")
	}
	return path, nil
}

type Output struct {
	Type    string        `json:"type"`
	Session string        `json:"session"`
	Epoch   uint64        `json:"epoch"`
	Event   *policy.Event `json:"event,omitempty"`
}

type Observer struct {
	Session        string
	Socket         string
	ReconnectDelay time.Duration
}

func (o Observer) Validate() error {
	if !identifier.MatchString(o.Session) || o.Socket == "" || !filepath.IsAbs(o.Socket) || len(o.Socket) >= 104 {
		return errors.New("invalid observer configuration")
	}
	return nil
}

// Run reconnects with bounded, nonbusy backoff. A new epoch invalidates all
// cached events from the prior connection; consumers must re-snapshot from the
// authoritative owner. No replay is emitted.
func (o Observer) Run(ctx context.Context, output io.Writer) error {
	if err := o.Validate(); err != nil {
		return err
	}
	if output == nil {
		return errors.New("nil observer output")
	}
	delay := o.ReconnectDelay
	if delay <= 0 {
		delay = 250 * time.Millisecond
	}
	if delay < 10*time.Millisecond {
		delay = 10 * time.Millisecond
	}
	if delay > 10*time.Second {
		delay = 10 * time.Second
	}
	maxDelay := 5 * time.Second
	if maxDelay < delay {
		maxDelay = delay
	}
	encoder := json.NewEncoder(output)
	var epoch uint64
	for ctx.Err() == nil {
		d := net.Dialer{Timeout: 3 * time.Second}
		conn, err := d.DialContext(ctx, "unix", o.Socket)
		if err == nil {
			epoch++
			if err := encoder.Encode(Output{Type: "resync_required", Session: o.Session, Epoch: epoch}); err != nil {
				_ = conn.Close()
				return fmt.Errorf("cannot emit stream state: %w", err)
			}
			delay = o.ReconnectDelay
			if delay <= 0 {
				delay = 250 * time.Millisecond
			}
			if delay < 10*time.Millisecond {
				delay = 10 * time.Millisecond
			}
			err = o.consume(ctx, conn, epoch, encoder)
			_ = conn.Close()
			if err != nil && !errors.Is(err, io.EOF) && ctx.Err() == nil { // Never print raw events or socket bytes.
				if !errors.Is(err, errFrameLimit) {
					return err
				}
			}
		}
		if ctx.Err() != nil {
			return nil
		}
		timer := time.NewTimer(delay)
		select {
		case <-ctx.Done():
			timer.Stop()
			return nil
		case <-timer.C:
		}
		if delay < maxDelay/2 {
			delay *= 2
		} else {
			delay = maxDelay
		}
	}
	return nil
}

var errFrameLimit = errors.New("event exceeded maximum length")

func (o Observer) consume(ctx context.Context, conn net.Conn, epoch uint64, enc *json.Encoder) error {
	done := context.AfterFunc(ctx, func() { _ = conn.Close() })
	defer done()
	scanner := bufio.NewScanner(conn)
	scanner.Buffer(make([]byte, 2048), MaxEventBytes+2)
	var seq uint64
	for scanner.Scan() {
		if len(scanner.Bytes()) > MaxEventBytes {
			return errFrameLimit
		}
		// Advance the source cursor even for unknown/dropped events so a consumer
		// sees gaps rather than assuming it received a complete event stream.
		seq++
		event, ok := Normalize(scanner.Text(), o.Session, epoch, seq, time.Now())
		if !ok {
			continue
		}
		if err := enc.Encode(Output{Type: "event", Session: o.Session, Epoch: epoch, Event: &event}); err != nil {
			return err
		}
	}
	if ctx.Err() != nil {
		return nil
	}
	if err := scanner.Err(); err != nil {
		if errors.Is(err, bufio.ErrTooLong) {
			return errFrameLimit
		}
		return io.EOF
	}
	return io.EOF
}

// DefaultSocket returns the user's Hyprland event socket without executing
// external commands. Production activation requires an explicit CLI opt-in.
func DefaultSocket() (string, error) {
	return SocketPath(os.Getenv("XDG_RUNTIME_DIR"), os.Getenv("HYPRLAND_INSTANCE_SIGNATURE"))
}

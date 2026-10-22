//go:build linux

package observehypr

import (
	"encoding/json"
	"errors"
	"net"
	"os"
	"path/filepath"
	"strings"
	"syscall"
	"time"
)

// OwnerState is a safe redacted snapshot, never the complete Hyprland JSON.
// All details are counters/booleans; monitor names, workspaces names, window
// titles, EDID, addresses and individual app properties are discarded.
type OwnerState struct {
	MonitorCount      int   `json:"monitor_count"`
	WorkspaceCount    int   `json:"workspace_count"`
	FocusedMonitor    bool  `json:"focused_monitor"`
	FocusedFullscreen bool  `json:"focused_fullscreen"`
	ObservedUnixMs    int64 `json:"observed_at_unix_ms"`
}

const ownerMaxReply = 512 * 1024
const ownerTimeout = 450 * time.Millisecond

// CommandSocketFromEvent converts only a known Hyprland event socket name to
// its synchronous request socket. A caller cannot smuggle arbitrary paths.
func CommandSocketFromEvent(path string) (string, error) {
	if !filepath.IsAbs(path) || filepath.Base(path) != ".socket2.sock" {
		return "", errors.New("not a Hyprland event socket")
	}
	return filepath.Join(filepath.Dir(path), ".socket.sock"), nil
}

func queryOwner(socketPath, request string, dest any) error {
	if !filepath.IsAbs(socketPath) || len(socketPath) >= 104 ||
		!strings.HasPrefix(request, "j/") {
		return errors.New("invalid Hyprland socket query")
	}
	meta, err := os.Lstat(socketPath)
	if err != nil || meta.Mode()&os.ModeSocket == 0 || meta.Mode()&os.ModeSymlink != 0 {
		return errors.New("owner socket is unavailable")
	}
	stat, ok := meta.Sys().(*syscall.Stat_t)
	if !ok || stat.Uid != uint32(os.Getuid()) {
		return errors.New("owner socket has another uid")
	}
	conn, err := net.DialTimeout("unix", socketPath, ownerTimeout)
	if err != nil {
		return errors.New("cannot connect owner socket")
	}
	defer conn.Close()
	_ = conn.SetDeadline(time.Now().Add(ownerTimeout))
	if _, err := conn.Write([]byte(request)); err != nil {
		return errors.New("owner query failed")
	}
	var data json.RawMessage
	decoder := json.NewDecoder(&limitReader{src: conn, remaining: ownerMaxReply})
	if err := decoder.Decode(&data); err != nil {
		return errors.New("invalid owner response")
	}
	if len(data) >= ownerMaxReply {
		return errors.New("oversized owner response")
	}
	return json.Unmarshal(data, dest)
}

// limitReader does not buffer the entire raw owner response, which may contain
// sensitive titles. It is decoded into narrow, typed structs and discarded.
type limitReader struct {
	src       net.Conn
	remaining int
}

func (r *limitReader) Read(p []byte) (int, error) {
	if r.remaining <= 0 {
		return 0, errors.New("reply size limit")
	}
	if len(p) > r.remaining {
		p = p[:r.remaining]
	}
	n, err := r.src.Read(p)
	r.remaining -= n
	return n, err
}

// ReadOwner obtains real Hyprland state with three short-lived read-only queries.
// hyprland processes each request synchronously, so never hold a connection
// open after decoding a result. There is no poll loop in this library.
func ReadOwner(socketPath string) (OwnerState, error) {
	var monitors []struct {
		Disabled bool `json:"disabled"`
		Focused  bool `json:"focused"`
	}
	if err := queryOwner(socketPath, "j/monitors", &monitors); err != nil {
		return OwnerState{}, err
	}
	var workspaces []struct {
		ID int `json:"id"`
	}
	if err := queryOwner(socketPath, "j/workspaces", &workspaces); err != nil {
		return OwnerState{}, err
	}
	if len(monitors) > 128 || len(workspaces) > 4096 {
		return OwnerState{}, errors.New("impossible owner counts")
	}
	var active struct {
		Fullscreen int `json:"fullscreen"`
	}
	if err := queryOwner(socketPath, "j/activewindow", &active); err != nil {
		return OwnerState{}, err
	}
	if active.Fullscreen < 0 || active.Fullscreen > 3 {
		return OwnerState{}, errors.New("invalid fullscreen state")
	}
	state := OwnerState{WorkspaceCount: len(workspaces), ObservedUnixMs: time.Now().UnixMilli()}
	state.FocusedFullscreen = active.Fullscreen == 2 || active.Fullscreen == 3
	for _, m := range monitors {
		if !m.Disabled {
			state.MonitorCount++
		}
		if m.Focused {
			state.FocusedMonitor = true
		}
	}
	return state, nil
}

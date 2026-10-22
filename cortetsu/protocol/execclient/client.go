// Package execclient invokes one explicitly configured, trusted Cortetsu Rust
// executable. Neither IPC requests nor policy rules can select argv, binary
// paths or environment variables. Requests use the strict typed exec contract.
package execclient

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"sync"
	"syscall"
	"time"

	"github.com/DilanRC/Cortetsu/cortetsu/protocol/execv1"
)

const MaxWireBytes = 64 * 1024
const MaxTimeout = 10 * time.Second

var ErrUnavailable = errors.New("OWNER_UNAVAILABLE")
var ErrInvalidResponse = errors.New("APPLY_VERIFICATION_FAILED")

// Client holds trusted configuration established at process startup.
// The binary cannot be supplied by IPC or rules.
type Client struct{ Binary string }

// Cmd owns and closes its copy pipes when WaitDelay expires. Keeping the
// bounded writer on Cmd avoids blocking outside Wait on an inherited stdout.
type boundedOutput struct {
	buffer   bytes.Buffer
	exceeded bool
	cancel   context.CancelFunc
}

func (b *boundedOutput) Len() int      { return b.buffer.Len() }
func (b *boundedOutput) Bytes() []byte { return b.buffer.Bytes() }

func (b *boundedOutput) Write(p []byte) (int, error) {
	count := len(p)
	if remaining := MaxWireBytes + 1 - b.Len(); remaining > 0 {
		if len(p) > remaining {
			p = p[:remaining]
		}
		_, _ = b.buffer.Write(p)
	}
	if b.Len() > MaxWireBytes && !b.exceeded {
		b.exceeded = true
		b.cancel()
	}
	return count, nil
}

func (c Client) Execute(ctx context.Context, request execv1.Request) (*execv1.Response, error) {
	if err := c.CheckBinary(); err != nil {
		return nil, err
	}
	body, err := json.Marshal(request)
	if err != nil {
		return nil, ErrUnavailable
	}
	if _, err := execv1.ParseRequest(body); err != nil {
		return nil, err
	}
	ctx, cancel := context.WithTimeout(ctx, time.Duration(request.DeadlineMs)*time.Millisecond)
	defer cancel()
	command := exec.CommandContext(ctx, c.Binary, "exec")
	command.Env = safeEnv()
	command.Stdin = bytes.NewReader(body)
	command.Stderr = io.Discard
	command.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
	var timerMu sync.Mutex
	var killTimer *time.Timer
	command.Cancel = func() error {
		err := syscall.Kill(-command.Process.Pid, syscall.SIGTERM)
		timerMu.Lock()
		killTimer = time.AfterFunc(200*time.Millisecond, func() { _ = syscall.Kill(-command.Process.Pid, syscall.SIGKILL) })
		timerMu.Unlock()
		return err
	}
	command.WaitDelay = 300 * time.Millisecond
	stdout := &boundedOutput{cancel: cancel}
	command.Stdout = stdout
	if err = command.Start(); err != nil {
		return nil, ErrUnavailable
	}
	waitErr := command.Wait()
	timerMu.Lock()
	if killTimer != nil {
		killTimer.Stop()
	}
	timerMu.Unlock()
	_ = syscall.Kill(-command.Process.Pid, syscall.SIGKILL)
	if stdout.exceeded {
		return nil, ErrInvalidResponse
	}
	if ctx.Err() != nil {
		return nil, ctx.Err()
	}
	wire := stdout.Bytes()
	response, err := execv1.ParseResponse(wire)
	if err != nil || response.RequestID != request.RequestID {
		return nil, ErrInvalidResponse
	}
	if response.Outcome == "rejected" || response.Outcome == "unknown" {
		return response, nil
	}
	expected := "read"
	if request.ExpectedRevision != nil && request.IdempotencyKey != "" {
		expected = "applied"
	}
	if waitErr != nil || response.Outcome != expected || !response.Verified || response.Error != nil {
		return nil, ErrInvalidResponse
	}
	return response, nil
}

// CheckBinary must be used before opening an IPC listener. F1b refuses
// symlinked binaries: the installed generation path must be immutable.
func (c Client) CheckBinary() error {
	if !filepath.IsAbs(c.Binary) {
		return ErrUnavailable
	}
	path := filepath.Clean(c.Binary)
	if path != c.Binary {
		return ErrUnavailable
	}
	meta, err := os.Lstat(path)
	if err != nil || !meta.Mode().IsRegular() || meta.Mode().Perm()&0111 == 0 || meta.Mode().Perm()&0022 != 0 {
		return ErrUnavailable
	}
	owner, ok := meta.Sys().(*syscall.Stat_t)
	if !ok || (owner.Uid != 0 && owner.Uid != uint32(os.Geteuid())) {
		return ErrUnavailable
	}
	return nil
}

func safeEnv() []string {
	keys := []string{"HOME", "XDG_DATA_HOME", "XDG_CONFIG_HOME", "XDG_STATE_HOME", "XDG_CACHE_HOME", "XDG_RUNTIME_DIR", "HYPRLAND_INSTANCE_SIGNATURE", "DBUS_SESSION_BUS_ADDRESS", "WAYLAND_DISPLAY", "PATH", "CORTETSU_DATA_ROOT", "CORTETSU_RUNTIME_ROOT"}
	env := make([]string, 0, len(keys))
	for _, k := range keys {
		if v := os.Getenv(k); v != "" && !strings.ContainsRune(v, '\x00') {
			env = append(env, k+"="+v)
		}
	}
	return env
}

// Verify returns only the read-only system.verify body after ensuring that
// the Rust process really reported verified=true. Exit 0 alone is never enough.
func (c Client) Verify(ctx context.Context, requestID string, timeout time.Duration) (json.RawMessage, error) {
	if timeout <= 0 || timeout > MaxTimeout {
		return nil, ErrUnavailable
	}
	request := execv1.Request{Protocol: execv1.Protocol, Version: execv1.Version{Major: 1, Minor: 0},
		RequestID: requestID, Operation: "system.verify", DeadlineMs: timeout.Milliseconds(), Arguments: json.RawMessage(`{}`)}
	response, err := c.Execute(ctx, request)
	if err != nil {
		return nil, err
	}
	if response.Outcome != "read" || !response.Verified || response.Error != nil {
		return nil, ErrInvalidResponse
	}
	return response.Body, nil
}

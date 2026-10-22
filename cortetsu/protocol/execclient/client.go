// Package execclient invokes one explicitly configured, trusted Cortetsu Rust
// executable. Neither IPC requests nor policy rules can select argv, binary
// paths or environment variables. Only system.verify is supported in F1b.
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
	return nil
}

func safeEnv() []string {
	keys := []string{"HOME", "XDG_DATA_HOME", "XDG_CONFIG_HOME", "CORTETSU_DATA_ROOT", "CORTETSU_RUNTIME_ROOT"}
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
	if err := c.CheckBinary(); err != nil {
		return nil, err
	}
	if timeout <= 0 || timeout > MaxTimeout {
		return nil, ErrUnavailable
	}
	ctx, cancel := context.WithTimeout(ctx, timeout)
	defer cancel()
	request := map[string]any{"protocol": execv1.Protocol, "version": execv1.Version{Major: 1, Minor: 0},
		"request_id": requestID, "operation": "system.verify", "deadline_ms": timeout.Milliseconds(), "arguments": map[string]any{}}
	body, err := json.Marshal(request)
	if err != nil {
		return nil, ErrUnavailable
	}
	if _, err := execv1.ParseRequest(body); err != nil {
		return nil, ErrUnavailable
	}
	command := exec.CommandContext(ctx, c.Binary, "exec")
	command.Env = safeEnv()
	command.Stdin = bytes.NewReader(body)
	stdout, err := command.StdoutPipe()
	if err != nil {
		return nil, ErrUnavailable
	}
	command.Stderr = io.Discard
	if err := command.Start(); err != nil {
		return nil, ErrUnavailable
	}
	// Bound memory even if a compromised child outputs unlimited data.
	wire, readErr := io.ReadAll(io.LimitReader(stdout, MaxWireBytes+1))
	if readErr != nil || len(wire) > MaxWireBytes {
		_ = command.Process.Kill()
	}
	waitErr := command.Wait()
	if readErr != nil || waitErr != nil || len(wire) > MaxWireBytes {
		return nil, ErrUnavailable
	}
	response, err := execv1.ParseResponse(wire)
	if err != nil || response.RequestID != requestID || response.Outcome != "read" || !response.Verified || response.Error != nil {
		return nil, ErrInvalidResponse
	}
	return response.Body, nil
}

//go:build linux

package ipcv1

import (
	"errors"
	"os"
	"path/filepath"
	"syscall"
)

// OpenReadOnlySessionListener is an explicit opt-in listener with exactly the
// same request allowlist as the isolated test listener. No mutating adapter is
// installed. It never launches a subprocess, calls a device API, or writes to
// an existing state file. The parent runtime directory must already be 0700
// and owned by the invoking uid. Refuse existing non-private/symlink roots.
func OpenReadOnlySessionListener(runtimeDir, session string, epoch uint64, source SnapshotSource) (*TestListener, error) {
	if !filepath.IsAbs(runtimeDir) || !id.MatchString(session) || epoch == 0 {
		return nil, fail("INVALID_REQUEST")
	}
	parent, err := os.Lstat(runtimeDir)
	if err != nil || !parent.IsDir() || parent.Mode().Perm()&0077 != 0 || parent.Mode()&os.ModeSymlink != 0 {
		return nil, fail("PERMISSION_DENIED")
	}
	owner, ok := parent.Sys().(*syscall.Stat_t)
	if !ok || owner.Uid != uint32(os.Getuid()) {
		return nil, fail("PERMISSION_DENIED")
	}
	private := filepath.Join(runtimeDir, "cortetsu")
	if err := os.Mkdir(private, 0700); err != nil && !errors.Is(err, os.ErrExist) {
		return nil, fail("PERMISSION_DENIED")
	}
	// OpenIsolatedListener checks uid, permissions, symlinks, session name,
	// preexisting socket collision and UNIX sun_path bounds before binding.
	listener, err := OpenIsolatedListener(private, session, epoch)
	if err != nil {
		return nil, err
	}
	listener.SetSnapshotSource(source)
	return listener, nil
}

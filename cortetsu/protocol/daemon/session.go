package daemon

import (
	"crypto/rand"
	"encoding/binary"
	"encoding/json"
	"errors"
	"fmt"
	"net"
	"os"
	"path/filepath"
	"regexp"
	"syscall"
	"time"
)

type Metadata struct {
	Protocol     string `json:"protocol"`
	SessionID    string `json:"session_id"`
	SessionEpoch uint64 `json:"session_epoch"`
	Socket       string `json:"socket"`
	Mode         string `json:"mode"`
}

func newEpoch() (uint64, error) {
	var raw [8]byte
	if _, err := rand.Read(raw[:]); err != nil {
		return 0, err
	}
	// QML transports JSON numbers as IEEE-754 doubles.
	n := binary.BigEndian.Uint64(raw[:]) & ((1 << 53) - 1)
	if n == 0 {
		n = 1
	}
	return n, nil
}
func privateDir(path string) error {
	m, err := os.Lstat(path)
	if err != nil {
		return err
	}
	owner, ok := m.Sys().(*syscall.Stat_t)
	if !m.IsDir() || m.Mode()&os.ModeSymlink != 0 || m.Mode().Perm()&0077 != 0 || !ok || owner.Uid != uint32(os.Getuid()) {
		return errors.New("PERMISSION_DENIED")
	}
	return nil
}

var sessionName = regexp.MustCompile(`^[A-Za-z0-9][A-Za-z0-9_.:-]{0,127}$`)

func lockSession(runtimeDir, session string) (func(), error) {
	if !filepath.IsAbs(runtimeDir) || !sessionName.MatchString(session) {
		return nil, errors.New("INVALID_REQUEST")
	}
	if err := privateDir(runtimeDir); err != nil {
		return nil, err
	}
	root := filepath.Join(runtimeDir, "cortetsu")
	if err := os.Mkdir(root, 0700); err != nil && !errors.Is(err, os.ErrExist) {
		return nil, err
	}
	if err := privateDir(root); err != nil {
		return nil, err
	}
	path := filepath.Join(root, "coordinator-"+session+".lock")
	fd, err := syscall.Open(path, syscall.O_RDWR|syscall.O_CREAT|syscall.O_NOFOLLOW|syscall.O_CLOEXEC, 0600)
	if err != nil {
		return nil, errors.New("PERMISSION_DENIED")
	}
	f := os.NewFile(uintptr(fd), path)
	m, err := f.Stat()
	if err != nil {
		f.Close()
		return nil, err
	}
	st, ok := m.Sys().(*syscall.Stat_t)
	if !m.Mode().IsRegular() || m.Mode().Perm() != 0600 || !ok || st.Uid != uint32(os.Getuid()) {
		f.Close()
		return nil, errors.New("PERMISSION_DENIED")
	}
	if err = syscall.Flock(fd, syscall.LOCK_EX|syscall.LOCK_NB); err != nil {
		f.Close()
		return nil, errors.New("SESSION_BUSY")
	}
	release := func() { _ = syscall.Flock(fd, syscall.LOCK_UN); _ = f.Close() }
	socket := filepath.Join(root, "cortetsu-"+session+".sock")
	if m, err := os.Lstat(socket); err == nil {
		st, ok := m.Sys().(*syscall.Stat_t)
		if m.Mode()&os.ModeSocket == 0 || m.Mode()&os.ModeSymlink != 0 || !ok || st.Uid != uint32(os.Getuid()) {
			release()
			return nil, errors.New("PERMISSION_DENIED")
		}
		// A pre-migration bridge might not yet own the new lock. Never steal
		// its listening socket. A crashed owner leaves a reclaimable inode.
		c, err := net.DialTimeout("unix", socket, 150*time.Millisecond)
		if err == nil {
			c.Close()
			release()
			return nil, errors.New("SESSION_BUSY")
		}
		if !errors.Is(err, syscall.ECONNREFUSED) {
			release()
			return nil, errors.New("OWNER_UNAVAILABLE")
		}
		if err = os.Remove(socket); err != nil {
			release()
			return nil, err
		}
	} else if !errors.Is(err, os.ErrNotExist) {
		release()
		return nil, err
	}
	return release, nil
}
func PublishMetadata(dir, session string, epoch uint64, socket string) (func(), error) {
	meta := Metadata{Protocol: "cortetsu.ipc", SessionID: session, SessionEpoch: epoch, Socket: socket, Mode: "coordinator"}
	dest := filepath.Join(dir, "bridge-"+session+".json")
	if old, err := os.Lstat(dest); err == nil && (!old.Mode().IsRegular() || old.Mode()&os.ModeSymlink != 0) {
		return nil, errors.New("unsafe metadata path")
	} else if err != nil && !errors.Is(err, os.ErrNotExist) {
		return nil, err
	}
	file, err := os.CreateTemp(dir, ".bridge-")
	if err != nil {
		return nil, err
	}
	defer os.Remove(file.Name())
	raw, err := json.Marshal(meta)
	if err == nil {
		_, err = file.Write(append(raw, '\n'))
	}
	if err == nil {
		err = file.Sync()
	}
	closeErr := file.Close()
	if err == nil {
		err = closeErr
	}
	if err != nil {
		return nil, fmt.Errorf("metadata write failed: %w", err)
	}
	if err = os.Rename(file.Name(), dest); err != nil {
		return nil, err
	}
	parent, err := os.Open(dir)
	if err != nil {
		return nil, err
	}
	err = parent.Sync()
	parent.Close()
	if err != nil {
		return nil, err
	}
	return func() {
		raw, err := os.ReadFile(dest)
		if err != nil {
			return
		}
		var m Metadata
		if json.Unmarshal(raw, &m) == nil && m.SessionEpoch == epoch && m.SessionID == session && m.Socket == socket {
			_ = os.Remove(dest)
		}
	}, nil
}

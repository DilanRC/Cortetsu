// Package policyaudit stores an opt-in, bounded, redacted simulation ledger.
// It never records event payloads, window titles, clipboard, tokens or secrets,
// and cannot authorize an action or replay an operation.
package policyaudit

import (
	"bufio"
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"regexp"
	"syscall"

	"github.com/DilanRC/Cortetsu/cortetsu/protocol/policy"
)

const MaxLogBytes int64 = 4 * 1024 * 1024
const MaxLineBytes = 2048

var safeID = regexp.MustCompile(`^[a-zA-Z0-9][a-zA-Z0-9._:-]{0,127}$`)
var safeCode = regexp.MustCompile(`^[A-Z][A-Z0-9_]{0,63}$`)

type Record struct {
	Schema    int    `json:"schema"`
	Session   string `json:"session"`
	Producer  string `json:"producer"`
	Epoch     uint64 `json:"epoch"`
	Sequence  uint64 `json:"sequence"`
	AtUnixMs  int64  `json:"at_unix_ms"`
	RuleID    string `json:"rule_id"`
	Resource  string `json:"resource"`
	Operation string `json:"operation"`
	Outcome   string `json:"outcome"`
	Reason    string `json:"reason"`
}

func NewRecord(ev policy.Event, decision policy.Decision, at int64) (Record, error) {
	r := Record{Schema: 1, Session: ev.Session, Producer: ev.Producer,
		Epoch: ev.Epoch, Sequence: ev.Sequence, AtUnixMs: at,
		RuleID: decision.RuleID, Resource: decision.Resource,
		Operation: decision.Operation, Outcome: decision.Outcome, Reason: decision.Reason}
	if err := r.Validate(); err != nil {
		return Record{}, err
	}
	return r, nil
}

func (r Record) Validate() error {
	if r.Schema != 1 || r.Epoch == 0 || r.Sequence == 0 || r.AtUnixMs <= 0 ||
		!safeID.MatchString(r.Session) || !safeID.MatchString(r.Producer) ||
		!safeID.MatchString(r.RuleID) || !safeID.MatchString(r.Resource) ||
		!safeID.MatchString(r.Operation) || !safeCode.MatchString(r.Outcome) || !safeCode.MatchString(r.Reason) {
		return errors.New("invalid redacted policy audit record")
	}
	return nil
}

// Ledger is an opt-in per-user log in a caller-owned 0700 directory. The
// directory must already exist; the library never creates an XDG home.
type Ledger struct{ Root string }

func (l Ledger) path() (string, error) {
	if !filepath.IsAbs(l.Root) {
		return "", errors.New("audit root must be absolute")
	}
	m, err := os.Lstat(l.Root)
	if err != nil || !m.IsDir() || m.Mode()&os.ModeSymlink != 0 || m.Mode().Perm() != 0700 {
		return "", errors.New("audit root is not private")
	}
	st, ok := m.Sys().(*syscall.Stat_t)
	if !ok || st.Uid != uint32(os.Getuid()) {
		return "", errors.New("audit root uid mismatch")
	}
	return filepath.Join(l.Root, "policy-decisions-v1.jsonl"), nil
}

func (l Ledger) Append(r Record) error {
	if err := r.Validate(); err != nil {
		return err
	}
	path, err := l.path()
	if err != nil {
		return err
	}
	raw, err := json.Marshal(r)
	if err != nil {
		return err
	}
	if len(raw) > MaxLineBytes-1 {
		return errors.New("audit record too large")
	}
	raw = append(raw, '\n')
	fd, err := syscall.Open(path, syscall.O_WRONLY|syscall.O_APPEND|syscall.O_CREAT|syscall.O_NOFOLLOW|syscall.O_CLOEXEC, 0600)
	if err != nil {
		return errors.New("cannot open audit file")
	}
	file := os.NewFile(uintptr(fd), path)
	defer file.Close()
	if err = syscall.Flock(fd, syscall.LOCK_EX); err != nil {
		return err
	}
	defer syscall.Flock(fd, syscall.LOCK_UN)
	stat, err := file.Stat()
	if err != nil {
		return err
	}
	owner, ok := stat.Sys().(*syscall.Stat_t)
	if !ok || !stat.Mode().IsRegular() || stat.Mode().Perm() != 0600 || owner.Uid != uint32(os.Getuid()) {
		return errors.New("audit file is not private")
	}
	if stat.Size() > MaxLogBytes-int64(len(raw)) {
		return errors.New("audit size limit reached; rotate manually")
	}
	n, err := file.Write(raw)
	if err != nil {
		return err
	}
	if n != len(raw) {
		return io.ErrShortWrite
	}
	return file.Sync()
}

// Read validates every newline-terminated record and bounds total input.
// It refuses a partially written line rather than silently accepting it.
func (l Ledger) Read() ([]Record, error) {
	path, err := l.path()
	if err != nil {
		return nil, err
	}
	fd, err := syscall.Open(path, syscall.O_RDONLY|syscall.O_NOFOLLOW|syscall.O_CLOEXEC, 0)
	if errors.Is(err, syscall.ENOENT) {
		return []Record{}, nil
	}
	if err != nil {
		return nil, errors.New("cannot read audit file")
	}
	f := os.NewFile(uintptr(fd), path)
	defer f.Close()
	st, err := f.Stat()
	if err != nil {
		return nil, err
	}
	meta, ok := st.Sys().(*syscall.Stat_t)
	if !ok || !st.Mode().IsRegular() || st.Mode().Perm() != 0600 || meta.Uid != uint32(os.Getuid()) || st.Size() > MaxLogBytes {
		return nil, errors.New("unsafe audit file")
	}
	reader := bufio.NewReader(f)
	var all []Record
	for {
		line, err := reader.ReadBytes('\n')
		if errors.Is(err, io.EOF) && len(line) == 0 {
			break
		}
		if err != nil {
			return nil, errors.New("truncated audit record")
		}
		if len(line) > MaxLineBytes {
			return nil, errors.New("oversized audit record")
		}
		var record Record
		d := json.NewDecoder(bytes.NewReader(line))
		d.DisallowUnknownFields()
		if err := d.Decode(&record); err != nil {
			return nil, fmt.Errorf("invalid audit entry: %w", err)
		}
		if err := record.Validate(); err != nil {
			return nil, err
		}
		all = append(all, record)
	}
	return all, nil
}

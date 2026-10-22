package daemon

import (
	"os"
	"path/filepath"
	"testing"
)

func TestEpochIsExactInQMLAndSessionLockExclusive(t *testing.T) {
	for i := 0; i < 32; i++ {
		n, err := newEpoch()
		if err != nil || n == 0 || n > 9007199254740991 {
			t.Fatal(n, err)
		}
	}
	dir := t.TempDir()
	if err := os.Chmod(dir, 0700); err != nil {
		t.Fatal(err)
	}
	unlock, err := lockSession(dir, "one")
	if err != nil {
		t.Fatal(err)
	}
	if release, err := lockSession(dir, "one"); err == nil {
		release()
		t.Fatal("two coordinators admitted")
	}
	releaseTwo, err := lockSession(dir, "two")
	if err != nil {
		t.Fatal(err)
	}
	releaseTwo()
	unlock()
	release, err := lockSession(dir, "one")
	if err != nil {
		t.Fatal(err)
	}
	release()
}
func TestSessionLockRefusesSymlink(t *testing.T) {
	dir := t.TempDir()
	os.Chmod(dir, 0700)
	os.Mkdir(filepath.Join(dir, "cortetsu"), 0700)
	os.Symlink(filepath.Join(dir, "foreign"), filepath.Join(dir, "cortetsu", "coordinator-one.lock"))
	if release, err := lockSession(dir, "one"); err == nil {
		release()
		t.Fatal("symlink lock accepted")
	}
}

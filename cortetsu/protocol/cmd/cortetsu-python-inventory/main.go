// cortetsu-python-inventory audits first-party Python paths without touching
// packages, helpers, personal files or installed system state.
package main

import (
	"bytes"
	"encoding/json"
	"flag"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"slices"
	"strings"
)

type Inventory struct {
	Schema  int      `json:"schema"`
	Runtime []string `json:"runtime_python"`
	Tests   []string `json:"test_python"`
	Tooling []string `json:"tooling_python"`
}

func inspect(repo string) (Inventory, error) {
	cmd := exec.Command("git", "-C", repo, "ls-files", "-z")
	raw, err := cmd.Output()
	if err != nil {
		return Inventory{}, fmt.Errorf("cannot inventory tracked files: %w", err)
	}
	result := Inventory{Schema: 1, Runtime: []string{}, Tests: []string{}, Tooling: []string{}}
	for _, item := range bytes.Split(raw, []byte{0}) {
		if len(item) == 0 {
			continue
		}
		path := string(item)
		file := filepath.Join(repo, filepath.FromSlash(path))
		info, err := os.Lstat(file)
		if err != nil || !info.Mode().IsRegular() {
			continue
		}
		isPython := strings.HasSuffix(path, ".py")
		if !isPython && info.Size() <= 1<<20 {
			fd, err := os.Open(file)
			if err != nil {
				return Inventory{}, fmt.Errorf("cannot examine tracked file %s", path)
			}
			var head [128]byte
			n, _ := fd.Read(head[:])
			_ = fd.Close()
			line := strings.SplitN(string(head[:n]), "\n", 2)[0]
			isPython = strings.HasPrefix(line, "#!") && strings.Contains(line, "python")
		}
		if !isPython {
			continue
		}
		switch {
		case strings.HasPrefix(path, "core/"), strings.HasPrefix(path, "cortetsu/bin/"):
			result.Runtime = append(result.Runtime, path)
		case strings.HasPrefix(path, "cortetsu/tests/"), strings.HasPrefix(path, "scripts/features/"), strings.HasPrefix(path, "docs/migration/"):
			result.Tests = append(result.Tests, path)
		default:
			result.Tooling = append(result.Tooling, path)
		}
	}
	slices.Sort(result.Runtime)
	slices.Sort(result.Tests)
	slices.Sort(result.Tooling)
	return result, nil
}

func main() {
	repo := flag.String("repo", ".", "local Cortetsu source repository")
	baseline := flag.String("baseline", "", "optional frozen runtime Python path baseline")
	flag.Parse()
	if len(flag.Args()) != 0 {
		os.Exit(2)
	}
	found, err := inspect(*repo)
	if err != nil {
		fmt.Fprintln(os.Stderr, "inventory unavailable")
		os.Exit(1)
	}
	out := json.NewEncoder(os.Stdout)
	out.SetIndent("", "  ")
	if err := out.Encode(found); err != nil {
		os.Exit(1)
	}
	if *baseline == "" {
		return
	}
	source, err := os.ReadFile(*baseline)
	if err != nil {
		fmt.Fprintln(os.Stderr, "baseline unavailable")
		os.Exit(1)
	}
	var original Inventory
	if err := json.Unmarshal(source, &original); err != nil || original.Schema != 1 {
		fmt.Fprintln(os.Stderr, "bad baseline")
		os.Exit(1)
	}
	known := map[string]bool{}
	for _, path := range original.Runtime {
		known[path] = true
	}
	for _, path := range found.Runtime {
		if !known[path] {
			fmt.Fprintln(os.Stderr, "new first-party Python runtime path:", path)
			os.Exit(1)
		}
	}
}

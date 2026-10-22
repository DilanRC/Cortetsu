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
	"regexp"
	"slices"
	"strings"
)

type Inventory struct {
	Schema      int      `json:"schema"`
	Runtime     []string `json:"runtime_python"`
	Tests       []string `json:"test_python"`
	Tooling     []string `json:"tooling_python"`
	Invocations []string `json:"runtime_python_invocations,omitempty"`
}

// Runtime invocations exclude historical scripts, generated fixtures and
// tests. They are a conservative dependency graph, not a total callgraph.
func runtimeLauncher(path string) bool {
	return strings.HasPrefix(path, "cortetsu/bin/") ||
		strings.HasPrefix(path, "cortetsu/modules/") ||
		strings.HasPrefix(path, "cortetsu/services/") ||
		strings.HasPrefix(path, "scripts/lib/") ||
		strings.HasPrefix(path, "config/systemd/") ||
		path == "scripts/cortetsu" || path == "scripts/install-cortetsu.sh"
}

func inspect(repo string) (Inventory, error) {
	cmd := exec.Command("git", "-C", repo, "ls-files", "--cached", "--others", "--exclude-standard", "-z")
	raw, err := cmd.Output()
	if err != nil {
		return Inventory{}, fmt.Errorf("cannot inventory tracked files: %w", err)
	}
	result := Inventory{Schema: 1, Runtime: []string{}, Tests: []string{}, Tooling: []string{}, Invocations: []string{}}
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
		// Conservative reverse edge audit: runtime QML, Bash and service
		// configuration calling the interpreter also block the F9 cutover.
		// Do not include documentation, test fixtures, or Python comments.
		if !isPython && info.Size() <= 2<<20 && (strings.HasSuffix(path, ".qml") ||
			strings.HasSuffix(path, ".sh") || strings.HasSuffix(path, ".service") || strings.HasPrefix(path, "scripts/cortetsu") ||
			strings.HasPrefix(path, "cortetsu/bin/")) &&
			runtimeLauncher(path) {
			body, err := os.ReadFile(file)
			if err != nil {
				return Inventory{}, fmt.Errorf("cannot read potential runtime dependency %s", path)
			}
			for _, line := range strings.Split(string(body), "\n") {
				trimmed := strings.TrimSpace(line)
				if strings.HasPrefix(trimmed, "#") || strings.HasPrefix(trimmed, "//") {
					continue
				}
				if regexp.MustCompile(`(^|[\s"',=])python(3([.][0-9]+)?)?([\s"',]|$)`).MatchString(line) {
					result.Invocations = append(result.Invocations, path)
					break
				}
			}
		}
		if !isPython {
			continue
		}
		switch {
		case strings.HasPrefix(path, "core/"), strings.HasPrefix(path, "cortetsu/bin/"), strings.HasPrefix(path, "cortetsu/services/"):
			result.Runtime = append(result.Runtime, path)
		case strings.HasPrefix(path, "tests/"), strings.HasPrefix(path, "cortetsu/tests/"), strings.Contains(path, "/tests/"), strings.HasPrefix(path, "scripts/features/"), strings.HasPrefix(path, "scripts/verification/"), strings.HasPrefix(path, "docs/migration/"):
			result.Tests = append(result.Tests, path)
		default:
			result.Tooling = append(result.Tooling, path)
		}
	}
	slices.Sort(result.Runtime)
	slices.Sort(result.Tests)
	slices.Sort(result.Tooling)
	slices.Sort(result.Invocations)
	return result, nil
}

func main() {
	repo := flag.String("repo", ".", "local Cortetsu source repository")
	baseline := flag.String("baseline", "", "optional frozen runtime Python path baseline")
	requireNative := flag.Bool("require-native", false, "fail if any first-party Python runtime file or invocation remains")
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
	if *requireNative && (len(found.Runtime) != 0 || len(found.Invocations) != 0) {
		fmt.Fprintln(os.Stderr, "first-party Python runtime dependency remains")
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
	// A new QML/Bash python3 invocation is an independent runtime
	// regression even when it reuses an already inventoried Python file.
	knownCallsites := make(map[string]bool, len(original.Invocations))
	for _, path := range original.Invocations {
		knownCallsites[path] = true
	}
	for _, path := range found.Invocations {
		if !knownCallsites[path] {
			fmt.Fprintln(os.Stderr, "new first-party Python runtime invocation:", path)
			os.Exit(1)
		}
	}
}

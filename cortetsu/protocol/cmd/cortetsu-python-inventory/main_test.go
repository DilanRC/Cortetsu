package main

import "testing"

func TestRuntimeLauncherScope(t *testing.T) {
	for _, input := range []string{
		"cortetsu/bin/build-runtime.sh", "cortetsu/modules/SomeWidget.qml",
		"cortetsu/services/ConnectivityNmAdapter.qml", "scripts/cortetsu",
		"scripts/install-cortetsu.sh", "scripts/lib/entry.sh",
	} {
		if !runtimeLauncher(input) {
			t.Errorf("did not count runtime caller %q", input)
		}
	}
	for _, input := range []string{
		"scripts/history/legacy.sh", "scripts/features/test-runtime.sh",
		"cortetsu/tests/test-service.sh", "docs/migration/F0/tools/bench_latency.py",
	} {
		if runtimeLauncher(input) {
			t.Errorf("counted non-runtime caller %q", input)
		}
	}
}

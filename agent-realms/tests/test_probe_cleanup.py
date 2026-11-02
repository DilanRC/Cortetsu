from __future__ import annotations

import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
REFERENCE_HEAD = "cd00962d7faf3a5059827994fbe746783695787f"


class ProbeCleanupTests(unittest.TestCase):
    def _run_probe(self, *, start_status: int, run_status: int = 0,
                   stop_status: int = 0) -> tuple[subprocess.CompletedProcess[str], str]:
        with tempfile.TemporaryDirectory(prefix="probe-cleanup-contract-") as directory:
            root = Path(directory)
            (root / "scripts").mkdir()
            (root / "bin").mkdir()
            fixture_dir = root / "tests/fixtures"
            fixture_dir.mkdir(parents=True)
            (root / "evidence/hypr-computer/live-probe").mkdir(parents=True)
            shutil.copy2(ROOT / "scripts/probe-hypr-computer.sh", root / "scripts/probe-hypr-computer.sh")
            shutil.copy2(ROOT / "tests/fixtures/hypr_computer_probe.py",
                         fixture_dir / "hypr_computer_probe.py")
            cli = root / "bin/agent-realm"
            cli.write_text("""#!/usr/bin/env bash
set -eu
printf '%s\\n' "$*" >> "$STUB_LOG"
case "$1" in
  doctor) exit 0 ;;
  start)
    mkdir -p "$XDG_DATA_HOME/cortetsu-agent-realms/$2/home"
    touch "$REALM_MARKER"
    exit "${START_STATUS:-0}"
    ;;
  run) exit "${RUN_STATUS:-0}" ;;
  stop)
    if [[ "${STOP_STATUS:-0}" == 0 ]]; then rm -f "$REALM_MARKER"; fi
    exit "${STOP_STATUS:-0}"
    ;;
esac
exit 2
""")
            cli.chmod(0o755)
            stub_bin = root / "stub-bin"
            stub_bin.mkdir()
            fake_git = stub_bin / "git"
            fake_git.write_text(f"#!/usr/bin/env bash\nprintf '%s\\n' '{REFERENCE_HEAD}'\n")
            fake_git.chmod(0o755)
            reference = root / "reference"
            (reference / ".venv/bin").mkdir(parents=True)
            fake_python = reference / ".venv/bin/python"
            fake_python.write_text("#!/usr/bin/env bash\nexit 0\n")
            fake_python.chmod(0o755)
            marker = root / "realm-alive"
            log = root / "calls.log"
            env = os.environ.copy()
            env.update({
                "PATH": f"{stub_bin}:/usr/bin:/bin",
                "XDG_DATA_HOME": str(root / "data"),
                "STUB_LOG": str(log),
                "REALM_MARKER": str(marker),
                "START_STATUS": str(start_status),
                "RUN_STATUS": str(run_status),
                "STOP_STATUS": str(stop_status),
            })
            result = subprocess.run(
                ["bash", str(root / "scripts/probe-hypr-computer.sh"), str(reference)],
                capture_output=True, text=True, env=env, timeout=10)
            calls = log.read_text()
            self.assertEqual(marker.exists(), stop_status != 0)
            return result, calls

    def test_partial_start_failure_still_attempts_stop(self) -> None:
        result, calls = self._run_probe(start_status=17)
        self.assertEqual(result.returncode, 17, result.stderr)
        self.assertIn("doctor\n", calls)
        self.assertRegex(calls, r"start hypr-computer-probe-.* --width 1280")
        self.assertRegex(calls, r"stop hypr-computer-probe-")
        self.assertNotIn("run ", calls)

    def test_stop_failure_changes_success_to_failure(self) -> None:
        result, calls = self._run_probe(start_status=0, run_status=0, stop_status=9)
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertIn("ERROR: failed to stop ephemeral realm", result.stderr)
        self.assertRegex(calls, r"stop hypr-computer-probe-")


if __name__ == "__main__":
    unittest.main()

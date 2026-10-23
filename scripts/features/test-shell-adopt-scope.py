#!/usr/bin/env python3
"""`cortetsu shell adopt` stops only the unsupervised Cortetsu Quickshell.

Three processes named `qs` run: a Cortetsu shell started outside systemd
(`qs -p <runtime>/current`), a foreign Quickshell config (`qs -p ~/other`) and a
foreign `qs` without -p. systemctl and cortetsu-platform are stubs, so nothing
on the real session is touched; the test re-executes itself in a private PID
namespace so even a global kill cannot reach the live shell. Only the Cortetsu one may receive SIGTERM.
"""
import os
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SLEEPER = "import signal, sys, time; signal.signal(signal.SIGTERM, lambda *_: sys.exit(0)); time.sleep(60)"


def main() -> int:
    # Run in a private PID namespace: a regression to a global `pkill qs`
    # must not reach the Quickshell of the session running the test.
    # CI containers may forbid user namespaces; they have no live session.
    unshare = ["unshare", "--user", "--map-root-user", "--pid", "--fork", "--mount-proc"]
    if os.environ.get("CORTETSU_ADOPT_NAMESPACE") != "1":
        isolated = shutil.which("unshare") and subprocess.run([*unshare, "true"], capture_output=True).returncode == 0
        if not isolated:
            if os.environ.get("CI") != "true":
                raise RuntimeError("unshare is required to isolate this test from the live session")
            os.environ["CORTETSU_ADOPT_NAMESPACE"] = "1"
    if os.environ.get("CORTETSU_ADOPT_NAMESPACE") != "1":
        os.execvpe("unshare", [*unshare, sys.executable, __file__], {**os.environ, "CORTETSU_ADOPT_NAMESPACE": "1"})
    with tempfile.TemporaryDirectory(prefix="adopt-") as tmp:
        base = Path(tmp)
        bin_dir, cli = base / "bin", base / "cli"
        bin_dir.mkdir()
        cli.mkdir()
        shutil.copy2(ROOT / "scripts/cortetsu", cli / "cortetsu")
        (cli / "cortetsu-platform").write_text("#!/bin/sh\nexit 0\n")
        (cli / "cortetsu-platform").chmod(0o755)
        calls = base / "systemctl.log"
        (bin_dir / "systemctl").write_text(f"#!/bin/sh\necho \"$*\" >> {calls}\nexit 0\n")
        (bin_dir / "systemctl").chmod(0o755)
        # A process whose comm is `qs`: execve through a link named qs.
        (bin_dir / "qs").symlink_to(shutil.which("python3"))
        config = base / "cfg"
        (config / "systemd/user").mkdir(parents=True)
        (config / "systemd/user/cortetsu-shell.service").write_text("[Service]\n")
        runtime = config / "quickshell/cortetsu"
        generation = base / "data/builds/g1"
        generation.mkdir(parents=True)
        runtime.mkdir(parents=True)
        (runtime / "current").symlink_to(generation)
        other = base / "other-config"
        other.mkdir()
        env = {**os.environ, "PATH": f"{bin_dir}:{os.environ['PATH']}", "XDG_CONFIG_HOME": str(config),
               "CORTETSU_RUNTIME_ROOT": str(runtime), "CORTETSU_DATA_ROOT": str(base / "data"),
               "CORTETSU_REPO_ROOT": str(ROOT)}

        def spawn(*args):
            return subprocess.Popen([str(bin_dir / "qs"), "-c", SLEEPER, *args], env=env)

        cortetsu = spawn("-p", str(runtime / "current"), "-n")
        foreign = spawn("-p", str(other), "-n")
        bare = spawn("-n")
        time.sleep(0.5)
        try:
            for proc in (cortetsu, foreign, bare):
                assert open(f"/proc/{proc.pid}/comm").read().strip() == "qs"
            result = subprocess.run([str(cli / "cortetsu"), "shell", "adopt"], env=env,
                                    capture_output=True, text=True, timeout=30)
            assert result.returncode == 0, result.stdout + result.stderr
            assert cortetsu.wait(timeout=5) == 0, "the unsupervised Cortetsu shell was not stopped"
            time.sleep(0.3)
            assert foreign.poll() is None, "a foreign Quickshell config was terminated"
            assert bare.poll() is None, "a foreign qs process was terminated"
            assert "enable --now cortetsu-shell.service" in calls.read_text()
        finally:
            for proc in (cortetsu, foreign, bare):
                if proc.poll() is None:
                    proc.kill()
                    proc.wait()
    print("PASS: shell adopt stops only the Cortetsu Quickshell")
    return 0


if __name__ == "__main__":
    sys.exit(main())

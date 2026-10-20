#!/usr/bin/env python3
"""ws2_run.py's Hyprland shim, without a desktop.

A fake hyprctl plays the desktop (runs the job it is handed, prints "ok") and
a fake Hyprland records what it was started with. Checks that argv, the
environment and the working directory survive quoting (quotes, spaces,
newlines, $, backslashes, empty args), that the compositor's output reaches
the caller's stdout, that TERM is forwarded and the job directory removed,
and that a rejected exec fails with 125.
"""
from __future__ import annotations

import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import time

sys.path.insert(0, str(Path(__file__).resolve().parent))
from ws2_run import render_shim  # noqa: E402

TRICKY = "it's \"quoted\" $HOME \\back\nnew line"
ARGS = ["a b", "it's", "$HOME", "", "--x=\"y\""]


def wait_for(predicate, what, timeout=10.0):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if predicate():
            return
        time.sleep(0.05)
    raise AssertionError(f"timeout: {what}")


def main() -> int:
    with tempfile.TemporaryDirectory(prefix="cz-shim-test-") as tmp:
        base = Path(tmp)
        state = base / "state"
        state.mkdir()
        record = base / "record.json"
        ctl = base / "fake-hyprctl"
        ctl.write_text(
            "#!/bin/sh\n"
            f'[ -e "{base}/reject" ] && {{ echo nope; exit 0; }}\n'
            'job=$(printf "%s" "$2" | sed \'s/.*exec_cmd("\\([^"]*\\)".*/\\1/\')\n'
            'case "$2" in *\'workspace = "2 silent"\'*) ;; *) echo "bad rule: $2"; exit 0;; esac\n'
            'setsid "$job" < /dev/null > /dev/null 2>&1 &\n'
            "echo ok\n")
        hyprland = base / "fake-Hyprland"
        hyprland.write_text(
            "#!/usr/bin/env python3\n"
            "import json, os, signal, sys, time\n"
            "print('compositor-output', flush=True)\n"
            "got = []\n"
            "signal.signal(signal.SIGTERM, lambda *a: got.append('TERM'))\n"
            f"json.dump({{'argv': sys.argv[1:], 'cwd': os.getcwd(), 'env': dict(os.environ)}}, open({str(record)!r}, 'w'))\n"
            "while not got: time.sleep(0.05)\n"
            f"open({str(record)!r} + '.term', 'w').write('TERM')\n")
        for script in (ctl, hyprland):
            script.chmod(0o755)
        shim = base / "Hyprland"
        shim.write_text(render_shim(str(state), "tok123", "desktop-his", "/run/user/test", 2,
                                    hyprctl=str(ctl), hyprland=str(hyprland)))
        shim.chmod(0o755)
        cwd = base / "dir with 'quote' and space"
        cwd.mkdir()
        out = base / "stdout.txt"

        env = {"PATH": os.environ["PATH"], "TRICKY": TRICKY, "XDG_RUNTIME_DIR": "/tmp/czr-test"}
        with out.open("w") as handle:
            process = subprocess.Popen([str(shim), *ARGS], cwd=cwd, env=env, stdout=handle, stderr=subprocess.STDOUT)
        try:
            wait_for(record.exists, "el Hyprland falso arrancó")
            time.sleep(0.2)
            seen = json.loads(record.read_text())
            assert seen["argv"] == ARGS, seen["argv"]
            assert seen["cwd"] == str(cwd), seen["cwd"]
            assert seen["env"].get("TRICKY") == TRICKY, repr(seen["env"].get("TRICKY"))
            assert seen["env"].get("XDG_RUNTIME_DIR") == "/tmp/czr-test", "el entorno del llamador no llegó"
            assert seen["env"].get("CORTETSU_WS2_RUN") == "tok123", "falta la marca de huérfanos"
            assert "HYPRLAND_INSTANCE_SIGNATURE" not in seen["env"], "se filtró la firma del escritorio"
            wait_for(lambda: "compositor-output" in out.read_text(), "salida del compositor en el stdout del llamador")
            assert process.poll() is None, "el shim terminó antes que el compositor"
            process.send_signal(signal.SIGTERM)
            wait_for(lambda: Path(str(record) + ".term").exists(), "TERM reenviado al compositor")
            process.wait(5)
            assert not any(state.iterdir()), f"quedó el directorio del job: {list(state.iterdir())}"
        finally:
            if process.poll() is None:
                process.kill()

        (base / "reject").touch()
        rejected = subprocess.run([str(shim)], cwd=cwd, env=env, capture_output=True, text=True, timeout=10)
        assert rejected.returncode == 125, (rejected.returncode, rejected.stderr)
        assert "exec rechazado" in rejected.stderr, rejected.stderr
        assert not any(state.iterdir()), "un exec rechazado dejó su directorio"
    print("PASS: ws2_run shim keeps argv, env and cwd, forwards TERM, cleans up, rejects a refused exec")
    return 0


if __name__ == "__main__":
    sys.exit(main())

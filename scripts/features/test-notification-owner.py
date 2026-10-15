#!/usr/bin/env python3
"""Cortetsu is the only notification server; mako cannot win the bus by activation.

The installer's mask_rival_notification_daemon runs against a fake systemctl.
On a live session the test also checks who owns the bus.
"""
from pathlib import Path
import os
import shutil
import subprocess
import tempfile
import textwrap

repo = Path(__file__).resolve().parents[2]
library = repo / "scripts/lib/notification-owner.sh"
installer = (repo / "scripts/install-cortetsu.sh").read_text(encoding="utf-8")
assert 'source "$REPO/scripts/lib/notification-owner.sh"\nmask_rival_notification_daemon\n' in installer

FAKE = textwrap.dedent("""\
    #!/bin/bash
    printf '%s\\n' "$*" >> "$FAKE_LOG"
    case "$2" in
        is-enabled) echo "$FAKE_STATE" ;;
        is-active) echo "$FAKE_ACTIVE" ;;
        cat) [[ "$FAKE_STATE" != missing ]] ;;
        mask) [[ "$FAKE_MASK" == ok ]] ;;
    esac
""")
MASK = "--user mask --now mako.service"
PROBES = ["--user is-enabled mako.service", "--user cat mako.service", "--user is-active mako.service"]
RESTART = "reinicia cortetsu-shell"

cases = [
    # state, active, mask result, expected calls, stdout must contain, stderr must contain
    ("enabled", "inactive", "ok", PROBES + [MASK], "enmascarada", ""),
    ("disabled", "inactive", "ok", PROBES + [MASK], "enmascarada", ""),
    ("static", "active", "ok", PROBES + [MASK], RESTART, ""),
    ("disabled", "inactive", "fail", PROBES + [MASK], "", "WARN"),
    ("masked", "inactive", "ok", PROBES[:1], "", ""),
    ("missing", "inactive", "ok", PROBES[:2], "", ""),
]
for state, active, mask, expected, out, err in cases:
    with tempfile.TemporaryDirectory(prefix="cortetsu mako ") as temporary:
        root = Path(temporary)
        (root / "systemctl").write_text(FAKE)
        (root / "systemctl").chmod(0o755)
        env = dict(os.environ, PATH=f"{root}:{os.environ['PATH']}", FAKE_LOG=str(root / "calls"),
                   FAKE_STATE=state, FAKE_ACTIVE=active, FAKE_MASK=mask)
        result = subprocess.run(["bash", "-c", 'set -euo pipefail; source "$1"; mask_rival_notification_daemon', "_",
                                 str(library)], capture_output=True, text=True, env=env, check=True)
        calls = (root / "calls").read_text().splitlines()
        assert calls == expected, (state, calls)
        assert out in result.stdout and err in result.stderr, (state, result)
        assert (RESTART in result.stdout) == (active == "active" and mask == "ok"), (state, result.stdout)

live = "; SKIP live check: no session bus"
if os.environ.get("DBUS_SESSION_BUS_ADDRESS") and shutil.which("busctl"):
    status = subprocess.run(["busctl", "--user", "status", "org.freedesktop.Notifications"],
                            capture_output=True, text=True)
    if status.returncode != 0:
        live = "; SKIP live check: nobody owns org.freedesktop.Notifications"
    else:
        assert "UserUnit=cortetsu-shell.service" in status.stdout, status.stdout
        info = subprocess.run(["busctl", "--user", "call", "org.freedesktop.Notifications",
                               "/org/freedesktop/Notifications", "org.freedesktop.Notifications",
                               "GetServerInformation"], capture_output=True, text=True).stdout
        assert '"quickshell"' in info, info
        live = "; live bus owned by cortetsu-shell"
print("PASS: installer masks only mako.service and reports failure and restart" + live)

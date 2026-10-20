#!/usr/bin/env python3
"""Run a command whose nested Hyprland windows are born on one desktop workspace.

    python3 scripts/integration/ws2_run.py [--workspace 2] [--timeout 900] LOG -- COMMAND...

Nested-Hyprland tests start `Hyprland` as a child; the desktop then places
that window by its ordinary rules (on this machine a personal rule sends
class `aquamarine` to WS 11; without one it lands on the active workspace).
Here COMMAND runs with a `Hyprland` shim first on PATH. The shim asks the
desktop's Hyprland to start the real /usr/bin/Hyprland itself, with the exec
rule `workspace = "<N> silent"`: the compositor is the process the desktop
spawned, so the rule applies (it does not reliably reach deeper descendants),
it wins over window rules, and focus and the active workspace never change.
The shim stays in the caller's place: it forwards TERM/INT/HUP and exits when
the compositor does. No rule is added to the desktop config.

Leftover compositors (shim killed with SIGKILL) carry CORTETSU_WS2_RUN=<token>
in their environment and are killed when COMMAND ends. Exit status is
COMMAND's; 124 on timeout.
"""
from __future__ import annotations

import argparse
import os
from pathlib import Path
import shlex
import signal
import subprocess
import sys
import tempfile
import time
import uuid

REAL_HYPRCTL = "/usr/bin/hyprctl"
REAL_HYPRLAND = "/usr/bin/Hyprland"

# bash (read -d). q() single-quotes a value for the job script the desktop runs.
SHIM = r"""#!/bin/bash
# Hyprland shim written by ws2_run.py: the desktop spawns the real compositor.
q() { printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"; }
# The job holds the whole environment: keep it in ws2_run's private directory,
# which is removed even if this shim is killed.
dir=$(mktemp -d @STATE@/job-XXXXXX) || exit 125
{
  echo '#!/bin/sh'
  echo "echo \$\$ > $dir/pid"
  echo "cd $(q "$PWD") || exit 125"
  printf 'exec env -i'
  env -0 | while IFS= read -r -d '' line; do printf ' %s' "$(q "$line")"; done
  printf ' CORTETSU_WS2_RUN=@TOKEN@ @HYPRLAND@'
  for arg in "$@"; do printf ' %s' "$(q "$arg")"; done
  printf ' >> /proc/%s/fd/1 2>> /proc/%s/fd/2\n' "$$" "$$"
} > "$dir/job.sh"
chmod +x "$dir/job.sh"
reply=$(HYPRLAND_INSTANCE_SIGNATURE=@HIS@ XDG_RUNTIME_DIR=@RUNTIME@ @HYPRCTL@ dispatch \
  "hl.dsp.exec_cmd(\"$dir/job.sh\", { workspace = \"@WORKSPACE@ silent\" })")
[ "$reply" = ok ] || { echo "ws2 shim: exec rechazado: $reply" >&2; rm -rf "$dir"; exit 125; }
i=0
while [ ! -s "$dir/pid" ]; do
  i=$((i + 1)); [ "$i" -gt 200 ] && { echo "ws2 shim: sin PID" >&2; exit 125; }; sleep 0.05
done
pid=$(cat "$dir/pid")
trap 'kill -TERM "$pid" 2>/dev/null' TERM INT HUP
while kill -0 "$pid" 2>/dev/null; do sleep 0.1; done
rm -rf "$dir"
"""


def render_shim(state: str, token: str, signature: str, runtime: str, workspace: int,
                hyprctl: str = REAL_HYPRCTL, hyprland: str = REAL_HYPRLAND) -> str:
    text = SHIM
    for key, value in {"@STATE@": shlex.quote(state), "@TOKEN@": token, "@HYPRLAND@": hyprland,
                       "@HYPRCTL@": hyprctl, "@HIS@": shlex.quote(signature),
                       "@RUNTIME@": shlex.quote(runtime), "@WORKSPACE@": str(int(workspace))}.items():
        text = text.replace(key, value)
    return text


def leftovers(token: str) -> list[int]:
    marker = f"CORTETSU_WS2_RUN={token}".encode()
    found = []
    for entry in Path("/proc").iterdir():
        if entry.name.isdigit():
            try:
                if marker in (entry / "environ").read_bytes().split(b"\0"):
                    found.append(int(entry.name))
            except OSError:
                pass
    return found


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--workspace", default="2")
    parser.add_argument("--timeout", type=float, default=900)
    parser.add_argument("log", type=Path)
    parser.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    command = args.command[1:] if args.command[:1] == ["--"] else args.command
    if not command or not os.environ.get("HYPRLAND_INSTANCE_SIGNATURE"):
        parser.error("hace falta un comando y una sesión de Hyprland")

    token = uuid.uuid4().hex
    with tempfile.TemporaryDirectory(prefix="cz-ws2-") as tmp:
        shim = Path(tmp) / "Hyprland"
        shim.write_text(render_shim(tmp, token, os.environ["HYPRLAND_INSTANCE_SIGNATURE"],
                                    os.environ["XDG_RUNTIME_DIR"], int(args.workspace)))
        shim.chmod(0o755)
        env = dict(os.environ, PATH=f"{tmp}:{os.environ['PATH']}")
        with args.log.open("w") as log:
            process = subprocess.Popen(command, env=env, stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
            try:
                rc = process.wait(args.timeout)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGTERM)
                try:
                    process.wait(10)
                except subprocess.TimeoutExpired:
                    os.killpg(process.pid, signal.SIGKILL)
                rc = 124
                print("ws2_run: tiempo agotado", file=sys.stderr)
        stray = leftovers(token)
        for pid in stray:
            try:
                os.kill(pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
        if stray:
            time.sleep(2)
            for pid in leftovers(token):
                try:
                    os.kill(pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
            print(f"ws2_run: compositores huérfanos terminados: {stray}", file=sys.stderr)
        return rc


if __name__ == "__main__":
    sys.exit(main())

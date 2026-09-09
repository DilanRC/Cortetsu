#!/usr/bin/env python3
"""Exercise the live-PID shell IPC bridge without changing shell state."""
from __future__ import annotations

import subprocess
from pathlib import Path

repo = Path(__file__).resolve().parents[2]
result = subprocess.run(
    [str(repo / "scripts/cortetsu"), "shell", "ipc", "clipboard", "isOpen"],
    cwd=repo,
    text=True,
    stdout=subprocess.PIPE,
    stderr=subprocess.STDOUT,
    check=True,
)

assert result.stdout.strip() in {"false", "true", "0", "1"}, result.stdout
print(f"Shell IPC eval: clipboard isOpen={result.stdout.strip()} via live MainPID")

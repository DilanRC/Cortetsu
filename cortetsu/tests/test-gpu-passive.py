#!/usr/bin/env python3
"""A runtime-suspended NVIDIA dGPU is reported without running nvidia-smi.

nvidia-smi resumes the dGPU from D3cold, so the probe and the power helper
must decide from power/runtime_status alone. A fake sysfs holds one NVIDIA
display device and a fake nvidia-smi on PATH records every call it gets.
"""
import json
import os
import subprocess
import tempfile
from pathlib import Path

BIN = Path(__file__).resolve().parents[1] / "bin"
SMI = """#!/bin/sh
echo called >> "$SMI_CALLS"
case "$1" in
  --query-gpu=name,utilization*) echo "NVIDIA GeForce RTX 4060 Laptop GPU, 37, 52, 812, 8188, 21.4" ;;
  *) echo "NVIDIA GeForce RTX 4060 Laptop GPU, P3, 21.40, 80.00, 52, 1200, 7000" ;;
esac
"""


def nvidia(gpus: list[dict]) -> list[dict]:
    return [gpu for gpu in gpus if gpu.get("vendor") == "NVIDIA"]


with tempfile.TemporaryDirectory(prefix="cortetsu-gpu-passive-") as tmp:
    root = Path(tmp)
    device = root / "sys/bus/pci/devices/0000:01:00.0"
    (device / "power").mkdir(parents=True)
    (device / "vendor").write_text("0x10de\n")
    (device / "class").write_text("0x030000\n")
    (device / "device").write_text("0x28e0\n")
    bindir = root / "bin"
    bindir.mkdir()
    (bindir / "nvidia-smi").write_text(SMI)
    (bindir / "nvidia-smi").chmod(0o755)
    calls = root / "smi-calls"
    env = {**os.environ, "CORTETSU_SYSFS_ROOT": str(root / "sys"), "SMI_CALLS": str(calls),
           "PATH": f"{bindir}:{os.environ['PATH']}", "XDG_RUNTIME_DIR": tmp}

    def run(tool: str, *args: str) -> list[dict]:
        result = subprocess.run(["python3", str(BIN / tool), *args], capture_output=True, text=True,
                                timeout=30, env=env, check=True)
        return nvidia(json.loads(result.stdout)["gpus"])

    def smi_calls() -> int:
        return len(calls.read_text().splitlines()) if calls.exists() else 0

    for status in ("suspended", "suspending"):
        (device / "power/runtime_status").write_text(f"{status}\n")
        probe, power = run("cortetsu-hardware-probe", "--gpus"), run("cortetsu-hardware-power")
        assert smi_calls() == 0, f"nvidia-smi ran while the dGPU was {status}"
        assert [gpu["state"] for gpu in probe] == ["suspended"], probe
        assert probe[0]["usage"] is None and probe[0]["temp_c"] is None, "no invented statistics while asleep"
        assert probe[0]["name"], "the name comes from pci.ids or the generic fallback"
        assert [gpu["state"] for gpu in power] == ["suspended"] and power[0]["power_w"] is None, power

    (device / "power/runtime_status").write_text("active\n")
    probe, power = run("cortetsu-hardware-probe", "--gpus"), run("cortetsu-hardware-power")
    assert smi_calls() == 2, "an active dGPU is queried once by each tool"
    assert probe == [{"vendor": "NVIDIA", "name": "NVIDIA GeForce RTX 4060 Laptop GPU", "state": "active",
                      "usage": 37.0, "temp_c": 52.0, "vram_used_gb": 0.79, "vram_total_gb": 8.0,
                      "power_w": 21.4}], probe
    assert power[0]["state"] == "active" and power[0]["power_w"] == 21.4, power

print("PASS: a suspended dGPU is reported from runtime_status without nvidia-smi; an active one is queried")

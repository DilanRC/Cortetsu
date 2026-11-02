#!/usr/bin/env python3
"""Write a simulated GPU layout into a realm's HOME for Cortetsu's hardware probe.

Usage: scripts/realm-gpu-scenario.py REALM SCENARIO   (prints the env to pass)
       scripts/realm-gpu-scenario.py --list

The probe reads its sysfs root from CORTETSU_SYSFS_ROOT and finds nvidia-smi
and lspci on PATH. This writes a small tree under the realm's own HOME
(never the real /sys, never a kernel device) and prints the variables that
point the probe at it, for realm-cortetsu.sh:

    CORTETSU_REALM_ENV="$(scripts/realm-gpu-scenario.py dev amd-nvidia-active)" \
        scripts/realm-cortetsu.sh dev WORKTREE

Every other sysfs path (CPU, hwmon, battery, network) links back to the realm's
read-only /sys. The AMD and NVIDIA names say "simulada"; the probe flags
the whole reading as simulated because the root is not /sys.
"""
from __future__ import annotations

import shutil
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "src"))
from cortetsu_agent_realms.paths import RealmError, paths_for  # noqa: E402

REALM_DIR = "/home/agent/.local/share/agent-realm-gpu"  # the same directory, seen from inside the realm
PASSTHROUGH = ("devices", "class/hwmon", "class/power_supply", "class/net", "block", "firmware", "fs", "kernel")
MIB = 1024 * 1024

AMD = {"vendor": "0x1002", "device": "0x1900", "slot": "0000:05:00.0", "name": "AMD Radeon 780M (simulada)",
       "busy": 23, "temp_mc": 54000, "power_uw": 12_500_000, "vram_total": 2048 * MIB, "vram_used": 512 * MIB}
NVIDIA = {"slot": "0000:01:00.0", "device": "0x25a2"}
SMI_ACTIVE = """#!/bin/sh
case "$1" in
  --query-gpu=name,utilization*) echo "NVIDIA GeForce RTX 3050 Laptop GPU (simulada), 41, 63, 1210, 4096, 27.5" ;;
  --query-gpu=name,pstate*) echo "NVIDIA GeForce RTX 3050 Laptop GPU (simulada), P2, 27.50, 60.00, 63, 1500, 6000" ;;
  *) exit 2 ;;
esac
"""
SMI_FAILING = "#!/bin/sh\necho 'NVIDIA-SMI has failed (simulado)' >&2\nexit 9\n"
SMI_WOKEN = "#!/bin/sh\necho called >> \"$HOME/.local/share/agent-realm-gpu/nvidia-smi-calls\"\nexit 9\n"

SCENARIOS = {
    "amd": "solo la iGPU AMD con todas sus lecturas",
    "amd-incomplete": "iGPU AMD sin carga, temperatura ni VRAM (driver incompleto)",
    "amd-nvidia-suspended": "AMD + NVIDIA en reposo (nvidia-smi registra si alguien lo llama)",
    "amd-nvidia-active": "AMD + NVIDIA activa con lecturas de nvidia-smi",
    "nvidia-unavailable": "AMD + NVIDIA activa con nvidia-smi fallando",
    "intel": "solo una iGPU Intel sin lectura de carga",
    "unknown": "una GPU de proveedor desconocido con carga y sin sensores",
    "none": "ninguna GPU",
}


def write(path: Path, text: str, mode: int = 0o644) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")
    path.chmod(mode)


def drm_card(sys_root: Path, card: str, vendor: str, device: str, slot: str, extra: dict[str, str]) -> Path:
    dev = sys_root / "class/drm" / card / "device"
    write(dev / "vendor", f"{vendor}\n")
    write(dev / "device", f"{device}\n")
    write(dev / "class", "0x030000\n")
    write(dev / "uevent", f"PCI_SLOT_NAME={slot}\n")
    for name, value in extra.items():
        write(dev / name, f"{value}\n")
    return dev


def amd(sys_root: Path, complete: bool) -> None:
    extra = {"power_dpm_state": "performance", "power_dpm_force_performance_level": "auto",
             "power/runtime_status": "active"}
    if complete:
        extra |= {"gpu_busy_percent": str(AMD["busy"]), "mem_info_vram_total": str(AMD["vram_total"]),
                  "mem_info_vram_used": str(AMD["vram_used"]), "hwmon/hwmon9/temp1_input": str(AMD["temp_mc"]),
                  "hwmon/hwmon9/power1_average": str(AMD["power_uw"])}
    drm_card(sys_root, "card1", AMD["vendor"], AMD["device"], AMD["slot"], extra)


def nvidia(sys_root: Path, status: str) -> None:
    pci = sys_root / "bus/pci/devices" / NVIDIA["slot"]
    write(pci / "vendor", "0x10de\n")
    write(pci / "class", "0x030200\n")
    write(pci / "device", f"{NVIDIA['device']}\n")
    write(pci / "power/runtime_status", f"{status}\n")


def build(home: Path, scenario: str) -> str:
    root = home / ".local/share/agent-realm-gpu"
    shutil.rmtree(root, ignore_errors=True)
    sys_root, bindir = root / "sys", root / "bin"
    (sys_root / "class/drm").mkdir(parents=True)
    (sys_root / "bus/pci/devices").mkdir(parents=True)
    bindir.mkdir()
    for part in PASSTHROUGH:  # dangling on the host, resolved inside the realm
        link = sys_root / part
        link.parent.mkdir(parents=True, exist_ok=True)
        link.symlink_to(f"/sys/{part}")
    # Without an NVIDIA device the probe must not call nvidia-smi; this one
    # records any call so a scenario can prove it, and never reaches a real GPU.
    write(bindir / "nvidia-smi", SMI_WOKEN, 0o755)
    write(bindir / "lspci", f"#!/bin/sh\necho \"{AMD['slot'][5:]} Display controller: {AMD['name']}\"\n", 0o755)

    if scenario in ("amd", "amd-nvidia-suspended", "amd-nvidia-active", "nvidia-unavailable"):
        amd(sys_root, complete=True)
    elif scenario == "amd-incomplete":
        amd(sys_root, complete=False)
    elif scenario == "intel":
        drm_card(sys_root, "card0", "0x8086", "0x46a6", "0000:00:02.0", {})
    elif scenario == "unknown":
        drm_card(sys_root, "card0", "0x1a03", "0x2000", "0000:07:00.0", {"gpu_busy_percent": "12"})
    if scenario == "amd-nvidia-suspended":
        nvidia(sys_root, "suspended")
    elif scenario == "amd-nvidia-active":
        nvidia(sys_root, "active")
        write(bindir / "nvidia-smi", SMI_ACTIVE, 0o755)
    elif scenario == "nvidia-unavailable":
        nvidia(sys_root, "active")
        write(bindir / "nvidia-smi", SMI_FAILING, 0o755)
    path = f"{REALM_DIR}/bin:/home/agent/.local/bin:/usr/local/bin:/usr/bin:/bin"
    return f"CORTETSU_SYSFS_ROOT={REALM_DIR}/sys PATH={path}"


def main(argv: list[str]) -> int:
    if argv[:1] == ["--list"]:
        for name, text in SCENARIOS.items():
            print(f"{name:22} {text}")
        return 0
    if len(argv) != 2 or argv[1] not in SCENARIOS:
        print(f"uso: realm-gpu-scenario.py REALM {{{','.join(SCENARIOS)}}} | --list", file=sys.stderr)
        return 2
    try:
        home = paths_for(argv[0]).home
    except RealmError as exc:
        print(f"realm-gpu-scenario: {exc}", file=sys.stderr)
        return 2
    if not home.is_dir():
        print(f"realm-gpu-scenario: el realm {argv[0]!r} no tiene HOME; inícialo antes", file=sys.stderr)
        return 2
    print(build(home, argv[1]))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))

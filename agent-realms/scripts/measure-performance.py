#!/usr/bin/env python3
"""Measure realm, simulator, MCP and observer cost on this machine.

Writes evidence/performance/report.json and report.md. PSS and CPU come from /proc,
summed over exact systemd scopes or PIDs; GPU busy is device-wide and is not attributed.
Usage: scripts/measure-performance.py [evidence-dir]   (needs .venv for the MCP part)
"""
from __future__ import annotations

import http.client
import json
import os
import re
import statistics
import subprocess
import sys
import tempfile
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "src"))
sys.path.insert(0, str(ROOT / "tests"))
from cortetsu_agent_realms.cli import _proc_scope_metrics  # noqa: E402
from cortetsu_agent_realms.paths import paths_for  # noqa: E402
from mcp_wire import Server  # noqa: E402

AR = str(ROOT / "bin/agent-realm")
OUT = Path(sys.argv[1] if len(sys.argv) > 1 else ROOT / "evidence/performance")
OUT.mkdir(parents=True, exist_ok=True)
REALM = f"perf-{os.getpid()}"
HZ = os.sysconf("SC_CLK_TCK")
report: dict = {"realm": REALM, "machine_note": "medido en el portátil del usuario con su sesión Hyprland activa"}


def cli(*args: str) -> dict | list:
    return json.loads(subprocess.run([AR, *args], check=True, capture_output=True, text=True).stdout)


def timed(fn, *args):
    start = time.monotonic()
    value = fn(*args)
    return value, round((time.monotonic() - start) * 1000, 1)


def pid_metrics(pid: int) -> tuple[int, float]:
    """PSS KiB and CPU seconds of one process."""
    pss = int(re.search(r"^Pss:\s+(\d+)", Path(f"/proc/{pid}/smaps_rollup").read_text(), re.M).group(1))
    fields = Path(f"/proc/{pid}/stat").read_text().rsplit(")", 1)[1].split()
    return pss, (int(fields[11]) + int(fields[12])) / HZ


def scope_metrics(units: set[str]) -> dict:
    count, ticks, pss = _proc_scope_metrics(Path("/proc"), units)
    return {"processes": count, "pss_mib": round(pss / 1024, 1), "cpu_s": round(ticks / HZ, 3)}


def realm_units() -> set[str]:
    out = subprocess.run(["systemctl", "--user", "list-units", f"agent-realm-{REALM}-*", "--no-legend",
                          "--plain"], capture_output=True, text=True).stdout
    return {line.split()[0] for line in out.splitlines() if line.strip()}


def sim_unit() -> str | None:
    apps = paths_for(REALM).control / "apps"
    for record in apps.glob("*.json"):
        data = json.loads(record.read_text())
        if "cortetsu_agent_realms.simulation.daemon" in data.get("command", []):
            return data["systemd_scope_unit"]
    return None


def median_ms(samples: list[float]) -> dict:
    return {"median_ms": round(statistics.median(samples), 1), "p90_ms": round(sorted(samples)[int(len(samples) * 0.9) - 1], 1),
            "n": len(samples)}


def idle_cpu(units: set[str], seconds: float = 10) -> float:
    before = scope_metrics(units)["cpu_s"]
    time.sleep(seconds)
    return round((scope_metrics(units)["cpu_s"] - before) / seconds * 100, 2)


def main() -> None:
    try:
        started, report["realm_start_ms"] = timed(cli, "start", "--ephemeral", REALM)
        assert started["state"] == "running"
        time.sleep(3)
        units = realm_units()
        report["realm_idle"] = {**scope_metrics(units), "cpu_percent_idle_10s": idle_cpu(units)}

        _, report["simulation_start_ms"] = timed(cli, "simulate", REALM, "--scenario", "charging")
        time.sleep(2)
        unit = sim_unit()
        report["simulator_idle"] = {**scope_metrics({unit}), "cpu_percent_idle_10s": idle_cpu({unit})}
        set_samples = [timed(cli, "simulate", REALM, "--set", f"upower.battery.percentage={p}")[1]
                       for p in (40, 50, 60, 70, 80)]
        report["simulation_set_latency"] = median_ms(set_samples)

        # MCP server bound to this realm through a temporary profile.
        with tempfile.TemporaryDirectory() as tmp:
            folder = Path(tmp) / "cortetsu-agent-realms"
            folder.mkdir(mode=0o700)
            (folder / "profiles.json").write_text(json.dumps({"schema": 1, "profiles": {
                "perf": {"realm": REALM, "capabilities": ["observe", "control", "admin"]}}}))
            (folder / "profiles.json").chmod(0o600)
            t0 = time.monotonic()
            server = Server(tmp, "perf")
            server.handshake()
            report["mcp_handshake_ms"] = round((time.monotonic() - t0) * 1000, 1)
            python_pid = server.proc.pid  # the wrapper execs python, so this is the server
            latencies = {}
            for name, args, n in (("realm_status", {}, 10), ("window_list", {}, 10),
                                  ("screenshot", {"max_width": 1280}, 5),
                                  ("pointer", {"action": "move", "x": 400, "y": 300}, 10),
                                  ("keyboard", {"action": "key", "value": "Shift_L"}, 5)):
                samples = []
                for _ in range(n):
                    t = time.monotonic()
                    reply = server.call(name, args)
                    assert not reply["result"].get("isError"), reply
                    samples.append((time.monotonic() - t) * 1000)
                latencies[name] = median_ms(samples)
            report["mcp_latency"] = latencies
            pss, cpu = pid_metrics(python_pid)
            report["mcp_server"] = {"pss_mib": round(pss / 1024, 1), "cpu_s_after_calls": round(cpu, 3)}
            cpu_before = scope_metrics(units)["cpu_s"]
            t = time.monotonic()
            for i in range(20):
                server.call("pointer", {"action": "move", "x": 100 + i * 10, "y": 200})
            wall = time.monotonic() - t
            report["realm_cpu_during_20_pointer_moves"] = {
                "cpu_percent": round((scope_metrics(units)["cpu_s"] - cpu_before) / wall * 100, 2), "wall_s": round(wall, 2)}
            server.close()

        # Authenticated observer.
        status, report["observer_start_ms"] = timed(cli, "observe", REALM)
        launch = cli("observe", REALM, "--launch-file")["launch_file"]
        port, ticket = re.search(r"127\.0\.0\.1:(\d+)/#t=([A-Za-z0-9_-]+)", Path(launch).read_text()).groups()
        conn = http.client.HTTPConnection("127.0.0.1", int(port), timeout=10)
        conn.request("POST", "/api/session", json.dumps({"ticket": ticket}),
                     {"Origin": f"http://127.0.0.1:{port}", "Content-Type": "application/json"})
        token = json.loads(conn.getresponse().read())["token"]
        samples = []
        for _ in range(10):
            time.sleep(0.55)  # past the frame cache interval: every sample is a fresh capture
            t = time.monotonic()
            conn.request("GET", "/api/frame", headers={"Authorization": f"Bearer {token}"})
            response = conn.getresponse()
            response.read()
            assert response.status == 200
            samples.append((time.monotonic() - t) * 1000)
        conn.close()
        report["observer_frame_latency"] = median_ms(samples)
        pss, cpu = pid_metrics(status["pid"])
        report["observer"] = {"pss_mib": round(pss / 1024, 1), "cpu_s_total": round(cpu, 3)}

        clicks = [timed(cli, "move", REALM, "300", "300")[1] for _ in range(5)]
        report["cli_command_latency_move"] = median_ms(clicks)
        host = []
        for _ in range(15):
            t = time.monotonic()
            subprocess.run(["hyprctl", "-j", "version"], capture_output=True)
            host.append((time.monotonic() - t) * 1000)
        report["host_hyprctl_latency_reference"] = median_ms(host)
        report["realm_with_sim_and_observer"] = scope_metrics(realm_units())
    finally:
        _, report["realm_stop_ms"] = timed(subprocess.run, [AR, "stop", REALM])
    time.sleep(1)
    runtime = paths_for(REALM).runtime
    leftovers = {
        "scopes": len(realm_units()),
        "processes": len([p for p in subprocess.run(["pgrep", "-f", REALM], capture_output=True, text=True).stdout.split()
                          if p and int(p) != os.getpid()]),
        "runtime_entries": sorted(p.name for p in runtime.iterdir()) if runtime.exists() else [],
        "observer_dir_entries": sorted(p.name for p in (Path(os.environ["XDG_RUNTIME_DIR"]) / "cortetsu-agent-realms"
                                                        / "observers" / REALM).iterdir())
        if (Path(os.environ["XDG_RUNTIME_DIR"]) / "cortetsu-agent-realms" / "observers" / REALM).exists() else [],
    }
    report["after_stop"] = leftovers
    (OUT / "report.json").write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n")
    print(json.dumps(report, indent=2, ensure_ascii=False))


if __name__ == "__main__":
    main()

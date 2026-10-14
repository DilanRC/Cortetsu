#!/usr/bin/env python3
"""Runtime check of the real Hardware Center summary against a scripted probe.

The real Content.qml, telemetry and summary page run inside Quickshell on the
offscreen platform. HOME points at a temporary tree whose probe prints fixed
readings, fails, or hangs on request, so the test never reads this machine and
every state of the page can be reached on demand.

Set CORTETSU_RENDER_DIR to keep a PNG of each state for visual review.
"""
import json
import os
import shutil
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2] / "cortetsu"
RENDER_DIR = os.environ.get("CORTETSU_RENDER_DIR", "")

CONFIG = """pragma Singleton
import QtQuick
QtObject {
    property bool transparencyEnabled: false
    property bool useTwelveHourClock: false
}
"""

# The real one opens a layer-shell window, which the offscreen platform lacks.
IDLE_INHIBITOR = """pragma Singleton
import QtQuick
QtObject { property bool enabled: false }
"""

PROBE = """#!/bin/sh
printf '%s\\n' "$*" >> "$HARDWARE_FIXTURES/calls.log"
mode=$(cat "$HARDWARE_FIXTURES/mode")
case "$mode" in
    fail) exit 3 ;;
    garbage) echo "not json" ;;
    hang) exec sleep 30 ;;
    *) if [ "$1" = "--top-processes" ]; then cat "$HARDWARE_FIXTURES/$mode.json"; else cat "$HARDWARE_FIXTURES/$mode.full.json"; fi ;;
esac
"""

SHELL = """import QtQuick
import QtQuick.Window
import Quickshell
import Quickshell.Io
import "modules/hardware"

ShellRoot {
    id: root
    property int checks: 0
    property int step: 0
    property var kept: ({})
    readonly property string fixtures: Quickshell.env("HARDWARE_FIXTURES")
    readonly property string renderDir: Quickshell.env("CORTETSU_RENDER_DIR")
    readonly property string scenario: Quickshell.env("HARDWARE_SCENARIO")
    readonly property var telemetry: content.telemetry

    function verify(value, reason) { if (!value) { console.log("HARDWARE_FAIL", reason); return; } checks++; }
    function render(name) {
        if (renderDir)
            content.grabToImage(result => result.saveToFile(`${renderDir}/${name}.png`));
    }
    // Written synchronously, so the next probe run is certain to see it.
    function mode(name) { modeFile.setText(name); content.refresh(); }
    function find(item, name) {
        if (!item)
            return null;
        if (item.objectName === name)
            return item;
        for (const child of item.children) {
            const found = find(child, name);
            if (found)
                return found;
        }
        return null;
    }
    function text(name) { return find(content, name)?.text ?? ""; }
    // Walks the Tab chain from the selected tab and names what it reaches.
    function tabOrder() {
        const names = [];
        const seen = [];
        let item = content;
        for (let i = 0; i < 60; ++i) {
            item = item.nextItemInFocusChain(true);
            if (!item || seen.includes(item))
                break;
            seen.push(item);
            names.push(item.objectName || "-");
        }
        return names;
    }

    FileView {
        id: modeFile
        path: `${root.fixtures}/mode`
        blockWrites: true
    }

    QtObject {
        id: retained
        property bool hardware: false
        function setRetained(name, value) { if (name === "hardware") hardware = value; }
    }
    QtObject {
        id: screenState
        property var cortetsuState: retained
    }

    Window {
        width: 1280; height: 900; visible: true; color: "#0B0D10"
        Content {
            id: content
            anchors.fill: parent
            screen: null
            screenState: screenState
            hardwareVisible: retained.hardware
        }
    }

    // Each step is [condition, action]. The action runs once the condition
    // holds, so a slow machine waits instead of failing.
    readonly property var summary: [
        [() => waitedMs >= 2000, () => {
            verify(telemetry.sampleCount === 0 && telemetry.status === "loading", "a closed centre does not sample");
            retained.hardware = true;
            content.openHardware();
        }],
        [() => telemetry.status === "live", () => {
            verify(text("healthHeadline") === "Todo en orden", "an ordinary reading is reported as fine");
            verify(text("cpuUsage") === "32 %", "the CPU figure comes from the reading");
            verify(find(content, "gpuRows").count === 2, "one row per detected GPU");
            verify(find(content, "processBlock").visibleRows === 5, "the busiest processes are listed");
            verify(find(content, "healthIssues").count === 0, "nothing is flagged");
            verify(find(content, "overviewState") === null, "the reading replaces the loading state");
            kept = {
                gpu: find(content, "gpuRows").itemAt(0),
                process: find(content, "processRows").itemAt(0),
                cpu: find(content, "cpuBlock")
            };
            // Header, the ten tabs, then the page top to bottom and left to right.
            const order = tabOrder().join(",");
            verify(order === "hardwareRefresh,hardwareClose,-,-,-,-,-,-,-,-,-,-,cpuBlock,-,-,memoryBlock,diskBlock,processBlock,powerLink,networkLink,coolingLink",
                `Tab follows the visual order (${order})`);
        }],
        [() => waitedMs >= 400, () => {
            render("ok");
            mode("attention");
        }],
        [() => text("cpuUsage") === "71 %", () => {
            verify(text("healthHeadline") === "Conviene revisar", "a warning changes the verdict");
            verify(find(content, "healthIssues").count === 2, "each problem is its own row");
            verify(find(content, "gpuRows").itemAt(0) === kept.gpu, "a new reading keeps the GPU rows");
            verify(find(content, "processRows").itemAt(0) === kept.process, "a new reading keeps the process rows");
            verify(find(content, "cpuBlock") === kept.cpu, "a new reading keeps the page");
            verify(tabOrder().indexOf("cpuBlock") === 14, "the two flagged rows come before the meters in the Tab order");
        }],
        [() => waitedMs >= 400, () => {
            render("attention");
            find(content, "healthIssues").itemAt(1).activated();
            verify(content.currentPage === 4, "the disk warning opens the I/O page");
            content.currentPage = 0;
            mode("critical");
        }],
        [() => text("cpuUsage") === "97 %", () => {
            verify(text("healthHeadline") === "Requiere atención ahora", "a critical reading says so");
            verify(find(content, "healthIssues").count === 3, "the critical item is added");
            verify(find(content, "processBlock").visibleRows >= 3, "three flagged rows still leave room for the processes");
        }],
        [() => waitedMs >= 400, () => {
            render("critical");
            find(content, "cpuBlock").activated();
            verify(content.currentPage === 1, "the CPU meter opens Performance");
            content.currentPage = 0;
        }],
        [() => !!find(content, "processBlock"), () => {
            find(content, "processBlock").activated();
            verify(content.currentPage === 2, "the process list opens Processes");
        }],
        [() => telemetry.snapshot.processes.length === 9, () => {
            verify(true, "the Processes page receives the whole table");
            content.currentPage = 0;
        }],
        [() => telemetry.snapshot.processes.length === 5, () => {
            verify(true, "leaving Processes returns to the trimmed reading");
            mode("fail");
        }],
        [() => telemetry.status === "stale", () => {
            verify(text("healthHeadline") === "Lecturas detenidas", "a stale reading is announced");
            verify(find(content, "healthRetry").visible, "a stale reading offers a retry");
            verify(text("cpuUsage") === "97 %", "the last reading stays on screen");
        }],
        [() => waitedMs >= 400, () => {
            render("stale");
            modeFile.setText("garbage");
            find(content, "healthRetry").clicked();
        }],
        [() => waitedMs >= 600 && !telemetry.sampling, () => {
            verify(telemetry.status === "stale", "output that is not a reading is a failure too");
            modeFile.setText("ok");
            find(content, "healthRetry").clicked();
        }],
        [() => telemetry.status === "live" && text("cpuUsage") === "32 %", () => {
            verify(text("healthHeadline") === "Todo en orden", "the retry recovers");
            verify(!find(content, "healthRetry").visible, "the retry leaves with the failure");
            retained.hardware = false;
            kept = { samples: telemetry.sampleCount };
        }],
        [() => waitedMs >= 3400, () => {
            verify(telemetry.sampleCount === kept.samples && !telemetry.sampling, "closing stops the sampling");
        }]
    ]

    readonly property var failing: [
        [null, () => {
            retained.hardware = true;
            content.openHardware();
        }],
        [() => telemetry.sampling, () => {
            verify(telemetry.status === "loading", "the first run is a loading state");
            const state = find(content, "overviewState");
            verify(state.visible && state.kind === "loading", "loading is shown, not zeros");
            verify(text("cpuUsage") === "", "no figure is invented before a reading");
            render("loading");
        }],
        [() => telemetry.status === "error", () => {
            verify(!telemetry.sampling && telemetry.failure === "probe timed out", "a hung probe is ended and named");
            const state = find(content, "overviewState");
            verify(state.visible && state.kind === "error", "the error replaces the loading state");
            verify(find(content, "overviewRetry").visible, "the error offers a retry");
            render("error");
            modeFile.setText("ok");
            find(content, "overviewRetry").clicked();
        }],
        [() => telemetry.status === "live", () => {
            verify(text("cpuUsage") === "32 %", "the retry reaches a reading");
            verify(find(content, "overviewRetry") === null, "the error state is gone");
        }]
    ]

    readonly property var missing: [
        [null, () => {
            retained.hardware = true;
            content.openHardware();
        }],
        [() => telemetry.status === "error", () => {
            verify(find(content, "overviewState").kind === "error", "a probe that cannot start is an error, not an endless wait");
        }]
    ]

    property int waitedMs: 0
    Timer {
        interval: 50; repeat: true; running: true
        onTriggered: {
            const steps = root[root.scenario];
            if (root.step >= steps.length) {
                console.log("HARDWARE_RUNTIME_PASS", root.checks);
                Qt.quit();
                return;
            }
            root.waitedMs += interval;
            const [condition, action] = steps[root.step];
            if (condition && !condition()) {
                if (root.waitedMs > 15000) {
                    console.log("HARDWARE_FAIL", `step ${root.step} never became ready`);
                    Qt.quit();
                }
                return;
            }
            root.step += 1;
            root.waitedMs = 0;
            action();
        }
    }
}
"""


def reading(**overrides) -> dict:
    processes = [
        {"pid": 100 + index, "ppid": 1, "name": name, "user": "dilan", "state": "S", "threads": 4,
         "elapsed_sec": 600, "cpu": cpu, "mem": mem, "command": name}
        for index, (name, cpu, mem) in enumerate([
            ("Hyprland", 22.3, 0.5), ("qs", 9.1, 3.6), ("brave", 6.4, 5.2), ("kitty", 2.0, 0.6),
            ("pipewire", 1.1, 0.2), ("fish", 0.4, 0.1), ("dbus-broker", 0.2, 0.1), ("systemd", 0.1, 0.1),
            ("NetworkManager", 0.0, 0.1)])
    ]
    base = {
        "timestamp": 1791054718, "host": "fixture", "kernel": "7.2.8-1-cachyos", "uptime_sec": 65422,
        "load": [1.24, 1.1, 0.98],
        "cpu": {"model": "AMD Ryzen 7 7445HS w/ Radeon 740M Graphics", "usage": 31.7, "per_core": [30.0, 33.0],
                "freq_mhz": 3525.0, "temp_c": 57.2, "governor": "powersave", "cores": 2},
        "memory": {"total_gb": 14.85, "used_gb": 9.03, "available_gb": 5.81, "cache_gb": 3.57, "buffers_gb": 0.0,
                   "usage": 60.8, "swap_used_gb": 7.2, "swap_total_gb": 14.85},
        "disk": {"total_gb": 475.44, "used_gb": 409.92, "free_gb": 61.33, "usage": 86.2},
        "disk_io": {"device": "nvme0n1", "model": "SAMSUNG", "serial": "", "rotational": False, "read_mib_s": 4.2,
                    "write_mib_s": 2.2, "read_iops": 111.7, "write_iops": 115.8, "read_total_gb": 74.6,
                    "write_total_gb": 80.8},
        "disks_io": [],
        "battery": {"present": True, "name": "BAT0", "percent": 100.0, "status": "Full", "power_w": 0.0},
        "network": {"interface": "wlan0", "rx_mbps": 3.06, "tx_mbps": 2.21, "rx_total_gb": 9.18, "tx_total_gb": 3.11,
                    "mac": "", "ipv4": "192.168.0.2", "ssid": "Red de prueba", "signal_dbm": -55.0,
                    "bitrate_mbps": 866.7},
        "gpus": [
            {"vendor": "AMD", "card": "card2", "name": "Advanced Micro Devices, Inc. [AMD/ATI] HawkPoint2 (rev ca)",
             "usage": 70.0, "temp_c": 55.0, "vram_total_gb": 0.5, "vram_used_gb": 0.44, "power_w": 15.4},
            {"vendor": "NVIDIA", "name": "NVIDIA GeForce RTX 3050 6GB Laptop GPU", "usage": 12.0, "temp_c": 52.0,
             "vram_used_gb": 0.05, "vram_total_gb": 6.0, "power_w": 7.8},
        ],
        "fans": [{"name": "hp fan 1", "rpm": 3194}, {"name": "hp fan 2", "rpm": 2739}],
        "processes": processes,
        "process_count": len(processes),
    }
    for key, value in overrides.items():
        base[key] = {**base[key], **value} if isinstance(value, dict) else value
    return base


def run(folder: Path, scenario: str, start_mode: str, with_probe: bool = True) -> str:
    fixtures = folder / f"fixtures-{scenario}"
    shutil.copytree(folder / "fixtures", fixtures)
    (fixtures / "mode").write_text(start_mode)
    home = folder / f"home-{scenario}"
    (home / ".local/bin").mkdir(parents=True)
    if with_probe:
        probe = home / ".local/bin/cortetsu-hardware-probe"
        probe.write_text(PROBE)
        probe.chmod(0o755)
    result = subprocess.run(
        ["quickshell", "-p", str(folder / "shell.qml")],
        env={**os.environ, "QT_QPA_PLATFORM": os.environ.get("CORTETSU_TEST_QPA", "offscreen"), "HOME": str(home),
             "XDG_STATE_HOME": str(home / "state"), "XDG_CACHE_HOME": str(home / "cache"),
             "HARDWARE_FIXTURES": str(fixtures), "HARDWARE_SCENARIO": scenario, "CORTETSU_RENDER_DIR": RENDER_DIR},
        capture_output=True, text=True, timeout=90,
    )
    output = result.stdout + result.stderr
    assert result.returncode == 0, output
    for marker in ("HARDWARE_FAIL", "TypeError", "ReferenceError", "is not a type", "Unable to assign",
                   "Binding loop", "Cannot anchor", "is not defined"):
        assert marker not in output, output
    calls = fixtures / "calls.log"
    return output, calls.read_text().splitlines() if calls.exists() else []


with tempfile.TemporaryDirectory(prefix="cortetsu-hardware-home-") as temporary:
    folder = Path(temporary)
    for name in ("modules", "components", "services", "theme", "assets"):
        shutil.copytree(ROOT / name, folder / name)
    (folder / "modules/CortetsuConfig.qml").write_text(CONFIG)
    (folder / "modules/CortetsuIdleInhibitor.qml").write_text(IDLE_INHIBITOR)
    (folder / "shell.qml").write_text(SHELL)

    fixtures = folder / "fixtures"
    fixtures.mkdir()
    readings = {
        "ok": reading(),
        "attention": reading(cpu={"usage": 71.0}, disk={"usage": 93.1, "free_gb": 32.8},
                             gpus=[reading()["gpus"][0], {**reading()["gpus"][1], "temp_c": 88.0}]),
        "critical": reading(cpu={"usage": 97.0, "temp_c": 98.0}, disk={"usage": 93.1, "free_gb": 32.8},
                            gpus=[reading()["gpus"][0], {**reading()["gpus"][1], "temp_c": 88.0}]),
    }
    for name, data in readings.items():
        # The scripted probe honours --top-processes the way the real one does.
        (fixtures / f"{name}.full.json").write_text(json.dumps(data))
        (fixtures / f"{name}.json").write_text(json.dumps({**data, "processes": data["processes"][:5]}))

    output, calls = run(folder, "summary", "ok")
    assert "HARDWARE_RUNTIME_PASS 29" in output, output
    assert calls and calls[0] == "--top-processes 5", calls[:3]
    assert "" in calls, "the Processes page asks for the whole table"
    assert calls[-1] == "--top-processes 5", "leaving Processes returns to the trimmed reading"

    output, calls = run(folder, "failing", "hang")
    assert "HARDWARE_RUNTIME_PASS 8" in output, output

    output, calls = run(folder, "missing", "ok", with_probe=False)
    assert "HARDWARE_RUNTIME_PASS 1" in output, output
    assert not calls, calls

print("PASS: the Hardware summary reports its verdict, updates in place, links to each page and survives a failing probe")

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
    property int dashboardResourceUpdateInterval: 3000
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
    *) all="$*"; case "$all" in *--process-detail*) target=${all##*--process-detail }; target=${target%%:*} ;; *) target="" ;; esac
       if [ -n "$target" ]; then cat "$HARDWARE_FIXTURES/$mode.detail-$target.json"
       elif [ "$1" = "--top-processes" ]; then cat "$HARDWARE_FIXTURES/$mode.json"; else cat "$HARDWARE_FIXTURES/$mode.full.json"; fi ;;
esac
"""

SHELL = """import QtQuick
import QtQuick.Window
import Quickshell
import Quickshell.Io
import "modules"
import "modules/hardware"
import "theme"
import "theme/ThemeProfiles.js" as Profiles

ShellRoot {
    id: root
    // HARDWARE_THEME=washi renders with that theme's tokens; empty is Ink.
    Component.onCompleted: CortetsuDesign.themeTokens = Profiles.tokens(Quickshell.env("HARDWARE_THEME") || "ink")
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
            content.grabToImage(result => result.saveToFile(
                `${renderDir}/${name}${Quickshell.env("HARDWARE_THEME") ? "-" + Quickshell.env("HARDWARE_THEME") : ""}.png`));
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
        // The same center on a second screen where it is closed.
        Content {
            id: hidden
            visible: false
            width: 1280; height: 900
            screen: null
            screenState: screenState
            hardwareVisible: false
        }
    }
    function typed(item, type) {
        if (!item) return null;
        if (String(item).startsWith(type)) return item;
        for (const child of item.children) { const hit = typed(child, type); if (hit) return hit; }
        return null;
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

    // Fn+Esc asks for the Sistema page through the seat-wide page, then opens.
    readonly property var system: [
        [null, () => {
            CortetsuShellState.hardwarePage = 9;
            retained.hardware = true;
            content.openHardware();
        }],
        [() => telemetry.status === "live" && !!find(content, "systemCopy"), () => {
            verify(content.currentPage === 9, "the shared page selects Sistema");
            verify(find(content, "cpuBlock") === null, "the summary is not loaded behind it");
        }],
        [() => waitedMs >= 400, () => render("system")],
        [() => waitedMs >= 400, () => {
            find(content, "systemCopy").clicked();
            const copied = Quickshell.clipboardText;
            verify(copied.includes("Kernel: 7.2.8-1-cachyos"), `the report has the kernel (${copied})`);
            verify(copied.includes("Gráficos: NVIDIA GeForce RTX 3050 6GB Laptop GPU · 6.0 GiB"), `one line per GPU (${copied})`);
            verify(copied.includes("(rev ca) · 512 MiB"), "a shared VRAM under 1 GiB reads in MiB, not rounded up to 1 GiB");
            verify(/Memoria: 14[.,][89] GiB/.test(copied), `total memory (${copied})`);
            verify(!copied.includes("No disponible"), "missing facts are left out, not reported as text");
            verify(find(content, "systemCopy").label === "Copiado", "the button confirms the copy");
            content.currentPage = 3;
            verify(CortetsuShellState.hardwarePage === 3, "a tab chosen by hand is the seat's page");
            content.currentPage = 8;
            verify(hidden.currentPage === 8, "the closed copy follows the seat's page");
            verify(typed(content, "StartupPage") !== null, "the visible copy builds Arranque");
            verify(typed(hidden, "StartupPage") === null, "the closed copy builds no page, so Arranque scans once");
        }]
    ]

    function processesPage() { return typed(content, "ProcessesPage"); }
    function processRow(name) { return telemetry.snapshot.processes.find(p => p.name === name); }

    // Processes: exact RSS in the table, the smaps breakdown for the
    // selected process only, unknown fields shown as unknown, never as 0.
    readonly property var processes: [
        [null, () => {
            retained.hardware = true;
            content.openHardware();
            content.currentPage = 2;
        }],
        [() => telemetry.snapshot?.processes?.length === 9 && !!processesPage(), () => {
            const page = processesPage();
            verify(page.ramText(processRow("qs")) === "470.6 MiB", `RSS comes from bytes, not from a rounded share (${page.ramText(processRow("qs"))})`);
            verify(page.ramText(processRow("brave")) === "1.21 GiB", "a gibibyte or more reads in GiB");
            page.numericMode = false;
            verify(page.ramText(processRow("qs")) === "3.1 %", "the share of RAM stays as its own reading");
            page.numericMode = true;
            // Regression: re-sorting moved rows in the ListView model and Qt
            // 6.12's delegate model crashed the shell (SIGSEGV in
            // QQmlDelegateModel::_q_itemsMoved). Rows now hold positions, so a
            // re-sort must never emit a move and each row shows its slot.
            const list = find(page, "processList");
            let moves = 0;
            list.model.rowsMoved.connect(() => moves++);
            page.setSort("rss_bytes");
            page.setSort("name");
            page.setSort("cpu");
            page.setSort("rss_bytes");
            verify(moves === 0, `a re-sort moves no model rows (${moves})`);
            verify(list.count === page.visibleProcesses.length, "one row per visible process");
            verify(list.itemAtIndex(0)?.modelData?.name === page.visibleProcesses[0].name, "the first row shows the first process after a re-sort");
            verify(page.visibleProcesses[0].name === "brave" && page.visibleProcesses[1].name === "qs", "the RSS column sorts by bytes");
            verify(page.visibleProcesses[2].name === "kitty", "bytes break the tie that equal rounded percentages made");
            page.selectedPid = 101;
            verify(page.detailText("pss_bytes") === "Leyendo…", "the breakdown is pending, not zero");
            verify(page.inspectorRssText() === "470.6 MiB", "until smaps arrives the inspector shows the table's statm RSS");
        }],
        [() => telemetry.processDetail?.pid === 101, () => {
            const page = processesPage();
            verify(page.detailText("pss_bytes") === "348.5 MiB", `PSS (${page.detailText("pss_bytes")})`);
            verify(page.inspectorRssText() === "471.1 MiB", `the inspector RSS comes from the same smaps read as PSS (${page.inspectorRssText()})`);
            verify(page.ramText(processRow("qs")) === "470.6 MiB", "the table keeps the cheap statm figure");
            verify(page.detailText("swap_bytes") === "43.2 MiB", "swap is shown apart");
            verify(page.detailText("anon_huge_bytes") === "44.0 MiB", "THP");
            verify(page.detailText("private_bytes") === "300.0 MiB", "private pages");
            verify(page.detailText("pss_anon_bytes") === "293.2 MiB", "anonymous PSS");
            verify(find(content, "memoryDetail").visible, "the inspector shows the breakdown");
            kept = { runs: telemetry.sampleCount };
            render("processes-detail");
        }],
        [() => telemetry.sampleCount > kept.runs && !telemetry.sampling, () => {
            verify(telemetry.processDetail?.pid === 101, "a run without a breakdown keeps the last one");
            processesPage().selectedPid = 102;
            verify(processesPage().processDetail === null, "a new selection never shows the previous process's numbers");
        }],
        [() => telemetry.processDetail?.pid === 102, () => {
            const page = processesPage();
            verify(page.detailText("pss_bytes") === "", "smaps that cannot be read is unavailable, not 0");
            verify(page.detailText("swap_bytes") === "12.0 MiB", "swap from status survives a denied smaps");
            verify(page.inspectorRssText() === page.ramText(page.selectedProcess), "a denied smaps falls back to the statm RSS");
            verify(find(content, "memoryDetailCaption").text.indexOf("sin permiso") > 0, "a denied smaps says so");
            // A frozen list can hold a row whose PID now belongs to another
            // process: the signal is refused, never sent to the newcomer.
            page.togglePause();
            page.frozenProcesses = page.frozenProcesses.map(p => Number(p.pid) === 102 ? Object.assign({}, p, { start_ticks: 1 }) : p);
            page.sendSignal("TERM");
            verify(page.actionStatus.indexOf("ya no existe") >= 0, `a reused PID gets no signal (${page.actionStatus})`);
            page.togglePause();
            page.selectedPid = 103;
        }],
        [() => telemetry.processDetail?.pid === 103, () => {
            verify(processesPage().detailText("pss_bytes") === "", "a process that ended has no breakdown");
            verify(find(content, "memoryDetailCaption").text.indexOf("sin permiso") < 0, "an ended process is not reported as a permission problem");
            // A zombie has already exited: signals reach nothing, so the
            // actions are off and the inspector says why.
            const page = processesPage();
            page.selectedPid = 108;
            verify(page.selectedZombie, "state Z is a zombie");
            // The fill alone all but vanished on Washi's paper (1.1:1): the
            // selected row also carries the indicator bar, like Settings' sidebar.
            const rows = find(page, "processList");
            const bars = Array.from({ length: rows.count }, (_, i) => find(rows.itemAtIndex(i), "selectionBar")?.visible === true);
            verify(bars.filter(b => b).length === 1 && rows.itemAtIndex(bars.indexOf(true)).modelData.pid === 108, "only the selected row shows the indicator bar");
            // WCAG 1.4.11: the bar is a state indicator, 3:1 against the
            // selected fill and the ground around it, in every theme.
            const bar = find(rows.itemAtIndex(bars.indexOf(true)), "selectionBar").color;
            const d = CortetsuDesign;
            const fill = Qt.tint(d.colorSurface, page.selectedRowColor);
            verify(d.contrast(bar, fill) >= 3 && d.contrast(bar, d.colorSurface) >= 3,
                `the selection bar reads at 3:1 (${d.contrast(bar, fill).toFixed(2)} on the row, ${d.contrast(bar, d.colorSurface).toFixed(2)} on the ground)`);
            verify(find(content, "forceClose").disabled, "no forced close for a zombie");
            page.forceClose();
            verify(!page.killArmed && page.actionStatus === "", "a zombie never arms or sends a signal");
            verify(find(content, "zombieNote").visible && find(content, "zombieNote").text.indexOf("PID 1") > 0, "the inspector names the parent that has to reap it");
        }],
        // Rows fade their highlight in: grab once it settles, then wait a
        // tick more because the grab itself is asynchronous.
        [() => root.waitedMs >= 600, () => render("processes-zombie")],
        [null, () => {
            const page = processesPage();
            page.selectedPid = 101;
            verify(!find(content, "forceClose").disabled && !find(content, "zombieNote").visible, "a live process gets its actions back");
            content.currentPage = 0;
        }],
        [() => telemetry.snapshot.processes.length === 5, () => {
            verify(telemetry.detailKey === "", "leaving Processes forgets the selection");
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
        {"pid": 100 + index, "ppid": 1, "name": name, "user": "dilan", "state": "Z" if name == "NetworkManager" else "S", "threads": 4,
         "elapsed_sec": 600, "cpu": cpu, "mem": mem, "rss_bytes": rss, "start_ticks": 5000 + index,
         "command": name}
        # RSS in bytes; mem is that share of 14.85 GiB, rounded as the probe does.
        for index, (name, cpu, mem, rss) in enumerate([
            ("Hyprland", 22.3, 0.5, 80_000_000), ("qs", 9.1, 3.1, 493_510_656), ("brave", 6.4, 8.1, 1_300_000_000),
            ("kitty", 2.0, 0.6, 95_000_000), ("pipewire", 1.1, 0.6, 94_000_000), ("fish", 0.4, 0.1, 9_000_000),
            ("dbus-broker", 0.2, 0.1, 8_000_000), ("systemd", 0.1, 0.1, 7_000_000),
            ("NetworkManager", 0.0, 0.1, 6_000_000)])
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


def run(folder: Path, scenario: str, start_mode: str, with_probe: bool = True, theme: str = "") -> str:
    fixtures = folder / f"fixtures-{scenario}{'-' + theme if theme else ''}"
    shutil.copytree(folder / "fixtures", fixtures)
    (fixtures / "mode").write_text(start_mode)
    home = folder / f"home-{scenario}{'-' + theme if theme else ''}"
    (home / ".local/bin").mkdir(parents=True)
    if with_probe:
        probe = home / ".local/bin/cortetsu-hardware-probe"
        probe.write_text(PROBE)
        probe.chmod(0o755)
    result = subprocess.run(
        ["quickshell", "-p", str(folder / "shell.qml")],
        env={**os.environ, "QT_QPA_PLATFORM": os.environ.get("CORTETSU_TEST_QPA", "offscreen"), "HOME": str(home),
             "XDG_STATE_HOME": str(home / "state"), "XDG_CACHE_HOME": str(home / "cache"),
             "HARDWARE_FIXTURES": str(fixtures), "HARDWARE_SCENARIO": scenario, "CORTETSU_RENDER_DIR": RENDER_DIR,
             "HARDWARE_THEME": theme},
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
    mib = 1024 * 1024
    details = {
        101: {"status": "ok", "smaps": "ok", "rss_bytes": 494_000_000, "pss_bytes": round(348.49 * mib),
              "pss_anon_bytes": round(293.18 * mib), "pss_file_bytes": round(55.34 * mib), "pss_shmem_bytes": 0,
              "private_bytes": 300 * mib, "swap_bytes": round(43.24 * mib), "swap_pss_bytes": round(43.24 * mib),
              "anon_huge_bytes": 44 * mib},
        102: {"status": "ok", "smaps": "denied", "rss_bytes": 1_300_000_000, "pss_bytes": None, "pss_anon_bytes": None,
              "pss_file_bytes": None, "pss_shmem_bytes": None, "private_bytes": None, "swap_bytes": 12 * mib,
              "swap_pss_bytes": None, "anon_huge_bytes": None},
        103: {"status": "gone"},
    }
    for pid, detail in details.items():
        detail = {"pid": pid, "start_ticks": 4900 + pid, **detail}
        (fixtures / f"ok.detail-{pid}.json").write_text(json.dumps({**readings["ok"], "process_detail": detail}))

    output, calls = run(folder, "summary", "ok")
    assert "HARDWARE_RUNTIME_PASS 29" in output, output
    assert calls and calls[0] == "--top-processes 5", calls[:3]
    assert "" in calls, "the Processes page asks for the whole table"
    assert calls[-1] == "--top-processes 5", "leaving Processes returns to the trimmed reading"

    output, calls = run(folder, "processes", "ok")
    assert "HARDWARE_RUNTIME_PASS 35" in output, output
    # The selection bar exists for light paper: prove it there and on steel.
    for theme in ("washi", "kurogane"):
        themed, _ = run(folder, "processes", "ok", theme=theme)
        assert "HARDWARE_RUNTIME_PASS 35" in themed, (theme, themed)
    detail_calls = [c for c in calls if "--process-detail" in c]
    assert detail_calls and all(c.split()[-1] in ("101:5001", "102:5002", "103:5003") for c in detail_calls), calls
    assert all("--process-detail" not in c for c in calls if c.startswith("--top-processes")), \
        "the summary never asks for a breakdown"
    assert len(detail_calls) < len(calls), "not every run reads smaps"

    output, calls = run(folder, "failing", "hang")
    assert "HARDWARE_RUNTIME_PASS 8" in output, output

    output, calls = run(folder, "system", "ok")
    assert "HARDWARE_RUNTIME_PASS 12" in output, output

    output, calls = run(folder, "missing", "ok", with_probe=False)
    assert "HARDWARE_RUNTIME_PASS 1" in output, output
    assert not calls, calls

print("PASS: the Hardware summary reports its verdict, updates in place, links to each page and survives a failing probe")

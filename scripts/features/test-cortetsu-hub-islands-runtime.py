#!/usr/bin/env python3
"""The Hub's islands and the App Rail's window preview, on the offscreen platform.

What qmltestrunner cannot load (these files pull in Quickshell):

- the view: the gaps between Núcleo, Aplicaciones and Sistema; which island an
  open popout or panel engages and that it leans towards the screen; tooltips
  stepping aside while one is open; an edge change placed at once and a rail
  that grows gliding; reduced motion making that glide instant;
- the window preview, fed by a stand-in Hub: one card per window, keyboard
  walk, Enter going to the chosen window and closing, a window closed under
  the open preview taking its card, the last one closing it, a lateral Hub
  showing one column;
- a hot theme switch repainting the islands, with a PNG per theme when
  CORTETSU_RENDER_DIR is set.
"""
import os
import shutil
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2] / "cortetsu"
RENDER_DIR = os.environ.get("CORTETSU_RENDER_DIR", "")
CHECKS = 38

SHELL = """import QtQuick
import QtQuick.Window
import Quickshell
import "modules"
import "modules/bar/popouts" as Pop
import "services"
import "theme"

ShellRoot {
    id: root
    property int checks: 0
    property int step: 0
    property var mark: null
    readonly property string renderDir: Quickshell.env("CORTETSU_RENDER_DIR")
    readonly property var colours: CortetsuColours
    function verify(value, reason) { if (!value) console.log("ISLAND_FAIL", reason); else checks++; }
    function grab(item, name) { if (renderDir) item.grabToImage(r => r.saveToFile(`${renderDir}/${name}.png`)); }
    // A grab that the next step waits for (a theme change must not land
    // in the picture of the previous one).
    property bool pending: false
    function shoot(item, name) {
        if (!renderDir) return;
        pending = true;
        item.grabToImage(r => { r.saveToFile(`${renderDir}/${name}.png`); root.pending = false; });
    }
    function client(address, title, ws) {
        return { address: address, title: title, lastIpcObject: { address: address, title: title,
            workspace: { id: ws, name: String(ws) }, size: [1600, 900] } };
    }

    QtObject { id: screen; property string name: "T" }

    // What the preview reads from its monitor's Hub (BottomHub.qml's window).
    QtObject {
        id: hub
        property var clients: [root.client("0x1", "Informe", 1), root.client("0x2", "Notas", 2), root.client("0x3", "Correo", 1)]
        property string activeAddress: "0x3"
        property bool hubVertical: false
        property int activeWsId: 1
        property var focused: null
        property var closed: []
        readonly property var dockViewItems: [{ key: "files", title: "Archivos", pinned: true, running: true,
            windowCount: clients.length, iconSource: "", active: true }]
        function dockItemForKey(key) {
            return key === "files" ? { key: "files", entry: { name: "Archivos" }, pinned: true, windows: clients } : null;
        }
        function focusWindow(c) { focused = c; }
        function closeWindow(c) { closed = closed.concat([c.address]); }
        function launchDockKey(key) {}
        function togglePinnedKey(key) {}
    }

    QtObject {
        id: popouts
        property string currentName: "apppreview:files"
        property bool hasCurrent: true
        property var screen: screen
    }

    Component.onCompleted: CortetsuShellState.registerState(screen, { cortetsuState: { bottomHub: hub } })

    property var dockItems: [
        { key: "files", title: "Files", active: false, pinned: true, running: true, windowCount: 2, iconSource: "" },
        { key: "notes", title: "Notes", active: false, pinned: true, running: false, windowCount: 0, iconSource: "" }
    ]

    Window {
        width: 1280; height: 760; visible: true; color: "#20242c"
        CortetsuBottomHubView {
            id: view
            y: 8
            width: 1280
            height: thickness
            anchor: "bottom-left"
            launcherActive: false
            workspaceCount: 3; workspaceDisplayType: 0; workspaceShowAppIcons: false; workspaceMonochromeIcons: false
            workspaceAppIconSources: ({}); workspaceOffset: 0; activeWsId: 1; occupiedWorkspaceIds: []
            dockItems: root.dockItems
            trayItems: [{ key: "t1", id: "t1", title: "Bandeja", needsAttention: false, iconSource: "", onlyMenu: false, hasMenu: true }]
            modeVisible: true; appsVisible: true; trayVisible: true; statusVisible: true
            volumeIcon: "volume_up"; volumeMuted: false; networkIcon: "wifi"; networkTooltip: "Red"; networkActive: true
            bluetoothIcon: "bluetooth"; bluetoothActive: false; batteryIcon: "battery_full"; batteryCritical: false
            batteryTooltip: "Batería"; audioVisible: true; networkVisible: true; bluetoothVisible: true; batteryVisible: true
            statusPopoutsEnabled: true; notificationCount: 0; sidebarActive: false; recordingActive: false
            dndActive: false; idleInhibited: false; now: new Date(2026, 10, 13, 12, 0); sessionActive: false
        }
        Pop.CortetsuWindowPreview {
            id: preview
            x: 16; y: 96
            width: implicitWidth; height: implicitHeight
            popouts: popouts
        }
    }

    readonly property var steps: [
        () => view.Window.window?.active === true && view.glide,
        // Groups apart, Sistema together.
        () => { const [mode, apps, tray, status] = view.islands;
                verify(apps.x - (mode.x + mode.width) === view.gap, `Núcleo to Aplicaciones ${apps.x - (mode.x + mode.width)}`);
                verify(tray.x - (apps.x + apps.width) === view.gap, `Aplicaciones to Sistema ${tray.x - (apps.x + apps.width)}`);
                verify(status.x - (tray.x + tray.width) === view.pairGap, `tray to status ${status.x - (tray.x + tray.width)}`);
                verify(view.pairGap < view.gap, "Sistema's islands sit closer than the groups");
                verify(view.packedLength === status.x + status.width - mode.x, `packed length ${view.packedLength}`);
                return true; },
        // Engaged follows the popout, tooltips step aside, the island leans.
        () => { CortetsuDesign.reducedMotion = true;
                const [mode, apps, tray, status] = view.islands;
                view.engagedPopout = "network";
                verify(status.engaged && !apps.engaged && !tray.engaged && !mode.engaged, "network engages Sistema");
                verify(view.tooltipsSuppressed, "tooltips step aside");
                verify(status.transform[0].y === -2, `bottom Hub leans up ${status.transform[0].y}`);
                view.engagedPopout = "traymenu0";
                verify(tray.engaged && !status.engaged, "a tray menu engages the tray");
                view.engagedPopout = "apppreview:files";
                verify(apps.engaged && !tray.engaged, "a preview engages Aplicaciones");
                view.engagedPopout = "";
                verify(!apps.engaged && !view.tooltipsSuppressed && status.transform[0].y === 0, "rest");
                view.statusPanelOpen = true;
                verify(status.engaged && view.tooltipsSuppressed, "notifications engage Sistema");
                view.statusPanelOpen = false;
                view.launcherActive = true;
                verify(mode.engaged, "the launcher engages Núcleo");
                view.launcherActive = false;
                view.anchor = "middle-left";
                view.engagedPopout = "audio";
                verify(status.transform[0].x === 2 && status.transform[0].y === 0, "a left Hub leans right");
                view.engagedPopout = "";
                view.anchor = "bottom-left";
                CortetsuDesign.reducedMotion = false;
                return true; },
        () => view.glide,
        // An edge change is placed at once; a rail that grows glides.
        () => { const status = view.islands[3];
                view.anchor = "bottom-right";
                verify(!view.glide && status.x === view.statusAt, `placed at once on the new edge (${status.x} vs ${view.statusAt})`);
                return true; },
        () => view.glide,
        // Packed at the end, Sistema stays at the edge and Núcleo moves over.
        // The rail measures itself on the next polish; the moment the new
        // place is known, the island has not jumped there.
        () => { const mode = view.islands[0];
                root.mark = null;
                const seen = () => {
                    view.modeAtChanged.disconnect(seen);
                    root.mark = { place: view.modeAt, x: mode.x };
                };
                view.modeAtChanged.connect(seen);
                root.dockItems = root.dockItems.concat([{ key: "mail", title: "Mail", active: false, pinned: false,
                    running: true, windowCount: 1, iconSource: "" }]);
                return true; },
        () => { if (!root.mark) return false;
                verify(root.mark.x !== root.mark.place, `mid-glide when the rail grew (${root.mark.x} vs ${root.mark.place})`);
                return true; },
        () => view.islands[0].x === view.modeAt,
        () => { CortetsuDesign.reducedMotion = true;
                root.dockItems = root.dockItems.slice(0, 2);
                verify(view.islands[0].x === view.modeAt, "reduced motion: no glide");
                CortetsuDesign.reducedMotion = false;
                view.anchor = "bottom-center";
                return true; },
        // The preview.
        () => { verify(preview.cardCount === 3, `three cards (${preview.cardCount})`);
                verify(preview.columns === 3, `three columns (${preview.columns})`);
                verify(preview.selected === -1, "nothing chosen before a key");
                preview.selectInitial();
                verify(preview.selected === 2, `the keyboard starts on the active window (${preview.selected})`);
                verify(preview.handleKey(Qt.Key_Left, 0) && preview.selected === 1, "Left");
                verify(preview.handleKey(Qt.Key_Tab, 0) && preview.selected === 2, "Tab");
                verify(preview.handleKey(Qt.Key_Tab, Qt.ShiftModifier) && preview.selected === 1, "Shift+Tab");
                verify(!preview.handleKey(Qt.Key_A, 0), "a letter is not the preview's");
                verify(preview.handleKey(Qt.Key_Delete, 0) && hub.closed[0] === "0x2", "Delete asks to close the chosen window");
                grab(preview, "preview-ink");
                verify(preview.handleKey(Qt.Key_Return, 0), "Enter");
                verify(hub.focused?.address === "0x2" && !popouts.hasCurrent, "Enter goes to the chosen window and closes");
                popouts.hasCurrent = true;
                return true; },
        () => { hub.clients = hub.clients.filter(c => c.address !== "0x2");
                verify(preview.cardCount === 2 && popouts.hasCurrent, "a window closed under the preview takes only its card");
                verify(preview.selected <= 1, `the choice stays on a card (${preview.selected})`);
                hub.hubVertical = true;
                verify(preview.columns === 1, "a lateral Hub shows one column");
                hub.hubVertical = false;
                hub.clients = [];
                verify(!popouts.hasCurrent, "the last window closes the preview");
                popouts.currentName = "";
                verify(preview.appKey === "files", "the app is kept while the popout fades out");
                return true; },
        // Hot theme switch repaints the islands. A grab paints on the next
        // frame, so the theme only changes once it is saved; reduced motion
        // makes the new colours final at once.
        () => { CortetsuDesign.reducedMotion = true;
                root.mark = String(view.islands[3].children.find(c => c.engaged !== undefined)?.color);
                shoot(view, "hub-ink");
                return true; },
        () => { if (root.pending) return false;
                CortetsuConfig.selectTheme("washi");
                return true; },
        () => { const island = view.islands[3].children.find(c => c.engaged !== undefined);
                verify(CortetsuConfig.themeId === "washi" && CortetsuDesign.materialShadowAlpha > 0, "Washi is live");
                verify(String(island.color) !== root.mark, "the island repainted");
                verify(island.children.filter(c => c.z < 0 && c.visible).length === 2, "Washi casts its shadow");
                shoot(view, "hub-washi");
                return true; },
        () => { if (root.pending) return false;
                CortetsuConfig.selectTheme("kurogane");
                return true; },
        () => { const island = view.islands[3].children.find(c => c.engaged !== undefined);
                verify(CortetsuConfig.themeId === "kurogane", "Kurogane is live");
                verify(island.radius === Math.min(island.height / 2, 8), `Kurogane keeps its firm corners (${island.radius})`);
                shoot(view, "hub-kurogane");
                return true; },
        () => { if (root.pending) return false;
                CortetsuConfig.selectTheme("ink");
                CortetsuDesign.reducedMotion = false;
                return true; },
        () => true
    ]

    Timer {
        interval: 80; repeat: true; running: true
        onTriggered: {
            if (root.step >= root.steps.length) { console.log(`ISLAND_RUNTIME_PASS ${root.checks}`); Qt.quit(); return; }
            if (root.steps[root.step]()) root.step++;
        }
    }
    Timer { interval: 15000; running: true; onTriggered: { console.log("ISLAND_FAIL timeout at", root.step); Qt.quit(); } }
}
"""

with tempfile.TemporaryDirectory(prefix="cortetsu-islands-") as temporary:
    folder = Path(temporary)
    for name in ("modules", "components", "services", "theme", "assets", "utils"):
        if (ROOT / name).exists():
            shutil.copytree(ROOT / name, folder / name)
    # Connectivity reads the VPN singleton, which only base/ provides; the
    # preview loads next to the popouts' state, also from base/.
    shutil.copy(ROOT / "base/services/VPN.qml", folder / "services/VPN.qml")
    shutil.copy(ROOT / "base/modules/bar/popouts/PopoutState.qml", folder / "modules/bar/popouts/PopoutState.qml")
    # The tray segment keys its items with the identity base/ provides.
    (folder / "base/modules/bar").mkdir(parents=True)
    shutil.copy(ROOT / "base/modules/bar/SystemTrayIdentity.js", folder / "base/modules/bar/SystemTrayIdentity.js")
    (folder / "shell.qml").write_text(SHELL)
    home = folder / "home"
    (home / ".config").mkdir(parents=True)
    env = {**os.environ, "QT_QPA_PLATFORM": "offscreen", "HOME": str(home),
           "XDG_CONFIG_HOME": str(home / ".config"), "XDG_CACHE_HOME": str(home / ".cache"),
           "XDG_STATE_HOME": str(home / ".local/state"), "CORTETSU_RENDER_DIR": RENDER_DIR}
    env.pop("WAYLAND_DISPLAY", None)
    result = subprocess.run(["quickshell", "-p", str(folder / "shell.qml")], env=env,
                            capture_output=True, text=True, timeout=90)
    output = result.stdout + result.stderr
    assert f"ISLAND_RUNTIME_PASS {CHECKS}" in output, output[-6000:]
    for marker in ("ISLAND_FAIL", "TypeError", "ReferenceError", "Binding loop", "is not a type", "Unable to assign",
                   "more visible items"):
        assert marker not in output, output[-6000:]

print(f"PASS: islands, their states and glide, the window preview and a hot theme switch ({CHECKS} checks)")

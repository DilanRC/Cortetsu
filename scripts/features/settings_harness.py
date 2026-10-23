"""Temporary runtime tree and service doubles for the Settings runtime tests.

The real Settings QML, the real preferences store, the real scheme service and
the real `cortetsu-scheme` run inside Quickshell. Only the services that talk
to the machine (NetworkManager, BlueZ, PipeWire, UPower, backlight, Hyprland)
are replaced, so a test can put each one in any state and never touches the
host.
"""
import json
import os
import shutil
import subprocess
import time
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
ROOT = REPO / "cortetsu"

# The real ones open a layer-shell window, which a plain Qt platform lacks.
IDLE = """pragma Singleton
import QtQuick
QtObject { property bool enabled: false; property bool isEnabled: false }
"""

WIFI = """pragma Singleton
import QtQuick

// NetworkManager double. A change stays pending until the test settles it.
QtObject {
    id: root
    property bool wifiEnabled: true
    property bool hardwareEnabled: true
    property var wifiDevice: ({ name: "wlan0" })
    property var networks: [
        { name: "Casa", connected: true, signalStrength: 82, security: 3, known: true, device: { name: "wlan0" } },
        { name: "Vecinos", connected: false, signalStrength: 41, security: 3, known: false, device: { name: "wlan0" } }
    ]
    readonly property var activeNetwork: wifiEnabled ? (networks.find(network => network.connected) || null) : null
    property var activeEthernet: null
    property bool connecting: false
    property string connectivity: "full"
    property var profiles: [{ uuid: "11111111-1111-4111-8111-111111111111", name: "Casa", ssid: "Casa", type: "802-11-wireless", autoconnect: true, interface: "" }]
    property var details: ({ wlan0: { uuid: "11111111-1111-4111-8111-111111111111", address: "192.168.0.2", gateway: "192.168.0.1", dns: ["1.1.1.1"] } })
    property string detailsState: "ready"
    property string metadataError: ""
    property var operation: ({ id: 0, kind: "", target: ({}), state: "idle", lastError: "", lastErrorCode: "", retryable: false })
    property var operationNetwork: null
    property bool pendingEnabled: false
    readonly property bool busy: ["connecting", "disconnecting", "forgetting", "changing"].includes(operation.state)

    function strengthPercent(raw) { return raw; }
    function setScanOwner(owner, enabled) {}
    function refresh() {}
    function refreshDetails(device) {}
    function refreshProfiles() {}
    function connectNetwork(network, password, profile) {}
    function disconnectNetwork(network) {}
    function forgetProfile(uuid) {}
    function setAutoconnect(uuid, enabled) {}
    function setEnabled(enabled) {
        pendingEnabled = enabled;
        operation = { id: operation.id + 1, kind: "enable", target: { enabled: enabled }, state: "changing", lastError: "", lastErrorCode: "", retryable: false };
    }
    // Test control: the radio answers, with success or with a failure.
    function settle(ok) {
        if (ok)
            wifiEnabled = pendingEnabled;
        operation = Object.assign({}, operation, ok
            ? { state: "idle" }
            : { state: "failed", lastError: "NetworkManager rechazó el cambio", lastErrorCode: "nm", retryable: true });
    }
}
"""

BLUETOOTH = """pragma Singleton
import QtQuick

// BlueZ double. `available` removes the adapter, as on a machine without one.
QtObject {
    id: root
    property bool available: true
    property bool enabled: true
    readonly property var adapter: available ? adapterObject : null
    readonly property QtObject adapterObject: QtObject { property string dbusPath: "/org/bluez/hci0" }
    property var allDevices: [
        { name: "Auriculares", connected: true, paired: true, adapter: adapterObject },
        { name: "Teclado", connected: false, paired: true, adapter: adapterObject }
    ]
    readonly property int connectedCount: allDevices.filter(device => device.connected).length
    property var operation: ({ id: 0, kind: "", state: "idle", target: null, lastError: "", lastErrorCode: "", retryable: false })
    property var operationTarget: null
    property bool pendingEnabled: false
    readonly property bool busy: operation.state === "pending"

    function selectAdapter(value) {}
    function connectDevice(device) { operationTarget = device; operation = { id: operation.id + 1, kind: "connect", state: "pending", target: device, lastError: "", lastErrorCode: "", retryable: false }; }
    function disconnectDevice(device) { connectDevice(device); }
    function pairDevice(device) { connectDevice(device); }
    function setEnabled(value) {
        pendingEnabled = value;
        operationTarget = adapter;
        operation = { id: operation.id + 1, kind: "power", state: "pending", target: adapter, lastError: "", lastErrorCode: "", retryable: false };
    }
    function settle(ok) {
        if (ok && operation.kind === "power")
            enabled = pendingEnabled;
        operation = Object.assign({}, operation, ok
            ? { state: "succeeded" }
            : { state: "failed", lastError: "El adaptador no respondió", lastErrorCode: "timeout", retryable: true });
        operationTarget = null;
    }
}
"""

CONNECTIVITY = """pragma Singleton
import QtQuick
QtObject {
    readonly property var wifi: ConnectivityWifi
    readonly property var bluetooth: ConnectivityBluetooth
}
"""

AUDIO = """pragma Singleton
import QtQuick

// PipeWire double. `available` removes every device, as with the service down.
QtObject {
    id: root
    property bool available: true
    readonly property QtObject speakers: QtObject {
        property int id: 41
        property string description: "Altavoces"
        property bool ready: true
        readonly property QtObject audio: QtObject { property bool muted: false; property real volume: 0.62 }
    }
    readonly property QtObject microphone: QtObject {
        property int id: 52
        property string description: "Micrófono interno"
        property bool ready: true
        readonly property QtObject audio: QtObject { property bool muted: false; property real volume: 0.5 }
    }
    readonly property var sink: available ? speakers : null
    readonly property var source: available ? microphone : null
    readonly property bool muted: !!sink?.audio?.muted
    readonly property real volume: sink?.audio?.volume ?? 0
    readonly property bool sourceMuted: !!source?.audio?.muted
    readonly property real sourceVolume: source?.audio?.volume ?? 0
    readonly property var sinks: available ? [speakers] : []
    readonly property var sources: available ? [microphone] : []
    property var streams: []

    function setVolume(value) { if (sink) sink.audio.volume = value; }
    function setSourceVolume(value) { if (source) source.audio.volume = value; }
    function setAudioSink(node) {}
    function setAudioSource(node) {}
    function setStreamVolume(node, value) {}
    function setStreamMuted(node, value) {}
    function getStreamVolume(node) { return 0; }
    function getStreamMuted(node) { return false; }
    function getStreamName(node) { return ""; }
}
"""

POWER = """pragma Singleton
import QtQuick
QtObject {
    property bool hasBattery: true
    property bool laptopBattery: true
    property int percent: 86
    readonly property real value: percent / 100
    property bool charging: false
    property bool onBattery: true
    readonly property bool critical: hasBattery && onBattery && value <= 0.2
    property int timeToFull: 0
    property int timeToEmpty: 9000
}
"""

BRIGHTNESS = """pragma Singleton
import QtQuick
QtObject {
    id: root
    property bool available: true
    readonly property QtObject monitor: QtObject {
        property real brightness: 0.7
        function setBrightness(value) { brightness = value; }
    }
    function getMonitorForScreen(screen) { return available ? monitor : null; }
}
"""

HYPR = """pragma Singleton
import QtQuick
QtObject {
    property bool keyboardKnown: true
    property string kbLayout: "es"
    property string kbLayoutFull: "Español (Latinoamérica)"
    property bool capsLock: false
    property bool numLock: false
    readonly property var monitors: ({ values: [
        { name: "eDP-1", width: 1920, height: 1080, scale: 1, focused: true },
        { name: "HDMI-A-1", width: 1920, height: 1080, scale: 1, focused: false }
    ] })
    readonly property var workspaces: ({ values: [] })
}
"""

NOTIFICATIONS = """pragma Singleton
import QtQuick
QtObject {
    property int count: 3
    property bool dnd: false
    function setDnd(value) { dnd = value; }
    function clear() { count = 0; }
}
"""

WALLPAPERS = """pragma Singleton
import QtQuick
QtObject {
    property string actualCurrent: "/home/prueba/Fondos/montaña.png"
    property string applyStatus: "idle"
    property string applyStatusPath: ""
    property string applyError: ""
}
"""

NVIBRANT = """pragma Singleton
import QtQuick
QtObject {
    readonly property int minimum: -1024
    readonly property int maximum: 1023
    property bool available: false
    property string connector: ""
    property bool known: false
    property int value: 0
    property int requested: 0
    property bool busy: false
    property string error: ""
    function setValue(next) { requested = next; value = next; known = true; }
}
"""

STUBS = {
    "modules/CortetsuIdleInhibitor.qml": IDLE,
    "services/IdleInhibitor.qml": IDLE,
    "services/ConnectivityWifi.qml": WIFI,
    "services/ConnectivityBluetooth.qml": BLUETOOTH,
    "services/Connectivity.qml": CONNECTIVITY,
    "modules/CortetsuAudio.qml": AUDIO,
    "services/CortetsuPower.qml": POWER,
    "services/Brightness.qml": BRIGHTNESS,
    "services/Hypr.qml": HYPR,
    "modules/CortetsuNotifications.qml": NOTIFICATIONS,
    "modules/CortetsuWallpapers.qml": WALLPAPERS,
    "services/Nvibrant.qml": NVIBRANT,
}

BINDINGS = {"ok": True, "bindings": [
    {"id": "a", "label": "Ajustes", "chord": "SUPER + I", "group": "Cortetsu", "description": "Abrir Ajustes"},
    {"id": "b", "label": "Hardware", "chord": "SUPER + H", "group": "Cortetsu", "description": "Abrir Hardware"},
    {"id": "c", "label": "Terminal", "chord": "SUPER + RETURN", "group": "Application", "description": "kitty"},
]}

# Each double command does what its mode file says, so a test can make the
# next call fail without restarting the shell.
COMMANDS = {
    "systemctl": '#!/bin/sh\nprintf "systemctl %s\\n" "$*" >> "$SETTINGS_FIXTURES/calls.log"\n'
                 '[ "$(cat "$SETTINGS_FIXTURES/systemctl-mode")" = ok ] || { echo "hyprsunset.service no existe" >&2; exit 5; }\n',
    "hyprctl": '#!/bin/sh\nprintf "hyprctl %s\\n" "$*" >> "$SETTINGS_FIXTURES/calls.log"\n',
    "cortetsu-keybinds": '#!/bin/sh\nprintf "cortetsu-keybinds %s\\n" "$*" >> "$SETTINGS_FIXTURES/calls.log"\n'
                         '[ "$(cat "$SETTINGS_FIXTURES/keybinds-mode")" = ok ] || exit 3\n'
                         'cat "$SETTINGS_FIXTURES/bindings.json"\n',
    # Called after the valid preferences have loaded. A nonempty directory
    # rejects both direct writes and atomic replacement, including under root.
    "cortetsu-test-block-preferences": '#!/bin/sh\nset -eu\n'
        'target="$XDG_CONFIG_HOME/cortetsu/preferences.json"\n'
        'saved="$SETTINGS_FIXTURES/preferences-before-failed-write.json"\n'
        'mv "$target" "$saved"\nmkdir "$target"\nmv "$saved" "$target/original.json"\n',
}

FAILURE_MARKERS = ("SETTINGS_FAIL", "TypeError", "ReferenceError", "is not a type", "Unable to assign",
                   "Binding loop", "Cannot anchor", "is not defined", "Cannot read property", "Failed to load",
                   "Cannot set activeFocusOnTab", "Cannot call method", "is not a function")


def build_tree(folder: Path) -> None:
    """The same overlay the runtime builder makes, plus the service doubles."""
    shutil.copytree(ROOT / "base", folder, dirs_exist_ok=True)
    for name in ("modules", "components", "utils", "services", "theme"):
        shutil.copytree(ROOT / name, folder / name, dirs_exist_ok=True)
    shutil.copytree(ROOT / "assets/branding", folder / "assets/branding", dirs_exist_ok=True)
    for relative, text in STUBS.items():
        (folder / relative).write_text(text, encoding="utf-8")
    (folder / "BUILD.json").write_text(json.dumps({
        "schema": 1, "buildId": "20261003-000000-1", "builtAt": "2026-10-03T12:00:00+00:00",
        "repositoryRevision": "0123456789abcdef0123456789abcdef01234567"}), encoding="utf-8")


HOST_SHELL = """import QtQuick
import QtQuick.Window
import Quickshell
import "modules"
import "modules/settings"
import "services"

// The real SettingsHost: a FloatingWindow per screen, which only a Wayland
// compositor can map. Opened, browsed, closed and reopened.
ShellRoot {
    id: root
    property int step: 0
    // SettingsContext also uses ShellState. Share its actual screen state so
    // creating Content cannot replace a separately registered test object.
    readonly property var hostState: ShellState.forScreen(Quickshell.screens[0])
    SettingsHost { id: host }
    Connections {
        target: host.windows.length > 0 ? host.windows[0] : null
        function onClosed() {
            console.log("SETTINGS_HOST_CLOSED", JSON.stringify({step: root.step,
                requested: root.hostState.settings, intended: target.requestedOpen,
                visible: target.visible, nativeClosePending: target.nativeClosePending}));
        }
    }
    function find(item, name) {
        if (item.objectName === name) return item;
        for (const child of item.children ?? []) {
            const found = find(child, name);
            if (found) return found;
        }
        return null;
    }
    function checkWindows(open) {
        const windows = host.windows;
        if (windows.length !== Quickshell.screens.length) {
            console.log("SETTINGS_FAIL", "the host must own one window per screen");
            Qt.quit(); return false;
        }
        for (const window of windows) {
            const loader = find(window.contentItem, "settingsContentLoader");
            if (window.visible !== open || !loader || loader.active !== open || !!loader.item !== open) {
                console.log("SETTINGS_FAIL", "window visibility and loaded content", JSON.stringify({
                    step: root.step, expected: open, requested: root.hostState.settings, intended: window.requestedOpen,
                    windowState: window.screenState?.settings, sameState: window.screenState === root.hostState,
                    nativeClosePending: window.nativeClosePending, visible: window.visible,
                    loaderActive: loader?.active, content: !!loader?.item,
                    screen: window.modelData?.name, nativeScreen: window.screen?.name,
                    registered: CortetsuShellState.states.map(entry => ({screen: entry.screen?.name,
                        sameScreen: entry.screen === window.modelData, sameState: entry.state === root.hostState}))}));
                Qt.quit(); return false;
            }
        }
        return true;
    }
    Timer {
        interval: 500; repeat: true; running: true
        onTriggered: {
            root.step++;
            if (!root.hostState) {
                console.log("SETTINGS_FAIL", "the host must have its registered screen state");
                Qt.quit(); return;
            }
            const ids = SettingsController.categories.map(item => item.id);
            if (root.step === 1 || root.step === ids.length + 4)
                root.hostState.settings = true;
            else if (root.step <= ids.length + 1) {
                if (!root.checkWindows(true)) return;
                SettingsController.select(ids[root.step - 2]);
            } else if (root.step === ids.length + 2)
                root.hostState.settings = false;
            else if (root.step === ids.length + 3) {
                if (!root.checkWindows(false)) return;
            } else if (root.step === ids.length + 5) {
                if (!root.checkWindows(true)) return;
            } else if (root.step === ids.length + 6) {
                // Close the real QWindow, as the WM does, without changing
                // the fixture's requested state first.
                host.windows[0].contentItem.Window.window.close();
            } else if (root.step === ids.length + 7) {
                if (root.hostState.settings || !root.checkWindows(false)) {
                    console.log("SETTINGS_FAIL", "a native close must clear the requested state and unload content");
                    Qt.quit(); return;
                }
                root.hostState.settings = true;
            } else if (root.step === ids.length + 8) {
                if (!root.checkWindows(true)) return;
                host.windows[0].contentItem.Window.window.close();
                if (root.hostState.settings) {
                    console.log("SETTINGS_FAIL", "native close must be observed before immediate reopen");
                    Qt.quit(); return;
                }
                // Both changes reach the same deferred transition. The native
                // requested visibility must still be reset before reopening.
                root.hostState.settings = true;
            } else if (root.step === ids.length + 9) {
                if (!root.checkWindows(true)) return;
                root.hostState.settings = false;
            } else if (root.step === ids.length + 10) {
                if (!root.checkWindows(false)) return;
                console.log("SETTINGS_HOST_PASS", Quickshell.screens.length);
                Qt.quit();
            }
        }
    }
}
"""


def run_host(folder: Path) -> str:
    """Runs the real window host inside a headless weston. Returns "" without weston."""
    if not shutil.which("weston"):
        return ""
    (folder / "host.qml").write_text(HOST_SHELL, encoding="utf-8")
    runtime = folder / "wayland-runtime"
    runtime.mkdir(mode=0o700)
    compositor = subprocess.Popen(
        ["weston", "--backend=headless", "--renderer=gl", "--width=1920", "--height=1080", "--socket=cortetsu-settings"],
        env={**os.environ, "XDG_RUNTIME_DIR": str(runtime)}, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        for _ in range(100):
            if (runtime / "cortetsu-settings").exists():
                break
            time.sleep(0.05)
        output, _ = run(folder, "host.qml", "host", timeout=60,
                        env={"LANG": "C.UTF-8", "XDG_RUNTIME_DIR": str(runtime), "WAYLAND_DISPLAY": "cortetsu-settings",
                             "QT_QPA_PLATFORM": "wayland"})
    finally:
        compositor.terminate()
        compositor.wait(timeout=10)
    return output


def run(folder: Path, shell: str, scenario: str, *, preferences: dict | None = None,
        scheme: dict | None = None, env: dict | None = None, timeout: int = 120, label: str = "") -> tuple[str, Path]:
    """Runs one scenario in its own home and returns the log and that home."""
    home = folder / f"home-{label or scenario}"
    fixtures = home / "fixtures"
    binaries = home / "bin"
    for path in (fixtures, binaries, home / ".config/cortetsu", home / "state/cortetsu"):
        path.mkdir(parents=True)
    for name, text in COMMANDS.items():
        (binaries / name).write_text(text, encoding="utf-8")
        (binaries / name).chmod(0o755)
    (binaries / "cortetsu-scheme").symlink_to(ROOT / "bin/cortetsu-scheme")
    (fixtures / "systemctl-mode").write_text("ok")
    (fixtures / "keybinds-mode").write_text("ok")
    (fixtures / "bindings.json").write_text(json.dumps(BINDINGS), encoding="utf-8")
    (home / "state/cortetsu/scheme.json").write_text(
        json.dumps(scheme or {"name": "dynamic", "flavour": "default", "colours": {}}), encoding="utf-8")
    if preferences is not None:
        (home / ".config/cortetsu/preferences.json").write_text(json.dumps(preferences), encoding="utf-8")
    result = subprocess.run(
        ["quickshell", "-p", str(folder / shell)],
        env={**os.environ, "QT_QPA_PLATFORM": os.environ.get("CORTETSU_TEST_QPA", "offscreen"), "HOME": str(home),
             "XDG_STATE_HOME": str(home / "state"), "XDG_CONFIG_HOME": str(home / ".config"),
             "XDG_CACHE_HOME": str(home / "cache"), "PATH": f'{binaries}:{os.environ["PATH"]}',
             "CORTETSU_SKIP_RELOAD": "1", "SETTINGS_FIXTURES": str(fixtures), "SETTINGS_SCENARIO": scenario,
             "CORTETSU_RENDER_DIR": os.environ.get("CORTETSU_RENDER_DIR", ""), **(env or {})},
        capture_output=True, text=True, timeout=timeout,
    )
    output = result.stdout + result.stderr
    assert result.returncode == 0, output
    for marker in FAILURE_MARKERS:
        assert marker not in output, output
    return output, home

pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import "."
import "../services"
import "CortetsuDesign.js" as CortetsuDesign
import "CortetsuWallpaperSearch.js" as WallpaperSearch

Singleton {
    id: root

    readonly property string home: Quickshell.env("HOME")
    readonly property string stateRoot: Quickshell.env("XDG_STATE_HOME") || `${home}/.local/state`
    readonly property string currentNamePath: `${stateRoot}/cortetsu/wallpaper/path.txt`
    readonly property string wallsdir: Quickshell.env("CORTETSU_WALLPAPERS_DIR") || CortetsuConfig.wallpaperDirectory.replace(/^~/, home)
    readonly property string fallback: Quickshell.shellPath("assets/wallpaper.webp")

    property var list: []
    property bool showPreview: false
    readonly property string current: showPreview ? previewPath : actualCurrent
    property string previewPath: ""
    property string actualCurrent: fallback
    property bool previewColourLock: false
    property string previewSchemeJson: ""
    property int previewGeneration: 0
    readonly property string pendingApplyPath: applyState.pendingPath
    readonly property bool applying: pendingApplyPath.length > 0
    property bool applyFailed: false
    property bool applySucceeded: false
    property string applyError: ""
    property string lastApplyPath: ""
    readonly property string applyStatus: applying
        ? "applying"
        : applyFailed
            ? "failed"
            : applySucceeded
                ? "applied"
                : "idle"
    readonly property string applyStatusPath: applying ? pendingApplyPath : lastApplyPath
    property bool randomApply: false
    property int applyGeneration: 0

    signal wallpaperApplySucceeded(string path, int generation)
    signal wallpaperApplyFailed(string path, int generation)

    function entry(path: string): var {
        const slash = path.lastIndexOf("/");
        const parent = slash < 0 ? "" : path.slice(0, slash);
        const name = slash < 0 ? path : path.slice(slash + 1);
        return { path, parentDir: parent, name, relativePath: path.slice(wallsdir.length + 1) };
    }

    function getCategoryFor(w): string {
        const relative = String(w?.parentDir ?? "").slice(wallsdir.length + 1);
        const slash = relative.indexOf("/");
        return slash < 0 ? relative : relative.slice(0, slash);
    }

    function query(search: string): var {
        const needle = String(search ?? "").trim();
        if (!needle)
            return list;
        return list.filter(w => WallpaperSearch.matches(
            `${w.name} ${w.relativePath}`,
            needle,
            CortetsuConfig.useFuzzyWallpapers
        ));
    }

    function reload(): void {
        scan.command = ["find", wallsdir, "-type", "f", "(", "-iname", "*.jpg", "-o", "-iname", "*.jpeg", "-o", "-iname", "*.png", "-o", "-iname", "*.webp", "-o", "-iname", "*.tif", "-o", "-iname", "*.tiff", "-o", "-iname", "*.gif", ")", "-print"];
        scan.running = true;
    }

    function apply(path: string): bool {
        const target = String(path ?? "").trim();
        if (!target || applying || target === actualCurrent)
            return false;
        stopPreview();
        applyGeneration += 1;
        applyState.pendingPath = target;
        randomApply = false;
        applyFailed = false;
        applySucceeded = false;
        applyError = "";
        lastApplyPath = target;
        applyTimeout.restart();
        Quickshell.execDetached(["cortetsu-wallpaper-select", target]);
        return true;
    }

    function applyRandom(): bool {
        if (applying)
            return false;
        stopPreview();
        applyGeneration += 1;
        applyState.pendingPath = actualCurrent;
        randomApply = true;
        applyFailed = false;
        applySucceeded = false;
        applyError = "";
        lastApplyPath = "";
        applyTimeout.restart();
        Quickshell.execDetached(["cortetsu-wallpaper-select", "--random", wallsdir]);
        return true;
    }

    function setRandom(): void { applyRandom(); }

    function setWallpaper(path: string): void { apply(path); }

    function cancelApply(): void {
        applyTimeout.stop();
        paletteApply.requestGeneration = -1;
        paletteApply.requestPath = "";
        paletteApply.running = false;
        applyState.pendingPath = "";
        randomApply = false;
        applyFailed = false;
        applySucceeded = false;
        applyError = "";
        lastApplyPath = "";
    }

    function completeApply(path: string, generation: int): void {
        if (!applying || generation !== applyGeneration)
            return;
        applyTimeout.stop();
        paletteApply.requestGeneration = -1;
        paletteApply.requestPath = "";
        applyState.pendingPath = "";
        randomApply = false;
        applyFailed = false;
        applySucceeded = true;
        applyError = "";
        lastApplyPath = path;
        previewColourLock = false;
        wallpaperApplySucceeded(path, generation);
    }

    function readActual(raw: string): void {
        const next = String(raw ?? "").trim() || fallback;
        actualCurrent = next;
        if (!applying)
            return;
        const confirmed = randomApply ? next !== pendingApplyPath : next === pendingApplyPath;
        if (!confirmed)
            return;
        const generation = applyGeneration;
        lastApplyPath = next;
        if (CortetsuConfig.smartScheme) {
            paletteApply.requestGeneration = generation;
            paletteApply.requestPath = next;
            paletteApply.command = ["cortetsu-apply-wallpaper-colors", next];
            paletteApply.running = true;
            return;
        }
        root.completeApply(next, generation);
    }

    function failApply(detail): void {
        if (!applying)
            return;
        detail = String(detail ?? "");
        const path = pendingApplyPath;
        const generation = applyGeneration;
        paletteApply.requestGeneration = -1;
        paletteApply.requestPath = "";
        paletteApply.running = false;
        applyTimeout.stop();
        applyState.pendingPath = "";
        randomApply = false;
        applyFailed = true;
        applySucceeded = false;
        applyError = detail;
        lastApplyPath = path;
        previewColourLock = false;
        wallpaperApplyFailed(path, generation);
    }

    function preview(path: string): void {
        previewGeneration += 1;
        previewPath = path;
        showPreview = true;
        previewPalette.requestGeneration = previewGeneration;
        previewPalette.command = ["cortetsu-wallpaper-colours", path];
        previewPalette.running = true;
    }

    function stopPreview(): void {
        previewGeneration += 1;
        previewPalette.running = false;
        showPreview = false;
        previewPath = "";
        previewSchemeJson = "";
        previewColourLock = false;
        CortetsuColours.clearPreview();
    }

    Component.onCompleted: reload()

    IpcHandler {
        target: "cortetsu-wallpaper"
        function get(): string { return root.actualCurrent; }
        function set(path: string): void { root.setWallpaper(path); }
        function list(): string { return root.list.map(w => w.path).join("\n"); }
    }

    QtObject {
        id: applyState
        property string pendingPath: ""
    }

    Timer {
        id: applyTimeout
        interval: CortetsuDesign.motionDeliberateMs * 8
        repeat: false
        onTriggered: root.failApply()
    }

    FileView {
        path: root.currentNamePath
        watchChanges: true
        printErrors: false
        onFileChanged: { root.readActual(text()); reload(); }
        onLoaded: root.readActual(text())
        onLoadFailed: root.readActual(root.fallback)
    }

    Process {
        id: scan
        stdout: StdioCollector {
            onStreamFinished: root.list = text.split("\n").filter(Boolean).sort().map(path => root.entry(path))
        }
    }

    Process {
        id: previewPalette
        property int requestGeneration: -1
        stdout: StdioCollector {
            onStreamFinished: {
                if (previewPalette.requestGeneration === root.previewGeneration && root.showPreview) {
                    root.previewSchemeJson = text;
                    if (CortetsuConfig.smartScheme)
                        CortetsuColours.load(text, true);
                }
            }
        }
    }

    Process {
        id: paletteApply
        property int requestGeneration: -1
        property string requestPath: ""
        command: []

        stderr: StdioCollector { id: paletteApplyStderr }

        onExited: code => { // qmllint disable signal-handler-parameters
            if (!root.applying
                || paletteApply.requestGeneration !== root.applyGeneration
                || paletteApply.requestPath !== root.actualCurrent)
                return;
            const detail = paletteApplyStderr.text.trim();
            if (code === 0)
                root.completeApply(root.actualCurrent, root.applyGeneration);
            else
                root.failApply(detail || qsTr("Dynamic scheme apply failed"));
        }
    }

    Timer { interval: 30000; repeat: true; running: true; onTriggered: root.reload() }
}

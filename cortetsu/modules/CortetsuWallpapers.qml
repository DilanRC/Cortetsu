pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import "."
import "../services"
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

    function setRandom(): void {
        stopPreview();
        Quickshell.execDetached(["cortetsu-wallpaper-select", "--random", wallsdir]);
    }

    function setWallpaper(path: string): void {
        stopPreview();
        actualCurrent = path;
        Quickshell.execDetached(["cortetsu-wallpaper-select", path]);
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

    FileView {
        path: root.currentNamePath
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: root.actualCurrent = text().trim() || root.fallback
        onLoadFailed: root.actualCurrent = root.fallback
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

    Timer { interval: 30000; repeat: true; running: true; onTriggered: root.reload() }
}

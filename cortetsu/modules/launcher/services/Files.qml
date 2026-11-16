pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import "../.."

// File search for the launcher (">files texto"). The index is plocate's
// (the system's updatedb, already installed and refreshed by its timer):
// this owner asks it once per settled query, keeps what is under the home
// folder and not hidden, and shapes each hit like a launcher action so the
// action cell shows and opens it. Nothing is read while the mode is off.
QtObject {
    id: root

    readonly property string home: Quickshell.env("HOME") || ""
    readonly property int maxResults: 30
    // idle | searching | ready | unavailable
    property string status: "idle"
    property string query: ""
    property var results: []

    function prefixFor(): string {
        return `${CortetsuConfig.actionPrefix}files `;
    }

    // Called by the launcher on every edit of the search text.
    function update(text: string): void {
        const next = text.startsWith(prefixFor()) ? text.slice(prefixFor().length).trim() : "";
        if (next === root.query)
            return;
        root.query = next;
        if (next.length < 2) {
            settle.stop();
            root.results = [];
            root.status = "idle";
            return;
        }
        root.status = "searching";
        settle.restart();
    }

    function iconFor(name: string): string {
        const extension = name.includes(".") ? name.split(".").pop().toLowerCase() : "";
        if (["png", "jpg", "jpeg", "webp", "gif", "svg", "avif"].includes(extension)) return "image";
        if (["mp4", "mkv", "webm", "mov", "avi"].includes(extension)) return "movie";
        if (["mp3", "flac", "ogg", "opus", "wav", "m4a"].includes(extension)) return "music_note";
        if (["pdf"].includes(extension)) return "picture_as_pdf";
        if (["zip", "tar", "gz", "xz", "zst", "7z", "rar"].includes(extension)) return "folder_zip";
        if (["md", "txt", "doc", "docx", "odt", "rtf"].includes(extension)) return "description";
        if (["qml", "js", "ts", "py", "rs", "go", "c", "cpp", "h", "sh", "lua", "json", "toml"].includes(extension)) return "code";
        return extension ? "draft" : "folder";
    }

    function shorten(path: string): string {
        return root.home && path.startsWith(root.home) ? `~${path.slice(root.home.length)}` : path;
    }

    function receive(raw: string): void {
        const needle = root.query.toLowerCase();
        const hits = [];
        for (const path of raw.split("\n")) {
            if (!path.startsWith(`${root.home}/`) || path.slice(root.home.length).includes("/."))
                continue;
            const name = path.split("/").pop();
            hits.push({ path, name, folder: path.slice(0, path.length - name.length - 1),
                        exact: name.toLowerCase().startsWith(needle) });
        }
        // Names that start with the query first, then shorter paths.
        hits.sort((a, b) => (b.exact - a.exact) || (a.path.length - b.path.length));
        root.results = hits.slice(0, root.maxResults).map(hit => ({
            id: hit.path,
            name: hit.name,
            desc: root.shorten(hit.folder),
            icon: root.iconFor(hit.name),
            dangerous: false,
            onClicked: list => {
                list.screenState.launcher = false;
                Quickshell.execDetached(["xdg-open", hit.path]);
            }
        }));
        root.status = "ready";
    }

    // A pause in typing, not every key, starts a search.
    // A newer query arrived while plocate was still running: that run is
    // stopped and this one starts when it exits.
    property bool restart: false
    // The query the running search answers.
    property string startedFor: ""

    function start(): void {
        root.startedFor = root.query;
        search.command = ["plocate", "--ignore-case", "--basename", "--limit", "400", "--", root.query];
        search.running = true;
    }

    property Timer settle: Timer {
        interval: 180
        onTriggered: {
            if (search.running) {
                root.restart = true;
                search.signal(15);
            } else {
                root.start();
            }
        }
    }

    // startup inventory: cortetsu:launcher-file-search (on query only)
    property Process search: Process {
        stdout: StdioCollector { id: output }
        onExited: code => {
            if (root.restart) {
                root.restart = false;
                if (root.query.length >= 2)
                    root.start();
                return;
            }
            // 1 is "no match"; any other failure is an index that cannot
            // be read (no database, no permission).
            // An answer for a query the user has already left is dropped.
            if (root.startedFor !== root.query || root.query.length < 2)
                return;
            if (code === 0 || code === 1) {
                root.receive(output.text);
            } else {
                root.results = [];
                root.status = "unavailable";
            }
        }
    }
}

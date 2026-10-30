pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import "../modules"
import "../utils"

// Lyrics for the active player.
//
// Spotify's own lyrics arrive from the spicetify extension through
// `cortetsu-lyrics serve`, one JSON line per song. For any other player, or
// a Spotify track the extension had nothing for, `cortetsu-lyrics lookup`
// tries an `Artist - Title.lrc` file in the lyrics folder, then lrclib.net.
// The backend setting (Auto, Local, LRCLIB, NetEase) narrows that: Local
// never goes online and ignores Spotify, LRCLIB skips the folder. NetEase
// is no longer offered and behaves as Auto. `lines` is [{t: ms, text}], sorted; `index` is the line
// being sung, and only advances while someone shows the lyrics.
Singleton {
    id: root

    property int consumers: 0
    readonly property string helper: `${Quickshell.env("HOME")}/.local/bin/cortetsu-lyrics`
    readonly property string lyricsDir: Quickshell.env("CORTETSU_LYRICS_DIR") || `${Paths.home}/Music/Lyrics`
    readonly property int backend: CortetsuConfig.lyricsBackend
    readonly property bool localOnly: backend === 1

    readonly property MprisPlayer player: Players.active
    readonly property bool isSpotify: (player?.identity ?? "").toLowerCase().includes("spotify")
    readonly property string spotifyId: {
        const id = String(player?.metadata?.["mpris:trackid"] ?? "");
        return id.match(/track[:/]([A-Za-z0-9]+)$/)?.[1] ?? "";
    }
    readonly property string title: player?.trackTitle ?? ""
    readonly property string artist: player?.trackArtist ?? ""
    readonly property string trackKey: isSpotify && spotifyId && !localOnly ? `spotify:${spotifyId}` : title ? `${artist}\u001f${title}` : ""

    // trackKey -> {source, synced, lines}; a handful of recent songs.
    property var cache: ({})
    property var cacheOrder: []
    readonly property var entry: trackKey ? cache[trackKey] ?? null : null
    readonly property var lines: entry?.lines ?? []
    readonly property bool synced: entry?.synced ?? false
    readonly property string source: entry?.source ?? ""
    readonly property bool loading: !!trackKey && !entry
    property real positionMs: 0
    readonly property int index: {
        if (!synced || lines.length === 0)
            return -1;
        let lo = 0, hi = lines.length - 1, found = -1;
        while (lo <= hi) {
            const mid = (lo + hi) >> 1;
            if (lines[mid].t <= positionMs + 250) { found = mid; lo = mid + 1; } else hi = mid - 1;
        }
        return found;
    }
    readonly property string currentLine: index >= 0 ? lines[index].text : ""

    function store(key: string, value: var): void {
        const next = Object.assign({}, cache);
        next[key] = value;
        const order = cacheOrder.filter(k => k !== key).concat([key]);
        while (order.length > 12)
            delete next[order.shift()];
        cacheOrder = order;
        cache = next;
    }

    // ---------------------------------------------------------- Spotify bridge

    // startup inventory: cortetsu:lyrics-bridge
    Process {
        id: bridge
        running: true
        command: [root.helper, "serve"]
        stdout: SplitParser {
            onRead: data => {
                let doc;
                try { doc = JSON.parse(data); } catch (e) { return; }
                if (!doc?.trackId || !Array.isArray(doc.lines))
                    return;
                const key = `spotify:${doc.trackId}`;
                // An empty answer from Spotify leaves room for lrclib.
                if (doc.lines.length === 0) {
                    if (key === root.trackKey && !root.entry)
                        lookup.startFor(key);
                    return;
                }
                root.store(key, { source: "spotify", synced: !!doc.synced, lines: doc.lines });
            }
        }
        // Port taken or helper missing: try again later, quietly.
        onExited: restart.start()
    }

    Timer {
        id: restart
        interval: 30000
        onTriggered: bridge.running = true
    }

    // ----------------------------------------------------- local and lrclib

    // Spotify gets a moment for its extension to answer first.
    Timer {
        id: fallbackDelay
        interval: root.isSpotify ? 2500 : 300
        onTriggered: if (root.trackKey && !root.entry) lookup.startFor(root.trackKey)
    }

    onTrackKeyChanged: {
        positionMs = (player?.position ?? 0) * 1000;
        if (trackKey && !entry)
            fallbackDelay.restart();
    }

    // startup inventory: cortetsu:lyrics-lookup
    Process {
        id: lookup
        property string key: ""
        function startFor(k: string): void {
            if (running || !root.title)
                return;
            key = k;
            const length = root.player?.length ?? 0;
            command = [root.helper, "lookup", "--title", root.title, "--artist", root.artist,
                "--album", root.player?.trackAlbum ?? "", "--duration", String(Math.round(length)),
                "--local-dir", root.lyricsDir].concat(root.localOnly ? ["--offline"] : root.backend === 2 ? ["--online-only"] : []);
            running = true;
        }
        stdout: StdioCollector {
            onStreamFinished: {
                let doc = null;
                try { doc = JSON.parse(text); } catch (e) {}
                const k = lookup.key;
                // A Spotify answer that came in meanwhile wins.
                if (k && !root.cache[k])
                    root.store(k, { source: doc?.source ?? "lrclib", synced: !!doc?.synced, lines: doc?.lines ?? [] });
            }
        }
        onExited: code => {
            if (code !== 0 && lookup.key && !root.cache[lookup.key])
                root.store(lookup.key, { source: "", synced: false, lines: [] });
        }
    }

    // --------------------------------------------------------------- position

    Timer {
        running: root.consumers > 0 && root.synced && !!root.player?.isPlaying
        interval: 200
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            root.player.positionChanged();
            root.positionMs = root.player.position * 1000;
        }
    }

    // Diagnostics: where the current lyrics came from, never their text.
    IpcHandler {
        target: "lyrics"
        function status(): string {
            return JSON.stringify({ track: root.trackKey, source: root.source, synced: root.synced, lines: root.lines.length, loading: root.loading, bridge: bridge.running });
        }
    }
}

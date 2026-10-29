pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import "../.."
import "../../../services"
import "EmojiSearch.js" as EmojiSearch

// Emoji mode of the launcher (`>emoji …`). The list is cortetsu-emoji's data:
// one "glyph words…" entry per line, the refreshed cache if `cortetsu emoji
// -f` ran, else the bundled data/emojis.txt.
Singleton {
    id: root

    readonly property int maxResults: 64
    property var entries: []
    property bool loaded: false

    function query(text: string): var {
        if (!loaded && !loader.running)
            loader.running = true;
        const search = text.slice(`${CortetsuConfig.actionPrefix}emoji `.length);
        return EmojiSearch.filter(entries, search, maxResults).map(e => ({
            id: e.glyph + " " + e.words,
            glyph: e.glyph,
            name: e.words,
            onClicked: list => root.copy(e.glyph, list)
        }));
    }

    function copy(glyph: string, list): void {
        Quickshell.execDetached(["wl-copy", "--", glyph]);
        CortetsuToaster.toast(qsTr("Copiado al portapapeles"), glyph, "content_copy");
        if (list)
            list.screenState.launcher = false;
    }

    Process {
        id: loader

        command: ["cortetsu-emoji"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.entries = EmojiSearch.parse(text);
                root.loaded = true;
            }
        }
        onExited: code => {
            if (code !== 0)
                console.warn(`cortetsu-emoji exited with ${code}`);
        }
    }
}

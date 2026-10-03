pragma Singleton

import ".."
import "../.."
import QtQuick
import Quickshell
import Quickshell.Io
import "../../../services"
import "../../../utils"

Searcher {
    id: root

    // The active scheme is what scheme.json holds. CortetsuColours watches
    // that file, so a scheme set here, from the launcher, from a terminal or
    // by the wallpaper shows up without asking the helper again.
    readonly property string currentScheme: `${CortetsuColours.scheme} ${CortetsuColours.flavour}`
    readonly property string currentVariant: CortetsuColours.variant
    property string error: ""
    property string pendingScheme: ""
    // idle | applying | applied | failed
    property string applyStatus: "idle"
    property string applyError: ""
    property string catalogText: ""
    // "name flavour" → { name, flavour, colours }. The list is built from the
    // keys, so a catalogue that gains or loses one scheme adds or removes one
    // object and leaves the others, and whatever draws them, alone.
    property var entries: ({})
    readonly property bool loading: getSchemes.running
    readonly property bool applying: applyStatus === "applying"
    readonly property int catalogCount: schemes.instances?.length ?? 0

    // A scheme set from outside the catalogue (the one derived from the
    // wallpaper) gets its entry as soon as it becomes the active one.
    onCurrentSchemeChanged: {
        if (catalogText.length > 0 && !entries[currentScheme])
            reload();
    }

    function transformSearch(search: string): string {
        return search.slice(`${CortetsuConfig.actionPrefix}scheme `.length);
    }

    function selector(item: var): string {
        return `${item.name} ${item.flavour}`;
    }

    function reload(): void {
        root.error = "";
        if (!getSchemes.running)
            getSchemes.running = true;
    }

    function apply(name: string, flavour: string): void {
        if (!name || !flavour || applyScheme.running)
            return;

        root.error = "";
        root.applyError = "";
        appliedNotice.stop();
        root.pendingScheme = `${name} ${flavour}`;
        root.applyStatus = "applying";
        applyScheme.command = ["cortetsu-scheme", "set", "-n", name, flavour];
        applyScheme.running = true;
    }

    list: schemes.instances
    useFuzzy: CortetsuConfig.useFuzzyApps
    keys: ["name", "flavour"]
    weights: [0.9, 0.1]

    Variants {
        id: schemes

        Scheme {}
    }

    // startup inventory: cortetsu:launcher-scheme-list
    Process {
        id: getSchemes

        running: true
        command: ["cortetsu-scheme", "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                // An unchanged catalogue keeps its objects, and with them
                // every card and row that is showing one.
                if (text === root.catalogText && text.length > 0)
                    return;
                try {
                    const schemeData = JSON.parse(text);
                    if (!schemeData || typeof schemeData !== "object" || Array.isArray(schemeData))
                        throw new Error("scheme catalog is not an object");

                    const entries = {};
                    for (const [name, flavours] of Object.entries(schemeData)) {
                        if (!flavours || typeof flavours !== "object" || Array.isArray(flavours))
                            continue;
                        for (const [flavour, colours] of Object.entries(flavours)) {
                            entries[`${name} ${flavour}`] = {
                                name,
                                flavour,
                                colours: colours && typeof colours === "object" ? colours : ({})
                            };
                        }
                    }

                    root.entries = entries;
                    schemes.model = Object.keys(entries).sort((a, b) => a.localeCompare(b));
                    root.catalogText = text;
                    root.error = "";
                } catch (error) {
                    root.error = qsTr("No se pudo leer el catálogo de esquemas");
                    console.warn("Cortetsu Schemes: invalid catalog:", error);
                }
            }
        }
    }

    Process {
        id: applyScheme
        command: []

        stderr: StdioCollector { id: applyStderr }

        onExited: code => { // qmllint disable signal-handler-parameters
            const detail = applyStderr.text.trim();
            if (code === 0) {
                root.applyStatus = "applied";
                root.applyError = "";
                appliedNotice.restart();
            } else {
                root.applyStatus = "failed";
                root.applyError = detail || qsTr("No se pudo aplicar el esquema");
            }
            if (!detail && code !== 0)
                console.warn(`Cortetsu Schemes: apply exited with code ${code}`);
        }
    }

    // "Applied" is a confirmation, not a state to keep on screen. A failure
    // stays until the next attempt.
    Timer {
        id: appliedNotice
        interval: 4000
        onTriggered: if (root.applyStatus === "applied") root.applyStatus = "idle"
    }

    component Scheme: QtObject {
        required property string modelData
        readonly property var entry: root.entries[modelData] ?? ({})
        readonly property string name: entry.name ?? ""
        readonly property string flavour: entry.flavour ?? ""
        readonly property var colours: entry.colours ?? ({})

        function onClicked(list: AppList): void {
            list.screenState.launcher = false;
            root.apply(name, flavour);
        }
    }
}

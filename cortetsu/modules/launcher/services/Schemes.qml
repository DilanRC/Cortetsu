pragma Singleton

import ".."
import "../.."
import QtQuick
import Quickshell
import Quickshell.Io
import "../../../utils"

Searcher {
    id: root

    property string currentScheme: ""
    property string currentVariant: ""
    property string error: ""
    readonly property bool loading: getSchemes.running || getCurrent.running
    readonly property bool applying: applyScheme.running
    readonly property int catalogCount: schemes.instances?.length ?? 0

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
        if (!getCurrent.running)
            getCurrent.running = true;
    }

    function apply(name: string, flavour: string): void {
        if (!name || !flavour || applyScheme.running)
            return;

        root.error = "";
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

    Process {
        id: getSchemes

        running: true
        command: ["cortetsu-scheme", "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const schemeData = JSON.parse(text);
                    if (!schemeData || typeof schemeData !== "object" || Array.isArray(schemeData))
                        throw new Error("scheme catalog is not an object");

                    const flat = [];
                    for (const [name, flavours] of Object.entries(schemeData)) {
                        if (!flavours || typeof flavours !== "object" || Array.isArray(flavours))
                            continue;
                        for (const [flavour, colours] of Object.entries(flavours)) {
                            flat.push({
                                name,
                                flavour,
                                colours: colours && typeof colours === "object" ? colours : ({})
                            });
                        }
                    }

                    schemes.model = flat.sort((a, b) =>
                        String(`${a.name} ${a.flavour}`).localeCompare(String(`${b.name} ${b.flavour}`)));
                    root.error = "";
                } catch (error) {
                    root.error = qsTr("Unable to read the scheme catalog");
                    console.warn("Cortetsu Schemes: invalid catalog:", error);
                }
            }
        }
    }

    Process {
        id: getCurrent

        running: true
        command: ["cortetsu-scheme", "get", "-nfv"]
        stdout: StdioCollector {
            onStreamFinished: {
                const parts = text.trim().split("\n");
                const name = parts[0]?.trim() ?? "";
                const flavour = parts[1]?.trim() ?? "";
                const variant = parts[2]?.trim() ?? "";

                if (!name || !flavour) {
                    root.error = root.error || qsTr("Unable to identify the active scheme");
                    return;
                }

                root.currentScheme = `${name} ${flavour}`;
                root.currentVariant = variant;
            }
        }
    }

    Process {
        id: applyScheme
        command: []

        onRunningChanged: {
            if (!running && command.length > 0)
                root.reload();
        }
    }

    component Scheme: QtObject {
        required property var modelData
        readonly property string name: modelData.name
        readonly property string flavour: modelData.flavour
        readonly property var colours: modelData.colours

        function onClicked(list: AppList): void {
            list.screenState.launcher = false;
            root.apply(name, flavour);
        }
    }
}

pragma Singleton

import Quickshell
import Quickshell.Io
import QtQml
import "../.."
import "../../../services"
import "../../../utils"

// First-party desktop-entry search and launch. DesktopEntry.command is already
// parsed by Quickshell; the helper moves the persistent child into its own
// user scope before the shell can supervise it.
QtObject {
    id: root

    readonly property bool useFuzzyApps: CortetsuConfig.useFuzzyApps

    function isLaunchable(entry): bool {
        return !!entry && !entry.noDisplay && Array.from(entry.command ?? []).length > 0;
    }

    // Applications as of the last finished scan, by name. Quickshell lists
    // them in hash order, which changes on every shell start, and rescans on
    // any change in a parent of an applications directory, the home directory
    // included. Mid-scan, DesktopEntries.applications.values drops every entry
    // that exists in two directories before putting it back.
    property var applications: []

    readonly property Connections scans: Connections {
        target: DesktopEntries

        function onApplicationsChanged(): void {
            root.settle();
        }
    }

    Component.onCompleted: settle()

    // Browse mode (empty search): favourites, then what was launched
    // recently, then everything else by name. Categories narrow it to a
    // freedesktop main category; only those with an installed app are
    // offered.
    readonly property var categoryDefinitions: [
        { id: "Development", label: qsTr("Desarrollo"), match: ["Development"] },
        { id: "Network", label: qsTr("Internet"), match: ["Network"] },
        { id: "AudioVideo", label: qsTr("Multimedia"), match: ["AudioVideo", "Audio", "Video"] },
        { id: "Game", label: qsTr("Juegos"), match: ["Game"] },
        { id: "Office", label: qsTr("Oficina"), match: ["Office"] },
        { id: "Graphics", label: qsTr("Gráficos"), match: ["Graphics"] },
        { id: "System", label: qsTr("Sistema"), match: ["System", "Settings"] },
        { id: "Utility", label: qsTr("Utilidades"), match: ["Utility"] }
    ]
    readonly property var categories: {
        const present = categoryDefinitions.filter(definition =>
            entries().some(entry => inCategory(entry, definition)));
        return [{ id: "home", label: qsTr("Inicio") }].concat(present);
    }

    function inCategory(entry, definition): bool {
        const own = Array.from(entry?.categories ?? []);
        return definition.match.some(name => own.includes(name));
    }

    // Views of the expanded launcher's navigation: "all" by name,
    // "favourites", "recent" (newest first) and "homeRest" (the home order
    // without the favourites, which have their own row above it).
    function favourites(): var {
        return entries().filter(entry => Strings.testRegexList(CortetsuConfig.favouriteApps, entry.id));
    }

    function browse(category: string): var {
        const all = entries();
        if (category === "all")
            return all.slice().sort((a, b) => String(a.name).localeCompare(String(b.name)));
        if (category === "favourites")
            return root.favourites();
        if (category === "recent")
            return recentIds.map(id => all.find(entry => entry.id === id)).filter(entry => !!entry);
        if (category === "homeRest") {
            const favourite = entry => Strings.testRegexList(CortetsuConfig.favouriteApps, entry.id);
            return browse("home").filter(entry => !favourite(entry));
        }
        if (category && category !== "home") {
            const definition = categoryDefinitions.find(item => item.id === category);
            return definition ? all.filter(entry => inCategory(entry, definition)) : all;
        }
        const favourite = entry => Strings.testRegexList(CortetsuConfig.favouriteApps, entry.id);
        const recentRank = id => {
            const index = recentIds.indexOf(id);
            return index < 0 ? Number.MAX_SAFE_INTEGER : index;
        };
        const pinned = all.filter(favourite);
        const recent = all.filter(entry => !favourite(entry) && recentIds.includes(entry.id))
            .sort((a, b) => recentRank(a.id) - recentRank(b.id));
        const rest = all.filter(entry => !favourite(entry) && !recentIds.includes(entry.id));
        return pinned.concat(recent, rest);
    }

    // Launch history: runtime state, not a preference, so it lives in the
    // state directory next to the notification history. Ids only, newest
    // first, at most twelve. A missing or damaged file is an empty history.
    property var recentIds: []
    readonly property int recentLimit: 12
    readonly property FileView recentStore: FileView {
        path: `${Quickshell.env("XDG_STATE_HOME") || `${Quickshell.env("HOME")}/.local/state`}/cortetsu/launcher-recent.json`
        blockLoading: false
        printErrors: false
        onLoaded: {
            try {
                const parsed = JSON.parse(text());
                root.recentIds = Array.isArray(parsed)
                    ? parsed.filter(id => typeof id === "string" && id.length > 0 && id.length < 512)
                        .slice(0, root.recentLimit)
                    : [];
            } catch (_) {
                root.recentIds = [];
            }
        }
        onLoadFailed: root.recentIds = []
    }

    function remember(entry): void {
        const id = entry?.id;
        if (!id)
            return;
        recentIds = [id].concat(recentIds.filter(item => item !== id)).slice(0, recentLimit);
        recentStore.setText(JSON.stringify(recentIds));
    }

    function settle(): void {
        applications = [...DesktopEntries.applications.values].sort((a, b) =>
            a.name.localeCompare(b.name) || a.id.localeCompare(b.id));
    }

    function entries(): var {
        return applications.filter(entry =>
            isLaunchable(entry)
            && !Strings.testRegexList(CortetsuConfig.hiddenApps, entry.id));
    }

    function launch(entry): void {
        if (!entry)
            return;

        let command = Array.from(entry.command ?? []);
        if (!command.length) {
            console.warn(`Launcher: ${entry.name ?? entry.id ?? "application"} has no executable command`);
            return;
        }

        if (entry.runInTerminal) {
            command = [
                ...CortetsuConfig.terminalCommand,
                `${Quickshell.shellDir}/assets/wrap_term_launch.sh`,
                ...command
            ];
        }

        CortetsuProcessLauncher.launchPersistent(
            command,
            entry.workingDirectory ?? "",
            entry.id ?? entry.name ?? "app"
        );
        remember(entry);
    }

    function search(text: string): var {
        const prefix = CortetsuConfig.specialPrefix;
        let query = text;
        let field = "name";
        const selectors = { i: "id", c: "categories", d: "comment", e: "execString",
                            w: "startupClass", g: "genericName", k: "keywords" };
        if (text.startsWith(`${prefix}t `))
            query = text.slice(prefix.length + 2);
        else if (text.startsWith(prefix) && text.length > 2 && text[1] in selectors) {
            field = selectors[text[1]];
            query = text.slice(prefix.length + 2);
        }
        const needle = query.toLowerCase();
        return entries().filter(entry => {
            if (text.startsWith(`${prefix}t `) && !entry.runInTerminal)
                return false;
            return String(entry[field] ?? "").toLowerCase().includes(needle);
        });
    }
}

pragma Singleton

import Quickshell
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

    function entries(): var {
        return DesktopEntries.applications.values.filter(entry =>
            !Strings.testRegexList(CortetsuConfig.hiddenApps, entry.id));
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

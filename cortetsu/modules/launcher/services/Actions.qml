pragma Singleton

import ".."
import "../.."
import QtQuick
import Quickshell
import "../../../services"
import "../../../utils"

Searcher {
    id: root

    function transformSearch(search: string): string {
        return search.slice(CortetsuConfig.actionPrefix.length);
    }

    list: variants.instances
    useFuzzy: CortetsuConfig.useFuzzyApps

    Variants {
        id: variants

        model: CortetsuConfig.actions.filter(a => (a.enabled ?? true) && (CortetsuConfig.enableDangerousActions || !(a.dangerous ?? false)))

        Action {}
    }

    component Action: QtObject {
        required property var modelData
        readonly property string name: modelData.name ?? qsTr("Unnamed")
        readonly property string desc: modelData.description ?? qsTr("No description")
        readonly property string icon: modelData.icon ?? "help_outline"
        readonly property list<string> command: modelData.command ?? []
        readonly property bool enabled: modelData.enabled ?? true
        readonly property bool dangerous: modelData.dangerous ?? false

        function onClicked(list: AppList): void {
            if (command.length === 0)
                return;

            if (command[0] === "autocomplete" && command.length > 1) {
                list.search.text = `${CortetsuConfig.actionPrefix}${command[1]} `;
            } else if (command[0] === "setMode" && command.length > 1) {
                list.screenState.launcher = false;
                Quickshell.execDetached(["cortetsu", "theme", "set", command[1]]);
            } else {
                list.screenState.launcher = false;
                CortetsuProcessLauncher.launchPersistent(command, "", name);
            }
        }
    }
}

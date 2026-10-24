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
    useFuzzy: CortetsuConfig.useFuzzyActions

    Variants {
        id: variants

        model: CortetsuConfig.actions.filter(a => (a.enabled ?? true) && (CortetsuConfig.enableDangerousActions || !(a.dangerous ?? false)))

        Action {}
    }

    component Action: QtObject {
        required property var modelData
        readonly property string name: modelData.name ?? qsTr("Sin nombre")
        // Sleep actions are named modes, not programs; logind decides
        // whether they can run here.
        readonly property string sleepMode: ["suspend", "hibernate", "suspendThenHibernate"].includes(command[0] ?? "")
            ? command[0] : ""
        // Light/dark actions inherited from the upstream defaults: no Cortetsu
        // command switches the mode of the current scheme, so they would run
        // nothing. Shown disabled with the reason instead of failing silently.
        readonly property bool modeSwitch: command[0] === "setMode"
        readonly property bool available: !modeSwitch && (!sleepMode || CortetsuSession.available(sleepMode))
        readonly property string desc: available
            ? (modelData.description ?? qsTr("Sin descripción"))
            : modeSwitch
                ? qsTr("No disponible: Cortetsu no tiene una orden para cambiar el modo del esquema actual")
                : CortetsuSession.reason(sleepMode)
        readonly property string icon: modelData.icon ?? "help_outline"
        readonly property list<string> command: modelData.command ?? []
        readonly property bool enabled: modelData.enabled ?? true
        readonly property bool dangerous: modelData.dangerous ?? false

        function onClicked(list: AppList): void {
            if (command.length === 0 || !available)
                return;

            if (command[0] === "autocomplete" && command.length > 1) {
                list.search.text = `${CortetsuConfig.actionPrefix}${command[1]} `;
            } else if (sleepMode) {
                list.screenState.launcher = false;
                CortetsuSession.request(sleepMode);
            } else {
                list.screenState.launcher = false;
                CortetsuProcessLauncher.launchPersistent(command, "", name);
            }
        }
    }
}

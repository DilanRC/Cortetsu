import QtQuick
import Quickshell
import "../services"

Scope {
    id: root

    property real lastPercentage: 100
    property bool criticalNoticeSent: false

    function notify(title: string, message: string): void {
        Quickshell.execDetached(["notify-send", "--app-name=Cortetsu", title, message]);
    }

    function inspect(): void {
        if (!CortetsuPower.hasBattery)
            return;
        const percentage = CortetsuPower.percent;
        if (!CortetsuPower.onBattery) {
            lastPercentage = percentage;
            criticalNoticeSent = false;
            return;
        }
        if (percentage <= 10 && lastPercentage > 10)
            notify(qsTr("Batería baja"), qsTr("El nivel de batería es %1%").arg(Math.round(percentage)));
        if (percentage <= 3 && !criticalNoticeSent) {
            criticalNoticeSent = true;
            notify(qsTr("Batería crítica"), qsTr("El equipo se dormirá en 5 segundos para evitar la pérdida de datos"));
            // The answer cached at startup can be stale (an inhibitor that has
            // since gone away); ask again before choosing the mode.
            CortetsuSession.refreshCapabilities();
            criticalSleep.start();
        }
        lastPercentage = percentage;
    }

    Connections {
        target: CortetsuPower
        function onOnBatteryChanged(): void { root.inspect(); }
        function onReadyChanged(): void { root.inspect(); }
        function onPercentChanged(): void { root.inspect(); }
    }
    // startup inventory: cortetsu:battery-notification
    Component.onCompleted: root.inspect()
    // The notice names the mode that actually runs.
    // startup inventory: cortetsu:battery-sleep
    Timer {
        id: criticalSleep
        interval: 5000
        onTriggered: {
            if (CortetsuSession.hibernate())
                root.notify(qsTr("Batería crítica"), qsTr("Hibernando"));
            else if (CortetsuSession.suspend())
                root.notify(qsTr("Batería crítica"), qsTr("Este equipo no puede hibernar; suspendiendo"));
            else
                root.notify(qsTr("Batería crítica"), qsTr("No se puede hibernar ni suspender. Conecta el cargador"));
        }
    }
}

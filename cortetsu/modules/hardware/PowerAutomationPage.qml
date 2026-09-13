pragma ComponentBehavior: Bound

import QtQuick
import ".."
import "../CortetsuDesign.js" as CortetsuDesign
import "../CortetsuTypography.js" as CortetsuTypography
import QtCore
import Quickshell.Io

Item {
    id: root

    property var automation: ({})
    property string statusText: qsTr("Leyendo estado de automatización…")
    property var controlArgs: []
    property bool actionBusy: false

    readonly property string controlPath:
        StandardPaths.writableLocation(StandardPaths.HomeLocation) +
        "/.local/bin/cortetsu-power-auto-control"

    readonly property var config: automation?.config ?? ({})
    readonly property var service: automation?.service ?? ({})
    readonly property var last: automation?.last ?? ({})
    readonly property var events: automation?.events ?? []

    function profileLabel(name): string {
        if (name === "power-saver") return qsTr("Power saver");
        if (name === "performance") return qsTr("Performance");
        if (name === "balanced") return qsTr("Equilibrado");
        return qsTr("Desconocido");
    }

    function profileIcon(name): string {
        if (name === "power-saver") return "eco";
        if (name === "performance") return "speed";
        return "balance";
    }

    function sourceLabel(event): string {
        if (event?.source === "ac") return qsTr("Corriente alterna");
        if (event?.source === "battery") return qsTr("Batería");
        return "—";
    }

    function timeText(timestamp): string {
        if (!timestamp)
            return "—";
        const d = new Date(Number(timestamp) * 1000);
        return `${String(d.getHours()).padStart(2, "0")}:${String(d.getMinutes()).padStart(2, "0")}:${String(d.getSeconds()).padStart(2, "0")}`;
    }

    function refresh(): void {
        if (!statusProbe.running && !root.actionBusy)
            statusProbe.running = true;
    }

    function runControl(args, message): void {
        if (root.actionBusy)
            return;
        root.controlArgs = Array.from(args);
        root.actionBusy = true;
        root.statusText = message || qsTr("Aplicando cambio…");
        controlProcess.running = true;
    }

    function setProfile(slot, profile): void {
        runControl(["set-profile", slot, profile], qsTr("Actualizando perfil automático…"));
    }

    function threshold(delta): void {
        const current = Number(config?.low_battery_threshold ?? 25);
        runControl(
            ["set-threshold", String(Math.max(5, Math.min(80, current + delta)))],
            qsTr("Actualizando umbral de batería baja…")
        );
    }

    function updateFromResult(parsed): void {
        if (parsed?.config !== undefined)
            root.automation = parsed;
        else
            root.refresh();

        if (parsed?.ok === false)
            root.statusText = parsed?.error ? String(parsed.error) : qsTr("La acción falló");
        else if (parsed?.service?.active)
            root.statusText = qsTr("Servicio de automatización activo");
        else if (parsed?.config?.enabled)
            root.statusText = qsTr("La automatización está activa, pero el servicio no lo está");
        else
            root.statusText = qsTr("Automatización desactivada · sin monitor en segundo plano");
    }

    Component.onCompleted: { if (root.visible) refresh(); }
    onVisibleChanged: { if (visible) refresh(); }

    Timer {
        interval: 3500
        repeat: true
        running: root.visible
        onTriggered: root.refresh()
    }

    Process {
        id: statusProbe
        command: [root.controlPath, "status"]

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const parsed = JSON.parse(text.trim());
                    root.automation = parsed;
                    root.statusText = parsed?.service?.active
                        ? qsTr("Servicio de automatización activo")
                        : (parsed?.config?.enabled
                            ? qsTr("La automatización está activa, pero el servicio no lo está")
                            : qsTr("Automatización desactivada · sin monitor en segundo plano"));
                } catch (error) {
                    root.statusText = qsTr("Estado de automatización no disponible");
                }
            }
        }
    }

    Process {
        id: controlProcess
        command: [root.controlPath].concat(root.controlArgs)

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.updateFromResult(JSON.parse(text.trim()));
                } catch (error) {
                    root.statusText = qsTr("La acción de automatización devolvió una respuesta no válida");
                }
                root.actionBusy = false;
                refreshAfterAction.restart();
            }
        }
    }

    Timer {
        id: refreshAfterAction
        interval: 450
        repeat: false
        onTriggered: root.refresh()
    }

    Column {
        anchors.fill: parent
        spacing: 12

        Rectangle {
            width: parent.width
            height: 126
            radius: CortetsuDesign.radiusLarge
            color: CortetsuDesign.colorSurface
            border.width: 1
            border.color: CortetsuDesign.colorOutlineVariant

            Row {
                anchors.fill: parent
                anchors.margins: 16
                spacing: 18

                Rectangle {
                    width: 52
                    height: 52
                    anchors.verticalCenter: parent.verticalCenter
                    radius: CortetsuDesign.radiusLarge
                    color: config?.enabled
                        ? CortetsuDesign.colorPrimaryContainer
                        : CortetsuDesign.colorSurfaceHigh

                    CortetsuIcon {
                        anchors.centerIn: parent
                        text: root.actionBusy ? "progress_activity" : "auto_mode"
                        color: config?.enabled
                            ? CortetsuDesign.colorOnPrimaryContainer
                            : CortetsuDesign.colorOnSurfaceVariant
                        iconSize: CortetsuTypography.iconExtraLargePx
                    }
                }

                Column {
                    width: parent.width - 52 - toggleButton.width - 54
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 3

                    CortetsuText {
                        text: qsTr("Perfiles de energía automáticos")
                        color: CortetsuDesign.colorOnSurface
                        textSize: CortetsuTypography.titleMediumPx
                    }

                    CortetsuText {
                        width: parent.width
                        text: qsTr("Reglas de corriente alterna, batería y batería baja. Desactivado significa que no hay monitor en segundo plano.")
                        color: CortetsuDesign.colorOnSurfaceVariant
                        textSize: CortetsuTypography.bodySmallPx
                        wrapMode: Text.WordWrap
                    }

                    CortetsuText {
                        width: parent.width
                        text: root.statusText
                        color: service?.active ? CortetsuDesign.colorPrimary : CortetsuDesign.colorOutline
                        textSize: CortetsuTypography.labelSmallPx
                        elide: Text.ElideRight
                    }
                }

                Rectangle {
                    id: toggleButton
                    width: 142
                    height: 48
                    anchors.verticalCenter: parent.verticalCenter
                    radius: CortetsuDesign.radiusMedium
                    color: config?.enabled
                        ? CortetsuDesign.colorSecondaryContainer
                        : CortetsuDesign.colorSurfaceHigh
                    border.width: config?.enabled ? 1 : 0
                    border.color: CortetsuDesign.colorPrimary
                    opacity: root.actionBusy ? 0.55 : 1

                    CortetsuStateLayer {
                        radius: parent.radius
                        enabled: !root.actionBusy
                        onClicked: root.runControl(
                            ["set-enabled", config?.enabled ? "false" : "true"],
                            config?.enabled ? qsTr("Stopping automation…") : qsTr("Starting automation…")
                        )
                    }

                    Row {
                        anchors.centerIn: parent
                        spacing: 7
                        CortetsuIcon {
                            text: config?.enabled ? "toggle_on" : "toggle_off"
                            color: config?.enabled
                                ? CortetsuDesign.colorOnSecondaryContainer
                                : CortetsuDesign.colorOnSurfaceVariant
                            iconSize: CortetsuTypography.iconMediumPx
                        }
                        CortetsuText {
                            text: config?.enabled ? qsTr("Enabled") : qsTr("Disabled")
                            color: config?.enabled
                                ? CortetsuDesign.colorOnSecondaryContainer
                                : CortetsuDesign.colorOnSurfaceVariant
                            textSize: CortetsuTypography.labelMediumPx
                        }
                    }
                }
            }
        }

        Grid {
            id: scenarioGrid
            width: parent.width
            height: 192
            columns: 2
            columnSpacing: 12

            Repeater {
                model: [
                    {
                        title: qsTr("On AC power"),
                        subtitle: qsTr("External power source online"),
                        icon: "power",
                        slot: "ac",
                        value: config?.ac_profile ?? "performance"
                    },
                    {
                        title: qsTr("On battery"),
                        subtitle: qsTr("Normal battery rule above the low threshold"),
                        icon: "battery_5_bar",
                        slot: "battery",
                        value: config?.battery_profile ?? "balanced"
                    }
                ]

                delegate: Rectangle {
                    id: scenarioCard
                    required property var modelData
                    width: (scenarioGrid.width - 12) / 2
                    height: scenarioGrid.height
                    radius: CortetsuDesign.radiusLarge
                    color: CortetsuDesign.colorSurface
                    border.width: 1
                    border.color: CortetsuDesign.colorOutlineVariant

                    Column {
                        anchors.fill: parent
                        anchors.margins: 16
                        spacing: 11

                        Row {
                            width: parent.width
                            spacing: 10

                            Rectangle {
                                width: 42
                                height: 42
                                radius: CortetsuDesign.radiusMedium
                                color: CortetsuDesign.colorSecondaryContainer
                                CortetsuIcon {
                                    anchors.centerIn: parent
                                    text: scenarioCard.modelData.icon
                                    color: CortetsuDesign.colorOnSecondaryContainer
                                    iconSize: CortetsuTypography.iconLargePx
                                }
                            }

                            Column {
                                width: parent.width - 52
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 1
                                CortetsuText {
                                    text: scenarioCard.modelData.title
                                    color: CortetsuDesign.colorOnSurface
                                    textSize: CortetsuTypography.titleSmallPx
                                }
                                CortetsuText {
                                    width: parent.width
                                    text: scenarioCard.modelData.subtitle
                                    color: CortetsuDesign.colorOutline
                                    textSize: CortetsuTypography.labelSmallPx
                                    elide: Text.ElideRight
                                }
                            }
                        }

                        Row {
                            width: parent.width
                            spacing: 8

                            Repeater {
                                model: ["power-saver", "balanced", "performance"]

                                delegate: Rectangle {
                                    id: profileChoice
                                    required property string modelData
                                    readonly property bool active: modelData === scenarioCard.modelData.value
                                    width: (parent.width - 16) / 3
                                    height: 78
                                    radius: CortetsuDesign.radiusMedium
                                    color: active
                                        ? CortetsuDesign.colorSecondaryContainer
                                        : CortetsuDesign.colorSurfaceHigh
                                    border.width: active ? 1 : 0
                                    border.color: CortetsuDesign.colorPrimary

                                    CortetsuStateLayer {
                                        radius: parent.radius
                                        enabled: !root.actionBusy
                                        onClicked: root.setProfile(scenarioCard.modelData.slot, profileChoice.modelData)
                                    }

                                    Column {
                                        anchors.centerIn: parent
                                        spacing: 5
                                        CortetsuIcon {
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            text: root.profileIcon(profileChoice.modelData)
                                            color: profileChoice.active
                                                ? CortetsuDesign.colorOnSecondaryContainer
                                                : CortetsuDesign.colorOnSurfaceVariant
                                            iconSize: CortetsuTypography.iconMediumPx
                                        }
                                        CortetsuText {
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            text: root.profileLabel(profileChoice.modelData)
                                            color: profileChoice.active
                                                ? CortetsuDesign.colorOnSecondaryContainer
                                                : CortetsuDesign.colorOnSurfaceVariant
                                            textSize: CortetsuTypography.labelSmallPx
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        Grid {
            width: parent.width
            height: parent.height - 342
            columns: 2
            columnSpacing: 12

            Rectangle {
                width: (parent.width - 12) / 2
                height: parent.height
                radius: CortetsuDesign.radiusLarge
                color: CortetsuDesign.colorSurface
                border.width: 1
                border.color: CortetsuDesign.colorOutlineVariant

                Column {
                    anchors.fill: parent
                    anchors.margins: 16
                    spacing: 11

                    Row {
                        width: parent.width

                        Column {
                            width: parent.width - lowToggle.width - 12
                            spacing: 2
                            CortetsuText {
                                text: qsTr("Low battery override")
                                color: CortetsuDesign.colorOnSurface
                                textSize: CortetsuTypography.titleSmallPx
                            }
                            CortetsuText {
                                width: parent.width
                                text: qsTr("A separate profile can take over below the selected threshold.")
                                color: CortetsuDesign.colorOutline
                                textSize: CortetsuTypography.labelSmallPx
                                wrapMode: Text.WordWrap
                            }
                        }

                        Rectangle {
                            id: lowToggle
                            width: 90
                            height: 38
                            radius: CortetsuDesign.radiusMedium
                            color: config?.low_battery_enabled
                                ? CortetsuDesign.colorSecondaryContainer
                                : CortetsuDesign.colorSurfaceHigh
                            CortetsuStateLayer {
                                radius: parent.radius
                                enabled: !root.actionBusy
                                onClicked: root.runControl(
                                    ["set-low-enabled", config?.low_battery_enabled ? "false" : "true"],
                                    qsTr("Actualizando regla de batería baja…")
                                )
                            }
                            CortetsuText {
                                anchors.centerIn: parent
                                text: config?.low_battery_enabled ? qsTr("Enabled") : qsTr("Off")
                                color: config?.low_battery_enabled
                                    ? CortetsuDesign.colorOnSecondaryContainer
                                    : CortetsuDesign.colorOnSurfaceVariant
                                textSize: CortetsuTypography.labelSmallPx
                            }
                        }
                    }

                    Row {
                        width: parent.width
                        height: 46
                        spacing: 8

                        Rectangle {
                            width: 46
                            height: 46
                            radius: CortetsuDesign.radiusMedium
                            color: CortetsuDesign.colorSurfaceHigh
                            CortetsuStateLayer { radius: parent.radius; enabled: !root.actionBusy; onClicked: root.threshold(-5) }
                            CortetsuIcon { anchors.centerIn: parent; text: "remove"; color: CortetsuDesign.colorOnSurfaceVariant }
                        }
                        Column {
                            width: parent.width - 108
                            anchors.verticalCenter: parent.verticalCenter
                            CortetsuText {
                                width: parent.width
                                text: `${Number(config?.low_battery_threshold ?? 25)}%`
                                color: CortetsuDesign.colorPrimary
                                textSize: CortetsuTypography.titleMediumPx
                                horizontalAlignment: Text.AlignHCenter
                            }
                            CortetsuText {
                                width: parent.width
                                text: qsTr("low-battery threshold")
                                color: CortetsuDesign.colorOutline
                                textSize: CortetsuTypography.labelSmallPx
                                horizontalAlignment: Text.AlignHCenter
                            }
                        }
                        Rectangle {
                            width: 46
                            height: 46
                            radius: CortetsuDesign.radiusMedium
                            color: CortetsuDesign.colorSurfaceHigh
                            CortetsuStateLayer { radius: parent.radius; enabled: !root.actionBusy; onClicked: root.threshold(5) }
                            CortetsuIcon { anchors.centerIn: parent; text: "add"; color: CortetsuDesign.colorOnSurfaceVariant }
                        }
                    }

                    Row {
                        width: parent.width
                        spacing: 8
                        Repeater {
                            model: ["power-saver", "balanced", "performance"]
                            delegate: Rectangle {
                                id: lowChoice
                                required property string modelData
                                readonly property bool active: modelData === (config?.low_battery_profile ?? "power-saver")
                                width: (parent.width - 16) / 3
                                height: 54
                                radius: CortetsuDesign.radiusMedium
                                color: active ? CortetsuDesign.colorSecondaryContainer : CortetsuDesign.colorSurfaceHigh
                                CortetsuStateLayer {
                                    radius: parent.radius
                                    enabled: !root.actionBusy
                                    onClicked: root.setProfile("low", lowChoice.modelData)
                                }
                                CortetsuText {
                                    anchors.centerIn: parent
                                    text: root.profileLabel(lowChoice.modelData)
                                    color: lowChoice.active
                                        ? CortetsuDesign.colorOnSecondaryContainer
                                        : CortetsuDesign.colorOnSurfaceVariant
                                    textSize: CortetsuTypography.labelSmallPx
                                }
                            }
                        }
                    }

                    Rectangle {
                        width: parent.width
                        height: 42
                        radius: CortetsuDesign.radiusMedium
                        color: CortetsuDesign.colorPrimaryContainer
                        CortetsuStateLayer {
                            radius: parent.radius
                            enabled: !root.actionBusy
                            onClicked: root.runControl(["apply-now"], qsTr("Aplicando la regla actual una vez…"))
                        }
                        Row {
                            anchors.centerIn: parent
                            spacing: 7
                            CortetsuIcon {
                                text: "play_arrow"
                                color: CortetsuDesign.colorOnPrimaryContainer
                                iconSize: CortetsuTypography.iconSmallPx
                            }
                            CortetsuText {
                                text: qsTr("Apply current rule once")
                                color: CortetsuDesign.colorOnPrimaryContainer
                                textSize: CortetsuTypography.labelMediumPx
                            }
                        }
                    }

                    CortetsuText {
                        width: parent.width
                        text: qsTr("Aplicar una vez funciona aunque la automatización esté desactivada; no activa el monitor.")
                        color: CortetsuDesign.colorOutline
                        textSize: CortetsuTypography.labelSmallPx
                        wrapMode: Text.WordWrap
                    }
                }
            }

            Rectangle {
                width: (parent.width - 12) / 2
                height: parent.height
                radius: CortetsuDesign.radiusLarge
                color: CortetsuDesign.colorSurface
                border.width: 1
                border.color: CortetsuDesign.colorOutlineVariant

                Column {
                    anchors.fill: parent
                    anchors.margins: 16
                    spacing: 8

                    Row {
                        width: parent.width

                        CortetsuText {
                            width: parent.width - eventActions.width - 10
                        text: qsTr("Estado y eventos de automatización")
                            color: CortetsuDesign.colorOnSurface
                            textSize: CortetsuTypography.titleSmallPx
                        }

                        Row {
                            id: eventActions
                            spacing: 6

                            Rectangle {
                                width: 76
                                height: 32
                                radius: CortetsuDesign.radiusSmall
                                color: CortetsuDesign.colorSurfaceHigh
                                CortetsuStateLayer {
                                    radius: parent.radius
                                    enabled: !root.actionBusy
                                    onClicked: root.runControl(["reset-defaults"], qsTr("Restaurando reglas predeterminadas…"))
                                }
                                CortetsuText {
                                    anchors.centerIn: parent
                                    text: qsTr("Predeterminadas")
                                    color: CortetsuDesign.colorOnSurfaceVariant
                                    textSize: CortetsuTypography.labelSmallPx
                                }
                            }

                            Rectangle {
                                width: 68
                                height: 32
                                radius: CortetsuDesign.radiusSmall
                                color: CortetsuDesign.colorSurfaceHigh
                                CortetsuStateLayer {
                                    radius: parent.radius
                                    enabled: !root.actionBusy
                                    onClicked: root.runControl(["clear-events"], qsTr("Borrando historial de eventos…"))
                                }
                                CortetsuText {
                                    anchors.centerIn: parent
                                    text: qsTr("Limpiar")
                                    color: CortetsuDesign.colorOnSurfaceVariant
                                    textSize: CortetsuTypography.labelSmallPx
                                }
                            }
                        }
                    }

                    Repeater {
                        model: [
                            { label: qsTr("Servicio"), value: service?.active ? qsTr("Activo") : qsTr("Detenido") },
                            { label: qsTr("Actual / deseado"), value: `${root.profileLabel(last?.profile ?? "")} → ${root.profileLabel(last?.desired_profile ?? "")}` },
                            { label: qsTr("Motivo"), value: last?.reason ?? qsTr("Aún no hay cambios automáticos") },
                            { label: qsTr("Batería"), value: last?.battery_percent !== undefined && last?.battery_percent !== null ? `${last.battery_percent}%` : "—" }
                        ]

                        delegate: Row {
                            required property var modelData
                            width: parent.width
                            height: 22
                            CortetsuText {
                                width: parent.width * 0.38
                                text: modelData.label
                                color: CortetsuDesign.colorOutline
                                textSize: CortetsuTypography.labelSmallPx
                            }
                            CortetsuText {
                                width: parent.width * 0.62
                                text: modelData.value
                                color: CortetsuDesign.colorOnSurfaceVariant
                                textSize: CortetsuTypography.labelSmallPx
                                horizontalAlignment: Text.AlignRight
                                elide: Text.ElideLeft
                            }
                        }
                    }

                    CortetsuText {
                        text: qsTr("Recent profile events")
                        color: CortetsuDesign.colorOnSurfaceVariant
                        textSize: CortetsuTypography.labelMediumPx
                    }

                    Repeater {
                        model: Array.from(root.events ?? []).slice(0, 5)

                        delegate: Rectangle {
                            required property var modelData
                            width: parent.width
                            height: 34
                            radius: CortetsuDesign.radiusSmall
                            color: CortetsuDesign.colorSurfaceHigh

                            Row {
                                anchors.fill: parent
                                anchors.leftMargin: 9
                                anchors.rightMargin: 9

                                CortetsuText {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width * 0.18
                                    text: root.timeText(modelData?.timestamp)
                                    color: CortetsuDesign.colorOutline
                                    textSize: CortetsuTypography.labelSmallPx
                                }
                                CortetsuText {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width * 0.17
                                    text: root.sourceLabel(modelData)
                                    color: CortetsuDesign.colorOnSurfaceVariant
                                    textSize: CortetsuTypography.labelSmallPx
                                }
                                CortetsuText {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width * 0.29
                                    text: root.profileLabel(modelData?.profile ?? modelData?.desired_profile ?? "")
                                    color: modelData?.ok === false ? CortetsuDesign.colorVermillion : CortetsuDesign.colorPrimary
                                    textSize: CortetsuTypography.labelSmallPx
                                    elide: Text.ElideRight
                                }
                                CortetsuText {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width * 0.36
                                    text: modelData?.reason ?? modelData?.error ?? "—"
                                    color: CortetsuDesign.colorOnSurfaceVariant
                                    textSize: CortetsuTypography.labelSmallPx
                                    horizontalAlignment: Text.AlignRight
                                    elide: Text.ElideLeft
                                }
                            }
                        }
                    }

                    CortetsuText {
                        visible: root.events.length === 0
                        text: qsTr("Aún no se han registrado eventos automáticos de perfiles.")
                        color: CortetsuDesign.colorOutline
                        textSize: CortetsuTypography.bodySmallPx
                    }
                }
            }
        }
    }
}

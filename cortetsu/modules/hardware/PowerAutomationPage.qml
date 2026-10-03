pragma ComponentBehavior: Bound

import QtQuick
import ".."
import "../../components"
import "../../theme"
import "../CortetsuTypography.js" as CortetsuTypography
import "summary"
import "Format.js" as Format
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
        const labels = { "power-saver": qsTr("Ahorro"), "balanced": qsTr("Equilibrado"), "performance": qsTr("Rendimiento") };
        return labels[name] ?? "";
    }

    // The watcher reports why it chose a profile in its own words.
    function reasonLabel(reason): string {
        const text = String(reason ?? "");
        const known = {
            "AC connected": qsTr("Conectado a la corriente"),
            "on battery": qsTr("En batería"),
            "automation disabled": qsTr("Automatización desactivada")
        };
        if (known[text])
            return known[text];
        return text.startsWith("battery") ? qsTr("Batería baja") : text;
    }

    function sourceLabel(event): string {
        if (event?.source === "ac") return qsTr("Corriente");
        if (event?.source === "battery") return qsTr("Batería");
        return "";
    }

    function timeText(timestamp): string {
        return timestamp ? Format.clock(new Date(Number(timestamp) * 1000), CortetsuConfig.useTwelveHourClock) : "";
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

    // startup inventory: cortetsu:hardware-power-automation-status
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

    readonly property bool enabledNow: root.config?.enabled === true
    readonly property bool lowEnabled: root.config?.low_battery_enabled === true
    readonly property int lowThreshold: Number(root.config?.low_battery_threshold ?? 25)
    readonly property var recentEvents: Array.from(root.events ?? []).slice(0, 5)

    Column {
        anchors.fill: parent
        spacing: CortetsuDesign.spacingStandard

        Panel {
            width: parent.width
            height: 76

            SummaryLabel {
                id: title
                icon: "auto_mode"
                text: qsTr("Cambio automático de perfil")
                anchors.rightMargin: 180
            }

            CortetsuText {
                anchors.left: parent.left
                anchors.right: switchRow.left
                anchors.rightMargin: CortetsuDesign.spacingStandard
                anchors.bottom: parent.bottom
                text: root.statusText
                color: CortetsuDesign.colorOnSurfaceVariant
                textSize: CortetsuTypography.bodySmallPx
                elide: Text.ElideRight
            }

            Row {
                id: switchRow
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: CortetsuDesign.spacingStandard

                CortetsuText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.enabledNow ? qsTr("Activado") : qsTr("Desactivado")
                    color: CortetsuDesign.colorOnSurfaceMuted
                    textSize: CortetsuTypography.bodyPx
                }

                CortetsuToggle {
                    objectName: "automationToggle"
                    anchors.verticalCenter: parent.verticalCenter
                    checked: root.enabledNow
                    disabled: root.actionBusy
                    Accessible.name: qsTr("Cambio automático de perfil")
                    onToggled: root.runControl(
                        ["set-enabled", root.enabledNow ? "false" : "true"],
                        root.enabledNow ? qsTr("Deteniendo la automatización…") : qsTr("Iniciando la automatización…"))
                }
            }
        }

        Panel {
            width: parent.width
            height: rules.implicitHeight + padding * 2

            Column {
                id: rules
                width: parent.width
                spacing: CortetsuDesign.spacingStandard

                SummaryLabel {
                    icon: "rule"
                    text: qsTr("Reglas")
                    detail: qsTr("Qué perfil se aplica en cada situación")
                    anchors.rightMargin: 0
                }

                Rule {
                    width: parent.width
                    icon: "power"
                    title: qsTr("Con corriente")
                    detail: qsTr("Cargador conectado")
                    slot: "ac"
                    value: root.config?.ac_profile ?? ""
                }

                Rule {
                    width: parent.width
                    icon: "battery_full"
                    title: qsTr("Con batería")
                    detail: qsTr("Por encima del umbral de batería baja")
                    slot: "battery"
                    value: root.config?.battery_profile ?? ""
                }

                Rule {
                    id: lowRule
                    width: parent.width
                    icon: "battery_alert"
                    title: qsTr("Batería baja")
                    detail: root.lowEnabled ? qsTr("Por debajo del %1 %").arg(root.lowThreshold) : qsTr("Regla desactivada")
                    slot: "low"
                    value: root.config?.low_battery_profile ?? ""
                    dimmed: !root.lowEnabled
                }

                Row {
                    x: lowRule.choicesX
                    spacing: CortetsuDesign.spacingStandard

                    CortetsuToggle {
                        anchors.verticalCenter: parent.verticalCenter
                        checked: root.lowEnabled
                        disabled: root.actionBusy
                        Accessible.name: qsTr("Regla de batería baja")
                        onToggled: root.runControl(
                            ["set-low-enabled", root.lowEnabled ? "false" : "true"],
                            qsTr("Actualizando regla de batería baja…"))
                    }

                    CortetsuText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: qsTr("Umbral")
                        color: CortetsuDesign.colorOnSurfaceVariant
                        textSize: CortetsuTypography.bodySmallPx
                    }

                    CortetsuButton {
                        compact: true
                        icon: "remove"
                        disabled: root.actionBusy || root.lowThreshold <= 5
                        tooltipText: qsTr("Bajar el umbral 5 puntos")
                        Accessible.name: qsTr("Bajar el umbral")
                        onClicked: root.threshold(-5)
                    }

                    CortetsuText {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 44
                        horizontalAlignment: Text.AlignHCenter
                        text: `${root.lowThreshold} %`
                        textSize: CortetsuTypography.bodyLargePx
                        font.weight: Font.DemiBold
                    }

                    CortetsuButton {
                        compact: true
                        icon: "add"
                        disabled: root.actionBusy || root.lowThreshold >= 80
                        tooltipText: qsTr("Subir el umbral 5 puntos")
                        Accessible.name: qsTr("Subir el umbral")
                        onClicked: root.threshold(5)
                    }
                }
            }
        }

        Panel {
            width: parent.width
            height: parent.height - y

            SummaryLabel {
                id: stateLabel
                icon: "history"
                text: qsTr("Estado")
                detail: root.service?.active ? qsTr("Servicio en ejecución") : qsTr("Servicio detenido")
                anchors.rightMargin: actions.width + CortetsuDesign.spacingStandard
            }

            Row {
                id: actions
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.topMargin: -4
                spacing: CortetsuDesign.spacingCompact

                CortetsuButton {
                    compact: true
                    icon: "play_arrow"
                    label: qsTr("Aplicar la regla ahora")
                    disabled: root.actionBusy
                    tooltipText: qsTr("Funciona con la automatización desactivada y no la activa")
                    onClicked: root.runControl(["apply-now"], qsTr("Aplicando la regla actual una vez…"))
                }

                CortetsuButton {
                    compact: true
                    icon: "restart_alt"
                    label: qsTr("Restaurar reglas")
                    disabled: root.actionBusy
                    onClicked: root.runControl(["reset-defaults"], qsTr("Restaurando reglas predeterminadas…"))
                }

                CortetsuButton {
                    compact: true
                    icon: "delete_sweep"
                    label: qsTr("Borrar historial")
                    disabled: root.actionBusy || root.events.length === 0
                    onClicked: root.runControl(["clear-events"], qsTr("Borrando historial de eventos…"))
                }
            }

            Row {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: stateLabel.bottom
                anchors.topMargin: CortetsuDesign.spacingStandard
                spacing: CortetsuDesign.spacingSpacious

                Column {
                    id: facts
                    width: Math.round((parent.width - parent.spacing) * 0.4)

                    FactRow { width: parent.width; label: qsTr("Perfil actual"); value: root.profileLabel(root.last?.profile ?? ""); emphasized: true }
                    FactRow { width: parent.width; label: qsTr("Perfil que pide la regla"); value: root.profileLabel(root.last?.desired_profile ?? "") }
                    FactRow { width: parent.width; label: qsTr("Motivo"); value: root.reasonLabel(root.last?.reason) }
                    FactRow { width: parent.width; label: qsTr("Batería en ese momento"); value: Format.percent(root.last?.battery_percent) }
                }

                Column {
                    id: history
                    width: parent.width - facts.width - parent.spacing

                    CortetsuText {
                        height: 28
                        verticalAlignment: Text.AlignVCenter
                        text: root.recentEvents.length > 0 ? qsTr("Últimos cambios") : qsTr("Todavía no hay cambios automáticos registrados")
                        color: CortetsuDesign.colorOnSurfaceVariant
                        textSize: CortetsuTypography.bodySmallPx
                    }

                    Repeater {
                        model: root.recentEvents.length

                        delegate: Item {
                            id: entry
                            required property int index
                            readonly property var event: root.recentEvents[entry.index] ?? ({})
                            readonly property bool failed: entry.event.ok === false

                            width: history.width
                            height: 28

                            CortetsuText {
                                id: when
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                width: 84
                                text: root.timeText(entry.event.timestamp)
                                color: CortetsuDesign.colorOnSurfaceVariant
                                textSize: CortetsuTypography.bodySmallPx
                            }

                            SeverityIcon {
                                id: failure
                                anchors.left: when.right
                                anchors.verticalCenter: parent.verticalCenter
                                severity: entry.failed ? "critical" : ""
                                iconSize: CortetsuTypography.iconSmallPx
                                rightPadding: 4
                            }

                            CortetsuText {
                                anchors.left: failure.visible ? failure.right : when.right
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                text: Format.join([
                                    root.profileLabel(entry.event.profile ?? entry.event.desired_profile ?? ""),
                                    entry.failed
                                        ? (entry.event.error ?? qsTr("No se pudo aplicar"))
                                        : (root.reasonLabel(entry.event.reason) || root.sourceLabel(entry.event))
                                ])
                                textSize: CortetsuTypography.bodySmallPx
                                elide: Text.ElideRight
                            }
                        }
                    }
                }
            }
        }
    }

    // A situation and the profile assigned to it.
    component Rule: Item {
        id: rule

        property string icon: ""
        property string title: ""
        property string detail: ""
        property string slot: ""
        property string value: ""
        property bool dimmed: false
        readonly property real choicesX: Math.round(rule.width * 0.3)

        height: 52

        CortetsuIcon {
            id: ruleIcon
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: rule.icon
            color: CortetsuDesign.colorOnSurfaceMuted
            iconSize: CortetsuTypography.iconMediumPx
        }

        Column {
            anchors.left: ruleIcon.right
            anchors.leftMargin: CortetsuDesign.spacingStandard
            anchors.verticalCenter: parent.verticalCenter
            width: rule.choicesX - ruleIcon.width - CortetsuDesign.spacingStandard * 2
            spacing: 1

            CortetsuText {
                width: parent.width
                text: rule.title
                textSize: CortetsuTypography.bodyPx
                font.weight: Font.DemiBold
                elide: Text.ElideRight
            }

            CortetsuText {
                width: parent.width
                text: rule.detail
                color: CortetsuDesign.colorOnSurfaceVariant
                textSize: CortetsuTypography.labelSmallPx
                elide: Text.ElideRight
            }
        }

        Row {
            id: ruleChoices
            x: rule.choicesX
            width: rule.width - rule.choicesX
            height: parent.height
            spacing: CortetsuDesign.spacingStandard
            opacity: rule.dimmed ? 0.55 : 1

            Repeater {
                model: ["power-saver", "balanced", "performance"]

                delegate: ProfileChoice {
                    required property string modelData

                    width: (ruleChoices.width - ruleChoices.spacing * 2) / 3
                    height: ruleChoices.height
                    profile: modelData
                    selected: rule.value === modelData
                    disabled: root.actionBusy
                    onChosen: root.setProfile(rule.slot, modelData)
                }
            }
        }
    }
}

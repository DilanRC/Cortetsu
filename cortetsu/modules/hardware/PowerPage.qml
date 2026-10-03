pragma ComponentBehavior: Bound

import QtQuick
import ".."
import "../../components"
import "../../theme"
import "../CortetsuTypography.js" as CortetsuTypography
import "summary"
import "Format.js" as Format
import QtCore
import Quickshell
import Quickshell.Io

Item {
    id: root

    property var power: ({})
    property string statusText: qsTr("Leyendo política de energía…")
    property string pendingProfile: ""

    readonly property string helperPath:
        StandardPaths.writableLocation(StandardPaths.HomeLocation) +
        "/.local/bin/cortetsu-hardware-power"

    readonly property var profiles: power?.profiles ?? ({})
    readonly property var cpu: power?.cpu ?? ({})
    readonly property var ac: power?.ac ?? ({})
    readonly property var battery: power?.battery ?? ({})
    readonly property var gpus: power?.gpus ?? []

    function profileAvailable(name): bool {
        return Array.from(root.profiles?.available ?? []).includes(name);
    }

    function profileLabel(name): string {
        const labels = { "power-saver": qsTr("Ahorro"), "balanced": qsTr("Equilibrado"), "performance": qsTr("Rendimiento") };
        return labels[name] ?? (name || qsTr("Desconocido"));
    }

    function refresh(): void {
        if (!powerProbe.running)
            powerProbe.running = true;
    }

    function requestProfile(name): void {
        if (!root.profiles?.can_set || !profileAvailable(name) || root.pendingProfile.length > 0)
            return;
        root.pendingProfile = name;
        root.statusText = qsTr("Aplicando %1…").arg(profileLabel(name));
        Quickshell.execDetached([root.helperPath, "set-profile", name]);
        refreshAfterAction.restart();
        verifyAction.restart();
    }

    Component.onCompleted: { if (root.visible) refresh(); }
    onVisibleChanged: { if (visible) refresh(); }

    Timer {
        interval: 2500
        repeat: true
        running: root.visible
        onTriggered: root.refresh()
    }

    Timer {
        id: refreshAfterAction
        interval: 900
        repeat: false
        onTriggered: root.refresh()
    }

    Timer {
        id: verifyAction
        interval: 2600
        repeat: false
        onTriggered: {
            if (root.pendingProfile.length > 0) {
                root.statusText = qsTr("No se pudo comprobar el cambio de perfil");
                root.pendingProfile = "";
            }
        }
    }

    // startup inventory: cortetsu:hardware-power-probe
    Process {
        id: powerProbe
        command: [root.helperPath]

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const parsed = JSON.parse(text.trim());
                    root.power = parsed;
                    const current = parsed?.profiles?.current ?? "";
                    if (root.pendingProfile.length > 0 && current === root.pendingProfile) {
                        root.statusText = qsTr("Perfil aplicado: %1").arg(root.profileLabel(current));
                        root.pendingProfile = "";
                        verifyAction.stop();
                    } else if (root.pendingProfile.length === 0) {
                        root.statusText = parsed?.profiles?.backend === "powerprofilesctl"
                            ? qsTr("Los cambios se aplican con power-profiles-daemon")
                            : qsTr("Solo lectura: no hay un servicio de perfiles de energía en este equipo");
                    }
                } catch (error) {
                    root.statusText = qsTr("La sonda de energía no devolvió datos válidos");
                    console.warn(`Hardware Center Power: invalid JSON: ${error}`);
                }
            }
        }
    }

    readonly property var batteryStates: ({
        "Charging": qsTr("cargando"),
        "Discharging": qsTr("en uso"),
        "Full": qsTr("cargada"),
        "Not charging": qsTr("conectada, sin cargar")
    })

    Column {
        anchors.fill: parent
        spacing: CortetsuDesign.spacingStandard

        Panel {
            width: parent.width
            height: profile.implicitHeight + padding * 2

            Column {
                id: profile
                width: parent.width
                spacing: CortetsuDesign.spacingStandard

                SummaryLabel {
                    icon: "bolt"
                    text: qsTr("Perfil de energía")
                    detail: root.statusText
                    anchors.rightMargin: 0
                }

                Row {
                    id: choices
                    width: parent.width
                    spacing: CortetsuDesign.spacingStandard

                    Repeater {
                        model: ["power-saver", "balanced", "performance"]

                        delegate: ProfileChoice {
                            required property string modelData
                            readonly property bool supported: root.profileAvailable(modelData)

                            width: (choices.width - choices.spacing * 2) / 3
                            profile: modelData
                            selected: root.profiles?.current === modelData
                            busy: root.pendingProfile === modelData
                            disabled: !supported || !root.profiles?.can_set || root.pendingProfile.length > 0
                            note: !supported
                                ? qsTr("No disponible en este equipo")
                                : selected ? qsTr("Activo") : busy ? qsTr("Aplicando…") : ""
                            onChosen: root.requestProfile(modelData)
                        }
                    }
                }
            }
        }

        Row {
            width: parent.width
            spacing: CortetsuDesign.spacingStandard

            Panel {
                id: cpuPanel
                width: (parent.width - parent.spacing) / 2
                height: Math.max(cpuFacts.implicitHeight, sourceFacts.implicitHeight) + padding * 2

                Column {
                    id: cpuFacts
                    width: parent.width
                    spacing: 0

                    SummaryLabel {
                        icon: "memory"
                        text: qsTr("Procesador")
                        detail: root.cpu?.driver ?? ""
                    }

                    Item { width: 1; height: CortetsuDesign.spacingCompact }

                    FactRow { width: parent.width; label: qsTr("Frecuencia actual"); value: Format.gigahertz(root.cpu?.current_mhz); emphasized: true }
                    FactRow {
                        width: parent.width
                        label: qsTr("Rango de frecuencias")
                        value: root.cpu?.min_mhz && root.cpu?.max_mhz
                            ? `${Format.fixed(root.cpu.min_mhz / 1000, 1)} a ${Format.fixed(root.cpu.max_mhz / 1000, 1)} GHz`
                            : ""
                    }
                    FactRow { width: parent.width; label: qsTr("Gobernador"); value: root.cpu?.governor ?? "" }
                    FactRow { width: parent.width; label: qsTr("Preferencia de energía (EPP)"); value: root.cpu?.epp ?? "" }
                    FactRow { width: parent.width; label: qsTr("Perfil de plataforma"); value: root.cpu?.platform_profile ?? "" }
                }
            }

            Panel {
                width: cpuPanel.width
                height: cpuPanel.height

                Column {
                    id: sourceFacts
                    width: parent.width
                    spacing: 0

                    SummaryLabel {
                        icon: root.ac?.online ? "power" : "battery_full"
                        text: qsTr("Alimentación")
                    }

                    Item { width: 1; height: CortetsuDesign.spacingCompact }

                    FactRow {
                        width: parent.width
                        label: qsTr("Fuente")
                        value: root.power?.ac === undefined
                            ? ""
                            : root.ac?.online ? qsTr("Conectado a la corriente") : qsTr("Batería")
                        emphasized: true
                    }
                    FactRow {
                        width: parent.width
                        label: qsTr("Batería")
                        value: root.power?.battery === undefined
                            ? ""
                            : !root.battery?.present
                                ? qsTr("Este equipo no tiene")
                                : Format.join([Format.percent(root.battery.percent), root.batteryStates[root.battery.status] ?? ""])
                    }
                    FactRow { visible: !!root.battery?.present; width: parent.width; label: qsTr("Flujo"); value: Format.watts(root.battery?.power_w) }
                    FactRow { visible: !!root.battery?.present; width: parent.width; label: qsTr("Capacidad"); value: Format.withUnit(root.battery?.energy_full_wh, 1, "Wh") }
                    FactRow { visible: !!root.battery?.present; width: parent.width; label: qsTr("Salud"); value: Format.percent(root.battery?.health_percent) }
                }
            }
        }

        Row {
            id: gpuRow
            width: parent.width
            spacing: CortetsuDesign.spacingStandard

            Repeater {
                // Index-based: a panel per GPU, updated in place by each reading.
                model: root.gpus.length

                delegate: Panel {
                    id: gpuPanel
                    required property int index
                    readonly property var gpu: root.gpus[gpuPanel.index] ?? ({})
                    readonly property bool nvidia: gpuPanel.gpu.vendor === "NVIDIA"

                    width: (gpuRow.width - gpuRow.spacing * (root.gpus.length - 1)) / Math.max(1, root.gpus.length)
                    height: gpuFacts.implicitHeight + padding * 2

                    Column {
                        id: gpuFacts
                        width: parent.width
                        spacing: 0

                        SummaryLabel {
                            icon: "view_in_ar"
                            text: gpuPanel.gpu.vendor ? qsTr("GPU %1").arg(gpuPanel.gpu.vendor) : qsTr("GPU")
                            detail: gpuPanel.nvidia ? (gpuPanel.gpu.name ?? "") : (gpuPanel.gpu.card ?? "")
                            anchors.rightMargin: 0
                        }

                        Item { width: 1; height: CortetsuDesign.spacingCompact }

                        FactRow {
                            width: parent.width
                            label: qsTr("Consumo")
                            value: gpuPanel.nvidia && Format.known(gpuPanel.gpu.power_limit_w)
                                ? qsTr("%1 de %2").arg(Format.watts(gpuPanel.gpu.power_w)).arg(Format.watts(gpuPanel.gpu.power_limit_w))
                                : Format.watts(gpuPanel.gpu.power_w)
                            emphasized: true
                        }
                        FactRow { width: parent.width; label: qsTr("Temperatura"); value: Format.celsius(gpuPanel.gpu.temp_c) }
                        FactRow { visible: gpuPanel.nvidia; width: parent.width; label: qsTr("Estado de rendimiento"); value: gpuPanel.gpu.pstate ?? "" }
                        FactRow { visible: gpuPanel.nvidia; width: parent.width; label: qsTr("Reloj gráfico"); value: Format.withUnit(gpuPanel.gpu.graphics_clock_mhz, 0, "MHz") }
                        FactRow { visible: !gpuPanel.nvidia; width: parent.width; label: qsTr("Nivel de rendimiento"); value: gpuPanel.gpu.performance_level ?? "" }
                        FactRow { visible: !gpuPanel.nvidia; width: parent.width; label: qsTr("Estado de energía"); value: gpuPanel.gpu.power_state ?? "" }
                        FactRow { visible: !gpuPanel.nvidia; width: parent.width; label: qsTr("Suspensión en ejecución"); value: gpuPanel.gpu.runtime_status ?? "" }
                    }
                }
            }
        }
    }
}

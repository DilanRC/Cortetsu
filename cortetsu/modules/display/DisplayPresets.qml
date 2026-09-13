pragma ComponentBehavior: Bound

import QtQuick
import QtCore
import Quickshell
import Quickshell.Io
import ".."
import "../../components"
import "../CortetsuDesign.js" as CortetsuDesign
import "../CortetsuTypography.js" as CortetsuTypography

Item {
    id: root

    required property var candidateOutputs
    signal candidateLoaded(var candidate)

    property var presets: []
    property string statusText: qsTr("Distribuciones guardadas")
    property string presetName: ""
    property string actionKind: ""
    readonly property string helperPath: StandardPaths.writableLocation(StandardPaths.HomeLocation) + "/.local/bin/cortetsu-display-presets"

    function run(kind, args): void {
        if (worker.running) return;
        actionKind = kind;
        worker.command = [helperPath, kind].concat(args);
        worker.running = true;
    }

    function refresh(): void { run("list", []); }

    function save(): void {
        if (!presetName.trim().length) {
            statusText = qsTr("Escribe un nombre primero");
            return;
        }
        run("save", ["--name", presetName.trim(), "--candidate", JSON.stringify({outputs:candidateOutputs})]);
    }

    function loadPreset(name): void { run("get", ["--name", name]); }
    function deletePreset(name): void { run("delete", ["--name", name]); }

    Component.onCompleted: refresh()

    Process {
        id: worker
        command: []
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const parsed = JSON.parse(text.trim());
                    if (!(parsed?.ok ?? false))
                        root.statusText = parsed?.error ?? qsTr("No se pudo ejecutar la acción del preajuste");
                    else if (root.actionKind === "list") {
                        root.presets = parsed?.presets ?? [];
                        root.statusText = root.presets.length ? qsTr("%1 guardados").arg(root.presets.length) : qsTr("No hay distribuciones guardadas");
                    } else if (root.actionKind === "get") {
                        root.candidateLoaded(parsed?.preset?.candidate ?? {});
                        root.statusText = qsTr("Cargado: %1").arg(parsed?.name ?? "");
                    } else {
                        root.statusText = root.actionKind === "save" ? qsTr("Guardado") : qsTr("Eliminado");
                        Qt.callLater(root.refresh);
                    }
                } catch(error) {
                    root.statusText = qsTr("Servicio de preajustes no disponible");
                }
            }
        }
    }

    Column {
        anchors.fill: parent
        anchors.margins: CortetsuDesign.spacingUnit
        spacing: CortetsuDesign.spacingCompact

        Row {
            width: parent.width
            height: 24

            CortetsuText {
                width: parent.width * 0.58
                text: qsTr("Distribuciones guardadas")
                color: CortetsuDesign.colorOnSurface
                textSize: CortetsuTypography.titleSmallPx
                font.weight: Font.DemiBold
            }
            CortetsuText {
                width: parent.width * 0.42
                text: root.statusText
                color: CortetsuDesign.colorOutline
                textSize: CortetsuTypography.labelSmallPx
                horizontalAlignment: Text.AlignRight
                elide: Text.ElideRight
            }
        }

        Row {
            width: parent.width
            height: 36
            spacing: CortetsuDesign.spacingCompact

            Item {
                width: parent.width - 76
                height: 36

                CortetsuSurface {
                    anchors.fill: parent
                    radiusValue: CortetsuDesign.radiusMedium
                    baseColor: Qt.alpha(CortetsuDesign.colorSurfaceGlass, 0.72)
                    outlineColor: nameInput.activeFocus
                        ? Qt.alpha(CortetsuDesign.colorPrimary, 0.68)
                        : Qt.alpha(CortetsuDesign.colorOutlineVariant, 0.18)
                    outlined: true
                }

                CortetsuText {
                    anchors.left: parent.left
                    anchors.leftMargin: CortetsuDesign.spacingStandard
                    anchors.verticalCenter: parent.verticalCenter
                    visible: nameInput.text.length === 0
                text: qsTr("Nombre de la distribución")
                    color: CortetsuDesign.colorOutline
                    textSize: CortetsuTypography.labelSmallPx
                }

                TextInput {
                    id: nameInput
                    anchors.fill: parent
                    anchors.leftMargin: CortetsuDesign.spacingStandard
                    anchors.rightMargin: CortetsuDesign.spacingStandard
                    verticalAlignment: TextInput.AlignVCenter
                    text: root.presetName
                    onTextChanged: root.presetName = text
                    color: CortetsuDesign.colorOnSurface
                    selectionColor: CortetsuDesign.colorPrimary
                }
            }

            CortetsuButton {
                width: 68
                height: 36
                compact: true
                label: qsTr("Guardar")
                active: true
                disabled: worker.running
                focus: false
                onClicked: root.save()
            }
        }

        Row {
            width: parent.width
            height: 36
            spacing: CortetsuDesign.spacingUnit

            Repeater {
                model: Array.from(root.presets ?? []).slice(0, 3)

                delegate: Row {
                    required property var modelData
                    width: (parent.width - parent.spacing * 2) / 3
                    height: 36
                    spacing: CortetsuDesign.spacingUnit

                    CortetsuButton {
                        width: parent.width - 32
                        height: 36
                        compact: true
                        label: modelData?.name ?? ""
                        tooltipText: qsTr("Cargar distribución")
                        focus: false
                        onClicked: root.loadPreset(modelData?.name ?? "")
                    }

                    CortetsuButton {
                        width: 28
                        height: 36
                        compact: true
                        label: ""
                        icon: "close"
                        danger: true
                        tooltipText: qsTr("Eliminar distribución")
                        focus: false
                        onClicked: root.deletePreset(modelData?.name ?? "")
                    }
                }
            }
        }
    }
}

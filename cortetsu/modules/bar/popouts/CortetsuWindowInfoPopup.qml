pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import "../../../components"
import "../../CortetsuDesign.js" as CortetsuDesign
import "../../CortetsuTypography.js" as CortetsuTypography
import ".."
import "../.."

CortetsuSurface {
    id: root

    required property var screen
    required property var client
    required property var popouts

    focus: visible
    Keys.onEscapePressed: event => {
        event.accepted = true;
        root.popouts.close();
    }

    implicitWidth: 720
    implicitHeight: 360
    radiusValue: CortetsuDesign.radiusLarge
    baseColor: CortetsuDesign.colorSurfaceGlassStrong
    outlined: true

    RowLayout {
        id: body
        anchors.fill: parent
        anchors.margins: CortetsuDesign.spacingComfortable
        spacing: CortetsuDesign.spacingComfortable
        z: 1

        CortetsuSurface {
            Layout.preferredWidth: 300
            Layout.preferredHeight: 300
            Layout.fillHeight: true
            color: CortetsuDesign.colorSurfaceGlass
            radiusValue: CortetsuDesign.radiusMedium

            Column {
                anchors.fill: parent
                anchors.margins: CortetsuDesign.spacingStandard
                spacing: CortetsuDesign.spacingCompact

                CortetsuText {
                    width: parent.width
                    text: root.client?.title ?? qsTr("No hay ventana activa")
                    textSize: CortetsuTypography.titleMediumPx
                    wrapMode: Text.WordWrap
                }
                CortetsuText {
                    width: parent.width
                    text: root.client?.lastIpcObject.class ?? qsTr("Escritorio")
                    color: CortetsuDesign.colorOnSurfaceVariant
                    elide: Text.ElideRight
                }

                Rectangle {
                    width: parent.width
                    height: 1
                    color: CortetsuDesign.colorOutlineVariant
                }

                Detail { icon: "location_on"; text: qsTr("Dirección: 0x%1").arg(root.client?.address ?? "desconocida") }
                Detail { icon: "workspaces"; text: qsTr("Espacio: %1").arg(root.client?.workspace?.name ?? "desconocido") }
                Detail { icon: "desktop_windows"; text: qsTr("Monitor: %1").arg(root.client?.monitor?.name ?? "desconocido") }
                Detail { icon: "resize"; text: qsTr("Tamaño: %1 × %2").arg(root.client?.lastIpcObject?.size?.[0] ?? -1).arg(root.client?.lastIpcObject?.size?.[1] ?? -1) }
            }
        }

        ColumnLayout {
            Layout.preferredHeight: 300
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: CortetsuDesign.spacingStandard

            CortetsuText {
                text: qsTr("Controles de ventana")
                textSize: CortetsuTypography.titleSmallPx
            }

            Flow {
                Layout.fillWidth: true
                spacing: CortetsuDesign.spacingCompact

                CortetsuButton {
                    compact: true
                    disabled: !root.client
                    label: root.client?.lastIpcObject.floating ? qsTr("Mosaico") : qsTr("Flotante")
                    icon: root.client?.lastIpcObject.floating ? "grid_view" : "picture_in_picture"
                    onClicked: root.dispatchWindow("float")
                }
                CortetsuButton {
                    compact: true
                    disabled: !root.client
                    label: root.client?.lastIpcObject.pinned ? qsTr("Desfijar") : qsTr("Fijar")
                    icon: "keep"
                    onClicked: root.dispatchWindow("pin")
                }
                CortetsuButton {
                    compact: true
                    disabled: !root.client
                    label: qsTr("Cerrar")
                    icon: "close"
                    danger: true
                    onClicked: root.dispatchWindow("kill")
                }
            }

            CortetsuText {
                text: qsTr("Mover al espacio de trabajo")
                textSize: CortetsuTypography.titleSmallPx
            }

            GridLayout {
                Layout.fillWidth: true
                columns: 5
                rowSpacing: CortetsuDesign.spacingCompact
                columnSpacing: CortetsuDesign.spacingCompact

                Repeater {
                    model: 10
                    CortetsuButton {
                        required property int index
                        compact: true
                        label: String(index + 1)
                        active: root.client?.workspace?.id === index + 1
                        disabled: !root.client || active
                        onClicked: root.moveToWorkspace(index + 1)
                    }
                }
            }

            Item { Layout.fillHeight: true }

            CortetsuButton {
                Layout.alignment: Qt.AlignRight
                compact: true
                icon: "close"
                label: qsTr("Listo")
                onClicked: root.popouts.close()
            }
        }
    }

    function windowSelector(): string {
        return `address:0x${root.client?.address ?? ""}`;
    }

    function dispatchWindow(action: string): void {
        if (!root.client)
            return;
        const selector = root.windowSelector();
        const commands = {
            float: CortetsuHypr.usingLua ? `hl.dsp.window.float({ window = "${selector}" })` : `togglefloating ${selector}`,
            pin: CortetsuHypr.usingLua ? `hl.dsp.window.pin({ window = "${selector}" })` : `pin ${selector}`,
            kill: CortetsuHypr.usingLua ? `hl.dsp.window.kill({ window = "${selector}" })` : `killwindow ${selector}`
        };
        CortetsuHypr.dispatch(commands[action]);
    }

    function moveToWorkspace(workspace: int): void {
        if (!root.client)
            return;
        CortetsuHypr.dispatch(CortetsuHypr.usingLua
            ? `hl.dsp.window.move({ window = "${root.windowSelector()}", workspace = "${workspace}", follow = true })`
            : `movetoworkspace ${workspace},${root.windowSelector()}`);
    }

    component Detail: RowLayout {
        required property string icon
        required property string text
        Layout.fillWidth: true
        spacing: CortetsuDesign.spacingCompact
        CortetsuIcon { text: parent.icon; color: CortetsuDesign.colorPrimary }
        CortetsuText { Layout.fillWidth: true; text: parent.text; elide: Text.ElideRight; textSize: CortetsuDesign.bodySmallPx }
    }
}

import QtQuick
import QtQuick.Layouts
import Quickshell
import ".."
import "../../components"
import "../CortetsuDesign.js" as CortetsuDesign
import "../CortetsuTypography.js" as CortetsuTypography
import "../../services"

Item {
    id: root

    required property var props
    required property var screenState
    required property var popouts
    readonly property real nonAnimHeight: column.implicitHeight + CortetsuDesign.spacingComfortable * 2
    implicitWidth: 480
    implicitHeight: column.implicitHeight + CortetsuDesign.spacingComfortable * 2

    CortetsuPopupSurface {
        id: panel
        anchors.fill: parent

        ColumnLayout {
            id: column
            anchors.fill: parent
            anchors.margins: CortetsuDesign.spacingComfortable
            spacing: CortetsuDesign.spacingStandard

            CortetsuSectionHeader {
                Layout.fillWidth: true
                title: qsTr("Ajustes rápidos")
                detail: qsTr("Control del sistema")
            }

            CortetsuSurface {
                Layout.fillWidth: true
                implicitHeight: 72
                radiusValue: CortetsuDesign.radiusMedium
                baseColor: CortetsuRecorder.running
                    ? Qt.alpha(CortetsuDesign.colorVermillion, 0.10)
                    : Qt.alpha(CortetsuDesign.colorSurfaceGlassStrong, 0.76)
                outlineColor: CortetsuRecorder.running
                    ? Qt.alpha(CortetsuDesign.colorVermillion, 0.34)
                    : Qt.alpha(CortetsuDesign.colorOutlineVariant, 0.22)
                outlined: true

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: CortetsuDesign.spacingStandard
                    spacing: CortetsuDesign.spacingStandard

                    Item {
                        Layout.preferredWidth: 40
                        Layout.preferredHeight: 40

                        CortetsuSurface {
                            anchors.fill: parent
                            radiusValue: CortetsuDesign.radiusMedium
                            baseColor: CortetsuRecorder.running
                                ? Qt.alpha(CortetsuDesign.colorVermillion, 0.14)
                                : Qt.alpha(CortetsuDesign.colorPrimary, 0.14)
                        }

                        CortetsuIcon {
                            anchors.centerIn: parent
                            text: CortetsuRecorder.running ? "radio_button_checked" : "tune"
                            iconSize: CortetsuDesign.iconMediumPx + 3
                            color: CortetsuRecorder.running
                                ? CortetsuDesign.colorVermillion
                                : CortetsuDesign.colorPrimary
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2

                        CortetsuText {
                            Layout.fillWidth: true
                            text: CortetsuRecorder.running
                                ? qsTr("Grabación de pantalla activa")
                                : qsTr("Cortetsu está listo")
                            textSize: CortetsuTypography.bodyPx
                            font.weight: Font.DemiBold
                            color: CortetsuDesign.colorOnSurface
                        }

                        CortetsuText {
                            Layout.fillWidth: true
                            text: CortetsuIdleInhibitor.enabled
                                ? qsTr("Mantener activo · reposo automático suspendido")
                                : qsTr("Reposo normal · el sistema puede suspenderse")
                            textSize: CortetsuTypography.labelSmallPx
                            color: CortetsuDesign.colorOnSurfaceVariant
                            elide: Text.ElideRight
                        }
                    }
                }
            }

            CortetsuSectionHeader {
                Layout.fillWidth: true
                title: qsTr("Controles de sesión")
                detail: qsTr("Uso frecuente")
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: CortetsuDesign.spacingCompact

                QuickAction {
                    Layout.fillWidth: true
                    icon: CortetsuIdleInhibitor.enabled ? "bedtime_off" : "bedtime"
                    title: CortetsuIdleInhibitor.enabled ? qsTr("Mantener activo") : qsTr("Permitir reposo")
                    detail: CortetsuIdleInhibitor.enabled ? qsTr("Activo") : qsTr("Normal")
                    active: CortetsuIdleInhibitor.enabled
                    onTriggered: CortetsuIdleInhibitor.enabled = !CortetsuIdleInhibitor.enabled
                }

                QuickAction {
                    Layout.fillWidth: true
                    icon: CortetsuRecorder.running ? "stop_circle" : "radio_button_checked"
                    title: CortetsuRecorder.running ? qsTr("Detener grabación") : qsTr("Grabar pantalla")
                    detail: CortetsuRecorder.running ? qsTr("Grabando") : qsTr("Capturar")
                    active: CortetsuRecorder.running
                    danger: CortetsuRecorder.running
                    onTriggered: {
                        if (CortetsuRecorder.running)
                            CortetsuRecorder.stop();
                        else
                            Quickshell.execDetached(["cortetsu-record", "start"]);
                    }
                }
            }

            CortetsuSectionHeader {
                Layout.fillWidth: true
                title: qsTr("Más")
                detail: qsTr("Superficies del sistema")
            }

            CortetsuListRow {
                Layout.fillWidth: true
                icon: "notifications"
                title: qsTr("Notificaciones")
                subtitle: qsTr("Historial, acciones y controles de interrupción")
                onClicked: {
                    root.screenState.utilities = false;
                    root.screenState.sidebar = true;
                }
            }
        }
    }

    component QuickAction: Item {
        id: action

        property string icon
        property string title
        property string detail
        property bool active: false
        property bool danger: false
        signal triggered()

        implicitHeight: 88
        focus: true
        activeFocusOnTab: true
        // The action layer supplies painted feedback while the item itself
        // remains a stable keyboard and pointer target.
        scale: 1

        CortetsuSurface {
            anchors.fill: parent
            radiusValue: CortetsuDesign.radiusMedium
            baseColor: action.danger
                ? Qt.alpha(CortetsuDesign.colorVermillion, 0.10)
                : action.active
                    ? Qt.alpha(CortetsuDesign.colorPrimaryContainer, 0.64)
                    : Qt.alpha(CortetsuDesign.colorSurfaceGlass, 0.70)
            outlineColor: action.activeFocus
                ? Qt.alpha(CortetsuDesign.colorWashi, 0.82)
                : action.danger
                    ? Qt.alpha(CortetsuDesign.colorVermillion, 0.34)
                    : action.active
                        ? Qt.alpha(CortetsuDesign.colorPrimary, 0.30)
                        : Qt.alpha(CortetsuDesign.colorOutlineVariant, 0.18)
            outlined: true
            focused: action.activeFocus
            hovered: actionLayer.containsMouse
            pressed: actionLayer.pressed
        }

        CortetsuStateLayer {
            id: actionLayer
            anchors.fill: parent
            radius: CortetsuDesign.radiusMedium
            onPressed: action.forceActiveFocus()
            onClicked: action.triggered()
        }

        Row {
            anchors.fill: parent
            anchors.margins: CortetsuDesign.spacingStandard
            spacing: CortetsuDesign.spacingStandard

            Item {
                width: 38
                height: 38
                anchors.verticalCenter: parent.verticalCenter

                CortetsuSurface {
                    anchors.fill: parent
                    radiusValue: CortetsuDesign.radiusSmall
                    baseColor: action.danger
                        ? Qt.alpha(CortetsuDesign.colorVermillion, 0.14)
                        : Qt.alpha(CortetsuDesign.colorPrimary, 0.14)
                }

                CortetsuIcon {
                    anchors.centerIn: parent
                    text: action.icon
                    iconSize: CortetsuDesign.iconMediumPx
                    color: action.danger
                        ? CortetsuDesign.colorVermillion
                        : action.active
                            ? CortetsuDesign.colorWashi
                            : CortetsuDesign.colorPrimary
                }
            }

            Column {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2
                width: Math.max(0, parent.width - x)

                CortetsuText {
                    width: parent.width
                    text: action.title
                    textSize: CortetsuTypography.bodySmallPx
                    font.weight: Font.DemiBold
                    color: CortetsuDesign.colorOnSurface
                    elide: Text.ElideRight
                }

                CortetsuText {
                    width: parent.width
                    text: action.detail
                    textSize: CortetsuTypography.labelSmallPx
                    color: action.danger
                        ? CortetsuDesign.colorVermillion
                        : CortetsuDesign.colorOnSurfaceVariant
                    elide: Text.ElideRight
                }
            }
        }

        Keys.onEnterPressed: action.triggered()
        Keys.onReturnPressed: action.triggered()
        Keys.onSpacePressed: action.triggered()
    }
}

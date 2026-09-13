import QtQuick
import QtQuick.Layouts
import Quickshell
import ".."
import "../CortetsuDesign.js" as CortetsuDesign
import "../CortetsuTypography.js" as CortetsuTypography
import "../../components"
import "../../services"

CortetsuPopupSurface {
    id: root

    required property var monitor
    required property var screenState
    required property real volume
    required property bool muted
    required property real brightness
    property bool hovered: false

    // Two action tiles need enough room for their Spanish labels at the
    // normal desktop scale. This avoids truncating "Mantener activo".
    implicitWidth: 420
    implicitHeight: body.implicitHeight + CortetsuDesign.spacingComfortable * 2

    HoverHandler {
        onHoveredChanged: root.hovered = hovered
    }

    ColumnLayout {
        id: body
        anchors.fill: parent
        anchors.margins: CortetsuDesign.spacingComfortable
        spacing: CortetsuDesign.spacingStandard

        RowLayout {
            Layout.fillWidth: true
            spacing: CortetsuDesign.spacingStandard

            CortetsuEvolvingMark {
                Layout.preferredWidth: 32
                Layout.preferredHeight: 32
                phase: "Ascended"
                animated: false
                monochrome: true
                monochromeColor: CortetsuDesign.colorWashi
            }

            CortetsuText {
                Layout.fillWidth: true
                text: qsTr("Acciones rápidas")
                textSize: CortetsuTypography.titleMediumPx
            }
        }

        GridLayout {
            Layout.fillWidth: true
            columns: 2
            rowSpacing: CortetsuDesign.spacingCompact
            columnSpacing: CortetsuDesign.spacingCompact

            CortetsuActionTile {
                Layout.fillWidth: true
                label: CortetsuRecorder.running ? qsTr("Detener grabación") : qsTr("Grabar pantalla")
                detail: CortetsuRecorder.running ? qsTr("Grabando") : qsTr("Iniciar captura")
                icon: CortetsuRecorder.running ? "stop_circle" : "radio_button_checked"
                highlighted: CortetsuRecorder.running
                warning: false
                onActivated: CortetsuRecorder.running ? CortetsuRecorder.stop() : CortetsuRecorder.start()
            }

            CortetsuActionTile {
                Layout.fillWidth: true
                label: CortetsuIdleInhibitor.enabled ? qsTr("Permitir reposo") : qsTr("Mantener activo")
                detail: CortetsuIdleInhibitor.enabled ? qsTr("Desactivado") : qsTr("Activo mientras trabajas")
                icon: CortetsuIdleInhibitor.enabled ? "bedtime" : "bedtime_off"
                highlighted: CortetsuIdleInhibitor.enabled
                warning: false
                onActivated: CortetsuIdleInhibitor.enabled = !CortetsuIdleInhibitor.enabled
            }

            CortetsuActionTile {
                Layout.columnSpan: 2
                Layout.fillWidth: true
                label: GameMode.enabled ? qsTr("Desactivar modo juego") : qsTr("Activar modo juego")
                detail: GameMode.enabled ? qsTr("Efectos reducidos") : qsTr("Menos animaciones y efectos")
                icon: GameMode.enabled ? "sports_esports" : "videogame_asset"
                highlighted: GameMode.enabled
                warning: false
                onActivated: GameMode.toggle()
            }
        }
    }

    CortetsuEvolvingMark {
        id: signatureMark
        visible: false
        x: CortetsuDesign.spacingStandard
        y: CortetsuDesign.spacingUnit
        width: 24
        height: 24
        phase: "Ascended"
        animated: false
        monochrome: true
        monochromeColor: CortetsuDesign.colorWashi
    }
    CortetsuText {
        visible: false
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.topMargin: CortetsuDesign.spacingCompact
        anchors.rightMargin: CortetsuDesign.spacingStandard
        text: qsTr("Controles anteriores")
        textSize: CortetsuTypography.labelSmallPx
        color: CortetsuDesign.colorOnSurfaceVariant
    }

    Column {
        id: indicators
        visible: false
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.topMargin: CortetsuDesign.spacingSection
        anchors.leftMargin: CortetsuDesign.spacingStandard
        anchors.rightMargin: CortetsuDesign.spacingStandard
        spacing: CortetsuDesign.spacingCompact

        // Volume and brightness are one hover island. Tracking the parent
        // avoids an exit/enter race while moving between the two indicators.
        HoverHandler {
            id: indicatorsHover
            onHoveredChanged: root.hovered = hovered
        }

        Repeater {
            model: [
                {
                    icon: root.muted ? "volume_off" : "volume_up",
                    label: qsTr("Volumen"),
                    value: root.volume,
                    muted: root.muted
                },
                {
                    icon: "brightness_6",
                    label: qsTr("Brillo"),
                    value: root.brightness,
                    muted: false
                }
            ]

            delegate: Item {
                id: indicator
                required property var modelData
                implicitWidth: indicators.width
                implicitHeight: 58

                CortetsuSurface {
                    anchors.fill: parent
                    radiusValue: CortetsuDesign.radiusMedium
                    baseColor: Qt.alpha(CortetsuDesign.colorSurfaceHigh, 0.88)
                    outlineColor: Qt.alpha(CortetsuDesign.colorOutlineVariant, 0.18)
                    outlined: true
                    hovered: indicatorMouse.containsMouse
                }

                Row {
                    anchors.fill: parent
                    anchors.margins: CortetsuDesign.spacingStandard
                    spacing: CortetsuDesign.spacingStandard

                    Item {
                        width: 32
                        height: 32
                        anchors.verticalCenter: parent.verticalCenter

                        CortetsuSurface {
                            anchors.fill: parent
                            radiusValue: CortetsuDesign.radiusSmall
                            baseColor: indicator.modelData.muted
                                ? Qt.alpha(CortetsuDesign.colorOnSurfaceVariant, 0.10)
                                : Qt.alpha(CortetsuDesign.colorPrimary, 0.14)
                        }

                        CortetsuIcon {
                            anchors.centerIn: parent
                            text: indicator.modelData.icon
                            color: indicator.modelData.muted
                                ? CortetsuDesign.colorOnSurfaceVariant
                                : CortetsuDesign.colorPrimary
                            iconSize: CortetsuTypography.iconMediumPx
                        }
                    }

                    Column {
                        width: Math.max(0, parent.width - x)
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 5

                        Item {
                            id: indicatorSummary
                            width: parent.width
                            height: Math.max(indicatorLabel.implicitHeight, indicatorValue.implicitHeight)

                            CortetsuText {
                                id: indicatorLabel
                                text: indicator.modelData.label
                                textSize: CortetsuTypography.labelSmallPx
                                color: CortetsuDesign.colorOnSurfaceVariant
                            }

                            CortetsuText {
                                id: indicatorValue
                                anchors.right: parent.right
                                text: indicator.modelData.muted
                                    ? qsTr("Silenciado")
                                    : indicator.modelData.value < 0
                                        ? qsTr("No disponible")
                                    : qsTr("%1%").arg(Math.round(indicator.modelData.value * 100))
                                textSize: CortetsuTypography.labelSmallPx
                                font.weight: Font.DemiBold
                                color: indicator.modelData.muted || indicator.modelData.value < 0
                                    ? CortetsuDesign.colorOnSurfaceVariant
                                    : CortetsuDesign.colorOnSurface
                            }
                        }

                        CortetsuProgressBar {
                            width: parent.width
                            value: indicator.modelData.value
                            visibleWhenUnavailable: true
                            barHeight: 4
                            barRadius: 2
                            trackColor: Qt.alpha(CortetsuDesign.colorOutlineVariant, 0.72)
                            fillColor: indicator.modelData.muted || indicator.modelData.value < 0
                                ? CortetsuDesign.colorOnSurfaceVariant
                                : CortetsuDesign.colorPrimary
                            motionDuration: CortetsuDesign.motionFastMs
                        }
                    }
                }

                MouseArea {
                    id: indicatorMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    onWheel: event => {
                        if (index === 0) {
                            if (event.angleDelta.y > 0)
                                CortetsuAudio.incrementVolume();
                            else
                                CortetsuAudio.decrementVolume();
                        } else if (root.monitor?.supported) {
                            root.monitor.setBrightness(
                                root.brightness + (event.angleDelta.y > 0 ? 0.05 : -0.05)
                            );
                        }
                    }
                }
            }
        }
    }
}

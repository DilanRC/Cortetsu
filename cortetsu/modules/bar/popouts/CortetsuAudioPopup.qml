import QtQuick
import QtQuick.Layouts
import "../../../services"
import "../../../utils"
import "../../../components"
import "../../CortetsuDesign.js" as CortetsuDesign
import "../.."

CortetsuPopupSurface {
    id: root

    required property var popouts
    implicitWidth: 348
    implicitHeight: body.implicitHeight + CortetsuDesign.spacingComfortable * 2

    readonly property int volumePercent: Math.round(CortetsuAudio.volume * 100)

    ColumnLayout {
        id: body
        anchors.fill: parent
        anchors.margins: CortetsuDesign.spacingComfortable
        spacing: CortetsuDesign.spacingStandard

        CortetsuSectionHeader {
            title: qsTr("Audio")
            detail: CortetsuAudio.muted ? qsTr("Silenciado") : qsTr("%1%").arg(root.volumePercent)
        }

        CortetsuSurface {
            Layout.fillWidth: true
            implicitHeight: 86
            radiusValue: CortetsuDesign.radiusMedium
            baseColor: Qt.alpha(CortetsuDesign.colorSurfaceGlassStrong, 0.78)
            outlineColor: Qt.alpha(CortetsuDesign.colorOutlineVariant, 0.24)
            outlined: true

            RowLayout {
                anchors.fill: parent
                anchors.margins: CortetsuDesign.spacingStandard
                spacing: CortetsuDesign.spacingStandard

                Item {
                    Layout.preferredWidth: 42
                    Layout.preferredHeight: 42

                    CortetsuSurface {
                        anchors.fill: parent
                        radiusValue: CortetsuDesign.radiusMedium
                        baseColor: CortetsuAudio.muted
                            ? Qt.alpha(CortetsuDesign.colorVermillion, 0.12)
                            : Qt.alpha(CortetsuDesign.colorPrimary, 0.14)
                    }

                    CortetsuIcon {
                        anchors.centerIn: parent
                        text: CortetsuAudio.muted ? "volume_off"
                            : CortetsuAudio.volume <= 0 ? "volume_mute"
                            : CortetsuAudio.volume < 0.5 ? "volume_down" : "volume_up"
                        iconSize: CortetsuDesign.iconMediumPx + 4
                        color: CortetsuAudio.muted
                            ? CortetsuDesign.colorVermillion
                            : CortetsuDesign.colorPrimary
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: CortetsuDesign.spacingCompact

                        CortetsuText {
                            Layout.fillWidth: true
                            text: CortetsuAudio.sink?.description ?? qsTr("Salida del sistema")
                            textSize: CortetsuDesign.bodySmallPx
                            color: CortetsuDesign.colorOnSurface
                            elide: Text.ElideRight
                        }

                        CortetsuText {
                            text: CortetsuAudio.muted ? qsTr("Silenciado") : qsTr("%1%").arg(root.volumePercent)
                            textSize: CortetsuDesign.labelSmallPx
                            color: CortetsuAudio.muted
                                ? CortetsuDesign.colorVermillion
                                : CortetsuDesign.colorOnSurfaceVariant
                        }
                    }

                    CortetsuSlider {
                        Layout.fillWidth: true
                        value: CortetsuAudio.volume
                        disabled: !CortetsuAudio.sink
                        onMoved: value => CortetsuAudio.setVolume(value)
                    }
                }

                CortetsuButton {
                    compact: true
                    icon: CortetsuAudio.muted ? "volume_off" : "volume_up"
                    tooltipText: CortetsuAudio.muted ? qsTr("Activar sonido") : qsTr("Silenciar")
                    disabled: !CortetsuAudio.sink?.audio
                    onClicked: {
                        if (CortetsuAudio.sink?.audio)
                            CortetsuAudio.sink.audio.muted = !CortetsuAudio.sink.audio.muted;
                    }
                }
            }
        }

        CortetsuSectionHeader {
            title: qsTr("Salida")
            detail: CortetsuAudio.sinks.length > 0
                ? qsTr("%1 dispositivos").arg(CortetsuAudio.sinks.length)
                : qsTr("Sin dispositivo")
        }

        Repeater {
            model: CortetsuAudio.sinks
            delegate: CortetsuListRow {
                required property var modelData
                Layout.fillWidth: true
                title: modelData.description ?? modelData.name ?? qsTr("Dispositivo desconocido")
                subtitle: CortetsuAudio.sink?.id === modelData.id
                    ? qsTr("Salida actual")
                    : qsTr("Cambiar salida")
                icon: "speaker"
                selected: CortetsuAudio.sink?.id === modelData.id
                onClicked: CortetsuAudio.setAudioSink(modelData)
            }
        }

        CortetsuStateMessage {
            Layout.fillWidth: true
            visible: CortetsuAudio.sinks.length === 0
            kind: CortetsuAudio.sink ? "empty" : "error"
            title: CortetsuAudio.sink ? qsTr("No hay otras salidas") : qsTr("Audio no disponible")
            detail: CortetsuAudio.sink ? "" : qsTr("No hay una salida lista")
        }
    }
}

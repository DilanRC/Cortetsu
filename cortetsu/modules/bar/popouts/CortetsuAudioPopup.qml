import QtQuick
import QtQuick.Layouts
import "../../../services"
import "../../../utils"
import "../../../components"
import "../../../theme"
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

        CortetsuPopoutHeader {
            title: qsTr("Audio")
            detail: CortetsuAudio.muted ? qsTr("Silenciado") : qsTr("%1%").arg(root.volumePercent)
            settingsPage: "sound"
            popouts: root.popouts
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

                CortetsuIconBadge {
                    icon: CortetsuAudio.muted ? "volume_off"
                        : CortetsuAudio.volume <= 0 ? "volume_mute"
                        : CortetsuAudio.volume < 0.5 ? "volume_down" : "volume_up"
                    tone: CortetsuAudio.muted ? CortetsuDesign.colorVermillion : CortetsuDesign.colorIndicator
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
                        accessibleName: qsTr("Volumen")
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
            detail: CortetsuAudio.sinks.length === 1 ? qsTr("1 dispositivo")
                : CortetsuAudio.sinks.length > 1 ? qsTr("%1 dispositivos").arg(CortetsuAudio.sinks.length)
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

        // Input: the microphone's level and mute, and the other inputs.
        CortetsuSectionHeader {
            title: qsTr("Entrada")
            detail: !CortetsuAudio.source?.audio ? qsTr("Sin micrófono")
                : CortetsuAudio.sourceMuted ? qsTr("Silenciado")
                : qsTr("%1%").arg(Math.round(CortetsuAudio.sourceVolume * 100))
        }

        RowLayout {
            objectName: "popoutMicrophone"
            Layout.fillWidth: true
            visible: !!CortetsuAudio.source?.audio
            spacing: CortetsuDesign.spacingStandard

            CortetsuIcon {
                text: CortetsuAudio.sourceMuted ? "mic_off" : "mic"
                iconSize: CortetsuDesign.iconMediumPx
                color: CortetsuAudio.sourceMuted ? CortetsuDesign.colorVermillion : CortetsuDesign.colorIndicator
            }

            CortetsuSlider {
                Layout.fillWidth: true
                accessibleName: qsTr("Volumen del micrófono")
                value: CortetsuAudio.sourceVolume
                onMoved: value => CortetsuAudio.setSourceVolume(value)
            }

            CortetsuButton {
                compact: true
                icon: CortetsuAudio.sourceMuted ? "mic_off" : "mic"
                label: ""
                tooltipText: CortetsuAudio.sourceMuted ? qsTr("Reactivar el micrófono") : qsTr("Silenciar el micrófono")
                Accessible.name: tooltipText
                onClicked: if (CortetsuAudio.source?.audio)
                    CortetsuAudio.source.audio.muted = !CortetsuAudio.source.audio.muted
            }
        }

        Repeater {
            // Only worth a list when there is a choice to make.
            model: CortetsuAudio.sources.length > 1 ? CortetsuAudio.sources : []
            delegate: CortetsuListRow {
                required property var modelData
                Layout.fillWidth: true
                title: modelData.description ?? modelData.name ?? qsTr("Dispositivo desconocido")
                subtitle: CortetsuAudio.source?.id === modelData.id ? qsTr("Entrada actual") : qsTr("Cambiar entrada")
                icon: "mic"
                selected: CortetsuAudio.source?.id === modelData.id
                onClicked: CortetsuAudio.setAudioSource(modelData)
            }
        }
    }
}

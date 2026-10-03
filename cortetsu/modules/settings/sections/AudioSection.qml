pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import "../../../components"
import "../.."
import "../../../services"
import "../../../theme"
import "../../CortetsuTypography.js" as CortetsuTypography

ColumnLayout {
    id: root

    required property var page

    spacing: CortetsuDesign.spacingStandard

    CortetsuSectionHeader {
        Layout.fillWidth: true
        title: qsTr("Audio")
        detail: qsTr("Control de salida PipeWire en vivo")
    }

    DomainHero {
        icon: CortetsuAudio.muted ? "volume_off" : "volume_up"
        title: CortetsuAudio.muted ? qsTr("Salida silenciada") : qsTr("Audio disponible")
        detail: root.page.activeOutputName
        value: qsTr("%1%").arg(root.page.volumePercent)
        meta: qsTr("%1 salidas · %2 entradas · %3 streams")
            .arg(CortetsuAudio.sinks.length)
            .arg(CortetsuAudio.sources.length)
            .arg(CortetsuAudio.streams.length)
        progress: CortetsuAudio.volume
        warningState: !CortetsuAudio.sink
    }

    PreferenceToggle {
        title: CortetsuAudio.muted ? qsTr("Salida silenciada") : qsTr("Salida activada")
        detail: qsTr("Volumen actual %1%").arg(root.page.volumePercent)
        icon: CortetsuAudio.muted ? "volume_off" : "volume_up"
        checked: !CortetsuAudio.muted
        controlDisabled: !CortetsuAudio.sink?.audio
        onChanged: enabled => {
            if (CortetsuAudio.sink?.audio)
                CortetsuAudio.sink.audio.muted = !enabled;
        }
    }

    CortetsuSurface {
        Layout.fillWidth: true
        implicitHeight: 86
        radiusValue: CortetsuDesign.radiusMedium
        baseColor: Qt.alpha(CortetsuDesign.colorSurfaceGlass, 0.72)
        outlined: true
        outlineColor: Qt.alpha(CortetsuDesign.colorOutlineVariant, 0.48)

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: CortetsuDesign.spacingStandard
            spacing: CortetsuDesign.spacingCompact
            RowLayout {
                Layout.fillWidth: true
                CortetsuText {
                    Layout.fillWidth: true
                    text: qsTr("Volumen de salida")
                    textSize: CortetsuTypography.bodyPx
                    font.weight: Font.DemiBold
                }
                CortetsuText {
                    text: qsTr("%1%").arg(root.page.volumePercent)
                    textSize: CortetsuTypography.labelSmallPx
                    color: CortetsuDesign.colorOnSurfaceVariant
                }
            }
            CortetsuSlider {
                Layout.fillWidth: true
                value: CortetsuAudio.volume
                onMoved: nextValue => CortetsuAudio.setVolume(nextValue)
            }
        }
    }

    CortetsuSectionHeader {
        Layout.fillWidth: true
        title: qsTr("Entrada")
        detail: root.page.activeInputName
    }

    PreferenceToggle {
        title: CortetsuAudio.sourceMuted ? qsTr("Entrada silenciada") : qsTr("Entrada activa")
        detail: qsTr("Volumen del micrófono %1%").arg(root.page.inputVolumePercent)
        icon: CortetsuAudio.sourceMuted ? "mic_off" : "mic"
        checked: !CortetsuAudio.sourceMuted
        controlDisabled: !CortetsuAudio.source?.audio
        onChanged: enabled => {
            if (CortetsuAudio.source?.audio)
                CortetsuAudio.source.audio.muted = !enabled;
        }
    }

    CortetsuSlider {
        Layout.fillWidth: true
        value: CortetsuAudio.sourceVolume
        disabled: CortetsuAudio.sourceMuted || !CortetsuAudio.source
        onMoved: nextValue => CortetsuAudio.setSourceVolume(nextValue)
    }

    CortetsuSectionHeader {
        Layout.fillWidth: true
        title: qsTr("Dispositivos de salida")
        detail: qsTr("%1 disponibles · %2 activo").arg(CortetsuAudio.sinks.length).arg(root.page.activeOutputName)
    }

    Repeater {
        model: CortetsuAudio.sinks
        delegate: CortetsuListRow {
            required property var modelData
            Layout.fillWidth: true
            title: modelData.description ?? modelData.name ?? qsTr("Salida desconocida")
            subtitle: CortetsuAudio.sink?.id === modelData.id ? qsTr("Salida actual") : qsTr("Usar esta salida")
            icon: "speaker"
            selected: CortetsuAudio.sink?.id === modelData.id
            onClicked: CortetsuAudio.setAudioSink(modelData)
        }
    }

    CortetsuSectionHeader {
        Layout.fillWidth: true
        title: qsTr("Dispositivos de entrada")
        detail: qsTr("Selecciona el micrófono predeterminado de PipeWire")
    }

    Repeater {
        model: CortetsuAudio.sources
        delegate: CortetsuListRow {
            required property var modelData
            Layout.fillWidth: true
            title: modelData.description ?? modelData.name ?? qsTr("Entrada desconocida")
            subtitle: CortetsuAudio.source?.id === modelData.id ? qsTr("Entrada actual") : qsTr("Usar esta entrada")
            icon: "mic"
            selected: CortetsuAudio.source?.id === modelData.id
            onClicked: CortetsuAudio.setAudioSource(modelData)
        }
    }

    CortetsuStateMessage {
        Layout.fillWidth: true
        visible: CortetsuAudio.streams.length === 0
        kind: "empty"
        icon: "music_off"
        title: qsTr("Sin aplicaciones reproduciendo audio")
        detail: qsTr("Los controles por aplicación aparecerán cuando PipeWire detecte un stream")
    }

    CortetsuSectionHeader {
        Layout.fillWidth: true
        title: qsTr("Aplicaciones reproduciendo")
        detail: qsTr("Volumen independiente por stream")
        visible: CortetsuAudio.streams.length > 0
    }

    Repeater {
        model: CortetsuAudio.streams
        delegate: CortetsuSurface {
            required property var modelData
            Layout.fillWidth: true
            implicitHeight: 78
            radiusValue: CortetsuDesign.radiusMedium
            baseColor: Qt.alpha(CortetsuDesign.colorSurfaceGlass, 0.72)
            outlined: true

            RowLayout {
                anchors.fill: parent
                anchors.margins: CortetsuDesign.spacingStandard
                spacing: CortetsuDesign.spacingStandard

                CortetsuIcon {
                    text: CortetsuAudio.getStreamMuted(parent.parent.modelData) ? "volume_off" : "music_note"
                    iconSize: CortetsuTypography.iconMediumPx
                    color: CortetsuDesign.colorPrimary
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    CortetsuText {
                        Layout.fillWidth: true
                        text: CortetsuAudio.getStreamName(parent.parent.modelData)
                        textSize: CortetsuTypography.bodyPx
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }
                    CortetsuSlider {
                        Layout.fillWidth: true
                        value: CortetsuAudio.getStreamVolume(parent.parent.modelData)
                        disabled: CortetsuAudio.getStreamMuted(parent.parent.modelData)
                        onMoved: nextValue => CortetsuAudio.setStreamVolume(parent.parent.modelData, nextValue)
                    }
                }

                CortetsuToggle {
                    checked: !CortetsuAudio.getStreamMuted(parent.parent.modelData)
                    onToggled: checked => CortetsuAudio.setStreamMuted(parent.parent.modelData, !checked)
                }
            }
        }
    }
}

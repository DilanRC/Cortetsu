pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../../components"
import "../../../services"
import "../../../theme"
import "../.."
import "../controls"

ColumnLayout {
    id: root

    required property var context

    spacing: CortetsuDesign.spacingSection

    SettingsGroup {
        title: qsTr("Salida")
        detail: root.context.outputName

        CortetsuStateMessage {
            objectName: "noOutput"
            Layout.fillWidth: true
            Layout.margins: CortetsuDesign.spacingSection
            visible: !CortetsuAudio.sink
            kind: "error"
            icon: "volume_off"
            title: qsTr("No hay dispositivo de salida")
            detail: qsTr("PipeWire no ofrece ninguna salida. Conecta un dispositivo o revisa el servicio de audio.")
        }

        SettingSliderRow {
            objectName: "outputVolume"
            visible: !!CortetsuAudio.sink
            title: qsTr("Volumen de salida")
            valueText: CortetsuAudio.muted ? qsTr("Silenciado") : qsTr("%1 %").arg(root.context.volumePercent)
            value: CortetsuAudio.volume
            to: CortetsuConfig.maxVolume
            onMoved: next => CortetsuAudio.setVolume(next)
        }

        SettingToggleRow {
            objectName: "outputMute"
            visible: !!CortetsuAudio.sink
            title: qsTr("Silenciar la salida")
            checked: CortetsuAudio.muted
            disabled: !CortetsuAudio.sink?.audio
            onToggled: value => {
                if (CortetsuAudio.sink?.audio)
                    CortetsuAudio.sink.audio.muted = value;
            }
        }

        Repeater {
            model: ScriptModel { values: CortetsuAudio.sinks }

            delegate: CortetsuListRow {
                required property var modelData
                readonly property bool current: CortetsuAudio.sink?.id === modelData.id
                Layout.fillWidth: true
                Layout.leftMargin: 2
                Layout.rightMargin: 2
                icon: "speaker"
                title: modelData.description ?? modelData.name ?? qsTr("Salida desconocida")
                subtitle: current ? qsTr("En uso") : qsTr("Usar esta salida")
                selected: current
                Accessible.role: Accessible.RadioButton
                Accessible.name: title
                Accessible.checked: current
                onClicked: CortetsuAudio.setAudioSink(modelData)
            }
        }
    }

    SettingsGroup {
        title: qsTr("Entrada")
        detail: root.context.inputName

        SettingValueRow {
            objectName: "noInput"
            visible: !CortetsuAudio.source
            title: qsTr("Micrófono")
            detail: qsTr("PipeWire no ofrece ninguna entrada")
            value: qsTr("No disponible")
        }

        SettingSliderRow {
            visible: !!CortetsuAudio.source
            title: qsTr("Volumen de entrada")
            valueText: CortetsuAudio.sourceMuted ? qsTr("Silenciado") : qsTr("%1 %").arg(root.context.inputVolumePercent)
            value: CortetsuAudio.sourceVolume
            onMoved: next => CortetsuAudio.setSourceVolume(next)
        }

        SettingToggleRow {
            visible: !!CortetsuAudio.source
            title: qsTr("Silenciar el micrófono")
            checked: CortetsuAudio.sourceMuted
            disabled: !CortetsuAudio.source?.audio
            onToggled: value => {
                if (CortetsuAudio.source?.audio)
                    CortetsuAudio.source.audio.muted = value;
            }
        }

        Repeater {
            model: ScriptModel { values: CortetsuAudio.sources }

            delegate: CortetsuListRow {
                required property var modelData
                readonly property bool current: CortetsuAudio.source?.id === modelData.id
                Layout.fillWidth: true
                Layout.leftMargin: 2
                Layout.rightMargin: 2
                icon: "mic"
                title: modelData.description ?? modelData.name ?? qsTr("Entrada desconocida")
                subtitle: current ? qsTr("En uso") : qsTr("Usar esta entrada")
                selected: current
                Accessible.role: Accessible.RadioButton
                Accessible.name: title
                Accessible.checked: current
                onClicked: CortetsuAudio.setAudioSource(modelData)
            }
        }
    }

    SettingsGroup {
        title: qsTr("Aplicaciones")
        detail: qsTr("Volumen de cada una")

        SettingValueRow {
            objectName: "noStreams"
            visible: CortetsuAudio.streams.length === 0
            title: qsTr("Nada se está reproduciendo")
            detail: qsTr("Cada aplicación aparece aquí mientras emite sonido")
        }

        Repeater {
            model: ScriptModel { values: CortetsuAudio.streams }

            delegate: SettingSliderRow {
                required property var modelData
                title: CortetsuAudio.getStreamName(modelData)
                valueText: CortetsuAudio.getStreamMuted(modelData)
                    ? qsTr("Silenciada")
                    : qsTr("%1 %").arg(Math.round(CortetsuAudio.getStreamVolume(modelData) * 100))
                value: CortetsuAudio.getStreamVolume(modelData)
                to: CortetsuConfig.maxVolume
                disabled: CortetsuAudio.getStreamMuted(modelData)
                onMoved: next => CortetsuAudio.setStreamVolume(modelData, next)
            }
        }
    }
}

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
        icon: "speaker"
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
            to: Math.max(CortetsuConfig.maxVolume, CortetsuAudio.volume)
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
            model: ScriptModel { values: [...CortetsuAudio.sinks] }

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
        icon: "mic"
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
            model: ScriptModel { values: [...CortetsuAudio.sources] }

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
        icon: "apps"
        detail: qsTr("Volumen de cada una")

        SettingValueRow {
            objectName: "noStreams"
            visible: CortetsuAudio.streams.length === 0
            title: qsTr("Nada se está reproduciendo")
            detail: qsTr("Cada aplicación aparece aquí mientras emite sonido")
        }

        Repeater {
            model: ScriptModel { values: [...CortetsuAudio.streams] }

            delegate: SettingSliderRow {
                required property var modelData
                title: CortetsuAudio.getStreamName(modelData)
                valueText: CortetsuAudio.getStreamMuted(modelData)
                    ? qsTr("Silenciada")
                    : qsTr("%1 %").arg(Math.round(CortetsuAudio.getStreamVolume(modelData) * 100))
                value: CortetsuAudio.getStreamVolume(modelData)
                to: CortetsuConfig.maxVolume
                mutable: true
                muted: CortetsuAudio.getStreamMuted(modelData)
                disabled: muted
                onMoved: next => CortetsuAudio.setStreamVolume(modelData, next)
                onMuteToggled: CortetsuAudio.setStreamMuted(modelData, !CortetsuAudio.getStreamMuted(modelData))
            }
        }
    }

    // The opt-in equalizer. Its controls exist only when the filter-chain
    // node does; otherwise the group says how to add it and draws no
    // slider that would move nothing.
    SettingsGroup {
        objectName: "equalizerGroup"
        title: qsTr("Ecualizador")
        icon: "equalizer"
        detail: !CortetsuEqualizer.available
            ? qsTr("Opcional: requiere el nodo de PipeWire de Cortetsu")
            : CortetsuAudio.sink?.name === CortetsuEqualizer.nodeName
                ? qsTr("Activo en la salida actual")
                : qsTr("Elige «Ecualizador de Cortetsu» como salida para oírlo")
        collapsible: true

        SettingValueRow {
            objectName: "equalizerMissing"
            visible: !CortetsuEqualizer.available
            title: qsTr("No instalado")
            detail: qsTr("Copia cortetsu/data/pipewire/cortetsu-eq.conf a ~/.config/pipewire/pipewire.conf.d/ y reinicia PipeWire (docs/AUDIO_EQ.md)")
            value: qsTr("No disponible")
        }

        SettingValueRow {
            objectName: "equalizerLegacyGraph"
            visible: CortetsuEqualizer.legacyGraph
            title: qsTr("Grafo anterior instalado")
            detail: qsTr("Funciona, pero el margen se aplica con un filtro en 0 Hz. Copia de nuevo cortetsu-eq.conf y reinicia PipeWire para usar el preamplificador lineal")
            value: qsTr("Actualizable")
        }

        SettingToggleRow {
            objectName: "equalizerEnabled"
            visible: CortetsuEqualizer.available
            title: qsTr("Aplicar la curva")
            detail: qsTr("Apagado deja la señal plana sin cambiar de dispositivo")
            checked: CortetsuEqualizer.enabled
            onToggled: value => CortetsuEqualizer.setEnabled(value)
        }

        SettingChoiceChips {
            objectName: "equalizerPreset"
            visible: CortetsuEqualizer.available
            title: qsTr("Curva")
            options: CortetsuEqualizer.presetIds.map(id => ({ value: id, label: CortetsuEqualizer.presets[id].label, name: `eq-${id}` }))
            current: CortetsuEqualizer.preset
            detail: CortetsuEqualizer.preset === "custom" ? qsTr("Curva propia") : ""
            disabled: !CortetsuEqualizer.enabled
            onChosen: value => CortetsuEqualizer.usePreset(value)
        }

        EqCurve {
            visible: CortetsuEqualizer.available
            Layout.fillWidth: true
            frequencies: CortetsuEqualizer.frequencies
            gains: CortetsuEqualizer.enabled ? CortetsuEqualizer.gains : CortetsuEqualizer.gains.map(() => 0)
            preamp: CortetsuEqualizer.preamp
        }

        Repeater {
            model: CortetsuEqualizer.available ? CortetsuEqualizer.frequencies.length : 0

            delegate: SettingSliderRow {
                required property int index
                readonly property real gain: CortetsuEqualizer.gains[index] ?? 0
                title: qsTr("%1 Hz").arg(CortetsuEqualizer.labels[index])
                valueText: gain > 0 ? qsTr("+%1 dB").arg(gain) : qsTr("%1 dB").arg(gain)
                from: -CortetsuEqualizer.maxDb
                to: CortetsuEqualizer.maxDb
                step: 1
                value: gain
                disabled: !CortetsuEqualizer.enabled
                onMoved: next => CortetsuEqualizer.setGain(index, next)
            }
        }

        SettingValueRow {
            visible: CortetsuEqualizer.available && CortetsuEqualizer.enabled && CortetsuEqualizer.preamp < 0
            title: qsTr("Margen contra la saturación")
            detail: qsTr("La señal baja lo que sube el punto más alto de la curva, contando el solape entre bandas")
            value: qsTr("%1 dB").arg(CortetsuEqualizer.preamp.toFixed(1))
        }
    }

    SettingsGroup {
        title: qsTr("Límites de audio")
        icon: "shield"
        collapsible: true
        detail: qsTr("El límite se aplica al próximo ajuste desde Cortetsu; los niveles actuales se conservan")
        SettingToggleRow {
            objectName: "audioProtection"
            title: qsTr("Limitar aumentos bruscos")
            detail: qsTr("Limita cada aumento solicitado desde Cortetsu; no controla otras aplicaciones")
            checked: CortetsuConfig.audioProtectionEnabled
            onToggled: enabled => { CortetsuConfig.audioProtectionEnabled = enabled; }
        }
        SettingSliderRow {
            objectName: "audioMaxIncrease"
            title: qsTr("Aumento máximo por ajuste")
            from: 1
            to: 100
            step: 1
            value: Math.round(CortetsuConfig.audioMaxIncrease * 100)
            valueText: qsTr("%1 %").arg(Math.round(value))
            disabled: !CortetsuConfig.audioProtectionEnabled
            onMoved: next => { CortetsuConfig.audioMaxIncrease = next / 100; }
        }
        SettingSliderRow {
            objectName: "audioLimit"
            title: qsTr("Límite al ajustar el volumen")
            from: 0
            to: 200
            step: 5
            value: Math.round(CortetsuConfig.maxVolume * 100)
            valueText: qsTr("%1 %").arg(Math.round(value))
            onMoved: next => { CortetsuConfig.maxVolume = next / 100; CortetsuConfig.save(); }
        }
        SettingSliderRow {
            objectName: "audioStep"
            title: qsTr("Incremento por paso")
            from: 1
            to: 100
            step: 1
            value: Math.round(CortetsuConfig.audioIncrement * 100)
            valueText: qsTr("%1 %").arg(Math.round(value))
            onMoved: next => { CortetsuConfig.audioIncrement = next / 100; CortetsuConfig.save(); }
        }
    }
}

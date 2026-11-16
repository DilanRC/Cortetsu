pragma Singleton

import QtQml
import Quickshell
import Quickshell.Services.Pipewire
import "../modules"

// The optional 10-band equalizer. Cortetsu does not create the audio
// graph: the user installs `cortetsu/data/pipewire/cortetsu-eq.conf` (a
// PipeWire filter-chain sink named "cortetsu_eq", see docs/AUDIO_EQ.md) and
// chooses it as the output. This owner only exists to set that node's band
// gains, read back nothing it did not write, and say plainly when the node
// is absent. No process is killed or restarted from here.
//
// Bypass is a flat curve (every gain and the preamp at 0 dB): the node
// stays in the path, so switching it never moves audio between devices.
QtObject {
    id: root

    readonly property var frequencies: [32, 64, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]
    readonly property var labels: ["32", "64", "125", "250", "500", "1k", "2k", "4k", "8k", "16k"]
    readonly property int maxDb: 12
    readonly property string nodeName: "cortetsu_eq"

    // Own curves, in dB per band.
    readonly property var presets: ({
        flat: { label: qsTr("Plano"), gains: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0] },
        bass: { label: qsTr("Graves"), gains: [6, 5, 3, 1, 0, 0, 0, 0, 0, 0] },
        treble: { label: qsTr("Agudos"), gains: [0, 0, 0, 0, 0, 1, 2, 4, 5, 5] },
        voice: { label: qsTr("Voz"), gains: [-3, -2, -1, 1, 3, 4, 3, 1, 0, -1] },
        loudness: { label: qsTr("Volumen bajo"), gains: [5, 4, 2, 0, -1, 0, 0, 1, 3, 4] }
    })
    readonly property var presetIds: ["flat", "bass", "treble", "voice", "loudness"]

    readonly property var node: {
        for (const item of Pipewire.nodes.values)
            if (item?.name === root.nodeName && !item.isStream)
                return item;
        return null;
    }
    readonly property bool available: !!node
    readonly property bool enabled: CortetsuConfig.eqEnabled
    readonly property var gains: CortetsuConfig.eqGains
    // The name of the preset the curve matches, or "custom".
    readonly property string preset: {
        for (const id of presetIds)
            if (presets[id].gains.every((value, index) => value === gains[index]))
                return id;
        return "custom";
    }
    // Headroom: the loudest boost is taken off the whole signal first, so a
    // boosted band cannot push a full-scale signal past 0 dBFS.
    readonly property real preamp: enabled ? -Math.max(0, ...gains) : 0
    property string lastError: ""

    function clamp(db: real): real {
        return Math.round(Math.max(-maxDb, Math.min(maxDb, Number(db) || 0)));
    }

    function setGain(index: int, db: real): void {
        if (index < 0 || index >= frequencies.length)
            return;
        const next = gains.slice();
        next[index] = clamp(db);
        if (next[index] === gains[index])
            return;
        CortetsuConfig.eqGains = next;
        CortetsuConfig.save();
    }

    function usePreset(id: string): void {
        if (!(id in presets))
            return;
        CortetsuConfig.eqGains = presets[id].gains.slice();
        CortetsuConfig.save();
    }

    function setEnabled(value: bool): void {
        CortetsuConfig.eqEnabled = value;
        CortetsuConfig.save();
    }

    function apply(): void {
        if (!node)
            return;
        const effective = enabled ? gains : gains.map(() => 0);
        const params = effective.map((db, i) => `"eq_band_${i + 1}:Gain" ${Number(db).toFixed(1)}`)
            .concat([`"eq_preamp:Gain" ${preamp.toFixed(1)}`])
            .join(" ");
        // An argument vector, never a shell: the payload is built from
        // numbers clamped above.
        Quickshell.execDetached(["pw-cli", "set-param", String(node.id), "Props", `{ params = [ ${params} ] }`]);
    }

    // Reapplied whenever the curve, the switch or the node changes: a
    // restarted filter-chain comes back flat and gets the saved curve again.
    onGainsChanged: Qt.callLater(apply)
    onEnabledChanged: Qt.callLater(apply)
    onNodeChanged: Qt.callLater(apply)
}

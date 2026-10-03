pragma Singleton

import Quickshell
import Quickshell.Services.Pipewire
import QtQml
import "../services"

Singleton {
    id: root

    readonly property var sink: Pipewire.defaultAudioSink
    readonly property bool muted: !!sink?.audio?.muted
    readonly property real volume: sink?.audio?.volume ?? 0
    readonly property var source: Pipewire.defaultAudioSource
    readonly property bool sourceMuted: !!source?.audio?.muted
    readonly property real sourceVolume: source?.audio?.volume ?? 0
    property list<var> sinks: []
    property list<var> sources: []
    property list<var> streams: []
    readonly property var cava: CortetsuSpectrum
    readonly property QtObject beatTracker: QtObject { property real bpm: 60 }

    function setVolume(value: real): void {
        if (!sink?.ready || !sink?.audio)
            return;
        sink.audio.muted = false;
        sink.audio.volume = Math.max(0, Math.min(CortetsuConfig.maxVolume, value));
    }

    function incrementVolume(amount: real): void {
        setVolume(volume + (amount || CortetsuConfig.audioIncrement));
    }

    function decrementVolume(amount: real): void {
        setVolume(volume - (amount || CortetsuConfig.audioIncrement));
    }

    function setSourceVolume(value: real): void {
        if (!source?.ready || !source.audio) return;
        source.audio.muted = false;
        source.audio.volume = Math.max(0, Math.min(CortetsuConfig.maxVolume, value));
    }
    function incrementSourceVolume(amount: real): void { setSourceVolume(sourceVolume + (amount || CortetsuConfig.audioIncrement)); }
    function decrementSourceVolume(amount: real): void { setSourceVolume(sourceVolume - (amount || CortetsuConfig.audioIncrement)); }
    function setAudioSink(node): void { Pipewire.preferredDefaultAudioSink = node; }
    function setAudioSource(node): void { Pipewire.preferredDefaultAudioSource = node; }
    function setStreamVolume(node, value: real): void { if (node?.ready && node.audio) node.audio.volume = Math.max(0, Math.min(CortetsuConfig.maxVolume, value)); }
    function setStreamMuted(node, value: bool): void { if (node?.ready && node.audio) node.audio.muted = value; }
    function getStreamVolume(node): real { return node?.audio?.volume ?? 0; }
    function getStreamMuted(node): bool { return !!node?.audio?.muted; }
    function getStreamName(node): string { return node?.properties?.["application.name"] || node?.description || node?.name || qsTr("Aplicación desconocida"); }
    function refreshNodes(): void {
        const nextSinks = [], nextSources = [], nextStreams = [];
        for (const node of Pipewire.nodes.values) {
            if (!node.isStream) {
                if (node.isSink) nextSinks.push(node);
                else if (node.audio) nextSources.push(node);
            } else if (node.audio) nextStreams.push(node);
        }
        sinks = nextSinks; sources = nextSources; streams = nextStreams;
    }
    Component.onCompleted: refreshNodes()
    Connections { target: Pipewire.nodes; function onValuesChanged(): void { root.refreshNodes(); } }

    PwObjectTracker {
        objects: [root.sink, root.source, ...root.sinks, ...root.sources, ...root.streams].filter(node => node)
    }
}

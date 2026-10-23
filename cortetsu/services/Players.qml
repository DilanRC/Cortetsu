pragma Singleton

import QtQml
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import "../modules"

Singleton {
    id: root
    readonly property list<MprisPlayer> list: Mpris.players.values
    readonly property MprisPlayer active: manualActive ?? list.find(p => getIdentity(p) === CortetsuConfig.defaultPlayer) ?? list[0] ?? null
    property MprisPlayer manualActive: null
    property bool activePlayerKnown: false
    property string lastAnnouncedTrack: ""

    function announceNowPlaying(player: MprisPlayer): void {
        if (!player || player.playbackState !== MprisPlaybackState.Playing)
            return;
        const title = player.trackTitle?.trim() ?? "";
        const key = `${player.identity}\u001f${title}`;
        if (!title || key === lastAnnouncedTrack)
            return;
        lastAnnouncedTrack = key;
        if (CortetsuConfig.toastNowPlaying)
            CortetsuToaster.toast(qsTr("Reproduciendo ahora"), title, "music_note");
    }

    readonly property Connections trackAnnouncements: Connections {
        target: root.active
        function onTrackTitleChanged(): void { root.announceNowPlaying(target); }
        function onPlaybackStateChanged(): void { root.announceNowPlaying(target); }
    }

    onActiveChanged: {
        if (activePlayerKnown)
            announceNowPlaying(active);
        activePlayerKnown = true;
    }

    function getIdentity(player: MprisPlayer): string {
        if (!player) return "";
        const alias = CortetsuConfig.playerAliases.find(a => a.from === player.identity);
        return alias?.to ?? player.identity;
    }

    function getArtUrl(player: MprisPlayer): string {
        if (!player) return "";
        if (player.trackArtUrl) return player.trackArtUrl;
        const url = player.metadata["xesam:url"] ?? "";
        const id = url.match(/[?&]v=([\w-]{11})/)?.[1];
        return id ? `https://img.youtube.com/vi/${id}/hqdefault.jpg` : "";
    }

    CortetsuShortcut { name: "mediaToggle"; onPressed: root.active?.togglePlaying() }
    CortetsuShortcut { name: "mediaPrev"; onPressed: root.active?.previous() }
    CortetsuShortcut { name: "mediaNext"; onPressed: root.active?.next() }
    CortetsuShortcut { name: "mediaStop"; onPressed: root.active?.stop() }

    IpcHandler {
        target: "mpris"
        function getActive(prop: string): string { return root.active ? root.active[prop] ?? "Invalid property" : "No active player"; }
        function list(): string { return root.list.map(p => root.getIdentity(p)).join("\n"); }
        function play(): void { root.active?.play(); }
        function pause(): void { root.active?.pause(); }
        function playPause(): void { root.active?.togglePlaying(); }
        function previous(): void { root.active?.previous(); }
        function next(): void { root.active?.next(); }
        function stop(): void { root.active?.stop(); }
    }
}

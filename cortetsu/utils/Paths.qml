pragma Singleton

import QtQuick
import Quickshell
import "../modules"

Singleton {
    id: root

    readonly property string home: Quickshell.env("HOME")
    readonly property string downloads: Quickshell.env("XDG_DOWNLOAD_DIR") || `${home}/Descargas`
    readonly property string desktop: Quickshell.env("XDG_DESKTOP_DIR") || `${home}/Escritorio`
    readonly property string documents: Quickshell.env("XDG_DOCUMENTS_DIR") || `${home}/Documentos`
    readonly property string music: Quickshell.env("XDG_MUSIC_DIR") || `${home}/Música`
    readonly property string pictures: Quickshell.env("XDG_PICTURES_DIR") || `${home}/Imágenes`
    readonly property string videos: Quickshell.env("XDG_VIDEOS_DIR") || `${home}/Vídeos`
    readonly property string templates: Quickshell.env("XDG_TEMPLATES_DIR") || `${home}/Plantillas`
    readonly property string publicShare: Quickshell.env("XDG_PUBLICSHARE_DIR") || `${home}/Público`
    readonly property string data: `${Quickshell.env("XDG_DATA_HOME") || `${home}/.local/share`}/cortetsu`
    readonly property string state: `${Quickshell.env("XDG_STATE_HOME") || `${home}/.local/state`}/cortetsu`
    readonly property string cache: `${Quickshell.env("XDG_CACHE_HOME") || `${home}/.cache`}/cortetsu`
    readonly property string config: `${Quickshell.env("XDG_CONFIG_HOME") || `${home}/.config`}/cortetsu`
    readonly property string imagecache: `${cache}/imagecache`
    readonly property string notifimagecache: `${imagecache}/notifs`
    readonly property string wallsdir: Quickshell.env("CORTETSU_WALLPAPERS_DIR") || absolutePath(CortetsuConfig.wallpaperDirectory)
    readonly property string recsdir: Quickshell.env("CORTETSU_RECORDINGS_DIR") || `${videos}/Recordings`
    readonly property string libdir: `${data}/lib`
    readonly property string noNotifsPic: Quickshell.shellPath("assets/dino.png")
    readonly property string lockNoNotifsPic: noNotifsPic

    function userDirectory(name: string): string {
        switch (name) {
        case "Downloads": return downloads;
        case "Desktop": return desktop;
        case "Documents": return documents;
        case "Music": return music;
        case "Pictures": return pictures;
        case "Videos": return videos;
        case "Templates": return templates;
        case "Public": return publicShare;
        default: return `${home}/${name}`;
        }
    }

    function toLocalFile(path: url): string {
        const resolved = String(Qt.resolvedUrl(path));
        return resolved.startsWith("file://") ? decodeURIComponent(resolved.slice(7)) : resolved;
    }

    function absolutePath(path: string): string {
        return path.replace(/~|\$({?)HOME(}?)/g, home);
    }

    function shortenHome(path: string): string {
        return path.startsWith(home) ? `~${path.slice(home.length)}` : path;
    }
}

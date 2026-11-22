.pragma library

// A named tray icon as Quickshell hands it: image://icon/NAME, with
// ?path=DIR when the app ships its own icon folder (IconThemePath).
// Returns { name, dir } (either may be ""), or null for pixmaps and files.
function namedIcon(icon) {
    const match = String(icon ?? "").match(/^image:\/\/icon\/([^?]*)(?:\?path=(.*))?$/);
    if (!match)
        return null;
    return { name: decodeURIComponent(match[1]), dir: match[2] ? decodeURIComponent(match[2]) : "" };
}

// A pixmap icon whose revision is 0: Quickshell hands this when the item
// published no pixmap at all (Linux Wallpaper Engine's Electron item), and
// the provider then paints the magenta checker. Real pixmaps count from 1.
function emptyPixmap(icon) {
    return /^image:\/\/qspixmap\/\d+\/0$/.test(String(icon ?? ""));
}

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

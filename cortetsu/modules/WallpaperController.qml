pragma Singleton

import QtQuick

// Wallpaper Manager: global shortcut "wallpapermanager", IPC target
// "wallpapermanager". A singleton because Bottom Hub and Settings open it on a
// given screen with open(screen).
RetainedSurfaceController {
    surfaceKey: "wallpaperManager"
    ipcTarget: "wallpapermanager"
    shortcutName: "wallpapermanager"
    shortcutDescription: "Toggle native wallpaper manager"
}

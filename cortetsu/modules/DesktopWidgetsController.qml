import QtQuick

// Desktop widget editor: global shortcut "desktopWidgets", IPC target
// "desktopWidgets" (open, close, toggle, isOpen).
RetainedSurfaceController {
    surfaceKey: "desktopWidgets"
    ipcTarget: "desktopWidgets"
    shortcutName: "desktopWidgets"
    shortcutDescription: "Toggle the Cortetsu desktop widget editor"
}

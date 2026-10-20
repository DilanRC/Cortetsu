import QtQuick

// Clipboard manager: global shortcut "clipboard", IPC target "clipboard".
RetainedSurfaceController {
    surfaceKey: "clipboard"
    ipcTarget: "clipboard"
    shortcutName: "clipboard"
    shortcutDescription: "Toggle native clipboard manager"
}

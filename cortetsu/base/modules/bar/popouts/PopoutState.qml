import QtQuick

QtObject {
    property string currentName
    property bool hasCurrent
    // The monitor these popouts belong to, for content that reads that
    // monitor's Hub (the App Rail's window preview).
    property var screen: null
    // The Hub holds the keyboard for this popout (Wrapper.keyboardHeld): the
    // keys typed on its icon drive it, so it shows where they act.
    property bool keyboardHeld: false

    signal detachRequested(mode: string)
    signal closeRequested()

    function close(): void {
        closeRequested();
    }
}

import QtQuick

QtObject {
    property string currentName
    property bool hasCurrent
    // The monitor these popouts belong to, for content that reads that
    // monitor's Hub (the App Rail's window preview).
    property var screen: null

    signal detachRequested(mode: string)
    signal closeRequested()

    function close(): void {
        closeRequested();
    }
}

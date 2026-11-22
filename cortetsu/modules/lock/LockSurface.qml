pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../../components"
import ".."
import "../../services"
import "../../utils"
import "../../theme"
import "../CortetsuTypography.js" as CortetsuTypography

WlSessionLockSurface {
    id: root
    required property WlSessionLock lock
    required property Pam pam

    // Layout and lock keys, read once by Lock.qml for every surface.
    required property var keyboard
    readonly property string keyboardLayout: keyboard.layout.length > 0
        ? keyboard.layout : qsTr("Distribución desconocida")
    readonly property string userLabel: Quickshell.env("USER") || qsTr("Usuario")
    readonly property int batteryPercent: CortetsuPower.percent
    readonly property bool batteryCharging: CortetsuPower.charging
    readonly property string batteryLabel: CortetsuPower.hasBattery
        ? qsTr("Batería %1 %").arg(CortetsuPower.percent)
        : qsTr("Corriente eléctrica")
    readonly property string networkLabel: CortetsuNetwork.activeEthernet
        ? qsTr("Ethernet")
        : CortetsuNetwork.active?.ssid ?? qsTr("Sin conexión")
    property bool authenticationAccepted: false
    color: CortetsuDesign.colorSumi

    Component.onCompleted: {
        Qt.callLater(() => keyboardFocus.forceActiveFocus());
        // A surface created after PAM succeeded (output hotplug) must still finish the release.
        if (pam.successPending) {
            authenticationAccepted = true;
            unlockTransition.restart();
        }
    }

    Connections {
        target: root.lock

        function onSecureChanged(): void {
            if (root.lock.secure)
                Qt.callLater(() => keyboardFocus.forceActiveFocus());
        }
    }

    // The wallpaper, dimmed: never a copy of the desktop, whose windows
    // would be readable by whoever stands in front of a locked screen. If
    // the image cannot load, the surface stays plain sumi.
    Image {
        objectName: "lockBackdrop"
        anchors.fill: parent
        // The applied wallpaper, never one being previewed.
        source: CortetsuWallpapers.actualCurrent
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: true
        sourceSize.width: root.width
        sourceSize.height: root.height
        visible: status === Image.Ready
    }

    Rectangle {
        anchors.fill: parent
        color: Qt.alpha(CortetsuDesign.colorSumi, 0.72)
    }

    Item {
        id: keyboardFocus
        anchors.fill: parent
        focus: true
        onActiveFocusChanged: {
            if (root.lock.secure && !activeFocus)
                forceActiveFocus();
        }
        Keys.onPressed: event => {
            pam.handleKey(event);
            event.accepted = true;
        }
    }

    LockCard {
        anchors.fill: parent
        pam: root.pam
        accepted: root.authenticationAccepted
        userLabel: root.userLabel
        keyboardLayout: root.keyboardLayout
        capsLock: root.keyboard.capsLock
        numLock: root.keyboard.numLock
        batteryLabel: root.batteryLabel
        batteryCharging: root.batteryCharging
        networkLabel: root.networkLabel
        onFocusRequested: keyboardFocus.forceActiveFocus()
    }

    Connections {
        target: pam
        function onAuthenticationSucceeded(): void {
            root.authenticationAccepted = true;
            unlockTransition.restart();
        }
    }

    Timer {
        id: unlockTransition
        // PAM already accepted: the scene holds Cosmic long enough to be
        // seen, then the lock is released. Nothing here decides the unlock.
        interval: CortetsuDesign.reducedMotion ? 0 : 900
        repeat: false
        onTriggered: pam.releaseAfterSuccess()
    }

    Component.onDestruction: unlockTransition.stop()
}

//@ pragma UseQApplication
import QtQuick
import Quickshell
import Quickshell.Wayland
import "modules/polkit" as Polkit
import "theme"

// Agent Realms only: the realm has no polkitd, so `cortetsu realm qa` copies the
// build's runtime to <worktree>/.realm-tools/polkit-preview, puts this file at its
// shell.qml (Quickshell resolves qs.* imports from the config root) and shows the
// real PolkitDialog of the build under test, on the same Overlay layer and
// scrim as PolkitHost, with a stand-in AuthFlow. Nothing is ever submitted.
ShellRoot {
    PanelWindow {
        screen: Quickshell.screens[0]
        color: "transparent"
        WlrLayershell.namespace: "cortetsu-polkit-preview"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.exclusionMode: ExclusionMode.Ignore
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        anchors { top: true; bottom: true; left: true; right: true }

        Rectangle { anchors.fill: parent; color: Qt.alpha(CortetsuDesign.colorScrim, 0.72) }

        Polkit.PolkitDialog {
            anchors.centerIn: parent
            width: Math.min(implicitWidth, parent.width - 48)
            flow: QtObject {
                property string message: "Se requiere autenticación para ejecutar un programa como root"
                property string actionId: "org.freedesktop.policykit.exec"
                property var identities: [{ displayName: "dilan" }]
                property var selectedIdentity: identities[0]
                property bool isResponseRequired: true
                property string inputPrompt: "Contraseña: "
                property bool responseVisible: false
                property string supplementaryMessage: ""
                property bool supplementaryIsError: false
                property bool isCompleted: false
                property bool failed: false
                function submit(value) {}
                function cancelAuthenticationRequest() {}
            }
        }
    }
}

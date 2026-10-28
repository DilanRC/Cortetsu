import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import "../../components"
import "../../theme"
import "../CortetsuTypography.js" as CortetsuTypography

// One polkit request. `flow` is a Quickshell AuthFlow, or a stand-in with the
// same properties and methods in tests.
CortetsuSurface {
    id: root
    required property var flow
    readonly property var identities: flow?.identities ?? []
    readonly property bool canRespond: !!flow && flow.isResponseRequired && !flow.isCompleted
    property bool submitted: false

    implicitWidth: 440
    implicitHeight: body.implicitHeight + CortetsuDesign.spacingComfortable * 2
    radiusValue: CortetsuDesign.radiusSurface
    baseColor: Qt.alpha(CortetsuDesign.colorSurface, 0.98)
    outlined: true
    outlineColor: Qt.alpha(CortetsuDesign.colorOutlineVariant, 0.72)

    function identityName(identity): string {
        return identity?.displayName || identity?.string || qsTr("Usuario desconocido");
    }

    function submit(): void {
        if (!root.canRespond || password.text.length === 0)
            return;
        root.submitted = true;
        root.flow.submit(password.text);
        password.clear();
    }

    function cancel(): void {
        password.clear();
        root.flow?.cancelAuthenticationRequest();
    }

    function nextIdentity(): void {
        const list = root.identities;
        if (list.length < 2)
            return;
        const index = Array.from(list).indexOf(root.flow.selectedIdentity);
        root.flow.selectedIdentity = list[(index + 1) % list.length];
    }

    // polkit asks again after a wrong password; refocus the field for it.
    onCanRespondChanged: {
        if (canRespond)
            Qt.callLater(() => password.forceActiveFocus());
    }
    onFlowChanged: {
        password.clear();
        submitted = false;
    }
    onVisibleChanged: {
        if (!visible)
            password.clear();
        else
            Qt.callLater(() => password.forceActiveFocus());
    }

    // A shortcut, not a key handler: the field is disabled until polkit asks
    // and while PAM checks the answer, and Escape must cancel then too.
    Shortcut {
        sequence: "Escape"
        enabled: root.visible && !!root.flow && !root.flow.isCompleted
        onActivated: root.cancel()
    }

    ColumnLayout {
        id: body
        anchors.fill: parent
        anchors.margins: CortetsuDesign.spacingComfortable
        spacing: CortetsuDesign.spacingStandard

        RowLayout {
            Layout.fillWidth: true
            spacing: CortetsuDesign.spacingStandard
            CortetsuIcon {
                text: "admin_panel_settings"
                color: CortetsuDesign.colorPrimary
            }
            CortetsuText {
                Layout.fillWidth: true
                text: qsTr("Autenticación requerida")
                textSize: CortetsuTypography.titleMediumPx
                color: CortetsuDesign.colorOnSurface
            }
        }

        CortetsuText {
            objectName: "message"
            Layout.fillWidth: true
            text: root.flow?.message ?? ""
            textSize: CortetsuDesign.bodySmallPx
            color: CortetsuDesign.colorOnSurface
            wrapMode: Text.WordWrap
        }

        // The action id says what is being authorised, whatever the message claims.
        CortetsuText {
            Layout.fillWidth: true
            visible: text.length > 0
            text: root.flow?.actionId ?? ""
            textSize: CortetsuDesign.labelSmallPx
            color: CortetsuDesign.colorOnSurfaceVariant
            elide: Text.ElideMiddle
        }

        RowLayout {
            Layout.fillWidth: true
            CortetsuText {
                objectName: "identity"
                Layout.fillWidth: true
                text: qsTr("Como %1").arg(root.identityName(root.flow?.selectedIdentity))
                textSize: CortetsuDesign.bodySmallPx
                color: CortetsuDesign.colorOnSurfaceVariant
                elide: Text.ElideRight
            }
            CortetsuButton {
                objectName: "switchIdentity"
                visible: root.identities.length > 1
                compact: true
                label: qsTr("Cambiar usuario")
                icon: "switch_account"
                onClicked: root.nextIdentity()
            }
        }

        TextField {
            id: password
            objectName: "password"
            Layout.fillWidth: true
            implicitHeight: CortetsuDesign.controlHeight
            // polkit sends "Password: "; the field reads better without the colon.
            placeholderText: (root.flow?.inputPrompt ?? "").replace(/:\s*$/, "") || qsTr("Contraseña")
            echoMode: root.flow?.responseVisible ? TextInput.Normal : TextInput.Password
            enabled: root.canRespond
            focus: true
            color: CortetsuDesign.colorOnSurface
            placeholderTextColor: CortetsuDesign.colorOnSurfaceVariant
            Accessible.name: placeholderText
            background: CortetsuSurface {
                anchors.fill: parent
                radiusValue: CortetsuDesign.radiusSmall
                baseColor: CortetsuDesign.colorSurfaceGlassStrong
                outlined: true
            }
            Keys.onReturnPressed: root.submit()
            Keys.onEnterPressed: root.submit()
        }

        CortetsuText {
            objectName: "feedback"
            Layout.fillWidth: true
            readonly property bool wrong: root.submitted && !!root.flow?.failed
            readonly property bool isError: wrong || !!root.flow?.supplementaryIsError
            visible: text.length > 0
            text: root.flow?.supplementaryMessage || (wrong ? qsTr("Contraseña incorrecta. Inténtalo de nuevo.") : "")
            textSize: CortetsuDesign.labelSmallPx
            color: isError ? CortetsuDesign.colorVermillion : CortetsuDesign.colorOnSurfaceVariant
            wrapMode: Text.WordWrap
        }

        RowLayout {
            Layout.fillWidth: true
            Item { Layout.fillWidth: true }
            CortetsuButton {
                objectName: "cancel"
                compact: true
                label: qsTr("Cancelar")
                onClicked: root.cancel()
            }
            CortetsuButton {
                objectName: "authenticate"
                compact: true
                active: true
                label: qsTr("Autenticar")
                icon: "lock_open"
                disabled: !root.canRespond || password.text.length === 0
                onClicked: root.submit()
            }
        }
    }
}

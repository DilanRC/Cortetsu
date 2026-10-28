import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import "../../components"
import "../../theme"
import "../CortetsuTypography.js" as CortetsuTypography

// One gcr prompt: a keyring unlock or creation from gnome-keyring, or a GPG
// passphrase from pinentry-gnome3. `prompt` is the request line from
// cortetsu-prompter (desktop-runtime-rs/src/prompter.rs); `waiting` is true
// between an answer and the client's next prompt or its close.
CortetsuSurface {
    id: root
    required property var prompt
    property bool waiting: false
    signal answered(bool accepted, string password, bool choice)

    readonly property bool asksPassword: prompt?.kind === "password"
    readonly property bool isNew: asksPassword && !!prompt?.passwordNew
    readonly property bool mismatch: isNew && confirmField.text.length > 0 && confirmField.text !== password.text
    readonly property bool canContinue: !waiting
        && (!asksPassword || isNew || password.text.length > 0)
        && !(isNew && confirmField.text !== password.text)
    property bool choice: !!prompt?.choiceChosen

    implicitWidth: 460
    implicitHeight: body.implicitHeight + CortetsuDesign.spacingComfortable * 2
    radiusValue: CortetsuDesign.radiusSurface
    baseColor: Qt.alpha(CortetsuDesign.colorSurface, 0.98)
    outlined: true
    outlineColor: Qt.alpha(CortetsuDesign.colorOutlineVariant, 0.72)

    // gcr labels may carry GTK mnemonics ("_Unlock"); "__" is a literal "_".
    function label(text: string, fallback: string): string {
        return (text || "").replace(/__|_/g, m => m === "__" ? "_" : "") || fallback;
    }

    function clear(): void {
        password.clear();
        confirmField.clear();
    }

    function accept(): void {
        if (!root.canContinue)
            return;
        const secret = root.asksPassword ? password.text : "";
        root.clear();
        root.answered(true, secret, root.choice);
    }

    function cancel(): void {
        root.clear();
        root.answered(false, "", root.choice);
    }

    function refocus(): void {
        if (root.asksPassword)
            password.forceActiveFocus();
        else
            continueButton.forceActiveFocus();
    }

    // A new prompt on the same dialog: after a wrong password the client
    // asks again with a warning.
    onPromptChanged: {
        root.clear();
        root.choice = !!prompt?.choiceChosen;
        Qt.callLater(root.refocus);
    }
    onWaitingChanged: if (!waiting) Qt.callLater(root.refocus)
    onVisibleChanged: {
        if (!visible)
            root.clear();
        else
            Qt.callLater(root.refocus);
    }

    // A shortcut, so Escape cancels while the fields are disabled too.
    Shortcut {
        sequence: "Escape"
        enabled: root.visible && !!root.prompt
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
                text: root.asksPassword ? "key" : "help"
                color: CortetsuDesign.colorPrimary
            }
            CortetsuText {
                objectName: "heading"
                Layout.fillWidth: true
                // pinentry-gnome3 sends the field label here ("Passphrase:").
                text: (root.prompt?.message ?? "").replace(/:\s*$/, "") || qsTr("Contraseña requerida")
                textSize: CortetsuTypography.titleMediumPx
                color: CortetsuDesign.colorOnSurface
                wrapMode: Text.WordWrap
            }
        }

        // Who asks: pinentry-gnome3 puts "[pid]@host (command)" here.
        CortetsuText {
            objectName: "caller"
            Layout.fillWidth: true
            visible: text.length > 0
            text: root.prompt?.title ?? ""
            textSize: CortetsuDesign.labelSmallPx
            color: CortetsuDesign.colorOnSurfaceVariant
            elide: Text.ElideMiddle
        }

        CortetsuText {
            objectName: "description"
            Layout.fillWidth: true
            visible: text.length > 0
            text: (root.prompt?.description ?? "").trim()
            textSize: CortetsuDesign.bodySmallPx
            color: CortetsuDesign.colorOnSurfaceVariant
            wrapMode: Text.WordWrap
        }

        TextField {
            id: password
            objectName: "password"
            Layout.fillWidth: true
            visible: root.asksPassword
            implicitHeight: CortetsuDesign.controlHeight
            placeholderText: root.isNew ? qsTr("Contraseña nueva") : qsTr("Contraseña")
            echoMode: TextInput.Password
            enabled: !root.waiting
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
            Keys.onReturnPressed: root.isNew ? confirmField.forceActiveFocus() : root.accept()
            Keys.onEnterPressed: root.isNew ? confirmField.forceActiveFocus() : root.accept()
        }

        TextField {
            id: confirmField
            objectName: "confirm"
            Layout.fillWidth: true
            visible: root.isNew
            implicitHeight: CortetsuDesign.controlHeight
            placeholderText: qsTr("Repite la contraseña")
            echoMode: TextInput.Password
            enabled: !root.waiting
            color: CortetsuDesign.colorOnSurface
            placeholderTextColor: CortetsuDesign.colorOnSurfaceVariant
            Accessible.name: placeholderText
            background: CortetsuSurface {
                anchors.fill: parent
                radiusValue: CortetsuDesign.radiusSmall
                baseColor: CortetsuDesign.colorSurfaceGlassStrong
                outlined: true
            }
            Keys.onReturnPressed: root.accept()
            Keys.onEnterPressed: root.accept()
        }

        CortetsuText {
            objectName: "feedback"
            Layout.fillWidth: true
            readonly property bool isError: !root.waiting && (root.mismatch || !!root.prompt?.warning)
            visible: text.length > 0
            text: root.waiting ? qsTr("Comprobando…")
                : root.mismatch ? qsTr("Las contraseñas no coinciden.")
                : (root.prompt?.warning ?? "")
            textSize: CortetsuDesign.labelSmallPx
            color: isError ? CortetsuDesign.colorVermillion : CortetsuDesign.colorOnSurfaceVariant
            wrapMode: Text.WordWrap
        }

        RowLayout {
            objectName: "choiceRow"
            Layout.fillWidth: true
            visible: (root.prompt?.choiceLabel ?? "").length > 0
            spacing: CortetsuDesign.spacingStandard
            CortetsuText {
                Layout.fillWidth: true
                text: root.label(root.prompt?.choiceLabel ?? "", "")
                textSize: CortetsuDesign.bodySmallPx
                color: CortetsuDesign.colorOnSurface
                wrapMode: Text.WordWrap
            }
            CortetsuToggle {
                objectName: "choice"
                accessibleName: root.label(root.prompt?.choiceLabel ?? "", "")
                checked: root.choice
                disabled: root.waiting
                onToggled: checked => root.choice = checked
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Item { Layout.fillWidth: true }
            CortetsuButton {
                objectName: "cancel"
                compact: true
                label: root.label(root.prompt?.cancelLabel ?? "", qsTr("Cancelar"))
                onClicked: root.cancel()
            }
            CortetsuButton {
                id: continueButton
                objectName: "continue"
                compact: true
                active: true
                label: root.label(root.prompt?.continueLabel ?? "", qsTr("Continuar"))
                icon: root.asksPassword ? "lock_open" : ""
                disabled: !root.canContinue
                onClicked: root.accept()
            }
        }
    }
}

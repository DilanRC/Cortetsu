import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import "../../components"
import "../../theme"
import "../CortetsuTypography.js" as CortetsuTypography

// One password or confirmation request. cortetsu-prompter
// (desktop-runtime-rs/src/prompter.rs) sends keyring unlocks and GPG
// passphrases; cortetsu-agents (src/agents.rs) sends Wi-Fi passwords,
// WPA-Enterprise logins and Bluetooth pairing codes. `prompt` is the request
// line; `waiting` is true between an answer and the client's next prompt or
// its close. A "display" request only shows a code until it is closed.
CortetsuSurface {
    id: root
    required property var prompt
    property bool waiting: false
    signal answered(bool accepted, string password, bool choice, string identity)

    readonly property bool asksPassword: prompt?.kind === "password"
    readonly property bool isDisplay: prompt?.kind === "display"
    readonly property bool asksIdentity: asksPassword && (prompt?.identityLabel ?? "").length > 0
    readonly property bool isNew: asksPassword && !!prompt?.passwordNew
    readonly property int minLength: asksPassword ? (prompt?.minLength ?? 0) : 0
    readonly property bool tooShort: password.text.length > 0 && password.text.length < minLength
    readonly property bool mismatch: isNew && confirmField.text.length > 0 && confirmField.text !== password.text
    readonly property bool canContinue: !waiting && !isDisplay
        && (!asksPassword || isNew || password.text.length > 0)
        && !tooShort
        && !(asksIdentity && identityField.text.trim().length === 0)
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
        const identity = root.asksIdentity ? identityField.text.trim() : "";
        root.clear();
        root.answered(true, secret, root.choice, identity);
    }

    function cancel(): void {
        root.clear();
        root.answered(false, "", root.choice, "");
    }

    function refocus(): void {
        if (root.asksIdentity && identityField.text.length === 0)
            identityField.forceActiveFocus();
        else if (root.asksPassword)
            password.forceActiveFocus();
        else if (root.isDisplay)
            cancelButton.forceActiveFocus();
        else
            continueButton.forceActiveFocus();
    }

    // A new prompt on the same dialog: after a wrong password the client
    // asks again with a warning.
    onPromptChanged: {
        root.clear();
        root.choice = !!prompt?.choiceChosen;
        identityField.text = prompt?.identity ?? "";
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
                text: root.prompt?.icon || (root.asksPassword ? "key" : "help")
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

        // A pairing code to compare or to type on the other device.
        CortetsuText {
            objectName: "code"
            Layout.fillWidth: true
            visible: text.length > 0
            text: root.prompt?.code ?? ""
            horizontalAlignment: Text.AlignHCenter
            font.features: { "tnum": 1 }
            font.letterSpacing: 4
            textSize: CortetsuTypography.displaySmallPx
            color: CortetsuDesign.colorOnSurface
            Accessible.name: qsTr("Código %1").arg(text.split("").join(" "))
        }

        TextField {
            id: identityField
            objectName: "identity"
            Layout.fillWidth: true
            visible: root.asksIdentity
            implicitHeight: CortetsuDesign.controlHeight
            placeholderText: root.prompt?.identityLabel ?? ""
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
            Keys.onReturnPressed: password.forceActiveFocus()
            Keys.onEnterPressed: password.forceActiveFocus()
        }

        RegularExpressionValidator {
            id: digitsValidator
            regularExpression: /[0-9]*/
        }

        TextField {
            id: password
            objectName: "password"
            Layout.fillWidth: true
            visible: root.asksPassword
            implicitHeight: CortetsuDesign.controlHeight
            placeholderText: root.isNew ? qsTr("Contraseña nueva") : (root.prompt?.passwordLabel || qsTr("Contraseña"))
            // A Bluetooth PIN or passkey is read off a screen, not a secret to hide.
            echoMode: root.prompt?.reveal ? TextInput.Normal : TextInput.Password
            maximumLength: root.prompt?.maxLength || 32767
            validator: root.prompt?.digits ? digitsValidator : null
            inputMethodHints: root.prompt?.digits ? Qt.ImhDigitsOnly : Qt.ImhSensitiveData | Qt.ImhNoPredictiveText
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
            readonly property bool isError: !root.waiting && !root.tooShort && (root.mismatch || !!root.prompt?.warning)
            visible: text.length > 0
            text: root.waiting ? qsTr("Comprobando…")
                : root.mismatch ? qsTr("Las contraseñas no coinciden.")
                : root.tooShort ? qsTr("Al menos %1 caracteres.").arg(root.minLength)
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
                id: cancelButton
                objectName: "cancel"
                compact: true
                label: root.label(root.prompt?.cancelLabel ?? "", qsTr("Cancelar"))
                onClicked: root.cancel()
            }
            CortetsuButton {
                id: continueButton
                objectName: "continue"
                visible: !root.isDisplay
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

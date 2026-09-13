import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import "../../../components"
import "../../../services"
import "../../CortetsuDesign.js" as CortetsuDesign
import "../.."

CortetsuSurface {
    id: root
    required property var popouts
    property var network: null
    property bool connecting: false
    property string errorText: ""

    implicitWidth: 324
    implicitHeight: body.implicitHeight + CortetsuDesign.spacingComfortable * 2
    radiusValue: CortetsuDesign.radiusLarge
    baseColor: CortetsuDesign.colorSurfaceGlass
    outlined: true
    focus: popouts.currentName === "wirelesspassword"

    ColumnLayout {
        id: body
        anchors.fill: parent
        anchors.margins: CortetsuDesign.spacingComfortable
        spacing: CortetsuDesign.spacingStandard

        CortetsuSectionHeader {
            title: qsTr("Conectarse a una red")
            detail: root.network?.name ?? qsTr("Wi‑Fi")
        }

        CortetsuText {
            Layout.fillWidth: true
            text: qsTr("Escribe la contraseña para conectarte.")
            textSize: CortetsuDesign.bodySmallPx
            color: CortetsuDesign.colorOnSurfaceVariant
            wrapMode: Text.WordWrap
        }

        TextField {
            id: password
            Layout.fillWidth: true
            implicitHeight: CortetsuDesign.controlHeight
            placeholderText: qsTr("Contraseña")
            echoMode: TextInput.Password
            enabled: !root.connecting
            color: CortetsuDesign.colorOnSurface
            placeholderTextColor: CortetsuDesign.colorOnSurfaceVariant
            background: CortetsuSurface {
                anchors.fill: parent
                radiusValue: CortetsuDesign.radiusSmall
                baseColor: CortetsuDesign.colorSurfaceGlassStrong
                outlined: true
            }
            Keys.onReturnPressed: root.connect()

            Component.onCompleted: {
                if (root.popouts.currentName === "wirelesspassword")
                    forceActiveFocus();
            }
        }

        CortetsuText {
            Layout.fillWidth: true
            visible: root.errorText.length > 0
            text: root.errorText
            textSize: CortetsuDesign.labelSmallPx
            color: CortetsuDesign.colorVermillion
            wrapMode: Text.WordWrap
        }

        RowLayout {
            Layout.fillWidth: true
            CortetsuButton {
                compact: true
                label: qsTr("Atrás")
                icon: "arrow_back"
                enabled: !root.connecting
                onClicked: root.closeDialog()
            }
            Item { Layout.fillWidth: true }
            CortetsuButton {
                compact: true
                active: true
                label: root.connecting ? qsTr("Conectando…") : qsTr("Conectar")
                icon: root.connecting ? "sync" : "link"
                disabled: root.connecting || !root.network || password.text.length === 0
                onClicked: root.connect()
            }
        }
    }

    Timer {
        id: timeout
        interval: 8000
        onTriggered: {
            root.connecting = false;
            root.errorText = qsTr("Se agotó el tiempo. Revisa la contraseña e inténtalo de nuevo.");
        }
    }

    Connections {
        target: CortetsuNetwork
        function onActiveChanged(): void {
            if (root.connecting && CortetsuNetwork.active?.ssid === root.network?.name) {
                timeout.stop();
                root.connecting = false;
                root.popouts.hasCurrent = false;
            }
        }
    }

    Connections {
        target: root.network
        function onConnectionFailed(_reason): void {
            if (!root.connecting)
                return;
            timeout.stop();
            root.connecting = false;
            root.errorText = qsTr("No se pudo conectar. Revisa la contraseña.");
            password.forceActiveFocus();
        }
    }

    Connections {
        target: root.popouts
        function onCurrentNameChanged(): void {
            if (root.popouts.currentName === "wirelesspassword")
                Qt.callLater(() => password.forceActiveFocus());
        }
    }

    Keys.onEscapePressed: root.closeDialog()

    function connect(): void {
        if (!root.network || password.text.length === 0 || root.connecting)
            return;
        root.errorText = "";
        root.connecting = true;
        timeout.restart();
        NetworkConnection.connectWithPassword(root.network, password.text, result => {
            if (result?.success !== true) {
                timeout.stop();
                root.connecting = false;
                root.errorText = qsTr("No se pudo conectar a esta red.");
            }
        });
    }

    function closeDialog(): void {
        timeout.stop();
        root.connecting = false;
        root.errorText = "";
        password.clear();
        root.popouts.currentName = "network";
    }
}

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import "../../../components"
import "../../../services"
import "../../../theme"
import "../.."

CortetsuSurface {
    id: root
    required property var popouts
    property var network: null
    readonly property bool connecting: Connectivity.wifi.operationNetwork === root.network && Connectivity.wifi.busy
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

    Connections {
        target: Connectivity.wifi
        function onOperationChanged(): void {
            if (Connectivity.wifi.operationNetwork !== root.network) return;
            const op = Connectivity.wifi.operation;
            if (op.state === "connected" && root.network?.connected) {
                password.clear();
                root.popouts.hasCurrent = false;
            } else if (op.state === "failed") {
                root.errorText = op.lastError;
                password.forceActiveFocus();
            }
        }
    }

    Connections {
        target: root.popouts
        function onCurrentNameChanged(): void {
            if (root.popouts.currentName === "wirelesspassword")
                Qt.callLater(() => password.forceActiveFocus());
            else password.clear();
        }
    }

    onVisibleChanged: { if (!visible) password.clear(); }
    Keys.onEscapePressed: root.closeDialog()

    function connect(): void {
        if (!root.network || password.text.length === 0 || root.connecting)
            return;
        root.errorText = "";
        Connectivity.wifi.connectNetwork(root.network, password.text, null);
        password.clear();
    }

    function closeDialog(): void {
        root.errorText = "";
        password.clear();
        root.popouts.currentName = "network";
    }
}

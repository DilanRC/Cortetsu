pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.components
import qs.components.controls
import qs.services
import qs.modules.nexus.common

// Sub-page for manually adding a (typically hidden) Wi-Fi network. Reached from
// the "Add network" row on NetworkPage via nState.openSubPage.
PageBase {
    id: root

    // Security model: index 0 = none, 1 = WPA/WPA2/WPA3 personal.
    readonly property bool secured: securitySelect.active !== noneItem
    property bool connecting: false
    property bool failed: false
    property bool success: false
    property bool existingNetwork: false

    function submit(): void {
        const ssid = ssidField.text;
        if (ssid.length === 0) {
            ssidField.isError = true;
            ssidField.forceActiveFocus();
            return;
        }
        if (root.secured && passwordField.text.length < (securitySelect.active === saeItem ? 1 : 8)) {
            passwordField.isError = true;
            passwordField.forceActiveFocus();
            return;
        }

        if (root.existingNetwork && !Connectivity.wifi.networks.includes(root.nState.selectedNetwork)) { root.failed = true; passwordField.text = ""; return; }
        const secret = root.secured ? passwordField.text : "";
        passwordField.text = "";
        if (root.nState.selectedNetwork && Connectivity.wifi.networks.includes(root.nState.selectedNetwork))
            Connectivity.wifi.connectNetwork(root.nState.selectedNetwork, secret, null);
        else Connectivity.wifi.connectHidden(ssid, Connectivity.wifi.wifiDevice?.name ?? "", secret, root.secured ? (securitySelect.active === saeItem ? "sae" : "wpa-psk") : "open");
        root.requestId = Connectivity.wifi.operation.id;
        root.connecting = Connectivity.wifi.busy;
        root.failed = ["failed", "auth-required"].includes(Connectivity.wifi.operation.state);
    }

    property int requestId: -1
    onVisibleChanged: { if (!visible) passwordField.text = ""; }
    Component.onCompleted: {
        root.existingNetwork = !!root.nState.selectedNetwork;
        ssidField.text = root.nState.selectedNetwork?.name ?? "";
        if (root.nState.selectedNetwork) hiddenToggle.checked = false;
    }
    property Connections operationConnections: Connections {
        target: Connectivity.wifi
        function onOperationChanged() {
            const op = Connectivity.wifi.operation;
            if (op.id !== root.requestId) return;
            root.connecting = Connectivity.wifi.busy;
            root.failed = ["failed", "auth-required"].includes(op.state);
            root.success = op.state === "connected";
            if (root.success) root.nState.closeSubPage();
        }
    }

    title: qsTr("Add network")
    isSubPage: true

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: CortetsuTokens.spacing.large

        CortetsuText {
            Layout.fillWidth: true
            Layout.leftMargin: CortetsuTokens.padding.extraSmall
            text: qsTr("Enter the details below to manually connect to a network.")
            color: CortetsuColours.palette.m3onSurfaceVariant
            font: CortetsuTokens.font.body.small
            wrapMode: Text.WordWrap
        }

        StyledTextField {
            id: ssidField
            readOnly: root.existingNetwork

            Layout.fillWidth: true
            Layout.topMargin: CortetsuTokens.spacing.extraSmall
            placeholderText: qsTr("Network name (SSID)")
            supportingText: qsTr("e.g. MyHiddenNetwork")
            leadingIcon: "wifi"
            errorText: qsTr("Network name is required")
            inputMethodHints: Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText

            onAccepted: root.secured ? passwordField.forceActiveFocus() : root.submit()
        }

        ToggleRow {
            id: hiddenToggle

            first: true
            text: qsTr("Hidden network")
            subtext: qsTr("Actively probe for a network that doesn't broadcast its name")
            checked: true
            enabled: false
        }

        SelectRow {
            id: securitySelect

            Layout.topMargin: CortetsuTokens.spacing.extraSmall / 2 - parent.spacing
            last: !root.secured
            label: qsTr("Security")
            fallbackText: qsTr("WPA/WPA2 Personal")
            fallbackIcon: "lock"

            menuItems: [
                MenuItem {
                    icon: "lock"
                    text: qsTr("WPA/WPA2 Personal")
                },
                MenuItem {
                    id: saeItem
                    icon: "lock"
                    text: qsTr("WPA3 Personal (SAE)")
                },
                MenuItem {
                    id: noneItem

                    icon: "lock_open"
                    text: qsTr("None (open)")
                }
            ]

            Behavior on bottomLeftRadius {
                Anim {
                    type: Anim.DefaultEffects
                }
            }

            Behavior on bottomRightRadius {
                Anim {
                    type: Anim.DefaultEffects
                }
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.bottomMargin: root.secured ? 0 : -parent.spacing
            implicitHeight: root.secured ? passwordField.implicitHeight : 0
            opacity: root.secured ? 1 : 0

            Behavior on Layout.bottomMargin {
                Anim {
                    type: Anim.DefaultEffects
                }
            }

            Behavior on implicitHeight {
                Anim {
                    type: Anim.DefaultEffects
                }
            }

            Behavior on opacity {
                Anim {
                    type: Anim.DefaultEffects
                }
            }

            StyledTextField {
                id: passwordField

                anchors.left: parent.left
                anchors.right: parent.right

                enabled: root.secured
                placeholderText: qsTr("Password")
                leadingIcon: "key"
                echoMode: TextInput.Password
                supportingText: qsTr("WPA passwords are at least 8 characters")
                errorText: root.failed ? qsTr("Connection failed — check the password") : qsTr("Password must be at least 8 characters")

                onAccepted: root.submit()
            }
        }

        RowLayout {
            Layout.alignment: Qt.AlignRight
            Layout.topMargin: CortetsuTokens.spacing.extraSmall - parent.spacing
            spacing: CortetsuTokens.spacing.small

            TextButton {
                Layout.fillHeight: true
                isRound: true
                horizontalPadding: CortetsuTokens.padding.extraLarge
                type: TextButton.Tonal
                text: qsTr("Cancel")
                onClicked: root.nState.closeSubPage()
            }

            // Connect button — swaps to a loading spinner while connecting,
            // matching the Wi-Fi list connect animation.
            ButtonBase {
                id: connectBtn

                shapeMorph: true
                isRound: true
                inactiveColour: CortetsuColours.palette.m3primary
                inactiveOnColour: CortetsuColours.palette.m3onPrimary
                stateLayer.disabled: root.connecting || ssidField.text.length === 0

                implicitWidth: connectMetrics.width + CortetsuTokens.padding.extraLarge * 2
                implicitHeight: connectMetrics.height + CortetsuTokens.padding.medium * 2

                onClicked: {
                    if (!root.connecting && ssidField.text.length > 0)
                        root.submit();
                }

                TextMetrics {
                    id: connectMetrics

                    text: qsTr("Connect")
                    font: connectBtn.font
                }

                AnimLoader {
                    id: connectContent

                    anchors.centerIn: parent
                    sourceComp: root.connecting ? connectLoadingComp : connectTextComp
                    outAnimType: Anim.SlowEffects
                    inAnimType: Anim.SlowEffects
                }

                Component {
                    id: connectLoadingComp

                    LoadingIndicator {
                        implicitSize: Math.round(CortetsuTokens.font.body.medium.pointSize * 1.4)
                        color: connectBtn.onColour
                    }
                }

                Component {
                    id: connectTextComp

                    CortetsuText {
                        text: connectMetrics.text
                        font: connectBtn.font
                        color: connectBtn.onColour
                    }
                }
            }
        }
    }
}

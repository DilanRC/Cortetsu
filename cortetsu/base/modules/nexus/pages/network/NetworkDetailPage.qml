pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell.Networking
import qs.components
import qs.components.controls
import qs.services
import qs.modules.nexus.common

// Detail / settings sub-page for the active Wi-Fi network. Reached by tapping
// the active network row (settings icon) on NetworkPage.
PageBase {
    id: root

    readonly property string ssid: nState.selectedNetworkSsid
    readonly property var ap: Connectivity.wifi.networks.includes(nState.selectedNetwork) ? nState.selectedNetwork : null
    readonly property string profileUuid: nState.selectedNetworkUuid || (ap?.connected ? Connectivity.wifi.details[ap.device.name]?.uuid ?? "" : "")
    readonly property var profile: Connectivity.wifi.profiles.find(item => item.uuid === profileUuid) ?? null
    readonly property var details: Connectivity.wifi.details[ap?.device?.name || profile?.interface] ?? ({})
    readonly property bool isActive: !!ap?.connected && details.uuid === profileUuid

    // Locally-edited IPv4 form state.
    property string ipMethod: "auto" // "auto" | "auto-dns" | "manual"
    property bool ipLoaded: false
    property bool savingIp: false
    readonly property bool autoconnect: profile?.autoconnect ?? false

    // Snapshot of the saved IPv4 config, so the Apply button only shows up once
    // something actually changed.
    property string origMethod: "auto"
    property string origAddress: ""
    property string origGateway: ""
    property string origDns: ""

    readonly property bool hasChanges: root.ipLoaded && (root.ipMethod !== root.origMethod || (root.ipMethod === "manual" && (addressField.text.trim() !== root.origAddress || gatewayField.text.trim() !== root.origGateway)) || ((root.ipMethod === "manual" || root.ipMethod === "auto-dns") && dnsField.text.trim() !== root.origDns))
    readonly property bool showDnsSettings: root.ipMethod === "manual" || root.ipMethod === "auto-dns"

    property int saveId: -1
    property int actionId: -1
    function observeAction(): void {
        const op = Connectivity.wifi.operation;
        if (op.id === actionId && ["idle", "connected"].includes(op.state) && !Connectivity.wifi.busy) root.nState.closeSubPage();
    }
    function loadIpConfig(): void {
        const cfg = profile?.ipv4;
        if (!cfg || root.ipLoaded) return;
        root.ipMethod = cfg.method === "auto" && cfg.ignoreAutoDns ? "auto-dns" : cfg.method;
        methodSelect.active = root.ipMethod === "manual" ? manualItem : (root.ipMethod === "auto-dns" ? autoDnsItem : autoItem);
        addressField.text = (cfg.addresses ?? []).join(", ");
        gatewayField.text = cfg.gateway ?? "";
        dnsField.text = (cfg.dns ?? []).join(", ");
        root.origMethod = root.ipMethod;
        root.origAddress = addressField.text;
        root.origGateway = gatewayField.text;
        root.origDns = dnsField.text;
        root.ipLoaded = true;
    }
    function saveIpConfig(): void {
        if (!root.profile || Connectivity.wifi.busy) return;
        Connectivity.wifi.setIpv4(root.profile.uuid, root.ipMethod === "auto-dns" ? "auto" : root.ipMethod,
            addressField.text.trim(), gatewayField.text.trim(), root.ipMethod === "auto" ? "" : dnsField.text.trim());
        root.saveId = Connectivity.wifi.operation.id;
        observeSave();
    }
    function observeSave(): void {
        const op = Connectivity.wifi.operation;
        if (op.id !== saveId) return;
        savingIp = Connectivity.wifi.busy;
        if (op.state === "failed") { addressField.isError = true; return; }
        if (!savingIp && op.state === "idle") {
            root.origMethod = root.ipMethod;
            root.origAddress = addressField.text.trim();
            root.origGateway = gatewayField.text.trim();
            root.origDns = dnsField.text.trim();
        }
    }
    onProfileChanged: { if (!root.ipLoaded) loadIpConfig(); }
    property Connections operationConnections: Connections {
        target: Connectivity.wifi
        function onOperationChanged() { root.observeSave(); root.observeAction(); }
    }

    // Close if the network is no longer active (e.g. disconnected elsewhere).
    // ...But not when the page was opened from saved networks
    onApChanged: {
        if (!nState.networkDetailsFromSaved && root.ipLoaded && !root.ap)
            nState.closeSubPage();
    }

    title: root.ssid || qsTr("Network")
    isSubPage: true

    Component.onCompleted: {
        Connectivity.wifi.refreshDetails(ap?.device?.name || profile?.interface || "");
        loadIpConfig();
    }

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: CortetsuTokens.spacing.extraSmall / 2

        // ---- Action buttons --------------------------------------------------
        ButtonRow {
            Layout.bottomMargin: CortetsuTokens.spacing.large - parent.spacing
            Layout.alignment: Qt.AlignHCenter
            Layout.minimumWidth: Math.round(root.cappedWidth * (root.isActive ? 0.7 : 0.5))
            spacing: CortetsuTokens.spacing.small

            ButtonBase {
                id: forgetBtn
                stateLayer.disabled: !root.profile || Connectivity.wifi.busy

                fillWidth: true
                shapeMorph: root.isActive
                isRound: true
                inactiveColour: CortetsuColours.palette.m3errorContainer
                inactiveOnColour: CortetsuColours.palette.m3onErrorContainer

                implicitWidth: forgetLayout.implicitWidth + CortetsuTokens.padding.extraLarge * 2
                implicitHeight: forgetLayout.implicitHeight + CortetsuTokens.padding.medium * 2

                onClicked: {
                    if (root.profile) Connectivity.wifi.forgetProfile(root.profile.uuid);
                    root.actionId = Connectivity.wifi.operation.id;
                    root.observeAction();
                }

                ColumnLayout {
                    id: forgetLayout

                    anchors.centerIn: parent
                    spacing: 0

                    CortetsuIcon {
                        Layout.alignment: Qt.AlignHCenter
                        text: "delete"
                        color: forgetBtn.onColour
                        fontStyle: CortetsuTokens.font.icon.medium
                    }

                    CortetsuText {
                        Layout.alignment: Qt.AlignHCenter
                        text: qsTr("Forget")
                        color: forgetBtn.onColour
                    }
                }
            }

            ButtonBase {
                id: disconnectBtn
                stateLayer.disabled: Connectivity.wifi.busy

                visible: root.isActive || !!root.profile
                fillWidth: true
                shapeMorph: true
                isRound: true
                inactiveColour: CortetsuColours.palette.m3primaryContainer
                inactiveOnColour: CortetsuColours.palette.m3onPrimaryContainer

                implicitWidth: disconnectLayout.implicitWidth + CortetsuTokens.padding.extraLarge * 2
                implicitHeight: disconnectLayout.implicitHeight + CortetsuTokens.padding.medium * 2

                onClicked: {
                    if (root.isActive && root.ap) Connectivity.wifi.disconnectNetwork(root.ap);
                    else if (root.profile) Connectivity.wifi.connectProfile(root.profile.uuid, root.ap?.device?.name || root.profile.interface || "");
                    root.actionId = Connectivity.wifi.operation.id;
                    root.observeAction();
                }

                ColumnLayout {
                    id: disconnectLayout

                    anchors.centerIn: parent
                    spacing: 0

                    CortetsuIcon {
                        Layout.alignment: Qt.AlignHCenter
                        text: root.isActive ? "link_off" : "link"
                        color: disconnectBtn.onColour
                        fontStyle: CortetsuTokens.font.icon.medium
                    }

                    CortetsuText {
                        Layout.alignment: Qt.AlignHCenter
                        text: root.isActive ? qsTr("Disconnect") : qsTr("Connect")
                        color: disconnectBtn.onColour
                    }
                }
            }
        }

        // ---- Connection info (only shows when active) ---------------------------------
        SectionHeader {
            first: true
            text: qsTr("Connection")
            visible: root.isActive
        }

        InfoRow {
            first: true
            icon: "signal_wifi_4_bar"
            label: qsTr("Signal")
            value: root.ap ? qsTr("%1%").arg(Math.round(root.ap.signalStrength * 100)) : qsTr("—")
            visible: root.isActive
        }

        InfoRow {
            icon: "lock"
            label: qsTr("Security")
            value: root.ap ? WifiSecurityType.toString(root.ap.security) : qsTr("—")
            visible: root.isActive
        }

        InfoRow {
            icon: "graphic_eq"
            label: qsTr("Frequency")
            value: root.ap ? qsTr("%1 MHz").arg(Connectivity.wifi.accessPoints.find(item => item.active && item.ssid === root.ap.name && item.device === root.ap.device.name)?.frequency ?? 0) : qsTr("—")
            visible: root.isActive
        }

        InfoRow {
            icon: "lan"
            label: qsTr("IP address")
            value: root.details?.address || qsTr("—")
            visible: root.isActive
        }

        InfoRow {
            icon: "router"
            label: qsTr("Gateway")
            value: root.details?.gateway || qsTr("—")
            visible: root.isActive
        }

        InfoRow {
            last: true
            icon: "memory"
            label: qsTr("MAC address")
            value: root.details?.macAddress || qsTr("—")
            visible: root.isActive
        }

        // ---- Behaviour -------------------------------------------------------
        SectionHeader {
            first: !root.isActive
            text: qsTr("Behaviour")
        }

        ToggleRow {
            Layout.fillWidth: true
            first: true
            last: true
            text: qsTr("Connect automatically")
            subtext: qsTr("Join this network when it's in range")
            checked: root.autoconnect
            enabled: root.ipLoaded
            onToggled: {
                if (root.profile) Connectivity.wifi.setAutoconnect(root.profile.uuid, checked);
            }
        }

        CortetsuText {
            Layout.fillWidth: true
            visible: root.saveId === Connectivity.wifi.operation.id
            text: Connectivity.wifi.operation.state === "failed" ? Connectivity.wifi.operation.lastError
                : !root.savingIp && Connectivity.wifi.operation.state === "idle" ? qsTr("Guardado y confirmado. Reconecta el perfil para aplicar IPv4.") : qsTr("Guardando IPv4…")
            wrapMode: Text.WordWrap
            color: CortetsuColours.palette.m3onSurfaceVariant
            font: CortetsuTokens.font.body.small
        }

        // ---- IPv4 ------------------------------------------------------------
        SectionHeader {
            text: qsTr("IPv4")
        }

        SelectRow {
            id: methodSelect

            first: true
            last: root.ipMethod === "auto"
            label: qsTr("IP assignment")
            fallbackText: qsTr("Automatic (DHCP)")
            fallbackIcon: "lan"

            onSelected: item => root.ipMethod = item === manualItem ? "manual" : (item === autoDnsItem ? "auto-dns" : "auto")

            menuItems: [
                MenuItem {
                    id: autoItem

                    icon: "lan"
                    text: qsTr("Automatic (DHCP)")
                },
                MenuItem {
                    id: autoDnsItem

                    icon: "dns"
                    text: qsTr("Automatic, DNS only")
                },
                MenuItem {
                    id: manualItem

                    icon: "edit"
                    text: qsTr("Manual")
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

        // Address + gateway: manual only. DNS: manual and DNS-only.
        Item {
            Layout.fillWidth: true
            Layout.topMargin: root.showDnsSettings ? CortetsuTokens.spacing.large : -parent.spacing
            implicitHeight: root.showDnsSettings ? dnsColumn.implicitHeight : 0
            opacity: root.showDnsSettings ? 1 : 0

            Behavior on Layout.topMargin {
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

            ColumnLayout {
                id: dnsColumn

                anchors.left: parent.left
                anchors.right: parent.right
                spacing: root.ipMethod === "manual" ? CortetsuTokens.spacing.large : 0

                Behavior on spacing {
                    Anim {
                        type: Anim.DefaultEffects
                    }
                }

                Item {
                    Layout.fillWidth: true
                    implicitHeight: root.ipMethod === "manual" ? manualDnsColumn.implicitHeight : 0
                    opacity: root.ipMethod === "manual" ? 1 : 0

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

                    ColumnLayout {
                        id: manualDnsColumn

                        anchors.left: parent.left
                        anchors.right: parent.right
                        spacing: CortetsuTokens.spacing.large

                        StyledTextField {
                            id: addressField

                            Layout.fillWidth: true
                            placeholderText: qsTr("Address (CIDR)")
                            leadingIcon: "router"
                            supportingText: qsTr("IP and prefix, e.g. 192.168.1.50/24")
                            errorText: qsTr("Enter a valid address in CIDR notation")
                            inputMethodHints: Qt.ImhNoPredictiveText
                            validate: /^(?:(?:25[0-5]|2[0-4]\d|1?\d?\d)\.){3}(?:25[0-5]|2[0-4]\d|1?\d?\d)\/(?:3[0-2]|[12]?\d)$/
                        }

                        StyledTextField {
                            id: gatewayField

                            Layout.fillWidth: true
                            placeholderText: qsTr("Gateway")
                            leadingIcon: "exit_to_app"
                            errorText: qsTr("Enter a valid gateway address")
                            inputMethodHints: Qt.ImhNoPredictiveText
                            validate: /^$|^(?:(?:25[0-5]|2[0-4]\d|1?\d?\d)\.){3}(?:25[0-5]|2[0-4]\d|1?\d?\d)$/
                        }
                    }
                }

                StyledTextField {
                    id: dnsField

                    Layout.fillWidth: true
                    placeholderText: qsTr("DNS servers")
                    leadingIcon: "dns"
                    supportingText: qsTr("Comma-separated")
                    errorText: qsTr("Enter valid DNS server addresses")
                    inputMethodHints: Qt.ImhNoPredictiveText
                    validate: /^$|^\s*(?:(?:25[0-5]|2[0-4]\d|1?\d?\d)\.){3}(?:25[0-5]|2[0-4]\d|1?\d?\d)(?:\s*,\s*(?:(?:25[0-5]|2[0-4]\d|1?\d?\d)\.){3}(?:25[0-5]|2[0-4]\d|1?\d?\d))*\s*$/
                }
            }
        }

        // Apply button — swaps to a loading spinner while applying, matching the
        // connect animation used in the Wi-Fi list. Only shown once the form
        // actually diverges from the saved config.
        Item {
            Layout.alignment: Qt.AlignRight
            implicitWidth: applyBtn.implicitWidth
            implicitHeight: root.hasChanges || root.savingIp ? applyBtn.implicitHeight : 0
            opacity: root.hasChanges || root.savingIp ? 1 : 0

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

            ButtonBase {
                id: applyBtn

                shapeMorph: true
                isRound: true
                inactiveColour: CortetsuColours.palette.m3primary
                inactiveOnColour: CortetsuColours.palette.m3onPrimary
                stateLayer.disabled: !root.ipLoaded || root.savingIp

                implicitWidth: applyMetrics.width + CortetsuTokens.padding.extraLarge * 2
                implicitHeight: applyMetrics.height + CortetsuTokens.padding.medium * 2

                onClicked: {
                    if (root.ipLoaded && !root.savingIp)
                        root.saveIpConfig();
                }

                TextMetrics {
                    id: applyMetrics

                    text: qsTr("Apply")
                    font: applyBtn.font
                }

                AnimLoader {
                    id: applyContent

                    anchors.centerIn: parent
                    sourceComp: root.savingIp ? applyLoadingComp : applyTextComp
                    outAnimType: Anim.SlowEffects
                    inAnimType: Anim.SlowEffects
                }

                Component {
                    id: applyLoadingComp

                    LoadingIndicator {
                        implicitSize: Math.round(CortetsuTokens.font.body.medium.pointSize * 1.4)
                        color: applyBtn.onColour
                    }
                }

                Component {
                    id: applyTextComp

                    CortetsuText {
                        text: applyMetrics.text
                        font: applyBtn.font
                        color: applyBtn.onColour
                    }
                }
            }
        }
    }
}

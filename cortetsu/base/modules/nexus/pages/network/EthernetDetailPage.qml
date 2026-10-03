pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQml.Models
import Quickshell.Networking
import qs.components
import qs.components.controls
import qs.services
import qs.modules.nexus.common

// Detail / settings sub-page for an ethernet device. Reached by tapping an
// ethernet row on NetworkPage.
PageBase {
    id: root

    readonly property string ifaceName: nState.selectedEthernetInterface
    readonly property var device: Connectivity.wifi.devices.find(d => d.type === DeviceType.Wired && d.name === root.ifaceName) ?? null
    readonly property var details: Connectivity.wifi.details[ifaceName] ?? ({})
    readonly property var compatibleProfiles: Connectivity.wifi.profiles.filter(item => item.type === "802-3-ethernet" && (!item.interface || item.interface === ifaceName))
    readonly property string profileUuid: nState.selectedEthernetUuid || details.uuid || (compatibleProfiles.length === 1 ? compatibleProfiles[0].uuid : "")
    readonly property var profile: Connectivity.wifi.profiles.find(item => item.uuid === profileUuid) ?? null
    readonly property string connectionName: profile?.name ?? details.profileName ?? ""

    // Locally-edited IPv4 form state.
    property string ipMethod: "auto" // "auto" | "auto-dns" | "manual"
    property bool ipLoaded: false
    property string loadedProfileUuid: ""
    property bool savingIp: false

    // Original loaded values, so the Apply button only shows on a real change.
    property string origMethod: "auto"
    property string origAddress: ""
    property string origGateway: ""
    property string origDns: ""

    readonly property bool hasChanges: root.ipLoaded && (root.ipMethod !== root.origMethod || (root.ipMethod === "manual" && (addressField.text.trim() !== root.origAddress || gatewayField.text.trim() !== root.origGateway)) || ((root.ipMethod === "manual" || root.ipMethod === "auto-dns") && dnsField.text.trim() !== root.origDns))

    property int saveId: -1
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
        loadedProfileUuid = profileUuid;

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
    onProfileChanged: { if (profile?.uuid !== loadedProfileUuid) root.ipLoaded = false; loadIpConfig(); }
    property Instantiator profileOptions: Instantiator {
        model: root.compatibleProfiles
        delegate: MenuItem {
            required property var modelData
            property string uuid: modelData.uuid
            text: modelData.name
            icon: "lan"
        }
    }
    property Connections operationConnections: Connections {
        target: Connectivity.wifi
        function onOperationChanged() { root.observeSave(); }
    }

    title: root.connectionName || root.ifaceName || qsTr("Ethernet")
    isSubPage: true

    Component.onCompleted: {
        Connectivity.wifi.refreshDetails(root.ifaceName);

        loadIpConfig();
    }

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: CortetsuTokens.spacing.extraSmall / 2

        // ---- Action button --------------------------------------------------
        ButtonRow {
            Layout.bottomMargin: CortetsuTokens.spacing.large - parent.spacing
            Layout.alignment: Qt.AlignHCenter
            Layout.minimumWidth: Math.round(root.cappedWidth * 0.5)
            spacing: CortetsuTokens.spacing.small

            ButtonBase {
                id: connectBtn
                stateLayer.disabled: Connectivity.wifi.busy || (!root.device?.connected && !root.profile)

                fillWidth: true
                shapeMorph: true
                isRound: true
                inactiveColour: root.device?.connected ? CortetsuColours.palette.m3primaryContainer : CortetsuColours.palette.m3secondaryContainer
                inactiveOnColour: root.device?.connected ? CortetsuColours.palette.m3onPrimaryContainer : CortetsuColours.palette.m3onSecondaryContainer

                implicitWidth: connectLayout.implicitWidth + CortetsuTokens.padding.extraLarge * 2
                implicitHeight: connectLayout.implicitHeight + CortetsuTokens.padding.medium * 2

                onClicked: {
                    if (root.device?.connected)
                        Connectivity.wifi.disconnectWired(root.device);
                    else
                        if (root.profile) Connectivity.wifi.connectProfile(root.profile.uuid, root.ifaceName);
                }

                ColumnLayout {
                    id: connectLayout

                    anchors.centerIn: parent
                    spacing: 0

                    CortetsuIcon {
                        Layout.alignment: Qt.AlignHCenter
                        text: root.device?.connected ? "link_off" : "link"
                        color: connectBtn.onColour
                        fontStyle: CortetsuTokens.font.icon.medium
                    }

                    CortetsuText {
                        Layout.alignment: Qt.AlignHCenter
                        text: root.device?.connected ? qsTr("Disconnect") : qsTr("Connect")
                        color: connectBtn.onColour
                    }
                }
            }
        }

        SelectRow {
            Layout.fillWidth: true
            visible: root.compatibleProfiles.length > 1
            label: qsTr("Connection profile")
            fallbackText: root.profile?.name ?? qsTr("Select a profile")
            fallbackIcon: "lan"
            menuItems: {
                const result = [];
                for (let i = 0; i < root.profileOptions.count; i++) result.push(root.profileOptions.objectAt(i));
                return result;
            }
            onSelected: item => { root.nState.selectedEthernetUuid = item.uuid; root.ipLoaded = false; root.loadIpConfig(); }
        }

        // ---- Connection info ------------------------------------------------
        SectionHeader {
            first: true
            text: qsTr("Connection")
        }

        InfoRow {
            first: true
            icon: "link"
            label: qsTr("Status")
            value: root.device?.connected ? qsTr("Connected") : qsTr("Not connected")
        }

        InfoRow {
            icon: "settings_ethernet"
            label: qsTr("Interface")
            value: root.ifaceName || qsTr("—")
        }

        InfoRow {
            icon: "speed"
            label: qsTr("Speed")
            visible: (root.device?.linkSpeed ?? 0) > 0
            value: qsTr("%1 Mbps").arg(root.device?.linkSpeed ?? 0)
        }

        InfoRow {
            icon: "lan"
            label: qsTr("IP address")
            value: root.details?.address || qsTr("—")
        }

        InfoRow {
            icon: "router"
            label: qsTr("Gateway")
            value: root.details?.gateway || qsTr("—")
        }

        InfoRow {
            last: true
            icon: "memory"
            label: qsTr("MAC address")
            value: root.details?.macAddress || qsTr("—")
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

            Layout.fillWidth: true
            first: true
            last: root.ipMethod === "auto"
            label: qsTr("IP assignment")
            fallbackText: qsTr("Automatic (DHCP)")
            fallbackIcon: "lan"

            menuItems: [autoItem, autoDnsItem, manualItem]

            onSelected: item => root.ipMethod = item === manualItem ? "manual" : (item === autoDnsItem ? "auto-dns" : "auto")

            MenuItem {
                id: autoItem

                icon: "lan"
                text: qsTr("Automatic (DHCP)")
            }

            MenuItem {
                id: autoDnsItem

                icon: "dns"
                text: qsTr("Automatic, DNS only")
            }

            MenuItem {
                id: manualItem

                icon: "edit"
                text: qsTr("Manual")
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.topMargin: CortetsuTokens.spacing.large
            spacing: CortetsuTokens.spacing.large
            visible: root.ipMethod === "manual" || root.ipMethod === "auto-dns"

            StyledTextField {
                id: addressField

                Layout.fillWidth: true
                visible: root.ipMethod === "manual"
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
                visible: root.ipMethod === "manual"
                placeholderText: qsTr("Gateway")
                leadingIcon: "exit_to_app"
                errorText: qsTr("Enter a valid gateway address")
                inputMethodHints: Qt.ImhNoPredictiveText
                validate: /^$|^(?:(?:25[0-5]|2[0-4]\d|1?\d?\d)\.){3}(?:25[0-5]|2[0-4]\d|1?\d?\d)$/
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

        // Apply button — swaps to a loading spinner while applying. Shown only
        // when the IP assignment has unsaved changes.
        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: CortetsuTokens.spacing.large
            spacing: CortetsuTokens.spacing.medium
            visible: root.hasChanges || root.savingIp

            Item {
                Layout.fillWidth: true
            }

            ButtonBase {
                id: applyBtn

                shapeMorph: true
                isRound: true
                inactiveColour: CortetsuColours.palette.m3primary
                inactiveOnColour: CortetsuColours.palette.m3onPrimary
                stateLayer.disabled: !root.ipLoaded || root.savingIp

                implicitWidth: applyContent.implicitWidth + CortetsuTokens.padding.extraLarge * 2
                implicitHeight: applyContent.implicitHeight + CortetsuTokens.padding.medium * 2

                onClicked: if (root.ipLoaded && !root.savingIp)
                    root.saveIpConfig()

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
                        text: qsTr("Apply")
                        color: applyBtn.onColour
                        animate: true
                    }
                }
            }
        }
    }
}

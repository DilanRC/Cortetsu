pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.components
import qs.components.controls
import qs.services
import qs.modules.settings as Settings
import qs.modules.nexus.common

PageBase {
    id: root
    title: qsTr("Conexiones")
    ColumnLayout {
        width: root.cappedWidth
        anchors.horizontalCenter: parent.horizontalCenter
        Settings.NetworkPage { Layout.fillWidth: true; screen: root.nState.screen; screenState: null; showVpn: false }
        // ---- VPN -------------------------------------------------------------
        ToggleRow {
            Layout.topMargin: CortetsuTokens.spacing.large
            Layout.fillWidth: true
            first: true
            text: qsTr("VPN")
            font: CortetsuTokens.font.body.medium
            horizontalPadding: CortetsuTokens.padding.largeIncreased
            checked: Connectivity.vpn.connected
            // Connectable as long as there's a provider and we're not mid-switch.
            disabled: Connectivity.vpn.connecting || Connectivity.vpn.disconnecting || Connectivity.vpn.providers.length === 0
            onToggled: Connectivity.vpn.toggle()


        }

        ItemList {
            id: providerList

            showList: true
            placeholderIcon: "add_circle"
            placeholderText: qsTr("No VPN providers configured")

            model: ScriptModel {
                values: [...Connectivity.vpn.providers]
            }

            delegate: Item {
                id: provider

                required property var modelData // QML types are annoying (causes null errors on destruction if typed correctly)
                readonly property bool isSelected: modelData.providerId === Connectivity.vpn.selectedProvider
                readonly property bool isConnected: isSelected && Connectivity.vpn.connected

                anchors.left: providerList.list.contentItem.left
                anchors.right: providerList.list.contentItem.right
                implicitHeight: providerLayout.implicitHeight + providerLayout.anchors.margins * 2

                CortetsuStateLayer {
                    enabled: !provider.isSelected
                    radius: CortetsuTokens.rounding.extraSmall
                    onClicked: {
                        if (!provider.isSelected)
                            Connectivity.vpn.setActiveProvider(provider.modelData.index);
                    }
                }

                RowLayout {
                    id: providerLayout

                    anchors.fill: parent
                    anchors.margins: CortetsuTokens.padding.medium
                    anchors.leftMargin: CortetsuTokens.padding.largeIncreased
                    anchors.rightMargin: CortetsuTokens.padding.medium
                    spacing: CortetsuTokens.spacing.medium

                    CortetsuSurface {
                        implicitWidth: implicitHeight
                        implicitHeight: providerIcon.implicitHeight + CortetsuTokens.padding.small * 2
                        radius: CortetsuTokens.rounding.full
                        color: provider.isConnected ? CortetsuColours.palette.m3primaryContainer : provider.isSelected ? CortetsuColours.palette.m3secondaryContainer : CortetsuColours.palette.m3surfaceContainerHighest

                        CortetsuIcon {
                            id: providerIcon

                            anchors.centerIn: parent
                            text: provider.isConnected || provider.isSelected ? "vpn_key" : "vpn_key_off"
                            fill: provider.isConnected ? 1 : 0
                            color: provider.isConnected ? CortetsuColours.palette.m3onPrimaryContainer : provider.isSelected ? CortetsuColours.palette.m3onSecondaryContainer : CortetsuColours.palette.m3onSurfaceVariant
                            fontStyle: CortetsuTokens.font.icon.medium
                            animate: true
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0

                        CortetsuText {
                            Layout.fillWidth: true
                            text: provider.modelData.displayName
                            font: CortetsuTokens.font.body.medium
                            elide: Text.ElideRight
                        }

                        CortetsuText {
                            Layout.fillWidth: true
                            text: {
                                if (!provider.isSelected)
                                    return qsTr("Tap to select");
                                if (Connectivity.vpn.connecting)
                                    return qsTr("Connecting...");
                                if (Connectivity.vpn.disconnecting)
                                    return qsTr("Disconnecting...");
                                switch (Connectivity.vpn.status.state) {
                                case "connected":
                                    return qsTr("Connected");
                                case "needs-auth":
                                    return Connectivity.vpn.status.reason || qsTr("Authentication required");
                                case "error":
                                    return Connectivity.vpn.status.reason || qsTr("An error occurred");
                                default:
                                    return qsTr("Selected");
                                }
                            }
                            color: {
                                if (!provider.isSelected)
                                    return CortetsuColours.palette.m3onSurfaceVariant;
                                switch (Connectivity.vpn.status.state) {
                                case "connected":
                                    return CortetsuColours.palette.m3primary;
                                case "needs-auth":
                                case "error":
                                    return CortetsuColours.palette.m3error;
                                default:
                                    return CortetsuColours.palette.m3secondary;
                                }
                            }
                            font: CortetsuTokens.font.label.small
                            elide: Text.ElideRight
                            animate: true
                        }
                    }

                    Item {
                        Layout.rightMargin: CortetsuTokens.spacing.small
                        opacity: provider.isConnected && root?.cappedWidth > CortetsuTokens.sizes.nexus.networkShowVpnDetailWidth ? 1 : 0
                        visible: opacity > 0

                        implicitWidth: provider.isConnected && root?.cappedWidth > CortetsuTokens.sizes.nexus.networkShowVpnDetailWidth ? providerDetailRow.implicitWidth : 0
                        implicitHeight: providerDetailRow.implicitHeight

                        Behavior on opacity {
                            Anim {
                                type: Anim.DefaultEffects
                            }
                        }

                        RowLayout {
                            id: providerDetailRow

                            anchors.right: parent.right
                            spacing: CortetsuTokens.spacing.large

                            ColumnLayout {
                                spacing: 0

                                CortetsuText {
                                    Layout.alignment: Qt.AlignRight
                                    text: qsTr("Interface")
                                    color: CortetsuColours.palette.m3onSurfaceVariant
                                    font: CortetsuTokens.font.label.small
                                    elide: Text.ElideRight
                                    horizontalAlignment: Text.AlignRight
                                }

                                CortetsuText {
                                    Layout.alignment: Qt.AlignRight
                                    text: provider.modelData.iface
                                    color: CortetsuColours.palette.m3outline
                                    font: CortetsuTokens.font.label.small
                                    elide: Text.ElideRight
                                    horizontalAlignment: Text.AlignRight
                                }
                            }

                            ColumnLayout {
                                spacing: 0

                                CortetsuText {
                                    Layout.alignment: Qt.AlignRight
                                    text: qsTr("Current Ping")
                                    color: CortetsuColours.palette.m3onSurfaceVariant
                                    font: CortetsuTokens.font.label.small
                                    elide: Text.ElideRight
                                    horizontalAlignment: Text.AlignRight
                                }

                                RowLayout {
                                    Layout.alignment: Qt.AlignRight
                                    spacing: CortetsuTokens.spacing.small

                                    CortetsuSurface {
                                        Layout.alignment: Qt.AlignVCenter
                                        implicitWidth: Math.round(CortetsuTokens.font.body.small.pointSize * 0.7)
                                        implicitHeight: implicitWidth
                                        radius: CortetsuTokens.rounding.full
                                        color: Connectivity.vpn.pingMs <= 80 ? CortetsuColours.palette.m3primary : Connectivity.vpn.pingMs <= 150 ? CortetsuColours.palette.m3tertiary : CortetsuColours.palette.m3error
                                    }

                                    CortetsuText {
                                        text: qsTr("%1 ms").arg(Connectivity.vpn.pingMs)
                                        color: CortetsuColours.palette.m3outline
                                        font: CortetsuTokens.font.label.small
                                        elide: Text.ElideRight
                                        horizontalAlignment: Text.AlignRight
                                    }
                                }
                            }
                        }
                    }

                    IconButton {
                        implicitWidth: implicitHeight + (CortetsuTokens.padding.large - padding) * 2
                        type: IconButton.Tonal
                        isRound: true
                        icon: "edit"
                        onClicked: {
                            root.nState.editingVpnIndex = provider.modelData.index;
                            root.nState.openSubPage(4); // Add/edit provider sub-page
                        }
                    }
                }
            }
        }

        // Add provider
        RowButton {
            last: true
            icon: "add"
            text: qsTr("Add provider")
            onClicked: {
                root.nState.editingVpnIndex = -1;
                root.nState.openSubPage(4); // Add/edit provider sub-page
            }
        }
    }
}

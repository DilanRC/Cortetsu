pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell.Bluetooth
import qs.components
import qs.components.controls
import qs.modules
import qs.services
import qs.modules.bar.popouts as BarPopouts

CortetsuSurface {
    id: root

    required property ScreenState screenState
    required property BarPopouts.Wrapper popouts

    readonly property var quickToggles: {
        const seenIds = new Set();

        return CortetsuConfig.quickToggles.filter(item => {
            if (!item.enabled)
                return false;

            if (seenIds.has(item.id)) {
                return false;
            }

            if (item.id === "vpn") {
                return CortetsuConfig.vpn.selectedProvider.length > 0;
            }

            seenIds.add(item.id);
            return true;
        });
    }
    readonly property int splitIndex: Math.ceil(quickToggles.length / 2)
    readonly property bool needExtraRow: quickToggles.length > 6

    implicitHeight: layout.implicitHeight + CortetsuTokens.padding.extraLargeIncreased

    radius: CortetsuTokens.rounding.large
    color: CortetsuColours.tPalette.m3surfaceContainer

    ColumnLayout {
        id: layout

        anchors.fill: parent
        anchors.margins: CortetsuTokens.padding.large
        spacing: CortetsuTokens.spacing.medium

        CortetsuText {
            text: qsTr("Quick Toggles")
            font: CortetsuTokens.font.body.medium
        }

        QuickToggleRow {
            model: root.needExtraRow ? root.quickToggles.slice(0, root.splitIndex) : root.quickToggles
        }

        QuickToggleRow {
            visible: root.needExtraRow
            model: root.needExtraRow ? root.quickToggles.slice(root.splitIndex) : []
        }
    }

    component QuickToggleRow: ButtonRow {
        property alias model: repeater.model

        Layout.fillWidth: true
        spacing: CortetsuTokens.spacing.small

        Repeater {
            id: repeater

            delegate: DelegateChooser {
                role: "id"

                DelegateChoice {
                    roleValue: "wifi"
                    delegate: Toggle {
                        icon: "wifi"
                        checked: Connectivity.wifi.wifiEnabled
                        onClicked: Connectivity.wifi.setEnabled(!Connectivity.wifi.wifiEnabled)
                    }
                }
                DelegateChoice {
                    roleValue: "bluetooth"
                    delegate: Toggle {
                        icon: "bluetooth"
                        checked: Connectivity.bluetooth.enabled // qmllint disable unresolved-type
                        onClicked: {
                            Connectivity.bluetooth.setEnabled(!Connectivity.bluetooth.enabled);
                        }
                    }
                }
                DelegateChoice {
                    roleValue: "mic"
                    delegate: Toggle {
                        icon: "mic"
                        checked: !Audio.sourceMuted
                        onClicked: {
                            const audio = Audio.source?.audio;
                            if (audio)
                                audio.muted = !audio.muted;
                        }
                    }
                }
                DelegateChoice {
                    roleValue: "settings"
                    delegate: Toggle {
                        icon: "settings"
                        inactiveOnColour: CortetsuColours.palette.m3onSurfaceVariant
                        isToggle: false
                        onClicked: {
                            root.screenState.utilities = true;
                        }
                    }
                }
                DelegateChoice {
                    roleValue: "gameMode"
                    delegate: Toggle {
                        icon: "gamepad"
                        checked: GameMode.enabled
                        onClicked: GameMode.enabled = !GameMode.enabled
                    }
                }
                DelegateChoice {
                    roleValue: "dnd"
                    delegate: Toggle {
                        icon: "notifications_off"
                        checked: Notifs.dnd
                        onClicked: Notifs.dnd = !Notifs.dnd
                    }
                }
                DelegateChoice {
                    roleValue: "vpn"
                    delegate: Toggle {
                        icon: "vpn_key"
                        checked: VPN.connected && VPN.status.state !== "needs-auth" && VPN.status.state !== "error"
                        enabled: !VPN.connecting && !VPN.disconnecting
                        isToggle: VPN.status.state !== "needs-auth" && VPN.status.state !== "error"
                        inactiveOnColour: CortetsuColours.palette.m3onSurfaceVariant
                        onClicked: VPN.toggle()
                    }
                }
            }
        }
    }

    component Toggle: IconButton {
        inactiveColour: CortetsuColours.layer(CortetsuColours.palette.m3surfaceContainerHighest, 2)
        fillWidth: true
        isToggle: true
        isRound: true
        shapeMorph: true
    }
}

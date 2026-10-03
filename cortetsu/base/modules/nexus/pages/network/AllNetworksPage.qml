pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell.Networking
import qs.components
import qs.components.controls
import qs.modules
import qs.services
import qs.modules.nexus.common

PageBase {
    id: root

    readonly property string scanOwner: "legacy-nexus-all-" + String(root)
    onVisibleChanged: Connectivity.wifi.setScanOwner(scanOwner, visible)
    Component.onCompleted: Connectivity.wifi.setScanOwner(scanOwner, visible)
    Component.onDestruction: Connectivity.wifi.setScanOwner(scanOwner, false)
    title: qsTr("All networks")
    isSubPage: true
    flickable.bottomMargin: CortetsuTokens.padding.extraExtraLarge * 2 // Extra scrolling space at the bottom

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: CortetsuTokens.spacing.extraSmall / 2


        ConnectedRect {
            Layout.fillWidth: true
            implicitHeight: headerLayout.implicitHeight + CortetsuTokens.padding.medium * 2
            first: true

            RowLayout {
                id: headerLayout

                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: CortetsuTokens.padding.largeIncreased
                anchors.rightMargin: CortetsuTokens.padding.large
                anchors.verticalCenterOffset: 1

                spacing: CortetsuTokens.spacing.extraSmall / 2

                CortetsuText {
                    text: qsTr("Filters")
                    font: CortetsuTokens.font.title.small
                }

                Item {
                    Layout.fillWidth: true
                }

                FilterButton {
                    id: savedFilter

                    function internalFilter(ap: var): bool {
                        return ap.known;
                    }

                    text: qsTr("Saved")
                    topLeftRadius: pressed ? pressedRadius : implicitHeight / 2
                    bottomLeftRadius: pressed ? pressedRadius : implicitHeight / 2

                    Behavior on topLeftRadius {
                        Anim {
                            type: Anim.DefaultEffects
                        }
                    }

                    Behavior on bottomLeftRadius {
                        Anim {
                            type: Anim.DefaultEffects
                        }
                    }
                }

                FilterButton {
                    id: secureFilter

                    function internalFilter(ap: var): bool {
                        return ap.security !== WifiSecurityType.Open;
                    }

                    text: qsTr("Secured")
                }

                FilterButton {
                    id: highFreqFilter

                    function internalFilter(ap: var): bool {
                        return (Connectivity.wifi.accessPoints.find(item => item.ssid === ap.name && item.device === ap.device.name)?.frequency ?? 0) >= 4900 && (Connectivity.wifi.accessPoints.find(item => item.ssid === ap.name && item.device === ap.device.name)?.frequency ?? 0) <= 5900;
                    }

                    text: qsTr("5 GHz")
                }

                FilterButton {
                    id: lowFreqFilter

                    function internalFilter(ap: var): bool {
                        return (Connectivity.wifi.accessPoints.find(item => item.ssid === ap.name && item.device === ap.device.name)?.frequency ?? 0) >= 2400 && (Connectivity.wifi.accessPoints.find(item => item.ssid === ap.name && item.device === ap.device.name)?.frequency ?? 0) <= 2500;
                    }

                    text: qsTr("2.4 GHz")
                    topRightRadius: pressed ? pressedRadius : implicitHeight / 2
                    bottomRightRadius: pressed ? pressedRadius : implicitHeight / 2

                    Behavior on topRightRadius {
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
            }
        }

        NetworkList {
            id: networkList

            function networkFilter(ap: var): bool {
                return savedFilter.filter(ap) && secureFilter.filter(ap) && highFreqFilter.filter(ap) && lowFreqFilter.filter(ap);
            }

            nState: root.nState
            enableFilter: true
            last: true
        }
    }

    component FilterButton: IconTextButton {
        id: filter

        property int filterState // 0 = default, 1 = on, 2 = negate

        function filter(ap: var): bool {
            if (filterState === 0)
                return true;
            if (filterState === 1)
                return internalFilter(ap);
            return !internalFilter(ap);
        }

        function internalFilter(ap: var): bool {
            return true;
        }

        onClicked: filterState = (filterState + 1) % 3

        defaultRadius: filterState > 0 ? implicitHeight / 2 : CortetsuTokens.rounding.small
        pressedRadius: CortetsuTokens.rounding.extraSmall
        spacing: CortetsuTokens.spacing.extraSmall

        icon: ["check_indeterminate_small", "check", "close"][filterState]
        inactiveColour: [CortetsuColours.palette.m3secondaryContainer, CortetsuColours.palette.m3secondary, CortetsuColours.palette.m3tertiary][filterState]
        inactiveOnColour: [CortetsuColours.palette.m3onSecondaryContainer, CortetsuColours.palette.m3onSecondary, CortetsuColours.palette.m3onTertiary][filterState]
    }
}

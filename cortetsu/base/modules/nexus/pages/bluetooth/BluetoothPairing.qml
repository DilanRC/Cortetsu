pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Bluetooth
import qs.components
import qs.components.controls
import qs.services
import qs.utils
import qs.modules.nexus.common

PageBase {
    id: root
    readonly property string scanOwner: "bluetooth-" + String(root)

    readonly property BluetoothAdapter adapter: ConnectivityBluetooth.adapter // qmllint disable unresolved-type

    function setScan(on: bool): void {
        ConnectivityBluetooth.setScanOwner(root.scanOwner, on);
    }

    title: qsTr("Pair new device")
    isSubPage: true

    Component.onCompleted: setScan(visible)
    Component.onDestruction: setScan(false)
    onVisibleChanged: setScan(visible)

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: CortetsuTokens.spacing.extraSmall / 2

        Connections {
            function onEnabledChanged(): void {
                if (root.adapter && !root.adapter.enabled)
                    root.nState.closeSubPage();
            }

            target: root.adapter
        }

        CortetsuText {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            text: ConnectivityBluetooth.operation.state === "failed" ? ConnectivityBluetooth.operation.lastError : ConnectivityBluetooth.authenticationNotice
            color: CortetsuColours.palette.m3onSurfaceVariant
            font: CortetsuTokens.font.body.small
        }

        RowButton {
            visible: ConnectivityBluetooth.busy && ConnectivityBluetooth.operation.kind === "pair"
            icon: "close"
            text: qsTr("Cancel pairing")
            onClicked: ConnectivityBluetooth.cancelPair()
        }

        ConnectedRect {
            Layout.fillWidth: true
            implicitHeight: headerText.implicitHeight + CortetsuTokens.padding.medium * 2
            first: true

            CortetsuText {
                id: headerText

                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: CortetsuTokens.padding.large
                anchors.verticalCenterOffset: Math.round(fontInfo.pointSize * 0.2)

                text: qsTr("Available devices")
                color: CortetsuColours.palette.m3onSurfaceVariant
                font: CortetsuTokens.font.body.small
            }
        }

        ItemList {
            id: deviceList

            Layout.fillWidth: true
            showList: true
            extraHeight: scanIndicator.implicitHeight
            last: true
            placeholderIcon: "bluetooth_searching"
            placeholderText: qsTr("Searching for devices…")
            list.anchors.top: scanIndicator.bottom

            model: ScriptModel {
                values: ConnectivityBluetooth.devices.filter(d => !d.bonded).sort((a, b) => (b.pairing - a.pairing) || a.name.localeCompare(b.name)) // qmllint disable unresolved-type
            }

            delegate: Item {
                id: newDevice

                required property BluetoothDevice modelData
                required property int index
                property real textOpacity: modelData?.pairing ? 0.5 : 1
                property bool wasPairing

                anchors.left: deviceList.list.contentItem.left
                anchors.right: deviceList.list.contentItem.right
                implicitHeight: newLayout.implicitHeight + newLayout.anchors.margins * 2

                Behavior on textOpacity {
                    Anim {
                        type: Anim.DefaultEffects
                    }
                }

                Connections {
                    function onPairedChanged(): void {
                        if (newDevice.wasPairing && newDevice.modelData?.paired)
                            root.nState.closeSubPage();
                    }

                    target: newDevice.modelData
                }

                CortetsuStateLayer {
                    radius: CortetsuTokens.rounding.extraSmall
                    bottomLeftRadius: newDevice.index === deviceList?.list.count - 1 ? CortetsuTokens.rounding.extraLarge : radius
                    bottomRightRadius: newDevice.index === deviceList?.list.count - 1 ? CortetsuTokens.rounding.extraLarge : radius
                    disabled: ConnectivityBluetooth.busy || (newDevice.modelData?.pairing ?? false)

                    onClicked: {
                        ConnectivityBluetooth.pairDevice(newDevice.modelData);
                        newDevice.wasPairing = true;
                    }
                }

                RowLayout {
                    id: newLayout

                    anchors.fill: parent
                    anchors.margins: CortetsuTokens.padding.medium
                    anchors.leftMargin: CortetsuTokens.padding.largeIncreased
                    anchors.rightMargin: CortetsuTokens.padding.largeIncreased
                    spacing: CortetsuTokens.spacing.medium

                    CortetsuIcon {
                        text: Icons.getBluetoothIcon(newDevice.modelData?.icon ?? "")
                        color: CortetsuColours.palette.m3onSurfaceVariant
                        fontStyle: CortetsuTokens.font.icon.medium
                        opacity: newDevice.textOpacity
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        opacity: newDevice.textOpacity

                        CortetsuText {
                            Layout.fillWidth: true
                            text: newDevice.modelData?.name || qsTr("Unknown device")
                            font: CortetsuTokens.font.body.small
                            elide: Text.ElideRight
                        }

                        CortetsuText {
                            Layout.fillWidth: true
                            text: newDevice.modelData?.pairing ? qsTr("Pairing...") : (newDevice.modelData?.address ?? "")
                            color: CortetsuColours.palette.m3outline
                            font: CortetsuTokens.font.label.small
                            elide: Text.ElideRight
                            animate: true
                        }
                    }

                    Loader {
                        asynchronous: true
                        active: opacity > 0
                        opacity: newDevice.modelData?.pairing ? 1 : 0

                        sourceComponent: LoadingIndicator {
                            implicitSize: Math.round(CortetsuTokens.font.icon.medium.pointSize * 1.3)
                        }

                        Behavior on opacity {
                            Anim {
                                type: Anim.DefaultEffects
                            }
                        }
                    }
                }
            }

            StyledProgressBar {
                id: scanIndicator

                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 1
                implicitHeight: CortetsuTokens.rounding.extraSmall
                indeterminate: true

                Behavior on implicitHeight {
                    Anim {
                        type: Anim.DefaultEffects
                    }
                }
            }
        }
    }
}

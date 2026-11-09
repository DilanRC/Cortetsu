pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import "../../../components"
import "../.."
import "../../../theme"
import "../../CortetsuTypography.js" as CortetsuTypography
import "BluetoothDevices.js" as Devices

// The explorer: filter, search and the device list, grouped as connected,
// paired and new. Selection follows the BlueZ object path, so a list that
// reorders while discovery runs keeps the same device selected.
Item {
    id: root

    required property var page

    height: implicitHeight
    implicitHeight: 580

    readonly property var filters: [
        { value: "all", label: qsTr("Todos") },
        { value: "paired", label: qsTr("Emparejados") },
        { value: "new", label: qsTr("Nuevos") }
    ]
    readonly property var groupTitles: ({
        connected: qsTr("Conectados"),
        paired: qsTr("Emparejados"),
        available: qsTr("Disponibles")
    })

    CortetsuSurface {
        anchors.fill: parent
        baseColor: Qt.alpha(CortetsuDesign.colorSurfaceGlass, 0.60)
        outlined: true
        radiusValue: CortetsuDesign.radiusMedium
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: CortetsuDesign.spacingCompact
        spacing: CortetsuDesign.spacingCompact

        RowLayout {
            Layout.fillWidth: true
            spacing: CortetsuDesign.spacingCompact

            Repeater {
                model: root.filters

                CortetsuButton {
                    required property var modelData
                    objectName: "bluetoothFilter-" + modelData.value
                    Layout.fillWidth: true
                    compact: true
                    label: `${modelData.label} ${Devices.count(root.page.devices, modelData.value)}`
                    active: root.page.filter === modelData.value
                    onClicked: root.page.filter = modelData.value
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 2
            spacing: CortetsuDesign.spacingCompact

            CortetsuIcon {
                text: root.page.bluetooth.discovering ? "bluetooth_searching" : "bluetooth"
                color: root.page.bluetooth.discovering ? CortetsuDesign.colorPrimary : CortetsuDesign.colorOnSurfaceVariant
                iconSize: CortetsuTypography.iconSmallPx
            }

            CortetsuText {
                objectName: "bluetoothDiscovery"
                Layout.fillWidth: true
                text: root.page.bluetooth.discovering
                    ? qsTr("Buscando dispositivos cercanos…")
                    : qsTr("Búsqueda en pausa")
                textSize: CortetsuTypography.labelSmallPx
                color: CortetsuDesign.colorOnSurfaceVariant
                elide: Text.ElideRight
            }
        }

        CortetsuSearchBar {
            Layout.fillWidth: true
            compact: true
            placeholderText: qsTr("Filtrar por nombre o dirección…")
            onTextChanged: root.page.query = text
        }

        ListView {
            id: deviceList
            objectName: "bluetoothDeviceList"
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: 3
            topMargin: 4
            bottomMargin: 4
            model: root.page.shownDevices
            currentIndex: root.page.shownDevices.findIndex(device => root.page.same(device, root.page.selectedDevice))
            // One Tab stop; Up and Down move the selection inside it. It stays
            // one while focused: Qt refuses to drop it from the focused item.
            activeFocusOnTab: count > 0 || activeFocus
            keyNavigationEnabled: true
            onCurrentIndexChanged: if (activeFocus && currentIndex >= 0)
                root.page.selectedPath = root.page.shownDevices[currentIndex]?.dbusPath ?? ""
            Keys.onReturnPressed: root.page.primaryAction(root.page.selectedDevice)
            Keys.onEnterPressed: root.page.primaryAction(root.page.selectedDevice)
            Accessible.role: Accessible.List
            Accessible.name: qsTr("Dispositivos Bluetooth")

            Rectangle {
                anchors.fill: parent
                z: 2
                visible: deviceList.activeFocus
                color: "transparent"
                radius: CortetsuDesign.radiusSmall
                border.width: 2
                border.color: Qt.alpha(CortetsuDesign.colorWashi, 0.82)
            }

            delegate: Column {
                id: entry
                required property var modelData
                required property int index
                readonly property string group: Devices.group(modelData)
                readonly property bool firstOfGroup: index === 0
                    || Devices.group(root.page.shownDevices[index - 1]) !== group
                readonly property bool selected: root.page.same(modelData, root.page.selectedDevice)
                width: deviceList.width

                CortetsuText {
                    visible: entry.firstOfGroup
                    width: parent.width
                    height: visible ? 26 : 0
                    leftPadding: CortetsuDesign.spacingStandard
                    topPadding: entry.index === 0 ? 4 : 10
                    text: root.groupTitles[entry.group]
                    textSize: CortetsuTypography.labelSmallPx
                    font.weight: Font.DemiBold
                    color: CortetsuDesign.colorOnSurfaceVariant
                }

                Item {
                    objectName: "bluetoothDevice-" + (entry.modelData.name ?? "")
                    width: parent.width
                    height: 56
                    Accessible.role: Accessible.ListItem
                    Accessible.name: `${Devices.displayName(entry.modelData)}, ${root.page.stateText(entry.modelData)}`

                    CortetsuSurface {
                        anchors.fill: parent
                        baseColor: entry.selected
                            ? Qt.alpha(CortetsuDesign.colorPrimaryContainer, 0.86)
                            : rowMouse.containsMouse ? Qt.alpha(CortetsuDesign.colorSurfaceGlassStrong, 0.94) : "transparent"
                        outlineColor: entry.selected ? Qt.alpha(CortetsuDesign.colorPrimary, 0.44) : "transparent"
                        outlined: entry.selected
                        radiusValue: CortetsuDesign.radiusSmall
                        hovered: rowMouse.containsMouse
                    }

                    Rectangle {
                        anchors.left: parent.left
                        anchors.leftMargin: 3
                        anchors.verticalCenter: parent.verticalCenter
                        width: 2
                        height: 28
                        visible: entry.selected
                        color: CortetsuDesign.colorWashi
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: CortetsuDesign.spacingStandard
                        anchors.rightMargin: CortetsuDesign.spacingStandard
                        spacing: CortetsuDesign.spacingCompact

                        CortetsuIcon {
                            text: Devices.icon(entry.modelData)
                            color: entry.modelData.connected ? CortetsuDesign.colorSuccess
                                : entry.selected ? CortetsuDesign.colorOnPrimaryContainer : CortetsuDesign.colorPrimary
                            iconSize: CortetsuTypography.iconMediumPx
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 1

                            CortetsuText {
                                Layout.fillWidth: true
                                text: Devices.displayName(entry.modelData)
                                textSize: CortetsuTypography.bodySmallPx
                                font.weight: entry.modelData.connected ? Font.DemiBold : Font.Normal
                                color: entry.selected ? CortetsuDesign.colorOnPrimaryContainer : CortetsuDesign.colorOnSurface
                                elide: Text.ElideRight
                            }

                            CortetsuText {
                                Layout.fillWidth: true
                                text: root.page.failed(entry.modelData)
                                    ? qsTr("Falló la última acción")
                                    : root.page.stateText(entry.modelData)
                                textSize: CortetsuTypography.labelSmallPx
                                color: root.page.failed(entry.modelData) ? CortetsuDesign.colorVermillion
                                    : entry.selected ? CortetsuDesign.colorOnPrimaryContainer : CortetsuDesign.colorOnSurfaceVariant
                                elide: Text.ElideRight
                            }
                        }

                        CortetsuText {
                            readonly property int percent: Devices.batteryPercent(entry.modelData)
                            visible: percent >= 0
                            text: qsTr("%1 %").arg(percent)
                            textSize: CortetsuTypography.labelSmallPx
                            color: entry.selected ? CortetsuDesign.colorOnPrimaryContainer : CortetsuDesign.colorOnSurfaceVariant
                        }

                        CortetsuIcon {
                            visible: entry.modelData.connected && !root.page.pending(entry.modelData)
                            text: "check"
                            color: CortetsuDesign.colorSuccess
                            iconSize: CortetsuTypography.iconSmallPx
                        }

                        CortetsuIcon {
                            visible: root.page.pending(entry.modelData)
                            text: "sync"
                            color: entry.selected ? CortetsuDesign.colorOnPrimaryContainer : CortetsuDesign.colorPrimary
                            iconSize: CortetsuTypography.iconSmallPx
                        }
                    }

                    MouseArea {
                        id: rowMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            deviceList.forceActiveFocus();
                            root.page.selectedPath = entry.modelData.dbusPath;
                        }
                        onDoubleClicked: root.page.primaryAction(entry.modelData)
                    }
                }
            }

            CortetsuStateMessage {
                objectName: "noDevices"
                anchors.centerIn: parent
                visible: deviceList.count === 0
                width: Math.max(0, deviceList.width - CortetsuDesign.spacingSection * 2)
                kind: root.page.bluetooth.discovering && root.page.query.length === 0 ? "loading" : "empty"
                icon: kind === "loading" ? "bluetooth_searching" : "devices_other"
                title: root.page.query.length > 0 ? qsTr("No hay coincidencias")
                    : root.page.filter === "paired" ? qsTr("Ningún dispositivo emparejado")
                    : root.page.bluetooth.discovering ? qsTr("Buscando dispositivos")
                    : qsTr("No hay dispositivos a la vista")
                detail: root.page.query.length > 0 ? qsTr("Prueba con otro nombre o con la dirección")
                    : root.page.filter === "paired" ? qsTr("Elige Nuevos para emparejar uno cercano")
                    : qsTr("Pon el dispositivo en modo de emparejamiento y mantenlo cerca")
            }
        }
    }
}

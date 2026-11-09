pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import "../../../components"
import "../.."
import "../../../theme"
import "../../CortetsuTypography.js" as CortetsuTypography
import "../network"
import "BluetoothDevices.js" as Devices

// The inspector: what BlueZ knows about the selected device and the actions it
// accepts. Rows for values BlueZ does not report (kind, battery) are hidden,
// never filled in. Forget and block need a second press.
Item {
    id: root

    required property var page

    readonly property var device: page.selectedDevice
    readonly property var bluetooth: page.bluetooth
    readonly property bool paired: !!device && (device.paired || device.bonded)
    readonly property bool blocked: page.property(device, "blocked")
    readonly property bool trusted: page.property(device, "trusted")
    readonly property bool pairing: bluetooth.busy && bluetooth.operation.kind === "pair" && page.targets(device)
    readonly property int battery: Devices.batteryPercent(device)

    height: implicitHeight
    implicitHeight: 580

    // Arming is per device: selecting another one disarms both.
    readonly property string devicePath: device?.dbusPath ?? ""
    onDevicePathChanged: { forget.armed = false; block.armed = false; }

    CortetsuSurface {
        anchors.fill: parent
        visible: !!root.device
        baseColor: Qt.alpha(CortetsuDesign.colorSurfaceGlass, 0.58)
        outlined: true
        radiusValue: CortetsuDesign.radiusMedium
    }

    CortetsuStateMessage {
        anchors.centerIn: parent
        width: Math.min(parent.width, 360)
        visible: !root.device
        kind: "empty"
        icon: "devices_other"
        title: qsTr("Selecciona un dispositivo")
        detail: qsTr("Elige uno de la lista para ver su estado, sus permisos y sus acciones")
    }

    ColumnLayout {
        objectName: "bluetoothInspector"
        anchors.fill: parent
        anchors.margins: CortetsuDesign.spacingStandard
        visible: !!root.device
        spacing: CortetsuDesign.spacingStandard

        RowLayout {
            Layout.fillWidth: true
            spacing: CortetsuDesign.spacingStandard

            Rectangle {
                Layout.preferredWidth: 52
                Layout.preferredHeight: 52
                radius: CortetsuDesign.radiusMedium
                color: root.device?.connected ? Qt.alpha(CortetsuDesign.colorSuccess, 0.16) : Qt.alpha(CortetsuDesign.colorPrimaryContainer, 0.72)

                CortetsuIcon {
                    anchors.centerIn: parent
                    text: Devices.icon(root.device)
                    color: root.device?.connected ? CortetsuDesign.colorSuccess : CortetsuDesign.colorOnPrimaryContainer
                    iconSize: CortetsuTypography.iconLargePx
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                CortetsuText {
                    objectName: "bluetoothDeviceName"
                    Layout.fillWidth: true
                    text: Devices.displayName(root.device)
                    textSize: CortetsuTypography.titleMediumPx
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }

                CortetsuText {
                    objectName: "bluetoothDeviceState"
                    Layout.fillWidth: true
                    text: root.page.stateText(root.device)
                    textSize: CortetsuTypography.labelSmallPx
                    color: root.device?.connected ? CortetsuDesign.colorSuccess : CortetsuDesign.colorOnSurfaceVariant
                    elide: Text.ElideRight
                }
            }

            CortetsuButton {
                objectName: "bluetoothPrimary"
                visible: !root.pairing && !root.blocked
                compact: true
                icon: root.device?.connected ? "link_off" : root.paired ? "link" : "add_link"
                label: root.device?.connected ? qsTr("Desconectar") : root.paired ? qsTr("Conectar") : qsTr("Emparejar")
                disabled: root.bluetooth.busy
                onClicked: root.page.primaryAction(root.device)
            }

            CortetsuButton {
                objectName: "bluetoothCancelPair"
                visible: root.pairing
                compact: true
                icon: "close"
                label: qsTr("Cancelar")
                onClicked: root.bluetooth.cancelPair()
            }
        }

        // The last action on this device failed: say why and offer it again.
        CortetsuSurface {
            objectName: "bluetoothError"
            Layout.fillWidth: true
            visible: root.page.failed(root.device)
            implicitHeight: errorRow.implicitHeight + CortetsuDesign.spacingStandard * 2
            baseColor: Qt.alpha(CortetsuDesign.colorWarning, 0.10)
            outlineColor: Qt.alpha(CortetsuDesign.colorWarning, 0.40)
            outlined: true
            radiusValue: CortetsuDesign.radiusSmall

            RowLayout {
                id: errorRow
                anchors.fill: parent
                anchors.margins: CortetsuDesign.spacingStandard
                spacing: CortetsuDesign.spacingStandard

                CortetsuIcon {
                    text: "warning"
                    color: CortetsuDesign.colorWarning
                    iconSize: CortetsuTypography.iconMediumPx
                }
                CortetsuText {
                    Layout.fillWidth: true
                    text: root.bluetooth.operation.lastError
                    textSize: CortetsuTypography.bodySmallPx
                    color: CortetsuDesign.colorOnSurface
                    wrapMode: Text.WordWrap
                }
                CortetsuButton {
                    visible: !root.blocked && root.bluetooth.operation.retryable
                        && ["pair", "connect", "disconnect"].includes(root.bluetooth.operation.kind)
                    compact: true
                    icon: "refresh"
                    label: qsTr("Reintentar")
                    disabled: root.bluetooth.busy
                    onClicked: root.page.primaryAction(root.device)
                }
            }
        }

        // Pairing goes through cortetsu-agents: codes and PINs open a dialog.
        CortetsuSurface {
            objectName: "bluetoothPairingNotice"
            Layout.fillWidth: true
            visible: !root.paired && !root.blocked
            implicitHeight: noticeRow.implicitHeight + CortetsuDesign.spacingStandard * 2
            baseColor: Qt.alpha(CortetsuDesign.colorPrimaryContainer, 0.26)
            outlined: false
            radiusValue: CortetsuDesign.radiusSmall

            RowLayout {
                id: noticeRow
                anchors.fill: parent
                anchors.margins: CortetsuDesign.spacingStandard
                spacing: CortetsuDesign.spacingStandard

                CortetsuIcon {
                    text: root.pairing ? "pin" : "info"
                    color: CortetsuDesign.colorPrimary
                    iconSize: CortetsuTypography.iconMediumPx
                }
                CortetsuText {
                    Layout.fillWidth: true
                    text: root.pairing
                        ? qsTr("Acepta el emparejamiento en el dispositivo. Si pide un código o un PIN, aparecerá un diálogo.")
                        : root.bluetooth.authenticationNotice ?? ""
                    textSize: CortetsuTypography.bodySmallPx
                    wrapMode: Text.WordWrap
                }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: CortetsuDesign.spacingCompact

            DetailRow {
                visible: Devices.kind(root.device).length > 0
                label: qsTr("Tipo")
                value: Devices.kind(root.device)
            }
            DetailRow {
                label: qsTr("Dirección")
                value: root.device?.address ?? ""
            }
            DetailRow {
                label: qsTr("Emparejamiento")
                value: root.device?.bonded ? qsTr("Emparejado y vinculado")
                    : root.device?.paired ? qsTr("Emparejado") : qsTr("Sin emparejar")
            }
            DetailRow {
                objectName: "bluetoothBattery"
                visible: root.battery >= 0
                label: qsTr("Batería")
                value: qsTr("%1 %").arg(root.battery)
            }
            DetailRow {
                label: qsTr("Adaptador")
                value: root.bluetooth.adapter?.name || root.bluetooth.adapter?.adapterId || ""
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 1
            visible: root.paired
            color: CortetsuDesign.colorOutlineVariant
        }

        RowLayout {
            Layout.fillWidth: true
            visible: root.paired
            spacing: CortetsuDesign.spacingStandard

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1

                CortetsuText {
                    Layout.fillWidth: true
                    text: qsTr("De confianza")
                    textSize: CortetsuTypography.bodySmallPx
                }
                CortetsuText {
                    Layout.fillWidth: true
                    text: qsTr("Se conecta sin pedir permiso para cada servicio")
                    textSize: CortetsuTypography.labelSmallPx
                    color: CortetsuDesign.colorOnSurfaceVariant
                    wrapMode: Text.WordWrap
                }
            }

            CortetsuToggle {
                objectName: "bluetoothTrusted"
                checked: root.trusted
                disabled: root.bluetooth.busy || root.blocked
                onToggled: checked => root.bluetooth.setTrusted(root.device, checked)
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 1
            visible: root.paired || root.blocked
            color: CortetsuDesign.colorOutlineVariant
        }

        // Removing or blocking the device: both need a second press.
        RowLayout {
            Layout.fillWidth: true
            visible: root.paired || root.blocked
            spacing: CortetsuDesign.spacingCompact

            CortetsuText {
                objectName: "bluetoothRemovalHint"
                Layout.fillWidth: true
                text: forget.armed
                    ? qsTr("Olvidar borra el emparejamiento. Para volver a usarlo habrá que emparejarlo otra vez.")
                    : block.armed
                        ? qsTr("Bloquear corta la conexión y rechaza cualquier intento de volver a conectarse.")
                        : root.blocked
                            ? qsTr("El dispositivo está bloqueado y no puede conectarse.")
                            : qsTr("Olvidar o bloquear el dispositivo en este equipo.")
                textSize: CortetsuTypography.labelSmallPx
                color: forget.armed || block.armed ? CortetsuDesign.colorVermillion : CortetsuDesign.colorOnSurfaceVariant
                wrapMode: Text.WordWrap
            }

            CortetsuButton {
                id: block
                objectName: "bluetoothBlock"
                property bool armed: false
                compact: true
                danger: !root.blocked
                icon: armed ? "warning" : "block"
                label: root.blocked ? qsTr("Desbloquear") : armed ? qsTr("Confirmar bloqueo") : qsTr("Bloquear")
                disabled: root.bluetooth.busy
                onClicked: {
                    if (root.blocked) { root.bluetooth.setBlocked(root.device, false); return; }
                    if (!armed) { armed = true; forget.armed = false; disarm.restart(); return; }
                    armed = false;
                    root.bluetooth.setBlocked(root.device, true);
                }
            }

            CortetsuButton {
                id: forget
                objectName: "bluetoothForget"
                property bool armed: false
                visible: root.paired
                compact: true
                danger: true
                icon: armed ? "warning" : "delete_outline"
                label: armed ? qsTr("Confirmar") : qsTr("Olvidar")
                disabled: root.bluetooth.busy
                onClicked: {
                    if (!armed) { armed = true; block.armed = false; disarm.restart(); return; }
                    armed = false;
                    root.bluetooth.forgetDevice(root.device);
                }
            }

            Timer {
                id: disarm
                interval: 4000
                onTriggered: { forget.armed = false; block.armed = false; }
            }
        }

        Item { Layout.fillHeight: true }
    }
}

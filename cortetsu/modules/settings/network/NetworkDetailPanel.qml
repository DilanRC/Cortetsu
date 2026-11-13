pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../../../components"
import "../../../services"
import "../.."
import "../../../theme"
import "../../CortetsuTypography.js" as CortetsuTypography
import "../controls"

// What can be read and done about the selection: the link's addresses and
// its actions when connected, the way in when it is not, and the stored
// preferences of a saved profile. Forgetting always asks twice.
ColumnLayout {
    id: root

    required property var page
    readonly property bool onNetwork: !root.page.showingProfiles && !!root.page.selectedNetwork
    readonly property bool onProfile: root.page.showingProfiles && !!root.page.selectedProfile
    readonly property bool connecting: root.page.wifi.operationNetwork === root.page.selectedNetwork
        && root.page.wifi.operation.state === "connecting"

    Layout.fillWidth: true
    spacing: CortetsuDesign.spacingSection

    SettingsGroup {
        objectName: "connectionState"
        visible: root.onNetwork && root.page.selectedIsActive
        title: qsTr("Estado de la conexión")
        icon: "info"

        SettingValueRow {
            objectName: "networkAddress"
            title: qsTr("Dirección IP")
            value: root.page.detailsValue(root.page.activeDetails.address)
        }

        SettingValueRow {
            title: qsTr("Puerta de enlace")
            value: root.page.detailsValue(root.page.activeDetails.gateway)
        }

        SettingValueRow {
            title: qsTr("DNS")
            value: root.page.detailsValue((root.page.activeDetails.dns ?? []).join(", "))
        }

        SettingValueRow {
            visible: CortetsuSettingsNetwork.detailsState === "error"
            title: qsTr("No se pudieron leer los detalles")
            detail: CortetsuSettingsNetwork.detailsError
            attention: true
        }

        SettingToggleRow {
            objectName: "networkAutoconnect"
            visible: !!root.page.selectedProfile
            title: qsTr("Conexión automática")
            detail: qsTr("Conectar cuando la red esté al alcance")
            checked: root.page.selectedProfile?.autoconnect ?? false
            disabled: CortetsuSettingsNetwork.busy
            onToggled: checked => root.page.wifi.setAutoconnect(root.page.selectedProfile.uuid, checked)
        }

        SettingActionRow {
            objectName: "disconnectNetwork"
            title: qsTr("Desconectar")
            detail: qsTr("Conserva el perfil guardado")
            actionLabel: qsTr("Desconectar")
            actionIcon: "link_off"
            disabled: CortetsuSettingsNetwork.busy
            onActivated: root.page.disconnectSelected()
        }

        SettingActionRow {
            objectName: "forgetNetwork"
            visible: !!root.page.selectedProfile
            title: qsTr("Olvidar esta red")
            detail: armed
                ? qsTr("Se borrará el perfil y su contraseña. Pulsa de nuevo para confirmar.")
                : qsTr("Borra el perfil y su contraseña")
            actionLabel: qsTr("Olvidar")
            actionIcon: "delete_outline"
            danger: true
            confirm: true
            disabled: CortetsuSettingsNetwork.busy
            onActivated: root.page.forgetSelected()
        }
    }

    SettingsGroup {
        objectName: "connectionJoin"
        visible: root.onNetwork && !root.page.selectedIsActive
        title: qsTr("Conectar")
        icon: "wifi"
        detail: root.page.selectedNeedsPassword
            ? qsTr("Esta red pide contraseña.")
            : root.page.selectedNetwork?.known
                ? qsTr("Ya tienes un perfil guardado para esta red.")
                : qsTr("Red abierta: no se pide contraseña y el tráfico no va cifrado.")

        SettingRow {
            visible: root.page.selectedNeedsPassword
            title: qsTr("Contraseña")

            TextField {
                id: passwordField
                objectName: "entry"
                implicitWidth: Math.min(240, root.width * 0.5)
                implicitHeight: CortetsuDesign.controlHeight
                echoMode: root.page.passwordVisible ? TextInput.Normal : TextInput.Password
                text: root.page.password
                onTextEdited: root.page.password = text
                onAccepted: if (text.length > 0) root.page.connectSelected()
                color: CortetsuDesign.colorOnSurface
                placeholderText: qsTr("Contraseña de Wi-Fi")
                placeholderTextColor: CortetsuDesign.colorOnSurfaceVariant
                selectionColor: CortetsuDesign.colorPrimaryContainer
                selectedTextColor: CortetsuDesign.colorOnPrimaryContainer
                font.family: CortetsuDesign.fontUi
                Accessible.name: qsTr("Contraseña de Wi-Fi")
                Accessible.passwordEdit: true
                background: Rectangle {
                    color: CortetsuDesign.colorSurfaceHigh
                    radius: CortetsuDesign.radiusSmall
                    border.width: passwordField.activeFocus ? 2 : 1
                    border.color: passwordField.activeFocus ? CortetsuDesign.colorIndicator : CortetsuDesign.colorOutlineVariant
                }
            }

            CortetsuButton {
                compact: true
                label: ""
                icon: root.page.passwordVisible ? "visibility_off" : "visibility"
                tooltipText: root.page.passwordVisible ? qsTr("Ocultar contraseña") : qsTr("Mostrar contraseña")
                Accessible.name: tooltipText
                onClicked: root.page.passwordVisible = !root.page.passwordVisible
            }
        }

        SettingActionRow {
            objectName: "connectNetwork"
            title: root.page.selectedNetwork?.name || qsTr("Red sin nombre")
            detail: root.page.securityLabel(root.page.selectedNetwork)
            status: root.connecting ? "busy" : ""
            statusText: qsTr("Conectando…")
            actionLabel: qsTr("Conectar")
            actionIcon: "wifi"
            actionDisabled: CortetsuSettingsNetwork.busy
                || (root.page.selectedNeedsPassword && root.page.password.length === 0)
            onActivated: root.page.connectSelected()
        }
    }

    SettingsGroup {
        objectName: "savedProfile"
        visible: root.onProfile
        title: root.page.selectedProfile?.name ?? ""
        icon: "bookmark"
        detail: qsTr("Perfil guardado en NetworkManager")

        SettingToggleRow {
            title: qsTr("Conexión automática")
            detail: qsTr("Conectar cuando la red esté al alcance")
            checked: root.page.selectedProfile?.autoconnect ?? false
            disabled: CortetsuSettingsNetwork.busy
            onToggled: checked => root.page.wifi.setAutoconnect(root.page.selectedProfile?.uuid ?? "", checked)
        }

        SettingActionRow {
            visible: root.page.selectedProfile?.uuid === root.page.activeDetails.uuid
            title: qsTr("Desconectar")
            detail: qsTr("Es la red en uso; el perfil se conserva")
            actionLabel: qsTr("Desconectar")
            actionIcon: "link_off"
            disabled: CortetsuSettingsNetwork.busy
            onActivated: root.page.disconnectProfile()
        }

        SettingActionRow {
            objectName: "forgetProfile"
            title: qsTr("Olvidar perfil")
            detail: armed
                ? qsTr("Se borrará el perfil y su contraseña. Pulsa de nuevo para confirmar.")
                : qsTr("Borra el perfil y su contraseña")
            actionLabel: qsTr("Olvidar")
            actionIcon: "delete_outline"
            danger: true
            confirm: true
            disabled: CortetsuSettingsNetwork.busy
            onActivated: root.page.wifi.forgetProfile(root.page.selectedProfile?.uuid ?? "")
        }
    }

    CortetsuStateMessage {
        objectName: "networkDetailState"
        Layout.fillWidth: true
        Layout.topMargin: CortetsuDesign.spacingSpacious
        visible: !root.onNetwork && !root.onProfile
        kind: "empty"
        icon: root.page.showingProfiles ? "bookmark" : "wifi_find"
        title: root.page.showingProfiles ? qsTr("Selecciona un perfil") : qsTr("Selecciona una red")
        detail: root.page.showingProfiles
            ? qsTr("Elige un perfil para administrar su conexión automática")
            : qsTr("Elige una red de la lista para ver su estado y sus acciones")
    }

    CortetsuText {
        objectName: "networkLastMessage"
        Layout.fillWidth: true
        visible: CortetsuSettingsNetwork.lastMessage.length > 0
        text: CortetsuSettingsNetwork.lastMessage
        textSize: CortetsuTypography.bodySmallPx
        color: CortetsuDesign.colorSuccess
        wrapMode: Text.WordWrap
    }
}

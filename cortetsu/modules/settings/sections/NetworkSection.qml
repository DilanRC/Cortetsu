pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import "../../../components"
import "../.."
import "../../../services"
import "../../../utils"
import "../../../theme"
import "../../CortetsuTypography.js" as CortetsuTypography

ColumnLayout {
    id: root

    required property var page

    spacing: CortetsuDesign.spacingStandard

    CortetsuSectionHeader {
        Layout.fillWidth: true
        title: qsTr("Estado de la red")
        detail: qsTr("NetworkManager · operaciones y señal en vivo")
    }

    RowLayout {
        Layout.fillWidth: true

        CortetsuText {
            Layout.fillWidth: true
            text: CortetsuNetwork.wifiDevice
                ? qsTr("Wi‑Fi · %1 redes visibles").arg(CortetsuNetwork.wifiDevice.networks?.values?.length ?? 0)
                : qsTr("Wi‑Fi no disponible")
            textSize: CortetsuTypography.bodySmallPx
            color: CortetsuDesign.colorOnSurfaceVariant
        }

        CortetsuButton {
            compact: true
            icon: CortetsuNetwork.refreshing ? "sync" : "refresh"
            label: qsTr("Actualizar")
            disabled: !CortetsuNetwork.wifiDevice || CortetsuNetwork.refreshing
            onClicked: CortetsuNetwork.refresh()
        }
    }

    PreferenceToggle {
        title: CortetsuSettingsNetwork.wifiEnabled ? qsTr("Wi‑Fi activado") : qsTr("Wi‑Fi desactivado")
        detail: CortetsuSettingsNetwork.state === "error"
            ? CortetsuSettingsNetwork.error
            : qsTr("Radio gestionada por NetworkManager")
        icon: CortetsuSettingsNetwork.wifiEnabled ? "wifi" : "wifi_off"
        checked: CortetsuSettingsNetwork.wifiEnabled
        controlDisabled: CortetsuSettingsNetwork.busy
        onChanged: enabled => CortetsuSettingsNetwork.setWifi(enabled)
    }

    StatusCard {
        title: CortetsuSettingsNetwork.busy
            ? CortetsuSettingsNetwork.operation.kind
            : qsTr("NetworkManager")
        value: CortetsuSettingsNetwork.busy
            ? qsTr("Aplicando…")
            : CortetsuSettingsNetwork.state === "error"
                ? qsTr("Error")
                : CortetsuSettingsNetwork.operation.state === "connected"
                    ? qsTr("Conectada")
                    : qsTr("Listo")
        detail: CortetsuSettingsNetwork.error
        icon: CortetsuSettingsNetwork.state === "error" ? "error"
            : CortetsuSettingsNetwork.busy ? "sync" : "check_circle"
        activeState: CortetsuSettingsNetwork.state !== "error" && !CortetsuSettingsNetwork.busy
        warningState: CortetsuSettingsNetwork.state === "error"
    }

    StatusCard {
        title: qsTr("Conexión actual")
        value: root.page.networkName
        detail: root.page.networkDetail
        icon: CortetsuNetwork.activeEthernet
            ? "cable"
            : CortetsuNetwork.connecting
                ? "sync"
                : CortetsuNetwork.active
                    ? "wifi"
                    : "wifi_off"
        activeState: !!CortetsuNetwork.active || !!CortetsuNetwork.activeEthernet
        warningState: !CortetsuNetwork.active && !CortetsuNetwork.activeEthernet && !CortetsuNetwork.connecting
    }

    Flow {
        Layout.fillWidth: true
        spacing: CortetsuDesign.spacingCompact

        Repeater {
            model: (CortetsuNetwork.wifiDevice?.networks?.values ?? [])
                .slice().sort((a, b) => Number(b.connected) - Number(a.connected)
                    || CortetsuNetwork.strengthPercent(b.signalStrength)
                    - CortetsuNetwork.strengthPercent(a.signalStrength)).slice(0, 6)

            delegate: StatusCard {
                required property var modelData
                width: Math.max(220, (parent?.width ?? 440) / 2 - CortetsuDesign.spacingCompact / 2)
                title: modelData.name ?? qsTr("Red Wi‑Fi")
                value: modelData.connected
                    ? qsTr("Conectada · %1%").arg(CortetsuNetwork.strengthPercent(modelData.signalStrength))
                    : qsTr("Señal %1%").arg(CortetsuNetwork.strengthPercent(modelData.signalStrength))
                detail: modelData.secured ? qsTr("Red protegida") : qsTr("Red abierta")
                icon: Icons.getNetworkIcon(CortetsuNetwork.strengthPercent(modelData.signalStrength))
                activeState: modelData.connected
            }
        }
    }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 0

        CortetsuSectionHeader {
            Layout.fillWidth: true
            title: qsTr("Perfiles guardados")
            detail: qsTr("Autoconexión y desconexión sin salir de Ajustes")
        }

        Repeater {
            model: CortetsuSettingsNetwork.profiles.filter(profile => profile.type === "802-11-wireless")
            delegate: CortetsuListRow {
                required property var modelData
                Layout.fillWidth: true
                title: modelData.name
                subtitle: modelData.autoconnect ? qsTr("Autoconexión activa") : qsTr("Autoconexión desactivada")
                icon: "bookmark"
                selected: Connectivity.wifi.details[Connectivity.wifi.wifiDevice?.name]?.uuid === modelData.uuid
                onClicked: { const network = Connectivity.wifi.networks.find(n => n.connected && Connectivity.wifi.details[n.device.name]?.uuid === modelData.uuid); if (network) Connectivity.wifi.disconnectNetwork(network); }
            }
        }
    }

    CortetsuText {
        Layout.fillWidth: true
        text: qsTr("Selecciona una red guardada para desconectarla. Las operaciones de conexión segura, DNS e IPv4 se incorporarán en el detalle del perfil.")
        textSize: CortetsuTypography.bodySmallPx
        color: CortetsuDesign.colorOnSurfaceVariant
        wrapMode: Text.WordWrap
    }
}

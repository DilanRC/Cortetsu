pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell.Networking
import "../../components"
import "../../services"
import "../CortetsuDesign.js" as Design

ColumnLayout {
    id: root
    readonly property var wifi: Connectivity.wifi
    property string profileUuid: ""
    property bool showHiddenNetwork: false
    property bool showIpv4: false
    signal profileSelected(string uuid)
    readonly property var profiles: wifi.profiles.filter(profile => ["802-11-wireless", "802-3-ethernet"].includes(profile.type))
    readonly property var profile: profiles.find(item => item.uuid === profileUuid) ?? null
    property int requestedIpv4Id: -1
    property string loadedProfileUuid: ""
    readonly property bool ipv4Confirmed: requestedIpv4Id === wifi.operation.id
        && wifi.operation.kind === "ipv4" && wifi.operation.state === "idle"
    readonly property var wiredDevices: wifi.devices.filter(device => device.type === DeviceType.Wired)
    spacing: Design.spacingStandard

    function loadProfile(): void {
        const config = profile?.ipv4;
        ipv4Method.currentIndex = config?.method === "manual" ? 1 : config?.method === "disabled" ? 2 : 0;
        loadedProfileUuid = config ? profileUuid : "";
        address.text = (config?.addresses ?? []).join(", ");
        gateway.text = config?.gateway ?? "";
        dns.text = (config?.dns ?? []).join(", ");
        requestedIpv4Id = -1;
    }
    function connectHidden(): void {
        const secret = hiddenPassword.text;
        hiddenPassword.clear();
        wifi.connectHidden(hiddenSsid.text, wifi.wifiDevices[hiddenInterface.currentIndex]?.name ?? "", secret,
            ["open", "wpa-psk", "sae"][hiddenSecurity.currentIndex]);
    }
    onProfileUuidChanged: loadProfile()
    onProfileChanged: { if (profile?.ipv4 && loadedProfileUuid !== profileUuid) loadProfile(); }
    onShowHiddenNetworkChanged: { if (!showHiddenNetwork) hiddenPassword.clear(); }
    onVisibleChanged: { if (!visible) hiddenPassword.clear(); }
    Connections {
        target: root.wifi
        function onProfilesChanged(): void {
            if (!root.profile) root.requestedIpv4Id = -1;
        }
    }

    RowLayout {
        Layout.fillWidth: true
        CortetsuSectionHeader { Layout.fillWidth: true; title: qsTr("Red oculta"); detail: qsTr("Conectar un punto de acceso que no anuncia su nombre") }
        CortetsuButton { compact: true; label: root.showHiddenNetwork ? qsTr("Cerrar") : qsTr("Añadir red"); icon: root.showHiddenNetwork ? "close" : "add"; onClicked: root.showHiddenNetwork = !root.showHiddenNetwork }
    }
    CortetsuSurface {
        Layout.fillWidth: true
        visible: root.showHiddenNetwork
        implicitHeight: hiddenBody.implicitHeight + Design.spacingComfortable * 2
        baseColor: Qt.alpha(Design.colorSurfaceGlass, 0.72)
        outlined: true
        radiusValue: Design.radiusMedium
        ColumnLayout {
            id: hiddenBody
            anchors.fill: parent
            anchors.margins: Design.spacingComfortable
            spacing: Design.spacingCompact
            Field {
                id: hiddenSsid
                Layout.fillWidth: true
                placeholderText: qsTr("Nombre de la red (SSID)")
                Accessible.name: qsTr("Nombre de la red oculta")
            }
            Choice {
                id: hiddenInterface
                Layout.fillWidth: true
                model: root.wifi.wifiDevices.map(device => device.name)
                Accessible.name: qsTr("Adaptador de la red oculta")
            }
            Choice {
                id: hiddenSecurity
                Layout.fillWidth: true
                model: [qsTr("Abierta"), "WPA / WPA2 Personal", "WPA3 Personal (SAE)"]
                currentIndex: 1
                onCurrentIndexChanged: hiddenPassword.clear()
                Accessible.name: qsTr("Seguridad de la red oculta")
            }
            Field {
                id: hiddenPassword
                Layout.fillWidth: true
                visible: hiddenSecurity.currentIndex !== 0
                echoMode: TextInput.Password
                placeholderText: qsTr("Contraseña de la red oculta")
                Accessible.name: placeholderText
                onAccepted: root.connectHidden()
            }
            CortetsuText {
                Layout.fillWidth: true
                text: qsTr("802.1X requiere un perfil configurado con identidad y certificados.")
                wrapMode: Text.WordWrap
                textSize: Design.bodySmallPx
                color: Design.colorOnSurfaceVariant
            }
            CortetsuButton {
                label: qsTr("Conectar red oculta")
                icon: "wifi"
                disabled: root.wifi.busy || !root.wifi.wifiEnabled || !root.wifi.hardwareEnabled
                    || hiddenSsid.text.length === 0 || hiddenInterface.currentIndex < 0
                onClicked: root.connectHidden()
            }
        }
    }

    RowLayout {
        Layout.fillWidth: true
        CortetsuSectionHeader { Layout.fillWidth: true; title: qsTr("IPv4 del perfil"); detail: qsTr("Configuración guardada por UUID") }
        CortetsuButton { compact: true; label: root.showIpv4 ? qsTr("Cerrar") : qsTr("Configurar IPv4"); icon: root.showIpv4 ? "close" : "settings"; onClicked: root.showIpv4 = !root.showIpv4 }
    }
    Choice {
        id: profileChoice
        visible: root.showIpv4
        Layout.fillWidth: true
        model: root.profiles
        textRole: "name"
        currentIndex: root.profiles.findIndex(item => item.uuid === root.profileUuid)
        onActivated: index => root.profileSelected(root.profiles[index].uuid)
        Accessible.name: qsTr("Perfil para configurar IPv4")
    }
    CortetsuStateMessage {
        Layout.fillWidth: true
        visible: root.showIpv4 && !root.profile
        title: qsTr("Selecciona un perfil guardado")
        detail: qsTr("La configuración IPv4 pertenece al perfil de Wi-Fi o Ethernet seleccionado")
    }
    CortetsuSurface {
        Layout.fillWidth: true
        visible: root.showIpv4 && !!root.profile
        implicitHeight: ipv4Body.implicitHeight + Design.spacingComfortable * 2
        baseColor: Qt.alpha(Design.colorSurfaceGlass, 0.72)
        outlined: true
        radiusValue: Design.radiusMedium
        ColumnLayout {
            id: ipv4Body
            anchors.fill: parent
            anchors.margins: Design.spacingComfortable
            spacing: Design.spacingCompact
            ConnectionDetail { Layout.fillWidth: true; label: "UUID"; value: root.profileUuid }
            Choice {
                id: ipv4Method
                Layout.fillWidth: true
                model: [qsTr("Automática (DHCP)"), qsTr("Manual"), qsTr("IPv4 desactivada")]
                Accessible.name: qsTr("Método IPv4")
            }
            Field {
                id: address
                Layout.fillWidth: true
                visible: ipv4Method.currentIndex === 1
                placeholderText: qsTr("Dirección y prefijo, por ejemplo 192.168.1.20/24")
                Accessible.name: qsTr("Dirección IPv4 y prefijo CIDR")
            }
            Field {
                id: gateway
                Layout.fillWidth: true
                visible: ipv4Method.currentIndex === 1
                placeholderText: qsTr("Puerta de enlace IPv4 (opcional)")
                Accessible.name: placeholderText
            }
            Field {
                id: dns
                Layout.fillWidth: true
                visible: ipv4Method.currentIndex !== 2
                placeholderText: qsTr("DNS IPv4 separados por comas; vacío usa los automáticos")
                Accessible.name: qsTr("Servidores DNS IPv4")
            }
            CortetsuButton {
                label: qsTr("Guardar IPv4")
                icon: "save"
                disabled: root.wifi.busy || !root.profile?.ipv4
                onClicked: {
                    root.wifi.setIpv4(root.profileUuid, ["auto", "manual", "disabled"][ipv4Method.currentIndex], address.text, gateway.text, dns.text);
                    root.requestedIpv4Id = root.wifi.operation.id;
                }
            }
            CortetsuText {
                Layout.fillWidth: true
                visible: root.ipv4Confirmed
                text: qsTr("Configuración confirmada en NetworkManager. Reconecta este perfil para aplicarla.")
                wrapMode: Text.WordWrap
                textSize: Design.bodySmallPx
                color: Design.colorOnSurfaceVariant
            }
        }
    }

    CortetsuSectionHeader { title: qsTr("Ethernet"); detail: Connectivity.internetLabel }
    CortetsuStateMessage {
        Layout.fillWidth: true
        visible: root.wiredDevices.length === 0
        title: qsTr("No hay interfaces Ethernet disponibles")
        detail: qsTr("Conecta un adaptador o comprueba que NetworkManager gestione la interfaz")
    }
    Repeater {
        model: root.wiredDevices
        delegate: CortetsuSurface {
            id: wired
            required property var modelData
            readonly property var details: root.wifi.details[modelData.name] ?? ({})
            Layout.fillWidth: true
            implicitHeight: wiredBody.implicitHeight + Design.spacingComfortable * 2
            baseColor: Qt.alpha(Design.colorSurfaceGlass, 0.72)
            outlined: true
            radiusValue: Design.radiusMedium
            Component.onCompleted: root.wifi.refreshDetails(modelData.name)
            ColumnLayout {
                id: wiredBody
                anchors.fill: parent
                anchors.margins: Design.spacingComfortable
                spacing: Design.spacingCompact
                CortetsuSectionHeader { title: wired.modelData.name; detail: wired.modelData.connected ? qsTr("Conectada") : qsTr("Desconectada") }
                ConnectionDetail { Layout.fillWidth: true; label: qsTr("Perfil activo"); value: wired.details.profileName ?? "" }
                ConnectionDetail { Layout.fillWidth: true; label: "UUID"; value: wired.details.uuid ?? "" }
                ConnectionDetail { Layout.fillWidth: true; label: "IPv4"; value: wired.details.address ?? "" }
                ConnectionDetail { Layout.fillWidth: true; label: "IPv6"; value: (wired.details.ipv6Addresses ?? []).join(", ") }
                ConnectionDetail { Layout.fillWidth: true; label: qsTr("Puerta de enlace"); value: wired.details.gateway ?? "" }
                ConnectionDetail { Layout.fillWidth: true; label: "DNS"; value: (wired.details.dns ?? []).join(", ") }
                CortetsuButton {
                    visible: wired.modelData.connected
                    label: qsTr("Desconectar Ethernet")
                    icon: "link_off"
                    disabled: root.wifi.busy
                    onClicked: root.wifi.disconnectWired(wired.modelData)
                }
                Repeater {
                    model: root.profiles.filter(profile => profile.type === "802-3-ethernet"
                        && (!profile.interface || profile.interface === wired.modelData.name))
                    delegate: CortetsuButton {
                        required property var modelData
                        Layout.fillWidth: true
                        label: qsTr("Conectar %1").arg(modelData.name)
                        icon: "link"
                        disabled: root.wifi.busy
                        onClicked: root.wifi.connectProfile(modelData.uuid, wired.modelData.name)
                    }
                }
            }
        }
    }
    component Choice: ComboBox {
        id: choice
        implicitHeight: Design.controlHeight
        leftPadding: Design.spacingStandard
        rightPadding: Design.spacingComfortable * 2
        font.pixelSize: Design.bodySmallPx
        contentItem: CortetsuText {
            text: choice.displayText
            textSize: Design.bodySmallPx
            color: Design.colorOnSurface
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
        }
        indicator: CortetsuIcon {
            x: choice.width - width - Design.spacingStandard
            y: (choice.height - height) / 2
            text: "expand_more"
            color: Design.colorOnSurfaceVariant
        }
        background: CortetsuSurface {
            baseColor: Design.colorSurfaceGlassStrong
            radiusValue: Design.radiusSmall
            focused: choice.activeFocus
            outlined: true
        }
        popup.background: CortetsuSurface {
            baseColor: Design.colorSurfaceGlassStrong
            radiusValue: Design.radiusSmall
            outlined: true
        }
        delegate: ItemDelegate {
            id: option
            required property int index
            required property var modelData
            width: choice.width
            highlighted: choice.highlightedIndex === index
            contentItem: CortetsuText {
                text: option.modelData?.name ?? String(option.modelData)
                textSize: Design.bodySmallPx
                color: Design.colorOnSurface
                elide: Text.ElideRight
            }
            background: CortetsuSurface {
                baseColor: option.highlighted ? Design.colorPrimaryContainer : Design.colorSurfaceGlassStrong
                radiusValue: Design.radiusSmall
                outlined: option.highlighted
            }
        }
    }
    component Field: TextField {
        font.pixelSize: Design.bodySmallPx
        implicitHeight: Design.controlHeight
        padding: Design.spacingStandard
        color: Design.colorOnSurface
        background: CortetsuSurface { baseColor: Design.colorSurfaceGlassStrong; radiusValue: Design.radiusSmall; focused: parent.activeFocus; outlined: true }
    }
}

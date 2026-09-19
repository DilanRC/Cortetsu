pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../../components"
import "../../services"
import ".."
import "../CortetsuDesign.js" as CortetsuDesign
import "../CortetsuTypography.js" as CortetsuTypography

// Wi-Fi is a workbench: the active link stays visible while the explorer and
// inspector handle discovery, saved profiles and NetworkManager actions.
Item {
    id: root

    required property var screenState
    required property var screen

    property bool showingProfiles: false
    property int selectedIndex: 0
    property string networkQuery: ""
    property bool strongestFirst: true
    property bool passwordVisible: false
    property string password: ""

    readonly property var networks: CortetsuSettingsNetwork.networks
    readonly property var profiles: CortetsuSettingsNetwork.profiles.filter(profile => profile.type === "802-11-wireless")
    readonly property var filteredNetworks: {
        const query = root.networkQuery.trim().toLowerCase();
        const matching = root.networks.filter(network =>
            !query || String(network.ssid ?? "").toLowerCase().includes(query));
        return matching.slice().sort((left, right) => {
            if (left.active !== right.active)
                return left.active ? -1 : 1;
            return root.strongestFirst
                ? Number(right.signal ?? 0) - Number(left.signal ?? 0)
                : String(left.ssid ?? "").localeCompare(String(right.ssid ?? ""));
        });
    }
    readonly property var selectedNetwork: root.showingProfiles
        ? null
        : root.filteredNetworks[root.selectedIndex] ?? null
    readonly property var activeNetwork: root.networks.find(network =>
        network.active || network.ssid === CortetsuSettingsNetwork.activeSsid) ??
        (CortetsuSettingsNetwork.activeSsid.length > 0
            ? { active: true, signal: -1, ssid: CortetsuSettingsNetwork.activeSsid,
                security: "", device: CortetsuSettingsNetwork.activeDevice }
            : null)
    readonly property var activeProfile: root.profiles.find(profile =>
        profile.name === (root.activeNetwork?.ssid ?? CortetsuSettingsNetwork.activeSsid)) ?? null
    readonly property var selectedProfile: {
        const name = root.showingProfiles
            ? root.profiles[root.selectedIndex]?.name
            : root.selectedNetwork?.ssid;
        return root.profiles.find(profile => profile.name === name) ?? null;
    }
    readonly property bool selectedIsActive: !!root.selectedNetwork
        && (root.selectedNetwork.active || root.selectedNetwork.ssid === CortetsuSettingsNetwork.activeSsid)
    readonly property bool selectedNeedsPassword: !!root.selectedNetwork
        && String(root.selectedNetwork.security ?? "").length > 0
        && !root.selectedIsActive
    readonly property bool selectedCanCopyPassword: !!root.selectedProfile
        && String(root.selectedNetwork?.security ?? "").length > 0
    readonly property bool compactLayout: width < 700
    readonly property var activeDetails: CortetsuSettingsNetwork.activeDetails

    // Content.qml places the page in the settings Flickable. This is tall
    // enough for the split workbench while still allowing the compact layout
    // to grow naturally when a narrow window wraps it vertically.
    implicitHeight: root.compactLayout ? 1060 : 720

    component SignalBars: Row {
        id: bars
        property real signalValue: 0
        property color activeColor: CortetsuDesign.colorPrimary
        property int barCount: 5
        spacing: 3
        height: 24

        Repeater {
            model: bars.barCount
            delegate: Rectangle {
                required property int index
                width: 5
                height: 8 + index * 4
                y: bars.height - height
                radius: 2
                color: index < Math.ceil(Math.max(0, bars.signalValue) / (100 / bars.barCount))
                    ? bars.activeColor
                    : Qt.alpha(CortetsuDesign.colorOutlineVariant, 0.48)
            }
        }
    }

    component DetailRow: RowLayout {
        required property string label
        required property string value
        Layout.fillWidth: true
        spacing: CortetsuDesign.spacingStandard

        CortetsuText {
            Layout.fillWidth: true
            text: parent.label
            textSize: CortetsuTypography.bodySmallPx
            color: CortetsuDesign.colorOnSurfaceVariant
        }

        CortetsuText {
            Layout.minimumWidth: 110
            text: parent.value
            textSize: CortetsuTypography.bodySmallPx
            font.weight: Font.DemiBold
            horizontalAlignment: Text.AlignRight
            elide: Text.ElideRight
        }
    }

    function signalLabel(signal): string {
        const value = Number(signal ?? -1);
        if (value < 0) return qsTr("Sin medición");
        if (value >= 80) return qsTr("Excelente");
        if (value >= 60) return qsTr("Buena");
        if (value >= 35) return qsTr("Aceptable");
        return qsTr("Débil");
    }

    function signalValue(signal): real {
        return Math.max(0, Math.min(100, Number(signal ?? 0))) / 100;
    }

    function signalText(signal): string {
        const value = Number(signal ?? -1);
        return value >= 0 ? qsTr("%1%").arg(value) : qsTr("—");
    }

    function securityLabel(network): string {
        if (!network || String(network.security ?? "").length === 0)
            return qsTr("Red abierta");
        return String(network.security);
    }

    function networkIsActive(network): bool {
        return !!network && (network.active || network.ssid === CortetsuSettingsNetwork.activeSsid);
    }

    function resetSelection(): void {
        selectedIndex = 0;
        password = "";
        passwordVisible = false;
    }

    function refreshDetails(): void {
        const device = root.activeNetwork?.device ?? "";
        if (device.length > 0)
            CortetsuSettingsNetwork.refreshDetails(device);
    }

    function refreshAll(): void {
        CortetsuSettingsNetwork.refreshAll();
        Qt.callLater(root.refreshDetails);
    }

    function connectSelected(): void {
        if (!root.selectedNetwork)
            return;
        CortetsuSettingsNetwork.connect(root.selectedNetwork.ssid,
            root.selectedNeedsPassword ? root.password : "");
        root.password = "";
    }

    function copySelectedPassword(): void {
        const profile = root.selectedProfile?.name ?? root.selectedNetwork?.ssid ?? "";
        if (profile.length > 0)
            CortetsuSettingsNetwork.copyPassword(profile);
    }

    function disconnectActive(): void {
        const profile = root.activeProfile?.name ?? root.activeNetwork?.ssid ?? "";
        if (profile.length > 0)
            CortetsuSettingsNetwork.disconnect(profile);
    }

    function forgetActive(): void {
        const profile = root.activeProfile?.name ?? root.activeNetwork?.ssid ?? "";
        if (profile.length > 0)
            CortetsuSettingsNetwork.forget(profile);
    }

    function detailsValue(value): string {
        return String(value ?? "").length > 0 ? String(value) : qsTr("No disponible");
    }

    onShowingProfilesChanged: resetSelection()
    onNetworkQueryChanged: resetSelection()

    Component.onCompleted: Qt.callLater(root.refreshDetails)

    Connections {
        target: CortetsuSettingsNetwork

        function onNetworksChanged(): void {
            if (root.selectedIndex >= root.filteredNetworks.length)
                root.resetSelection();
            root.refreshDetails();
        }

        function onProfilesChanged(): void {
            if (root.showingProfiles && root.selectedIndex >= root.profiles.length)
                root.resetSelection();
        }

        function onActiveSsidChanged(): void {
            root.refreshDetails();
        }

        function onActiveDeviceChanged(): void {
            root.refreshDetails();
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: CortetsuDesign.spacingStandard

        CortetsuSurface {
            Layout.fillWidth: true
            visible: CortetsuSettingsNetwork.state === "error"
            implicitHeight: 52
            baseColor: Qt.alpha(CortetsuDesign.colorWarning, 0.12)
            outlineColor: Qt.alpha(CortetsuDesign.colorWarning, 0.54)
            outlined: true
            radiusValue: CortetsuDesign.radiusMedium

            RowLayout {
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
                    text: CortetsuSettingsNetwork.error
                    textSize: CortetsuTypography.bodySmallPx
                    color: CortetsuDesign.colorWarning
                    elide: Text.ElideRight
                }

                CortetsuButton {
                    compact: true
                    icon: "refresh"
                    label: qsTr("Reintentar")
                    disabled: CortetsuSettingsNetwork.busy
                    onClicked: root.refreshAll()
                }
            }
        }

        CortetsuSurface {
            Layout.fillWidth: true
            visible: !!root.activeNetwork
            implicitHeight: 104
            baseColor: Qt.alpha(CortetsuDesign.colorPrimaryContainer, 0.64)
            outlineColor: Qt.alpha(CortetsuDesign.colorPrimary, 0.54)
            outlined: true
            radiusValue: CortetsuDesign.radiusMedium

            RowLayout {
                anchors.fill: parent
                anchors.margins: CortetsuDesign.spacingStandard
                spacing: CortetsuDesign.spacingStandard

                CortetsuSurface {
                    Layout.preferredWidth: 64
                    Layout.preferredHeight: 64
                    baseColor: Qt.alpha(CortetsuDesign.colorPrimary, 0.18)
                    outlined: false
                    radiusValue: CortetsuDesign.radiusMedium

                    CortetsuIcon {
                        anchors.centerIn: parent
                        text: "wifi"
                        color: CortetsuDesign.colorPrimary
                        iconSize: CortetsuTypography.iconLargePx
                    }
                }

                ColumnLayout {
                    Layout.preferredWidth: 185
                    Layout.minimumWidth: 145
                    spacing: 2

                    CortetsuText {
                        text: qsTr("Conexión actual")
                        textSize: CortetsuTypography.labelSmallPx
                        color: CortetsuDesign.colorOnSurfaceVariant
                    }

                    CortetsuText {
                        Layout.fillWidth: true
                        text: root.activeNetwork?.ssid ?? qsTr("No hay conexión Wi‑Fi activa")
                        textSize: CortetsuTypography.titleMediumPx
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }

                    CortetsuText {
                        Layout.fillWidth: true
                        text: qsTr("Conectada · %1 · %2 · %3")
                            .arg(root.signalLabel(root.activeNetwork?.signal))
                            .arg(root.securityLabel(root.activeNetwork))
                            .arg(root.activeNetwork?.device || qsTr("dispositivo no disponible"))
                        textSize: CortetsuTypography.labelSmallPx
                        color: CortetsuDesign.colorOnSurfaceVariant
                        elide: Text.ElideRight
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 150
                    spacing: CortetsuDesign.spacingCompact

                    RowLayout {
                        Layout.fillWidth: true
                        CortetsuText {
                            Layout.fillWidth: true
                            text: qsTr("Calidad de la señal")
                            textSize: CortetsuTypography.labelSmallPx
                            color: CortetsuDesign.colorOnSurfaceVariant
                        }
                        CortetsuText {
                            text: root.signalText(root.activeNetwork?.signal)
                            textSize: CortetsuTypography.bodyPx
                            font.weight: Font.DemiBold
                        }
                    }

                    CortetsuProgressBar {
                        Layout.fillWidth: true
                        value: root.signalValue(root.activeNetwork?.signal)
                        fillColor: CortetsuDesign.colorPrimary
                        barHeight: 6
                    }

                    SignalBars {
                        Layout.alignment: Qt.AlignRight
                        signalValue: root.activeNetwork?.signal ?? 0
                        activeColor: CortetsuDesign.colorPrimary
                    }
                }

                RowLayout {
                    visible: !root.compactLayout
                    Layout.alignment: Qt.AlignRight
                    spacing: CortetsuDesign.spacingCompact

                    CortetsuButton {
                        compact: true
                        danger: true
                        icon: "link_off"
                        label: qsTr("Desconectar")
                        disabled: CortetsuSettingsNetwork.busy
                        onClicked: root.disconnectActive()
                    }

                    CortetsuButton {
                        compact: true
                        icon: "visibility_off"
                        label: qsTr("Olvidar")
                        disabled: CortetsuSettingsNetwork.busy
                        onClicked: root.forgetActive()
                    }
                }
            }
        }

        RowLayout {
            visible: !!root.activeNetwork && root.compactLayout
            Layout.fillWidth: true
            spacing: CortetsuDesign.spacingCompact

            CortetsuButton {
                compact: true
                danger: true
                icon: "link_off"
                label: qsTr("Desconectar")
                disabled: CortetsuSettingsNetwork.busy
                onClicked: root.disconnectActive()
            }

            CortetsuButton {
                compact: true
                icon: "visibility_off"
                label: qsTr("Olvidar")
                disabled: CortetsuSettingsNetwork.busy
                onClicked: root.forgetActive()
            }
        }

        Flow {
            id: workbench
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: CortetsuDesign.spacingSection
            property bool compact: root.compactLayout
            height: compact
                ? listPanel.implicitHeight + detailPanel.implicitHeight + spacing
                : Math.max(listPanel.implicitHeight, detailPanel.implicitHeight)

            Item {
                id: listPanel
                width: workbench.compact
                    ? workbench.width
                    : Math.min(390, Math.max(340, workbench.width * 0.34))
                height: implicitHeight
                implicitHeight: 520

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

                        CortetsuButton {
                            Layout.fillWidth: true
                            compact: true
                            icon: "wifi"
                            label: qsTr("Cercanas")
                            active: !root.showingProfiles
                            onClicked: root.showingProfiles = false
                        }

                        CortetsuButton {
                            Layout.fillWidth: true
                            compact: true
                            icon: "bookmark"
                            label: qsTr("Guardadas")
                            active: root.showingProfiles
                            onClicked: root.showingProfiles = true
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true

                        CortetsuText {
                            Layout.fillWidth: true
                            text: root.showingProfiles
                                ? qsTr("%1 perfiles guardados").arg(root.profiles.length)
                                : qsTr("%1 redes visibles").arg(root.filteredNetworks.length)
                            textSize: CortetsuTypography.labelSmallPx
                            color: CortetsuDesign.colorOnSurfaceVariant
                        }

                        CortetsuButton {
                            compact: true
                            visible: !root.showingProfiles
                            icon: root.strongestFirst ? "sort" : "sort_by_alpha"
                            label: root.strongestFirst ? qsTr("Señal") : qsTr("Nombre")
                            tooltipText: qsTr("Cambiar orden de la lista")
                            onClicked: root.strongestFirst = !root.strongestFirst
                        }
                    }

                    CortetsuSearchBar {
                        Layout.fillWidth: true
                        compact: true
                        visible: !root.showingProfiles
                        placeholderText: qsTr("Filtrar redes…")
                        onTextChanged: root.networkQuery = text
                    }

                    ListView {
                        id: networkList
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        spacing: 3
                        model: root.showingProfiles ? root.profiles : root.filteredNetworks
                        currentIndex: root.selectedIndex
                        onCurrentIndexChanged: if (currentIndex >= 0) root.selectedIndex = currentIndex

                        delegate: Item {
                            id: networkDelegate
                            required property var modelData
                            required property int index
                            width: networkList.width
                            height: 60

                            CortetsuSurface {
                                anchors.fill: parent
                                baseColor: index === root.selectedIndex
                                    ? Qt.alpha(CortetsuDesign.colorPrimaryContainer, 0.86)
                                    : delegateMouse.containsMouse
                                        ? Qt.alpha(CortetsuDesign.colorSurfaceGlassStrong, 0.94)
                                        : "transparent"
                                outlineColor: index === root.selectedIndex
                                    ? Qt.alpha(CortetsuDesign.colorPrimary, 0.44)
                                    : "transparent"
                                outlined: index === root.selectedIndex
                                radiusValue: CortetsuDesign.radiusSmall
                                hovered: delegateMouse.containsMouse
                            }

                            Rectangle {
                                anchors.left: parent.left
                                anchors.leftMargin: 3
                                anchors.verticalCenter: parent.verticalCenter
                                width: 2
                                height: 30
                                radius: 1
                                visible: index === root.selectedIndex
                                color: CortetsuDesign.colorWashi
                            }

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: CortetsuDesign.spacingStandard
                                anchors.rightMargin: CortetsuDesign.spacingCompact
                                spacing: CortetsuDesign.spacingCompact

                                CortetsuIcon {
                                    text: root.showingProfiles
                                        ? "bookmark"
                                        : root.networkIsActive(networkDelegate.modelData)
                                            ? "wifi"
                                            : networkDelegate.modelData.security
                                                ? "wifi_lock"
                                                : "wifi_find"
                                    color: root.networkIsActive(networkDelegate.modelData)
                                        ? CortetsuDesign.colorSuccess
                                        : index === root.selectedIndex
                                            ? CortetsuDesign.colorOnPrimaryContainer
                                            : CortetsuDesign.colorPrimary
                                    iconSize: CortetsuTypography.iconMediumPx
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 1

                                    CortetsuText {
                                        Layout.fillWidth: true
                                        text: root.showingProfiles
                                            ? networkDelegate.modelData.name
                                            : (networkDelegate.modelData.ssid || qsTr("Red sin nombre"))
                                        textSize: CortetsuTypography.bodySmallPx
                                        font.weight: root.networkIsActive(networkDelegate.modelData) ? Font.DemiBold : Font.Normal
                                        color: index === root.selectedIndex
                                            ? CortetsuDesign.colorOnPrimaryContainer
                                            : CortetsuDesign.colorOnSurface
                                        elide: Text.ElideRight
                                    }

                                    CortetsuText {
                                        Layout.fillWidth: true
                                        text: root.showingProfiles
                                            ? (networkDelegate.modelData.autoconnect
                                                ? qsTr("Autoconexión activa")
                                                : qsTr("Autoconexión desactivada"))
                                            : qsTr("%1 · %2")
                                                .arg(root.signalLabel(networkDelegate.modelData.signal))
                                                .arg(root.securityLabel(networkDelegate.modelData))
                                        textSize: CortetsuTypography.labelSmallPx
                                        color: index === root.selectedIndex
                                            ? Qt.alpha(CortetsuDesign.colorOnPrimaryContainer, 0.76)
                                            : CortetsuDesign.colorOnSurfaceVariant
                                        elide: Text.ElideRight
                                    }
                                }

                                SignalBars {
                                    visible: !root.showingProfiles
                                    signalValue: Number(networkDelegate.modelData.signal ?? 0)
                                    activeColor: root.networkIsActive(networkDelegate.modelData)
                                        ? CortetsuDesign.colorSuccess
                                        : index === root.selectedIndex
                                            ? CortetsuDesign.colorOnPrimaryContainer
                                            : CortetsuDesign.colorPrimary
                                }

                                CortetsuIcon {
                                    visible: !root.showingProfiles && root.networkIsActive(networkDelegate.modelData)
                                    text: "check"
                                    color: CortetsuDesign.colorSuccess
                                    iconSize: CortetsuTypography.iconSmallPx
                                }
                            }

                            MouseArea {
                                id: delegateMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.selectedIndex = networkDelegate.index
                            }
                        }

                        CortetsuStateMessage {
                            anchors.centerIn: parent
                            visible: networkList.count === 0
                            kind: CortetsuSettingsNetwork.busy ? "loading" : "empty"
                            title: CortetsuSettingsNetwork.busy
                                ? qsTr("Buscando redes")
                                : root.showingProfiles
                                    ? qsTr("No hay perfiles guardados")
                                    : root.networkQuery.length > 0
                                        ? qsTr("No hay coincidencias")
                                        : qsTr("No hay redes visibles")
                            detail: root.showingProfiles
                                ? qsTr("Los perfiles aparecerán después de conectarte a una red")
                                : qsTr("Pulsa Actualizar para volver a escanear")
                        }
                    }
                }
            }

            Item {
                id: detailPanel
                width: workbench.compact
                    ? workbench.width
                    : Math.max(0, workbench.width - listPanel.width - workbench.spacing)
                height: implicitHeight
                implicitHeight: 520

                CortetsuSurface {
                    id: detailBackdrop
                    anchors.fill: detailColumn
                    visible: !root.showingProfiles && !!root.selectedNetwork
                    z: -1
                    baseColor: Qt.alpha(CortetsuDesign.colorSurfaceGlass, 0.58)
                    outlined: true
                    radiusValue: CortetsuDesign.radiusMedium
                }

                ColumnLayout {
                    id: detailColumn
                    anchors.fill: parent
                    anchors.margins: root.showingProfiles || !root.selectedNetwork ? 0 : CortetsuDesign.spacingStandard
                    spacing: root.showingProfiles || !root.selectedNetwork ? CortetsuDesign.spacingStandard : 0

                    RowLayout {
                        id: detailHeader
                        Layout.fillWidth: true
                        visible: root.showingProfiles || !root.selectedNetwork

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2

                            CortetsuText {
                                Layout.fillWidth: true
                                text: root.showingProfiles
                                    ? (root.selectedProfile?.name ?? qsTr("Perfil guardado"))
                                    : (root.selectedNetwork?.ssid ?? qsTr("Selecciona una red"))
                                textSize: CortetsuTypography.titleMediumPx
                                font.weight: Font.DemiBold
                                elide: Text.ElideRight
                            }

                            CortetsuText {
                                Layout.fillWidth: true
                                text: root.showingProfiles
                                    ? qsTr("Preferencias de conexión guardadas")
                                    : root.selectedNetwork
                                        ? qsTr("%1 · %2")
                                            .arg(root.securityLabel(root.selectedNetwork))
                                            .arg(root.selectedNetwork.device || qsTr("dispositivo no disponible"))
                                        : qsTr("Elige una red para ver sus propiedades")
                                textSize: CortetsuTypography.labelSmallPx
                                color: CortetsuDesign.colorOnSurfaceVariant
                                elide: Text.ElideRight
                            }
                        }

                        CortetsuButton {
                            visible: !root.showingProfiles && root.selectedCanCopyPassword
                            compact: true
                            icon: root.secretState === "ready" ? "check" : "key"
                            label: root.secretState === "ready"
                                ? qsTr("Contraseña copiada")
                                : qsTr("Copiar contraseña")
                            disabled: CortetsuSettingsNetwork.secretBusy
                            onClicked: root.copySelectedPassword()
                        }
                    }

                    CortetsuSurface {
                        Layout.fillWidth: true
                        visible: !root.showingProfiles && !!root.selectedNetwork
                        implicitHeight: 206
                        baseColor: "transparent"
                        outlined: false
                        radiusValue: 0

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: CortetsuDesign.spacingStandard
                            spacing: CortetsuDesign.spacingStandard

                            RowLayout {
                                Layout.fillWidth: true

                                CortetsuSurface {
                                    Layout.preferredWidth: 54
                                    Layout.preferredHeight: 54
                                    baseColor: root.selectedIsActive
                                        ? Qt.alpha(CortetsuDesign.colorSuccess, 0.16)
                                        : Qt.alpha(CortetsuDesign.colorPrimary, 0.14)
                                    outlined: false
                                    radiusValue: CortetsuDesign.radiusMedium

                                    CortetsuIcon {
                                        anchors.centerIn: parent
                                        text: root.selectedIsActive ? "wifi" : "wifi_find"
                                        color: root.selectedIsActive
                                            ? CortetsuDesign.colorSuccess
                                            : CortetsuDesign.colorPrimary
                                        iconSize: CortetsuTypography.iconLargePx
                                    }
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 2

                                    RowLayout {
                                        spacing: CortetsuDesign.spacingCompact
                                        CortetsuText {
                                            text: root.selectedIsActive
                                                ? qsTr("Conectada ahora")
                                                : qsTr("Red disponible")
                                            textSize: CortetsuTypography.labelSmallPx
                                            color: CortetsuDesign.colorOnSurfaceVariant
                                        }
                                        Rectangle {
                                            visible: root.selectedIsActive
                                            width: 8
                                            height: width
                                            radius: width / 2
                                            color: CortetsuDesign.colorSuccess
                                            Layout.alignment: Qt.AlignVCenter
                                        }
                                    }

                                    CortetsuText {
                                        text: root.selectedNetwork?.ssid ?? ""
                                        textSize: CortetsuTypography.titleMediumPx
                                        font.weight: Font.DemiBold
                                        elide: Text.ElideRight
                                    }

                                    CortetsuText {
                                        text: root.signalLabel(root.selectedNetwork?.signal)
                                        textSize: CortetsuTypography.bodySmallPx
                                        color: root.selectedIsActive
                                            ? CortetsuDesign.colorSuccess
                                            : CortetsuDesign.colorOnSurfaceVariant
                                    }
                                }

                                CortetsuText {
                                    text: root.signalText(root.selectedNetwork?.signal)
                                    textSize: CortetsuTypography.titleMediumPx
                                    font.weight: Font.DemiBold
                                }

                                CortetsuButton {
                                    visible: root.selectedCanCopyPassword
                                    compact: true
                                    icon: root.secretState === "ready" ? "check" : "key"
                                    label: root.secretState === "ready"
                                        ? qsTr("Contraseña copiada")
                                        : qsTr("Copiar contraseña")
                                    disabled: CortetsuSettingsNetwork.secretBusy
                                    onClicked: root.copySelectedPassword()
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: true

                                CortetsuText {
                                    Layout.fillWidth: true
                                    text: qsTr("Calidad de la señal")
                                    textSize: CortetsuTypography.labelSmallPx
                                    color: CortetsuDesign.colorOnSurfaceVariant
                                }

                                SignalBars {
                                    signalValue: root.selectedNetwork?.signal ?? 0
                                    activeColor: root.selectedIsActive
                                        ? CortetsuDesign.colorSuccess
                                        : CortetsuDesign.colorPrimary
                                }
                            }

                            CortetsuProgressBar {
                                Layout.fillWidth: true
                                value: root.signalValue(root.selectedNetwork?.signal)
                                fillColor: root.selectedIsActive
                                    ? CortetsuDesign.colorSuccess
                                    : CortetsuDesign.colorPrimary
                                barHeight: 7
                            }
                        }
                    }

                    CortetsuSurface {
                        Layout.fillWidth: true
                        visible: !root.showingProfiles && !!root.selectedNetwork
                        implicitHeight: 134
                        baseColor: "transparent"
                        outlined: false
                        radiusValue: 0

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: CortetsuDesign.spacingStandard
                            spacing: CortetsuDesign.spacingCompact

                            DetailRow {
                                label: qsTr("Seguridad")
                                value: root.securityLabel(root.selectedNetwork)
                            }

                            DetailRow {
                                label: qsTr("Dispositivo")
                                value: root.detailsValue(root.selectedNetwork?.device)
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                CortetsuText {
                                    Layout.fillWidth: true
                                    text: root.selectedProfile?.autoconnect
                                        ? qsTr("Conexión automática")
                                        : qsTr("Conexión automática desactivada")
                                    textSize: CortetsuTypography.bodySmallPx
                                    color: CortetsuDesign.colorOnSurfaceVariant
                                }
                                CortetsuToggle {
                                    checked: root.selectedProfile?.autoconnect ?? false
                                    visible: !!root.selectedProfile
                                    disabled: CortetsuSettingsNetwork.busy
                                    onToggled: checked => CortetsuSettingsNetwork.setAutoconnect(root.selectedProfile.name, checked)
                                }
                            }
                        }
                    }

                    CortetsuSurface {
                        Layout.fillWidth: true
                        visible: !root.showingProfiles && root.selectedIsActive
                        implicitHeight: 92
                        baseColor: "transparent"
                        outlined: false
                        radiusValue: 0

                        GridLayout {
                            anchors.fill: parent
                            anchors.margins: CortetsuDesign.spacingStandard
                            columns: 3
                            columnSpacing: CortetsuDesign.spacingStandard
                            rowSpacing: CortetsuDesign.spacingCompact

                            CortetsuText { text: qsTr("Dirección IP"); textSize: CortetsuTypography.labelSmallPx; color: CortetsuDesign.colorOnSurfaceVariant }
                            CortetsuText { text: qsTr("Puerta de enlace"); textSize: CortetsuTypography.labelSmallPx; color: CortetsuDesign.colorOnSurfaceVariant }
                            CortetsuText { text: qsTr("DNS"); textSize: CortetsuTypography.labelSmallPx; color: CortetsuDesign.colorOnSurfaceVariant }
                            CortetsuText { Layout.fillWidth: true; text: root.detailsValue(root.activeDetails.address); textSize: CortetsuTypography.bodySmallPx; font.weight: Font.DemiBold; elide: Text.ElideRight }
                            CortetsuText { Layout.fillWidth: true; text: root.detailsValue(root.activeDetails.gateway); textSize: CortetsuTypography.bodySmallPx; font.weight: Font.DemiBold; elide: Text.ElideRight }
                            CortetsuText { Layout.fillWidth: true; text: root.detailsValue((root.activeDetails.dns ?? []).join(", ")); textSize: CortetsuTypography.bodySmallPx; font.weight: Font.DemiBold; elide: Text.ElideRight }
                        }
                    }

                    CortetsuSurface {
                        Layout.fillWidth: true
                        visible: !root.showingProfiles && root.selectedIsActive
                            && CortetsuSettingsNetwork.detailsState === "error"
                        implicitHeight: 44
                        baseColor: Qt.alpha(CortetsuDesign.colorWarning, 0.10)
                        outlineColor: Qt.alpha(CortetsuDesign.colorWarning, 0.34)
                        outlined: true
                        radiusValue: CortetsuDesign.radiusSmall
                        CortetsuText {
                            anchors.fill: parent
                            anchors.margins: CortetsuDesign.spacingStandard
                            text: CortetsuSettingsNetwork.detailsError
                            textSize: CortetsuTypography.labelSmallPx
                            color: CortetsuDesign.colorWarning
                            elide: Text.ElideRight
                        }
                    }

                    CortetsuSurface {
                        Layout.fillWidth: true
                        visible: !root.showingProfiles && !!root.selectedNetwork
                        implicitHeight: root.selectedIsActive ? 64 : 108
                        baseColor: Qt.alpha(CortetsuDesign.colorPrimaryContainer, 0.26)
                        outlineColor: "transparent"
                        outlined: false
                        radiusValue: CortetsuDesign.radiusSmall

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: CortetsuDesign.spacingStandard
                            spacing: CortetsuDesign.spacingCompact

                            RowLayout {
                                Layout.fillWidth: true
                                CortetsuIcon {
                                    text: "info"
                                    color: CortetsuDesign.colorPrimary
                                    iconSize: CortetsuTypography.iconMediumPx
                                }
                                CortetsuText {
                                    Layout.fillWidth: true
                                    text: root.selectedIsActive
                                        ? qsTr("Estás conectado a esta red.")
                                        : root.selectedNeedsPassword
                                            ? qsTr("Esta red requiere una contraseña para conectarse.")
                                            : qsTr("Esta red está abierta y puede conectarse directamente.")
                                    textSize: CortetsuTypography.bodySmallPx
                                    wrapMode: Text.WordWrap
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                visible: !root.selectedIsActive
                                CortetsuText {
                                    Layout.fillWidth: true
                                    text: root.selectedNeedsPassword
                                        ? qsTr("Introduce la contraseña y pulsa Conectar.")
                                        : qsTr("No se solicitará contraseña.")
                                    textSize: CortetsuTypography.labelSmallPx
                                    color: CortetsuDesign.colorOnSurfaceVariant
                                }
                                CortetsuButton {
                                    compact: true
                                    icon: "wifi"
                                    label: qsTr("Conectar")
                                    disabled: CortetsuSettingsNetwork.busy
                                        || (root.selectedNeedsPassword && root.password.length === 0)
                                    onClicked: root.connectSelected()
                                }
                            }
                        }
                    }

                    TextField {
                        Layout.fillWidth: true
                        visible: !root.showingProfiles && root.selectedNeedsPassword
                        placeholderText: qsTr("Contraseña de Wi‑Fi")
                        echoMode: root.passwordVisible ? TextInput.Normal : TextInput.Password
                        text: root.password
                        onTextChanged: root.password = text
                        color: CortetsuDesign.colorOnSurface
                        placeholderTextColor: CortetsuDesign.colorOnSurfaceVariant
                        leftPadding: CortetsuDesign.spacingStandard
                        rightPadding: CortetsuDesign.spacingStandard
                        implicitHeight: 42
                        background: CortetsuSurface {
                            radiusValue: CortetsuDesign.radiusSmall
                            baseColor: CortetsuDesign.colorSurfaceGlassStrong
                            outlined: true
                        }
                    }

                    CortetsuButton {
                        Layout.fillWidth: true
                        visible: !root.showingProfiles && root.selectedNeedsPassword
                        compact: true
                        label: root.passwordVisible ? qsTr("Ocultar contraseña") : qsTr("Mostrar contraseña")
                        icon: root.passwordVisible ? "visibility_off" : "visibility"
                        onClicked: root.passwordVisible = !root.passwordVisible
                    }

                    CortetsuSurface {
                        Layout.fillWidth: true
                        visible: !root.showingProfiles && root.selectedCanCopyPassword
                            && CortetsuSettingsNetwork.secretState === "error"
                        implicitHeight: 44
                        baseColor: Qt.alpha(CortetsuDesign.colorWarning, 0.10)
                        outlineColor: Qt.alpha(CortetsuDesign.colorWarning, 0.34)
                        outlined: true
                        radiusValue: CortetsuDesign.radiusSmall
                        CortetsuText {
                            anchors.fill: parent
                            anchors.margins: CortetsuDesign.spacingStandard
                            text: CortetsuSettingsNetwork.secretError
                            textSize: CortetsuTypography.labelSmallPx
                            color: CortetsuDesign.colorWarning
                            elide: Text.ElideRight
                        }
                    }

                    CortetsuSurface {
                        Layout.fillWidth: true
                        visible: root.showingProfiles && !!root.selectedProfile
                        implicitHeight: 210
                        baseColor: Qt.alpha(CortetsuDesign.colorSurfaceGlass, 0.68)
                        outlined: true
                        radiusValue: CortetsuDesign.radiusMedium

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: CortetsuDesign.spacingStandard
                            spacing: CortetsuDesign.spacingStandard

                            RowLayout {
                                Layout.fillWidth: true
                                CortetsuIcon {
                                    text: "bookmark"
                                    color: CortetsuDesign.colorPrimary
                                    iconSize: CortetsuTypography.iconMediumPx
                                }
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    CortetsuText { text: qsTr("Perfil de NetworkManager"); textSize: CortetsuTypography.labelSmallPx; color: CortetsuDesign.colorOnSurfaceVariant }
                                    CortetsuText { text: root.selectedProfile?.name ?? ""; textSize: CortetsuTypography.titleMediumPx; font.weight: Font.DemiBold; elide: Text.ElideRight }
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                CortetsuText {
                                    Layout.fillWidth: true
                                    text: root.selectedProfile?.autoconnect
                                        ? qsTr("Se conectará automáticamente cuando esté disponible")
                                        : qsTr("La conexión automática está desactivada")
                                    textSize: CortetsuTypography.bodySmallPx
                                    color: CortetsuDesign.colorOnSurfaceVariant
                                    wrapMode: Text.WordWrap
                                }
                                CortetsuToggle {
                                    checked: root.selectedProfile?.autoconnect ?? false
                                    disabled: CortetsuSettingsNetwork.busy
                                    onToggled: checked => CortetsuSettingsNetwork.setAutoconnect(root.selectedProfile?.name ?? "", checked)
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                CortetsuButton {
                                    Layout.fillWidth: true
                                    compact: true
                                    icon: "link_off"
                                    label: qsTr("Desconectar")
                                    disabled: CortetsuSettingsNetwork.busy
                                    onClicked: CortetsuSettingsNetwork.disconnect(root.selectedProfile?.name ?? "")
                                }
                                CortetsuButton {
                                    Layout.fillWidth: true
                                    compact: true
                                    icon: "delete_outline"
                                    label: qsTr("Olvidar perfil")
                                    danger: true
                                    disabled: CortetsuSettingsNetwork.busy
                                    onClicked: CortetsuSettingsNetwork.forget(root.selectedProfile?.name ?? "")
                                }
                            }
                        }
                    }

                    CortetsuStateMessage {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        visible: root.showingProfiles
                            ? !root.selectedProfile
                            : !root.selectedNetwork
                        kind: "empty"
                        title: root.showingProfiles
                            ? qsTr("Selecciona un perfil")
                            : qsTr("Selecciona una red")
                        detail: root.showingProfiles
                            ? qsTr("Elige un perfil para administrar su conexión automática")
                            : qsTr("Elige una red de la lista para consultar su señal, seguridad y acciones")
                    }

                    CortetsuText {
                        Layout.fillWidth: true
                        visible: CortetsuSettingsNetwork.lastMessage.length > 0
                        text: CortetsuSettingsNetwork.lastMessage
                        textSize: CortetsuTypography.bodySmallPx
                        color: CortetsuDesign.colorSuccess
                        wrapMode: Text.WordWrap
                    }
                }
            }
        }
    }
}

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../../../components"
import "../../../services"
import "../.."
import "../../CortetsuDesign.js" as CortetsuDesign
import "../../CortetsuTypography.js" as CortetsuTypography

Item {
    id: root

    required property var page

    height: implicitHeight
    implicitHeight: 520

    CortetsuSurface {
        id: detailBackdrop
        anchors.fill: detailColumn
        visible: !root.page.showingProfiles && !!root.page.selectedNetwork
        z: -1
        baseColor: Qt.alpha(CortetsuDesign.colorSurfaceGlass, 0.58)
        outlined: true
        radiusValue: CortetsuDesign.radiusMedium
    }

    ColumnLayout {
        id: detailColumn
        anchors.fill: parent
        anchors.margins: root.page.showingProfiles || !root.page.selectedNetwork ? 0 : CortetsuDesign.spacingStandard
        spacing: root.page.showingProfiles || !root.page.selectedNetwork ? CortetsuDesign.spacingStandard : 0

        RowLayout {
            id: detailHeader
            Layout.fillWidth: true
            visible: root.page.showingProfiles || !root.page.selectedNetwork

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                CortetsuText {
                    Layout.fillWidth: true
                    text: root.page.showingProfiles
                        ? (root.page.selectedProfile?.name ?? qsTr("Perfil guardado"))
                        : (root.page.selectedNetwork?.name ?? qsTr("Selecciona una red"))
                    textSize: CortetsuTypography.titleMediumPx
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }

                CortetsuText {
                    Layout.fillWidth: true
                    text: root.page.showingProfiles
                        ? qsTr("Preferencias de conexión guardadas")
                        : root.page.selectedNetwork
                            ? qsTr("%1 · %2")
                                .arg(root.page.securityLabel(root.page.selectedNetwork))
                                .arg(root.page.selectedNetwork.device.name || qsTr("dispositivo no disponible"))
                            : qsTr("Elige una red para ver sus propiedades")
                    textSize: CortetsuTypography.labelSmallPx
                    color: CortetsuDesign.colorOnSurfaceVariant
                    elide: Text.ElideRight
                }
            }

            CortetsuButton {
                visible: !root.page.showingProfiles && root.page.selectedCanCopyPassword
                compact: true
                icon: root.page.secretState === "ready" ? "check" : "key"
                label: root.page.secretState === "ready"
                    ? qsTr("Contraseña copiada")
                    : qsTr("Copiar contraseña")
                disabled: CortetsuSettingsNetwork.secretBusy
                onClicked: root.page.copySelectedPassword()
            }
        }

        SelectedNetworkCard {
            Layout.fillWidth: true
            page: root.page
        }

        CortetsuSurface {
            Layout.fillWidth: true
            visible: !root.page.showingProfiles && !!root.page.selectedNetwork
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
                    value: root.page.securityLabel(root.page.selectedNetwork)
                }

                DetailRow {
                    label: qsTr("Dispositivo")
                    value: root.page.detailsValue(root.page.selectedNetwork?.device?.name)
                }

                RowLayout {
                    Layout.fillWidth: true
                    CortetsuText {
                        Layout.fillWidth: true
                        text: root.page.selectedProfile?.autoconnect
                            ? qsTr("Conexión automática")
                            : qsTr("Conexión automática desactivada")
                        textSize: CortetsuTypography.bodySmallPx
                        color: CortetsuDesign.colorOnSurfaceVariant
                    }
                    CortetsuToggle {
                        checked: root.page.selectedProfile?.autoconnect ?? false
                        visible: !!root.page.selectedProfile
                        disabled: CortetsuSettingsNetwork.busy
                        onToggled: checked => root.page.wifi.setAutoconnect(root.page.selectedProfile.uuid, checked)
                    }
                }
            }
        }

        CortetsuSurface {
            Layout.fillWidth: true
            visible: !root.page.showingProfiles && root.page.selectedIsActive
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
                CortetsuText { Layout.fillWidth: true; text: root.page.detailsValue(root.page.activeDetails.address); textSize: CortetsuTypography.bodySmallPx; font.weight: Font.DemiBold; elide: Text.ElideRight }
                CortetsuText { Layout.fillWidth: true; text: root.page.detailsValue(root.page.activeDetails.gateway); textSize: CortetsuTypography.bodySmallPx; font.weight: Font.DemiBold; elide: Text.ElideRight }
                CortetsuText { Layout.fillWidth: true; text: root.page.detailsValue((root.page.activeDetails.dns ?? []).join(", ")); textSize: CortetsuTypography.bodySmallPx; font.weight: Font.DemiBold; elide: Text.ElideRight }
            }
        }

        CortetsuSurface {
            Layout.fillWidth: true
            visible: !root.page.showingProfiles && root.page.selectedIsActive
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
            visible: !root.page.showingProfiles && !!root.page.selectedNetwork
            implicitHeight: root.page.selectedIsActive ? 64 : 108
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
                        text: root.page.selectedIsActive
                            ? qsTr("Estás conectado a esta red.")
                            : root.page.selectedNeedsPassword
                                ? qsTr("Esta red requiere una contraseña para conectarse.")
                                : qsTr("Esta red está abierta y puede conectarse directamente.")
                        textSize: CortetsuTypography.bodySmallPx
                        wrapMode: Text.WordWrap
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    visible: !root.page.selectedIsActive
                    CortetsuText {
                        Layout.fillWidth: true
                        text: root.page.selectedNeedsPassword
                            ? qsTr("Introduce la contraseña y pulsa Conectar.")
                            : qsTr("No se solicitará contraseña.")
                        textSize: CortetsuTypography.labelSmallPx
                        color: CortetsuDesign.colorOnSurfaceVariant
                    }
                    CortetsuButton {
                        compact: true
                        icon: "wifi"
                        label: root.page.wifi.operationNetwork === root.page.selectedNetwork && root.page.wifi.operation.state === "connecting" ? qsTr("Conectando…") : qsTr("Conectar")
                        disabled: CortetsuSettingsNetwork.busy
                            || (root.page.selectedNeedsPassword && root.page.password.length === 0)
                        onClicked: root.page.connectSelected()
                    }
                }
            }
        }

        TextField {
            Layout.fillWidth: true
            visible: !root.page.showingProfiles && root.page.selectedNeedsPassword
            placeholderText: qsTr("Contraseña de Wi‑Fi")
            echoMode: root.page.passwordVisible ? TextInput.Normal : TextInput.Password
            text: root.page.password
            onTextChanged: root.page.password = text
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
            visible: !root.page.showingProfiles && root.page.selectedNeedsPassword
            compact: true
            label: root.page.passwordVisible ? qsTr("Ocultar contraseña") : qsTr("Mostrar contraseña")
            icon: root.page.passwordVisible ? "visibility_off" : "visibility"
            onClicked: root.page.passwordVisible = !root.page.passwordVisible
        }

        CortetsuSurface {
            Layout.fillWidth: true
            visible: !root.page.showingProfiles && root.page.selectedCanCopyPassword
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

        SavedProfileCard {
            Layout.fillWidth: true
            page: root.page
        }

        CortetsuStateMessage {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.page.showingProfiles
                ? !root.page.selectedProfile
                : !root.page.selectedNetwork
            kind: "empty"
            title: root.page.showingProfiles
                ? qsTr("Selecciona un perfil")
                : qsTr("Selecciona una red")
            detail: root.page.showingProfiles
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

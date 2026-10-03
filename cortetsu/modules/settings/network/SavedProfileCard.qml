pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import "../../../components"
import "../../../services"
import "../.."
import "../../../theme"
import "../../CortetsuTypography.js" as CortetsuTypography

CortetsuSurface {
    id: root

    required property var page

    visible: root.page.showingProfiles && !!root.page.selectedProfile
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
                CortetsuText { text: root.page.selectedProfile?.name ?? ""; textSize: CortetsuTypography.titleMediumPx; font.weight: Font.DemiBold; elide: Text.ElideRight }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            CortetsuText {
                Layout.fillWidth: true
                text: root.page.selectedProfile?.autoconnect
                    ? qsTr("Se conectará automáticamente cuando esté disponible")
                    : qsTr("La conexión automática está desactivada")
                textSize: CortetsuTypography.bodySmallPx
                color: CortetsuDesign.colorOnSurfaceVariant
                wrapMode: Text.WordWrap
            }
            CortetsuToggle {
                checked: root.page.selectedProfile?.autoconnect ?? false
                disabled: CortetsuSettingsNetwork.busy
                onToggled: checked => root.page.wifi.setAutoconnect(root.page.selectedProfile?.uuid ?? "", checked)
            }
        }

        RowLayout {
            Layout.fillWidth: true
            CortetsuButton {
                Layout.fillWidth: true
                compact: true
                icon: "link_off"
                label: qsTr("Desconectar")
                disabled: CortetsuSettingsNetwork.busy || root.page.selectedProfile?.uuid !== root.page.activeDetails.uuid
                onClicked: root.page.disconnectProfile()
            }
            CortetsuButton {
                Layout.fillWidth: true
                compact: true
                icon: "delete_outline"
                label: qsTr("Olvidar perfil")
                danger: true
                disabled: CortetsuSettingsNetwork.busy
                onClicked: root.page.wifi.forgetProfile(root.page.selectedProfile?.uuid ?? "")
            }
        }
    }
}

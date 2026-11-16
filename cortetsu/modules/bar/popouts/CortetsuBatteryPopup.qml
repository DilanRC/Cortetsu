pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell.Services.UPower
import "../../../components"
import "../../../services"
import "../../../theme"
import "../../../utils"
import "../../CortetsuTypography.js" as CortetsuTypography

// Energy at level 1: the charge and what it is doing, the time UPower
// estimates (only when it gives one), and the power profile. Everything
// else (inhibitors, suspend, automation) is in Settings → Energía.
CortetsuPopupSurface {
    id: root

    // The popout state, closed when Settings opens. Optional: the detached
    // window has none.
    property var popouts: null

    implicitWidth: 336
    implicitHeight: body.implicitHeight + CortetsuDesign.spacingComfortable * 2

    readonly property bool hasBattery: CortetsuPower.hasBattery
    readonly property int percentage: CortetsuPower.percent
    readonly property bool batteryCharging: CortetsuPower.charging
    readonly property bool critical: CortetsuPower.hasBattery && root.percentage <= 15 && CortetsuPower.onBattery
    readonly property string batteryStatus: !root.hasBattery
            ? (CortetsuPower.laptopBattery ? qsTr("Batería no disponible") : qsTr("Alimentación externa"))
        : root.batteryCharging && root.percentage >= 100
            ? qsTr("Carga completa")
        : root.batteryCharging
            ? qsTr("Cargando")
        : CortetsuPower.onBattery
            ? qsTr("Con batería")
            : qsTr("Conectado, sin cargar")
    // UPower reports 0 while it has no estimate yet; that is no estimate,
    // not "0 minutes".
    readonly property int estimateSeconds: root.batteryCharging && root.percentage < 100
        ? CortetsuPower.timeToFull
        : CortetsuPower.onBattery ? CortetsuPower.timeToEmpty : 0
    readonly property string estimate: root.estimateSeconds <= 0 ? ""
        : root.batteryCharging
            ? qsTr("%1 para la carga completa").arg(root.formatSeconds(root.estimateSeconds))
            : qsTr("%1 restantes").arg(root.formatSeconds(root.estimateSeconds))
    readonly property var profiles: [
        { profile: PowerProfile.PowerSaver, label: qsTr("Ahorro"), icon: "energy_savings_leaf" },
        { profile: PowerProfile.Balanced, label: qsTr("Equilibrado"), icon: "balance" }
    ].concat(PowerProfiles.hasPerformanceProfile
        ? [{ profile: PowerProfile.Performance, label: qsTr("Rendimiento"), icon: "rocket_launch" }]
        : [])
    readonly property int profileIndex: {
        for (let i = 0; i < profiles.length; ++i)
            if (profiles[i].profile === PowerProfiles.profile)
                return i;
        return -1;
    }

    function formatSeconds(seconds: int): string {
        const hours = Math.floor(seconds / 3600);
        const minutes = Math.floor(seconds / 60) % 60;
        return hours > 0
            ? qsTr("%1 h %2 min").arg(hours).arg(minutes)
            : qsTr("%1 min").arg(minutes);
    }

    ColumnLayout {
        id: body

        anchors.fill: parent
        anchors.margins: CortetsuDesign.spacingComfortable
        spacing: CortetsuDesign.spacingStandard

        CortetsuPopoutHeader {
            title: qsTr("Energía")
            detail: root.batteryStatus
            settingsPage: "power"
            popouts: root.popouts
        }

        // The charge is the protagonist: a figure, what it is doing, and the
        // bar. No card around it; a critical level turns the figure and the
        // bar vermilion.
        ColumnLayout {
            objectName: "batteryCharge"
            Layout.fillWidth: true
            visible: root.hasBattery
            spacing: CortetsuDesign.spacingCompact

            RowLayout {
                Layout.fillWidth: true
                spacing: CortetsuDesign.spacingStandard

                CortetsuIcon {
                    text: Icons.getBatteryIcon(CortetsuPower.value, root.batteryCharging)
                    iconSize: CortetsuTypography.iconLargePx
                    color: root.critical ? CortetsuDesign.colorVermillion : CortetsuDesign.colorIndicator
                }

                CortetsuText {
                    text: qsTr("%1%").arg(root.percentage)
                    textSize: CortetsuTypography.displaySmallPx
                    font.weight: Font.DemiBold
                    color: root.critical ? CortetsuDesign.colorVermillion : CortetsuDesign.colorOnSurface
                }

                CortetsuText {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignBottom
                    Layout.bottomMargin: 3
                    text: root.estimate
                    textSize: CortetsuTypography.labelMediumPx
                    color: CortetsuDesign.colorOnSurfaceVariant
                    horizontalAlignment: Text.AlignRight
                    elide: Text.ElideRight
                }
            }

            CortetsuProgressBar {
                Layout.fillWidth: true
                value: CortetsuPower.value
                barHeight: 5
                barRadius: 3
                trackColor: Qt.alpha(CortetsuDesign.colorSurfaceGlassStrong, 0.9)
                fillColor: root.critical
                    ? CortetsuDesign.colorVermillion
                    : CortetsuDesign.colorIndicator
                motionDuration: CortetsuDesign.motionStandardMs
            }
        }

        CortetsuText {
            Layout.fillWidth: true
            visible: !root.hasBattery
            text: CortetsuPower.laptopBattery
                ? qsTr("UPower no da una lectura de la batería ahora mismo.")
                : qsTr("Este equipo funciona con alimentación externa.")
            textSize: CortetsuTypography.bodySmallPx
            color: CortetsuDesign.colorOnSurfaceVariant
            wrapMode: Text.WordWrap
        }

        CortetsuDivider { Layout.fillWidth: true }

        CortetsuText {
            text: qsTr("Perfil de energía")
            textSize: CortetsuTypography.labelMediumPx
            font.weight: Font.DemiBold
            color: CortetsuDesign.colorOnSurfaceVariant
        }

        // The selection is what power-profiles-daemon reports back.
        CortetsuTabBar {
            objectName: "batteryProfiles"
            Layout.fillWidth: true
            accessibleName: qsTr("Perfil de energía")
            model: root.profiles
            currentIndex: root.profileIndex
            onSelected: index => PowerProfiles.profile = root.profiles[index].profile
        }

        CortetsuText {
            Layout.fillWidth: true
            visible: PowerProfiles.degradationReason !== PerformanceDegradationReason.None
            text: qsTr("Rendimiento limitado: %1").arg(
                PerformanceDegradationReason.toString(PowerProfiles.degradationReason))
            textSize: CortetsuTypography.labelSmallPx
            color: CortetsuDesign.colorVermillion
            wrapMode: Text.WordWrap
        }
    }
}

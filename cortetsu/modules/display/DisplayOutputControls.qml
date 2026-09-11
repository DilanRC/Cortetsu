pragma ComponentBehavior: Bound

import QtQuick
import ".."
import "../../components"
import "../CortetsuDesign.js" as CortetsuDesign
import "../CortetsuTypography.js" as CortetsuTypography

Item {
    id: root

    required property var editorItem
    required property var monitor

    readonly property var candidate: editorItem?.selectedCandidate ?? ({})
    readonly property bool tenBitProven: Number(monitor?.max_bpc ?? 0) >= 10 || String(monitor?.current_format ?? "").toUpperCase().includes("2101010")
    readonly property bool hdrProven: tenBitProven && monitor?.hdr_capable === true
    readonly property bool wideProven: tenBitProven && monitor?.wide_color_capable === true
    readonly property bool vrrProven: Boolean(monitor?.vrr_capable)
    readonly property int bitdepth: Number(candidate?.bitdepth ?? (String(monitor?.current_format ?? "").toUpperCase().includes("2101010") ? 10 : 8))
    readonly property string cm: String(candidate?.cm ?? "srgb")
    readonly property int vrr: Number(candidate?.vrr ?? (monitor?.vrr ? 1 : 0))

    function setColor(bitdepth, cm): void {
        editorItem.updateSelected("bitdepth", bitdepth)
        editorItem.updateSelected("cm", cm)
    }

    function toggleVrr(): void {
        if (!vrrProven) return
        editorItem.updateSelected("vrr", vrr > 0 ? 0 : 1)
    }

    Column {
        anchors.fill: parent
        anchors.margins: CortetsuDesign.spacingUnit
        spacing: CortetsuDesign.spacingCompact

        Row {
            width: parent.width
            height: 24

            CortetsuText {
                width: parent.width * 0.6
                text: qsTr("Color & VRR")
                color: CortetsuDesign.colorOnSurface
                textSize: CortetsuTypography.titleSmallPx
                font.weight: Font.DemiBold
            }
            CortetsuText {
                width: parent.width * 0.4
                text: `${root.monitor?.current_format ?? "—"}`
                color: CortetsuDesign.colorOutline
                textSize: CortetsuTypography.labelSmallPx
                horizontalAlignment: Text.AlignRight
                elide: Text.ElideLeft
            }
        }

        Row {
            width: parent.width
            height: 36
            spacing: CortetsuDesign.spacingUnit

            Repeater {
                model: [
                    { label: qsTr("SDR"), enabled: true, active: root.bitdepth === 8 && root.cm === "srgb", action: () => root.setColor(8, "srgb") },
                    { label: qsTr("10-bit"), enabled: root.tenBitProven, active: root.bitdepth === 10 && root.cm === "auto", action: () => root.setColor(10, "auto") },
                    { label: qsTr("Wide"), enabled: root.wideProven, active: root.bitdepth === 10 && root.cm === "wide", action: () => root.setColor(10, "wide") },
                    { label: qsTr("HDR"), enabled: root.hdrProven, active: root.bitdepth === 10 && (root.cm === "hdr" || root.cm === "hdredid"), action: () => root.setColor(10, "hdredid") }
                ]

                delegate: CortetsuButton {
                    required property var modelData
                    width: (parent.width - parent.spacing * 3) / 4
                    height: 36
                    label: modelData.label
                    compact: true
                    active: modelData.active
                    disabled: !modelData.enabled
                    focus: false
                    onClicked: modelData.action()
                }
            }
        }

        Item {
            width: parent.width
            height: 36
            enabled: root.vrrProven
            opacity: enabled ? 1 : 0.4

            CortetsuSurface {
                anchors.fill: parent
                radiusValue: CortetsuDesign.radiusMedium
                baseColor: root.vrr > 0 && root.vrrProven
                    ? Qt.alpha(CortetsuDesign.colorPrimaryContainer, 0.8)
                    : CortetsuDesign.colorSurfaceGlass
                outlined: false
            }
            Row {
                anchors.fill: parent
                anchors.leftMargin: CortetsuDesign.spacingStandard
                anchors.rightMargin: CortetsuDesign.spacingStandard
                spacing: CortetsuDesign.spacingCompact

                CortetsuText {
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.max(0, parent.width - vrrStatus.width - vrrToggle.width - parent.spacing * 2)
                    text: qsTr("Variable refresh")
                    color: CortetsuDesign.colorOnSurfaceVariant
                    textSize: CortetsuTypography.labelSmallPx
                }
                CortetsuText {
                    id: vrrStatus
                    anchors.verticalCenter: parent.verticalCenter
                    width: 64
                    text: !root.vrrProven ? qsTr("Unavailable") : root.vrr > 0 ? qsTr("On") : qsTr("Off")
                    color: root.vrr > 0 ? CortetsuDesign.colorOnSurface : CortetsuDesign.colorOutline
                    textSize: CortetsuTypography.labelSmallPx
                    horizontalAlignment: Text.AlignRight
                }
                CortetsuToggle {
                    id: vrrToggle
                    anchors.verticalCenter: parent.verticalCenter
                    checked: root.vrr > 0 && root.vrrProven
                    disabled: !root.vrrProven
                    onToggled: root.toggleVrr()
                }
            }
        }
    }
}

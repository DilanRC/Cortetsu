pragma ComponentBehavior: Bound

import QtQuick
import "../../../components"
import "../../../theme"
import "../../CortetsuTypography.js" as CortetsuTypography
import "../Format.js" as Format

// One detected GPU: load, then temperature, memory and draw.
NavBlock {
    id: root

    required property var gpu
    property string temperatureSeverity: ""

    // "Advanced Micro Devices, Inc. [AMD/ATI] HawkPoint2 (rev ca)" and
    // "NVIDIA GeForce RTX 3050" both repeat the vendor shown beside them.
    readonly property string model: {
        const name = String(root.gpu?.name ?? "");
        const vendor = String(root.gpu?.vendor ?? "");
        const bracket = name.lastIndexOf("] ");
        if (bracket >= 0)
            return name.slice(bracket + 2);
        return vendor && name.startsWith(`${vendor} `) ? name.slice(vendor.length + 1) : name;
    }
    readonly property string vram: Format.ratioGib(root.gpu?.vram_used_gb, root.gpu?.vram_total_gb)

    height: 84
    accessibleName: qsTr("GPU %1 al %2").arg(root.gpu?.vendor ?? "").arg(Format.percent(root.gpu?.usage))

    SummaryLabel {
        icon: "view_in_ar"
        text: root.gpu?.vendor ? qsTr("GPU %1").arg(root.gpu.vendor) : qsTr("GPU")
        detail: root.model
    }

    CortetsuText {
        id: usage
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        width: 64
        text: Format.percent(root.gpu?.usage)
        textSize: CortetsuTypography.titleLargePx
        font.weight: Font.DemiBold
    }

    CortetsuProgressBar {
        anchors.left: usage.right
        anchors.leftMargin: CortetsuDesign.spacingStandard
        anchors.right: facts.left
        anchors.rightMargin: CortetsuDesign.spacingComfortable
        anchors.verticalCenter: usage.verticalCenter
        value: Format.fraction(root.gpu?.usage)
        barHeight: 6
    }

    SummaryFacts {
        id: facts
        anchors.right: parent.right
        anchors.verticalCenter: usage.verticalCenter
        lead: Format.celsius(root.gpu?.temp_c)
        rest: Format.join([
            root.vram ? qsTr("VRAM %1").arg(root.vram) : "",
            Format.watts(root.gpu?.power_w)
        ])
        severity: root.temperatureSeverity
    }
}

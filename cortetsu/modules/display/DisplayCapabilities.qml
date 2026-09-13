pragma ComponentBehavior: Bound

import QtQuick
import ".."
import "../CortetsuDesign.js" as CortetsuDesign
import "../CortetsuTypography.js" as CortetsuTypography

Rectangle {
    id: root
    required property var monitor
    radius: CortetsuDesign.radiusLarge
    color: CortetsuDesign.colorSurfaceHigh
    border.width: 1
    border.color: CortetsuDesign.colorOutlineVariant

    function tri(value): string {
        if (value === true || Number(value) === 1) return qsTr("yes");
        if (value === false || Number(value) === 0) return qsTr("no");
        return qsTr("unknown");
    }

    Column {
        anchors.fill: parent; anchors.margins: 12; spacing: 6
        CortetsuText { text: qsTr("Capacidades de salida"); color: CortetsuDesign.colorOnSurface; textSize: CortetsuTypography.titleSmallPx }
        Row { width: parent.width
            CortetsuText { width: parent.width * 0.52; text: qsTr("VRR capable"); color: CortetsuDesign.colorOutline; textSize: CortetsuTypography.labelSmallPx }
            CortetsuText { width: parent.width * 0.48; text: root.tri(root.monitor?.vrr_capable); color: CortetsuDesign.colorPrimary; textSize: CortetsuTypography.labelSmallPx; horizontalAlignment: Text.AlignRight }
        }
        Row { width: parent.width
            CortetsuText { width: parent.width * 0.52; text: qsTr("HDR / wide color"); color: CortetsuDesign.colorOutline; textSize: CortetsuTypography.labelSmallPx }
            CortetsuText { width: parent.width * 0.48; text: `${root.tri(root.monitor?.hdr_capable)} / ${root.tri(root.monitor?.wide_color_capable)}`; color: CortetsuDesign.colorOnSurfaceVariant; textSize: CortetsuTypography.labelSmallPx; horizontalAlignment: Text.AlignRight }
        }
        Row { width: parent.width
            CortetsuText { width: parent.width * 0.52; text: qsTr("Max bpc / format"); color: CortetsuDesign.colorOutline; textSize: CortetsuTypography.labelSmallPx }
            CortetsuText { width: parent.width * 0.48; text: `${root.monitor?.max_bpc ?? "—"} / ${root.monitor?.current_format ?? "—"}`; color: CortetsuDesign.colorOnSurfaceVariant; textSize: CortetsuTypography.labelSmallPx; horizontalAlignment: Text.AlignRight; elide: Text.ElideLeft }
        }
        CortetsuText { width: parent.width; text: qsTr("Lo desconocido nunca se considera compatible. Los controles HDR/10 bits permanecen desactivados hasta confirmar la capacidad."); color: CortetsuDesign.colorOutline; textSize: CortetsuTypography.labelSmallPx; wrapMode: Text.WordWrap; maximumLineCount: 2; elide: Text.ElideRight }
    }
}

import QtQuick
import QtQuick.Layouts
import Quickshell.Wayland
import Quickshell.Widgets
import "../../../utils"
import ".."
import "../.."
import "../../../components"
import "../../CortetsuDesign.js" as CortetsuDesign

Item {
    id: root
    required property PopoutState popouts
    implicitWidth: 360
    implicitHeight: column.implicitHeight

    Column {
        id: column
        width: parent.width
        spacing: CortetsuDesign.spacingStandard

        CortetsuSurface {
            width: parent.width
            implicitHeight: header.implicitHeight + CortetsuDesign.spacingStandard * 2
            color: CortetsuDesign.colorSurfaceGlass
            radius: CortetsuDesign.radiusLarge

            RowLayout {
                id: header
                anchors.fill: parent
                anchors.margins: CortetsuDesign.spacingStandard
                spacing: CortetsuDesign.spacingStandard
                IconImage { Layout.preferredWidth: 32; Layout.preferredHeight: 32; source: Icons.getAppIcon(CortetsuHypr.activeToplevel?.lastIpcObject.class ?? "", "image-missing") }
                ColumnLayout {
                    Layout.fillWidth: true
                    CortetsuText { Layout.fillWidth: true; text: CortetsuHypr.activeToplevel?.title ?? qsTr("No active window"); elide: Text.ElideRight }
                    CortetsuText { Layout.fillWidth: true; text: CortetsuHypr.activeToplevel?.lastIpcObject.class ?? qsTr("Desktop"); color: CortetsuDesign.colorOnSurfaceVariant; elide: Text.ElideRight }
                }
                CortetsuButton { compact: true; icon: "open_in_full"; label: qsTr("Details"); onClicked: root.popouts.detachRequested("winfo") }
            }
        }

        ClippingWrapperRectangle {
            visible: CortetsuHypr.activeToplevel !== null
            width: parent.width
            height: 220
            color: CortetsuDesign.colorSurfaceGlass
            radius: CortetsuDesign.radiusLarge
            ScreencopyView { anchors.fill: parent; captureSource: CortetsuHypr.activeToplevel?.wayland ?? null; live: visible }
        }
    }
}

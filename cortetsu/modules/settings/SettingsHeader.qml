pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import "../../components"
import "../../theme"
import ".."
import "../CortetsuTypography.js" as CortetsuTypography
import "controls"

// Where the page is, as Windows 11 writes it: the path is the title,
// "Personalización › Temas", and the category in it leads back to the
// category. Below, how the page's domain stands or what is wrong with it.
ColumnLayout {
    id: root

    property var category: null
    property var subpage: null
    property string summary: ""
    property bool alerting: false
    property bool canGoBack: false
    signal backRequested()
    signal categoryRequested()

    spacing: 2

    RowLayout {
        Layout.fillWidth: true
        // Room on the right for the window's close button.
        Layout.rightMargin: 44
        spacing: CortetsuDesign.spacingCompact

        CortetsuButton {
            objectName: "settingsBack"
            visible: root.canGoBack
            compact: true
            icon: "arrow_back"
            label: ""
            tooltipText: qsTr("Atrás")
            Accessible.name: qsTr("Volver a la página anterior")
            onClicked: root.backRequested()
        }

        Item {
            objectName: "breadcrumbCategory"
            visible: root.subpage !== null
            implicitWidth: crumb.implicitWidth
            implicitHeight: crumb.implicitHeight
            // Qt will not drop the flag from the item that holds the focus.
            activeFocusOnTab: visible || activeFocus
            Accessible.role: Accessible.Link
            Accessible.name: qsTr("Volver a %1").arg(crumb.text)
            Accessible.onPressAction: root.categoryRequested()
            Keys.onReturnPressed: root.categoryRequested()
            Keys.onEnterPressed: root.categoryRequested()
            Keys.onSpacePressed: root.categoryRequested()

            CortetsuText {
                id: crumb
                text: root.category?.title ?? ""
                textSize: CortetsuTypography.displaySmallPx
                font.family: CortetsuDesign.fontHeading
                font.weight: CortetsuDesign.headingWeight
                color: crumbMouse.containsMouse || parent.activeFocus ? CortetsuDesign.colorOnSurface : CortetsuDesign.colorOnSurfaceVariant
                font.underline: parent.activeFocus
            }

            MouseArea {
                id: crumbMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.categoryRequested()
            }
        }

        CortetsuIcon {
            visible: root.subpage !== null
            text: "chevron_right"
            iconSize: CortetsuTypography.iconMediumPx
            color: CortetsuDesign.colorOnSurfaceVariant
        }

        CortetsuText {
            objectName: "pageTitle"
            Layout.fillWidth: true
            text: root.subpage?.title ?? root.category?.title ?? qsTr("Ajustes")
            textSize: CortetsuTypography.displaySmallPx
            font.family: CortetsuDesign.fontHeading
            font.weight: CortetsuDesign.headingWeight
            elide: Text.ElideRight
        }

        SaveIndicator {
            objectName: "saveIndicator"
            Layout.alignment: Qt.AlignVCenter
        }
    }

    CortetsuText {
        objectName: "pageSummary"
        Layout.fillWidth: true
        Layout.leftMargin: root.canGoBack ? 40 : 0
        visible: text.length > 0
        text: root.summary
        textSize: CortetsuTypography.bodyPx
        color: root.alerting ? CortetsuDesign.colorVermillion : CortetsuDesign.colorOnSurfaceVariant
        elide: Text.ElideRight
    }
}

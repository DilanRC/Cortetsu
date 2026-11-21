pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import "../../components"
import "../../theme"
import "../CortetsuTypography.js" as CortetsuTypography

// The expanded launcher's left column (03-launcher): the mark, then the
// views of the app list. Each row is a view that exists; Ajustes opens the
// real settings. Pointer rows only: the keyboard keeps Tab for the results
// and Ctrl+Left/Right for the views.
ColumnLayout {
    id: root

    required property string view
    signal viewRequested(string view)
    signal settingsRequested()

    spacing: CortetsuDesign.spacingUnit

    RowLayout {
        Layout.fillWidth: true
        Layout.bottomMargin: CortetsuDesign.spacingStandard
        spacing: CortetsuDesign.spacingStandard

        CortetsuEvolvingMark {
            phase: "Ascended"
            animated: false
            monochrome: true
            monochromeColor: CortetsuDesign.colorPrimary
            Layout.preferredWidth: 34
            Layout.preferredHeight: 34
        }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0
            CortetsuText {
                text: "Cortetsu"
                textSize: CortetsuTypography.titleSmallPx
                font.weight: Font.DemiBold
            }
            CortetsuText {
                text: qsTr("Launcher")
                textSize: CortetsuTypography.labelSmallPx
                color: CortetsuDesign.colorOnSurfaceVariant
            }
        }
    }

    Repeater {
        model: [
            { view: "home", icon: "home", title: qsTr("Inicio") },
            { view: "all", icon: "apps", title: qsTr("Aplicaciones") },
            { view: "favourites", icon: "star", title: qsTr("Favoritos") },
            { view: "recent", icon: "history", title: qsTr("Recientes") }
        ]
        delegate: CortetsuListRow {
            required property var modelData
            objectName: `launcherNav-${modelData.view}`
            Layout.fillWidth: true
            activeFocusOnTab: false
            icon: modelData.icon
            title: modelData.title
            selected: root.view === modelData.view
            onClicked: root.viewRequested(modelData.view)
        }
    }

    Item { Layout.fillHeight: true }

    CortetsuListRow {
        Layout.fillWidth: true
        activeFocusOnTab: false
        icon: "settings"
        title: qsTr("Configuración")
        onClicked: root.settingsRequested()
    }
}

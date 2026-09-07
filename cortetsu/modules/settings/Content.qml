pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Bluetooth
import qs.components
import qs.modules 1.0
import qs.services
import qs.modules.launcher.services
import "../CortetsuDesign.js" as CortetsuDesign
import "../CortetsuTypography.js" as CortetsuTypography

Item {
    id: root
    required property var screenState
    required property var controller

    function schemeColour(value, fallback) {
        return value ? `#${value}` : fallback;
    }

    CortetsuText {
        id: title
        anchors.top: parent.top
        anchors.left: parent.left
        text: qsTr("Cortetsu Settings")
        textSize: CortetsuTypography.titleLargePx
        font.weight: Font.DemiBold
    }

    CortetsuText {
        anchors.top: title.bottom
        anchors.topMargin: CortetsuDesign.spacingUnit
        anchors.left: title.left
        text: qsTr("A quiet control room for your desktop shell")
        textSize: CortetsuTypography.bodySmallPx
        color: CortetsuDesign.colorOnSurfaceVariant
    }

    CortetsuButton {
        anchors.right: parent.right
        anchors.top: parent.top
        compact: true
        icon: "close"
        label: qsTr("Close")
        onClicked: root.screenState.settings = false
    }

    RowLayout {
        anchors.top: title.bottom
        anchors.topMargin: CortetsuDesign.spacingSection
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: CortetsuDesign.spacingSection

        CortetsuSurface {
            Layout.fillHeight: true
            Layout.preferredWidth: 278
            radiusValue: CortetsuDesign.radiusLarge
            baseColor: Qt.alpha(CortetsuDesign.colorSurfaceGlass, 0.72)
            outlined: true

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: CortetsuDesign.spacingCompact
                spacing: CortetsuDesign.spacingUnit

                CortetsuText {
                    Layout.leftMargin: CortetsuDesign.spacingCompact
                    Layout.topMargin: CortetsuDesign.spacingCompact
                    text: qsTr("CONTROL SURFACES")
                    textSize: CortetsuTypography.labelSmallPx
                    color: CortetsuDesign.colorOnSurfaceVariant
                    font.weight: Font.DemiBold
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 38
                    radius: CortetsuDesign.radiusSmall
                    color: Qt.alpha(CortetsuDesign.colorSumi, 0.42)
                    border.width: 1
                    border.color: Qt.alpha(CortetsuDesign.colorOutlineVariant, 0.64)
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: CortetsuDesign.spacingCompact
                        anchors.rightMargin: CortetsuDesign.spacingCompact
                        CortetsuIcon { text: "search"; iconSize: CortetsuTypography.iconSmallPx; color: CortetsuDesign.colorOnSurfaceVariant }
                        Item {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 20
                            TextInput {
                                id: searchField
                                anchors.fill: parent
                                color: CortetsuDesign.colorOnSurface
                                font.pixelSize: CortetsuTypography.bodyPx
                                clip: true
                                onTextChanged: root.controller.search = text
                            }
                            Text {
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                visible: searchField.text.length === 0
                                text: qsTr("Search settings")
                                color: CortetsuDesign.colorOnSurfaceVariant
                                font.pixelSize: CortetsuTypography.bodyPx
                            }
                        }
                    }
                }

                ListView {
                    id: nav
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    spacing: 2
                    model: root.controller.filteredCategories
                    delegate: CortetsuListRow {
                        required property var modelData
                        width: nav.width
                        icon: modelData.icon
                        title: modelData.title
                        subtitle: ""
                        selected: root.controller.selectedId === modelData.id
                        onClicked: root.controller.select(modelData.id)
                    }
                }
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            Flickable {
                anchors.fill: parent
                clip: true
                contentWidth: width
                contentHeight: page.implicitHeight
                boundsBehavior: Flickable.StopAtBounds

                ColumnLayout {
                    id: page
                    width: parent.width
                    spacing: CortetsuDesign.spacingSection

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: CortetsuDesign.spacingStandard
                        Image { source: Quickshell.shellPath("assets/branding/cortetsu-mark.svg"); sourceSize.width: 32; sourceSize.height: 32; Layout.preferredWidth: 32; Layout.preferredHeight: 32; fillMode: Image.PreserveAspectFit }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2
                            CortetsuText { text: root.controller.categories.find(item => item.id === root.controller.selectedId)?.title ?? qsTr("Settings"); textSize: CortetsuTypography.titleLargePx; font.weight: Font.DemiBold }
                            CortetsuText { text: root.controller.categories.find(item => item.id === root.controller.selectedId)?.detail ?? ""; textSize: CortetsuTypography.bodySmallPx; color: CortetsuDesign.colorOnSurfaceVariant }
                        }
                    }

                    Item {
                        Layout.fillWidth: true
                        implicitHeight: appearance.implicitHeight
                        visible: root.controller.selectedId === "appearance"
                        ColumnLayout {
                            id: appearance
                            width: parent.width
                            spacing: CortetsuDesign.spacingSection
                            CortetsuSectionHeader { Layout.fillWidth: true; title: qsTr("Scheme gallery"); detail: qsTr("Preview and apply every installed family") }
                            Flow {
                                Layout.fillWidth: true
                                spacing: CortetsuDesign.spacingCompact
                                Repeater {
                                    model: Schemes.list
                                    delegate: CortetsuSurface {
                                        required property var modelData
                                        readonly property var schemeData: modelData
                                        width: 192
                                        height: 116
                                        radiusValue: CortetsuDesign.radiusMedium
                                        active: `${modelData.name} ${modelData.flavour}` === Schemes.currentScheme
                                        baseColor: active ? Qt.alpha(CortetsuDesign.colorPrimaryContainer, 0.76) : CortetsuDesign.colorSurfaceGlass
                                        outlined: true
                                        CortetsuText { anchors.left: parent.left; anchors.top: parent.top; anchors.margins: CortetsuDesign.spacingStandard; text: schemeData.name; textSize: CortetsuTypography.bodyPx; font.weight: Font.DemiBold }
                                        CortetsuText { anchors.left: parent.left; anchors.top: parent.top; anchors.topMargin: 34; anchors.leftMargin: CortetsuDesign.spacingStandard; text: schemeData.flavour; textSize: CortetsuTypography.labelSmallPx; color: CortetsuDesign.colorOnSurfaceVariant }
                                        Row { anchors.left: parent.left; anchors.bottom: parent.bottom; anchors.margins: CortetsuDesign.spacingStandard; spacing: 4; Repeater { model: ["primary", "secondary", "tertiary", "surface", "error"]; delegate: Rectangle { required property string modelData; width: 22; height: 22; radius: 5; color: root.schemeColour(schemeData.colours[modelData], CortetsuDesign.colorOutlineVariant) } } }
                                        MouseArea { anchors.fill: parent; hoverEnabled: true; onClicked: Quickshell.execDetached(["cortetsu-scheme", "set", "-n", schemeData.name, schemeData.flavour]) }
                                    }
                                }
                            }
                            CortetsuSectionHeader { Layout.fillWidth: true; title: qsTr("Shell appearance"); detail: qsTr("These controls persist through CortetsuConfig") }
                            RowLayout {
                                Layout.fillWidth: true
                                CortetsuText { Layout.fillWidth: true; text: qsTr("Smart scheme"); textSize: CortetsuTypography.bodyPx }
                                CortetsuToggle { checked: CortetsuConfig.smartScheme; onToggled: { CortetsuConfig.smartScheme = checked; CortetsuConfig.save(); } }
                            }
                            RowLayout {
                                Layout.fillWidth: true
                                CortetsuText { Layout.fillWidth: true; text: qsTr("Wallpaper integration"); textSize: CortetsuTypography.bodyPx }
                                CortetsuToggle { checked: CortetsuConfig.wallpaperEnabled; onToggled: { CortetsuConfig.wallpaperEnabled = checked; CortetsuConfig.save(); } }
                            }
                            RowLayout {
                                Layout.fillWidth: true
                                CortetsuText { Layout.fillWidth: true; text: qsTr("Transparent surfaces"); textSize: CortetsuTypography.bodyPx }
                                CortetsuToggle { checked: CortetsuConfig.transparencyEnabled; onToggled: CortetsuConfig.transparencyEnabled = checked }
                            }
                        }
                    }

                    Item { Layout.fillWidth: true; implicitHeight: generic.implicitHeight; visible: root.controller.selectedId !== "appearance" && root.controller.selectedId !== "about" }
                    ColumnLayout {
                        id: generic
                        width: page.width
                        visible: root.controller.selectedId !== "appearance" && root.controller.selectedId !== "about"
                        spacing: CortetsuDesign.spacingSection
                        CortetsuSectionHeader { Layout.fillWidth: true; title: qsTr("Live shell preferences"); detail: qsTr("Only connected Cortetsu backends are exposed here") }
                        CortetsuSurface {
                            Layout.fillWidth: true
                            implicitHeight: 92
                            radiusValue: CortetsuDesign.radiusMedium
                            baseColor: Qt.alpha(CortetsuDesign.colorSurfaceGlass, 0.7)
                            outlined: true
                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: CortetsuDesign.spacingStandard
                                CortetsuIcon { text: "info"; iconSize: 22; color: CortetsuDesign.colorWarning }
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    CortetsuText { text: qsTr("This section is connected in stages"); textSize: CortetsuTypography.bodyPx; font.weight: Font.DemiBold }
                                    CortetsuText { Layout.fillWidth: true; text: qsTr("The page is ready for the real backend. Controls are not shown until they can read and write state safely."); textSize: CortetsuTypography.bodySmallPx; color: CortetsuDesign.colorOnSurfaceVariant; wrapMode: Text.WordWrap }
                                }
                            }
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            visible: root.controller.selectedId === "bottomhub"
                            CortetsuText { Layout.fillWidth: true; text: qsTr("Status popouts"); textSize: CortetsuTypography.bodyPx }
                            CortetsuToggle { checked: CortetsuConfig.bar.popouts.statusIcons; onToggled: CortetsuConfig.bar.popouts.statusIcons = checked }
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            visible: root.controller.selectedId === "launcher"
                            CortetsuText { Layout.fillWidth: true; text: qsTr("Fuzzy application search"); textSize: CortetsuTypography.bodyPx }
                            CortetsuToggle { checked: CortetsuConfig.useFuzzyApps; onToggled: { CortetsuConfig.useFuzzyApps = checked; CortetsuConfig.save(); } }
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            visible: root.controller.selectedId === "notifications"
                            CortetsuText { Layout.fillWidth: true; text: qsTr("Open notifications expanded"); textSize: CortetsuTypography.bodyPx }
                            CortetsuToggle { checked: CortetsuConfig.notificationOpenExpanded; onToggled: CortetsuConfig.notificationOpenExpanded = checked }
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            visible: root.controller.selectedId === "power"
                            CortetsuText { Layout.fillWidth: true; text: qsTr("Prevent idle while audio plays"); textSize: CortetsuTypography.bodyPx }
                            CortetsuToggle { checked: CortetsuConfig.idleInhibitWhenAudio; onToggled: { CortetsuConfig.idleInhibitWhenAudio = checked; CortetsuConfig.save(); } }
                        }
                    }

                    ColumnLayout {
                        width: page.width
                        visible: root.controller.selectedId === "about"
                        spacing: CortetsuDesign.spacingStandard
                        CortetsuSectionHeader { Layout.fillWidth: true; title: qsTr("About Cortetsu"); detail: qsTr("First-party desktop shell") }
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: CortetsuDesign.spacingSpacious
                            Image { source: Quickshell.shellPath("assets/branding/cortetsu-mark.svg"); sourceSize.width: 72; sourceSize.height: 72; Layout.preferredWidth: 72; Layout.preferredHeight: 72; fillMode: Image.PreserveAspectFit }
                            ColumnLayout {
                                Layout.fillWidth: true
                                CortetsuText { text: qsTr("Cortetsu"); textSize: 28; font.weight: Font.DemiBold }
                                CortetsuText { text: qsTr("Precision shell for focused work"); textSize: CortetsuTypography.bodyPx; color: CortetsuDesign.colorOnSurfaceVariant }
                                CortetsuText { text: qsTr("Generation: Ascension · first-party surfaces"); textSize: CortetsuTypography.labelMediumPx; color: CortetsuDesign.colorOnSurfaceVariant }
                            }
                        }
                    }
                }
            }
        }
    }

    Shortcut { sequence: "Escape"; onActivated: root.screenState.settings = false }
}

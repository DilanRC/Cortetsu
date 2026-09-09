pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import "../../components"
import ".."
import "../launcher/services"
import "../CortetsuSearchBar.qml"
import "../CortetsuDesign.js" as CortetsuDesign
import "../CortetsuTypography.js" as CortetsuTypography

Item {
    id: root

    required property var screenState
    required property var screen
    required property var controller

    readonly property var selectedCategory: controller.categories.find(item => item.id === controller.selectedId) ?? null

    function schemeColour(value, fallback) {
        const text = String(value ?? "").trim();
        if (!text)
            return fallback;
        return text.startsWith("#") ? text : `#${text}`;
    }

    Component.onCompleted: Schemes.reload()

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

                CortetsuSearchBar {
                    id: searchField
                    Layout.fillWidth: true
                    compact: true
                    placeholderText: qsTr("Search settings")
                    onTextChanged: root.controller.search = text
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
                id: scroller
                anchors.fill: parent
                clip: true
                contentWidth: width
                contentHeight: Math.max(height, page.implicitHeight)
                boundsBehavior: Flickable.StopAtBounds

                ScrollBar.vertical: ScrollBar {
                    policy: scroller.contentHeight > scroller.height
                        ? ScrollBar.AsNeeded
                        : ScrollBar.AlwaysOff
                }

                ColumnLayout {
                    id: page
                    width: scroller.width
                    spacing: CortetsuDesign.spacingSection

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: CortetsuDesign.spacingStandard

                        Image {
                            source: Quickshell.shellPath("assets/branding/cortetsu-mark.svg")
                            sourceSize.width: 32
                            sourceSize.height: 32
                            Layout.preferredWidth: 32
                            Layout.preferredHeight: 32
                            fillMode: Image.PreserveAspectFit
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2

                            CortetsuText {
                                text: root.selectedCategory?.title ?? qsTr("Settings")
                                textSize: CortetsuTypography.titleLargePx
                                font.weight: Font.DemiBold
                            }

                            CortetsuText {
                                text: root.selectedCategory?.detail ?? ""
                                textSize: CortetsuTypography.bodySmallPx
                                color: CortetsuDesign.colorOnSurfaceVariant
                            }
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        visible: root.controller.selectedId === "appearance"
                        spacing: CortetsuDesign.spacingSection

                        CortetsuSectionHeader {
                            Layout.fillWidth: true
                            title: qsTr("Scheme gallery")
                            detail: Schemes.error.length > 0
                                ? Schemes.error
                                : Schemes.loading
                                    ? qsTr("Reading installed scheme families…")
                                    : qsTr("%1 installed · %2 active").arg(Schemes.catalogCount).arg(Schemes.currentScheme || qsTr("none"))
                        }

                        CortetsuSurface {
                            Layout.fillWidth: true
                            implicitHeight: 54
                            visible: Schemes.list.length === 0
                            radiusValue: CortetsuDesign.radiusMedium
                            baseColor: Qt.alpha(CortetsuDesign.colorSurfaceGlass, 0.70)
                            outlined: true

                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: CortetsuDesign.spacingStandard
                                spacing: CortetsuDesign.spacingStandard

                                CortetsuIcon {
                                    text: Schemes.loading ? "sync" : "palette"
                                    iconSize: CortetsuTypography.iconSmallPx
                                    color: Schemes.error.length > 0
                                        ? CortetsuDesign.colorWarning
                                        : CortetsuDesign.colorOnSurfaceVariant
                                }

                                CortetsuText {
                                    Layout.fillWidth: true
                                    text: Schemes.loading
                                        ? qsTr("Loading scheme catalog")
                                        : Schemes.error.length > 0
                                            ? Schemes.error
                                            : qsTr("No schemes are currently available")
                                    textSize: CortetsuTypography.bodySmallPx
                                    color: CortetsuDesign.colorOnSurfaceVariant
                                    wrapMode: Text.WordWrap
                                }

                                CortetsuButton {
                                    compact: true
                                    icon: "refresh"
                                    label: ""
                                    tooltipText: qsTr("Reload schemes")
                                    disabled: Schemes.loading
                                    onClicked: Schemes.reload()
                                }
                            }
                        }

                        Flow {
                            id: schemeGrid
                            Layout.fillWidth: true
                            Layout.preferredHeight: childrenRect.height
                            spacing: CortetsuDesign.spacingCompact

                            Repeater {
                                model: Schemes.list

                                delegate: CortetsuSurface {
                                    id: schemeCard
                                    required property var modelData

                                    readonly property var schemeData: modelData
                                    readonly property bool selectedScheme: `${modelData.name} ${modelData.flavour}` === Schemes.currentScheme

                                    width: 192
                                    height: 116
                                    radiusValue: CortetsuDesign.radiusMedium
                                    active: selectedScheme
                                    activeColor: Qt.alpha(CortetsuDesign.colorPrimaryContainer, 0.74)
                                    baseColor: selectedScheme
                                        ? Qt.alpha(CortetsuDesign.colorPrimaryContainer, 0.74)
                                        : CortetsuDesign.colorSurfaceGlass
                                    hoverColor: selectedScheme
                                        ? Qt.alpha(CortetsuDesign.colorPrimaryContainer, 0.84)
                                        : CortetsuDesign.colorSurfaceHigh
                                    outlined: true
                                    outlineColor: selectedScheme
                                        ? Qt.alpha(CortetsuDesign.colorPrimary, 0.58)
                                        : Qt.alpha(CortetsuDesign.colorOutlineVariant, 0.52)

                                    CortetsuText {
                                        anchors.left: parent.left
                                        anchors.top: parent.top
                                        anchors.margins: CortetsuDesign.spacingStandard
                                        width: parent.width - CortetsuDesign.spacingStandard * 2
                                        text: schemeCard.schemeData.name
                                        textSize: CortetsuTypography.bodyPx
                                        font.weight: Font.DemiBold
                                        elide: Text.ElideRight
                                    }

                                    CortetsuText {
                                        anchors.left: parent.left
                                        anchors.top: parent.top
                                        anchors.topMargin: 34
                                        anchors.leftMargin: CortetsuDesign.spacingStandard
                                        width: parent.width - CortetsuDesign.spacingStandard * 2
                                        text: schemeCard.selectedScheme
                                            ? qsTr("%1 · active").arg(schemeCard.schemeData.flavour)
                                            : schemeCard.schemeData.flavour
                                        textSize: CortetsuTypography.labelSmallPx
                                        color: schemeCard.selectedScheme
                                            ? CortetsuDesign.colorPrimary
                                            : CortetsuDesign.colorOnSurfaceVariant
                                        elide: Text.ElideRight
                                    }

                                    Row {
                                        anchors.left: parent.left
                                        anchors.bottom: parent.bottom
                                        anchors.margins: CortetsuDesign.spacingStandard
                                        spacing: 4

                                        Repeater {
                                            model: ["primary", "secondary", "tertiary", "surface", "error"]
                                            delegate: Rectangle {
                                                required property string modelData
                                                width: 22
                                                height: 22
                                                radius: 5
                                                color: root.schemeColour(schemeCard.schemeData.colours[modelData], CortetsuDesign.colorOutlineVariant)
                                                border.width: 1
                                                border.color: Qt.alpha(CortetsuDesign.colorWashi, 0.16)
                                            }
                                        }
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        enabled: !Schemes.applying
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onEntered: schemeCard.hovered = true
                                        onExited: {
                                            schemeCard.hovered = false;
                                            schemeCard.pressed = false;
                                        }
                                        onPressedChanged: schemeCard.pressed = pressed
                                        onClicked: Schemes.apply(schemeCard.schemeData.name, schemeCard.schemeData.flavour)
                                    }
                                }
                            }
                        }

                        CortetsuSectionHeader {
                            Layout.fillWidth: true
                            title: qsTr("Shell appearance")
                            detail: qsTr("Persistent Cortetsu presentation preferences")
                        }

                        SystemPage {
                            Layout.fillWidth: true
                            section: "appearance-internal"
                            screen: root.screen
                            screenState: root.screenState
                            visible: false
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            CortetsuText {
                                Layout.fillWidth: true
                                text: qsTr("Smart scheme")
                                textSize: CortetsuTypography.bodyPx
                            }
                            CortetsuToggle {
                                checked: CortetsuConfig.smartScheme
                                onToggled: {
                                    CortetsuConfig.smartScheme = checked;
                                    CortetsuConfig.save();
                                }
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            CortetsuText {
                                Layout.fillWidth: true
                                text: qsTr("Wallpaper integration")
                                textSize: CortetsuTypography.bodyPx
                            }
                            CortetsuToggle {
                                checked: CortetsuConfig.wallpaperEnabled
                                onToggled: {
                                    CortetsuConfig.wallpaperEnabled = checked;
                                    CortetsuConfig.save();
                                }
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            CortetsuText {
                                Layout.fillWidth: true
                                text: qsTr("Transparent surfaces")
                                textSize: CortetsuTypography.bodyPx
                            }
                            CortetsuToggle {
                                checked: CortetsuConfig.transparencyEnabled
                                onToggled: CortetsuConfig.transparencyEnabled = checked
                            }
                        }
                    }

                    SystemPage {
                        Layout.fillWidth: true
                        visible: root.controller.selectedId !== "appearance" && root.controller.selectedId !== "about"
                        section: root.controller.selectedId
                        screen: root.screen
                        screenState: root.screenState
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        visible: root.controller.selectedId === "about"
                        spacing: CortetsuDesign.spacingStandard

                        CortetsuSectionHeader {
                            Layout.fillWidth: true
                            title: qsTr("About Cortetsu")
                            detail: qsTr("First-party desktop shell")
                        }

                        CortetsuSurface {
                            Layout.fillWidth: true
                            implicitHeight: 128
                            radiusValue: CortetsuDesign.radiusLarge
                            baseColor: Qt.alpha(CortetsuDesign.colorSurfaceGlass, 0.72)
                            outlined: true

                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: CortetsuDesign.spacingSpacious
                                spacing: CortetsuDesign.spacingSpacious

                                Image {
                                    source: Quickshell.shellPath("assets/branding/cortetsu-mark.svg")
                                    sourceSize.width: 72
                                    sourceSize.height: 72
                                    Layout.preferredWidth: 72
                                    Layout.preferredHeight: 72
                                    fillMode: Image.PreserveAspectFit
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: CortetsuDesign.spacingUnit
                                    CortetsuText {
                                        text: qsTr("Cortetsu")
                                        textSize: 28
                                        font.weight: Font.DemiBold
                                    }
                                    CortetsuText {
                                        text: qsTr("Precision shell for focused work")
                                        textSize: CortetsuTypography.bodyPx
                                        color: CortetsuDesign.colorOnSurfaceVariant
                                    }
                                    CortetsuText {
                                        text: qsTr("Generation: Ascension · first-party surfaces")
                                        textSize: CortetsuTypography.labelMediumPx
                                        color: CortetsuDesign.colorOnSurfaceVariant
                                    }
                                }
                            }
                        }
                    }

                    Item {
                        Layout.fillWidth: true
                        Layout.preferredHeight: CortetsuDesign.spacingSpacious
                    }
                }
            }
        }
    }

    Shortcut {
        sequence: "Escape"
        onActivated: root.screenState.settings = false
    }
}

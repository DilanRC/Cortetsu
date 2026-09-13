pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Widgets
import "../../../components"
import "../../CortetsuDesign.js" as CortetsuDesign

CortetsuPopupSurface {
    id: root

    required property PopoutState popouts
    required property QsMenuHandle trayItem
    property real menuContentHeight: 72
    property real menuContentWidth: 184
    readonly property real menuMinWidth: 152
    // Keep long DBus labels readable without letting one Steam title stretch
    // the popup. The width cap leaves the useful name prefix visible and
    // lets Text.ElideRight handle the rest.
    readonly property real menuMaxWidth: 152
    // StackView does not propagate the implicit size of a dynamically-created
    // Column. Keep the popup measurable so the menu is not rendered as an
    // empty square while its DBus entries are loading.
    implicitWidth: menuContentWidth + CortetsuDesign.spacingStandard * 2
    implicitHeight: menuContentHeight + CortetsuDesign.spacingStandard * 2

    StackView {
        id: stack
        anchors.fill: parent
        anchors.margins: CortetsuDesign.spacingStandard
        initialItem: menuComponent.createObject(null, { handle: root.trayItem })

        pushEnter: Transition {
            ParallelAnimation {
                NumberAnimation {
                    property: "x"
                    from: CortetsuDesign.spacingComfortable
                    to: 0
                    duration: CortetsuDesign.motionStandardMs
                    easing.type: Easing.OutCubic
                }
                NumberAnimation {
                    property: "opacity"
                    from: 0
                    to: 1
                    duration: CortetsuDesign.motionFastMs
                    easing.type: Easing.OutCubic
                }
            }
        }

        pushExit: Transition {
            ParallelAnimation {
                NumberAnimation {
                    property: "x"
                    from: 0
                    to: -CortetsuDesign.spacingCompact
                    duration: CortetsuDesign.motionStandardMs
                    easing.type: Easing.OutCubic
                }
                NumberAnimation {
                    property: "opacity"
                    from: 1
                    to: 0.72
                    duration: CortetsuDesign.motionFastMs
                }
            }
        }

        popEnter: Transition {
            ParallelAnimation {
                NumberAnimation {
                    property: "x"
                    from: -CortetsuDesign.spacingCompact
                    to: 0
                    duration: CortetsuDesign.motionStandardMs
                    easing.type: Easing.OutCubic
                }
                NumberAnimation {
                    property: "opacity"
                    from: 0.72
                    to: 1
                    duration: CortetsuDesign.motionFastMs
                }
            }
        }

        popExit: Transition {
            ParallelAnimation {
                NumberAnimation {
                    property: "x"
                    from: 0
                    to: CortetsuDesign.spacingComfortable
                    duration: CortetsuDesign.motionFastMs
                    easing.type: Easing.InCubic
                }
                NumberAnimation {
                    property: "opacity"
                    from: 1
                    to: 0
                    duration: CortetsuDesign.motionFastMs
                }
            }
        }
    }

    function activateEntry(entry): void {
        if (!entry)
            return;
        if (!entry.enabled)
            return;
        if (entry.hasChildren)
            stack.push(menuComponent.createObject(null, { handle: entry, subMenu: true }));
        else {
            entry.triggered();
            root.popouts.hasCurrent = false;
        }
    }

    Component {
        id: menuComponent

        Column {
            id: menu
            required property QsMenuHandle handle
            property bool subMenu: false
            padding: CortetsuDesign.spacingCompact
            spacing: CortetsuDesign.spacingUnit
            readonly property real fittedWidth: {
                let widest = 0;
                for (let i = 0; i < entries.count; i++) {
                    const item = entries.itemAt(i);
                    if (item)
                        widest = Math.max(widest, item.naturalWidth);
                }
                return Math.max(root.menuMinWidth, Math.min(root.menuMaxWidth, widest + padding * 2));
            }
            width: fittedWidth
            height: Math.max(
                48,
                childrenRect.height + padding * 2
                    + (subMenu ? CortetsuDesign.spacingStandard + 48 : 0)
            )

            onHeightChanged: root.menuContentHeight = height
            onWidthChanged: root.menuContentWidth = width

            QsMenuOpener {
                id: opener
                menu: menu.handle
            }

            Repeater {
                id: entries
                // QsMenuOpener.children is a live ObjectModel. Keeping it as
                // the Repeater model preserves asynchronous DBus menu updates.
                model: opener.children

                CortetsuSurface {
                    required property QsMenuEntry modelData
                    readonly property real naturalWidth: modelData.isSeparator
                        ? 0
                        : labelMetrics.width
                            + (menuIcon.visible ? menuIcon.width + row.spacing : 0)
                            + (submenuIcon.visible ? submenuIcon.width + row.spacing : 0)
                            + CortetsuDesign.spacingCompact * 2
                    focus: modelData.enabled && index === 0
                    activeFocusOnTab: modelData.enabled
                    width: Math.max(0, menu.width - menu.padding * 2)
                    implicitHeight: modelData.isSeparator
                        ? 1
                        : row.implicitHeight + CortetsuDesign.spacingStandard
                    baseColor: modelData.isSeparator ? CortetsuDesign.colorOutlineVariant : "transparent"
                    disabled: !modelData.enabled
                    focused: activeFocus && !modelData.isSeparator
                    hovered: stateLayer.containsMouse
                    pressed: stateLayer.pressed
                    radiusValue: modelData.isSeparator ? 0 : CortetsuDesign.radiusSmall
                    hoverColor: Qt.alpha(CortetsuDesign.colorSurfaceGlassStrong, 0.9)
                    outlineColor: activeFocus
                        ? Qt.alpha(CortetsuDesign.colorWashi, 0.82)
                        : Qt.alpha(CortetsuDesign.colorOutlineVariant, 0.12)

                    Row {
                        id: row
                        anchors.fill: parent
                        anchors.margins: CortetsuDesign.spacingCompact
                        spacing: CortetsuDesign.spacingStandard

                        IconImage {
                            id: menuIcon
                            visible: modelData.icon !== ""
                            implicitSize: label.implicitHeight
                            source: modelData.icon
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        CortetsuText {
                            id: label
                            width: Math.max(0, row.width
                                - (menuIcon.visible ? menuIcon.width + row.spacing : 0)
                                - (submenuIcon.visible ? submenuIcon.width + row.spacing : 0))
                            text: modelData.text
                            color: modelData.enabled
                                ? CortetsuDesign.colorOnSurface
                                : CortetsuDesign.colorOutline
                            elide: Text.ElideRight
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        CortetsuIcon {
                            id: submenuIcon
                            visible: modelData.hasChildren
                            text: "chevron_right"
                            color: activeFocus
                                ? CortetsuDesign.colorWashi
                                : CortetsuDesign.colorOnSurfaceVariant
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    TextMetrics {
                        id: labelMetrics
                        text: modelData.text
                        font: label.font
                    }

                    CortetsuStateLayer {
                        id: stateLayer
                        anchors.fill: parent
                        radius: parent.radiusValue
                        disabled: !modelData.enabled
                        onPressed: parent.forceActiveFocus()
                        onClicked: root.activateEntry(modelData)
                    }

                    Keys.onPressed: event => {
                        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
                            root.activateEntry(modelData);
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Right && modelData.hasChildren) {
                            root.activateEntry(modelData);
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Left && menu.subMenu) {
                            stack.pop();
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Escape) {
                            root.popouts.hasCurrent = false;
                            event.accepted = true;
                        }
                    }
                }
            }

            CortetsuButton {
                visible: menu.subMenu
                compact: true
                icon: "chevron_left"
                label: qsTr("Atrás")
                onClicked: stack.pop()
                Keys.onEscapePressed: root.popouts.hasCurrent = false
            }
        }
    }
}

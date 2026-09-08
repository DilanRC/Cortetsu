pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.components
import qs.components.containers
import qs.modules
import qs.modules.session as Session
import "CortetsuDesign.js" as CortetsuDesign
import "CortetsuTypography.js" as CortetsuTypography

Scope {
    Variants {
        model: CortetsuScreens.screens

        StyledWindow {
            id: window
            required property ShellScreen modelData
            readonly property var screenState: CortetsuShellState.forActive()
            readonly property bool open: screenState?.session ?? false

            screen: modelData
            name: "session"
            visible: true
            WlrLayershell.exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
            mask: open ? null : emptyRegion
            anchors.top: true
            anchors.bottom: true
            anchors.left: true
            anchors.right: true

            Region { id: emptyRegion }

            Rectangle { anchors.fill: parent; visible: window.open; color: Qt.alpha(CortetsuDesign.colorScrim, 0.54) }

            CortetsuSurface {
                id: panel
                anchors.centerIn: parent
                visible: window.open
                width: Math.min(440, parent.width - 48)
                implicitHeight: contentColumn.implicitHeight + CortetsuDesign.spacingComfortable * 2
                baseColor: Qt.alpha(CortetsuDesign.colorSurface, 0.98)
                outlined: true
                radiusValue: CortetsuDesign.radiusSurface
                outlineColor: Qt.alpha(CortetsuDesign.colorOutlineVariant, 0.72)

                Column {
                    id: contentColumn
                    anchors.fill: parent
                    anchors.margins: CortetsuDesign.spacingComfortable
                    spacing: CortetsuDesign.spacingStandard

                    Row {
                        spacing: CortetsuDesign.spacingStandard
                        CortetsuSurface {
                            width: 44; height: 44
                            radiusValue: CortetsuDesign.radiusMedium
                            baseColor: Qt.alpha(CortetsuDesign.colorPrimary, 0.14)
                            CortetsuIcon { anchors.centerIn: parent; text: "power_settings_new"; color: CortetsuDesign.colorPrimary; iconSize: CortetsuTypography.iconLargePx }
                        }
                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 2
                            CortetsuText { text: qsTr("Session"); textSize: CortetsuTypography.titleMediumPx; color: CortetsuDesign.colorOnSurface }
                            CortetsuText { text: qsTr("Power and session actions"); textSize: CortetsuTypography.bodySmallPx; color: CortetsuDesign.colorOnSurfaceVariant }
                        }
                    }

                    Rectangle { width: parent.width; height: 1; color: CortetsuDesign.colorOutlineVariant; opacity: 0.45 }

                    Session.Content { width: parent.width; screenState: window.screenState }
                }
            }

            Shortcut { sequence: "Escape"; enabled: window.open; onActivated: window.screenState.session = false }
        }
    }
}

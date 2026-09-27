pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Services.SystemTray
import qs.components
import qs.modules
import qs.services
import "../SystemTrayIdentity.js" as TrayIdentity

CortetsuSurface {
    id: root

    readonly property alias layout: layout
    readonly property alias items: items
    readonly property alias expandIcon: expandIcon

    readonly property int padding: CortetsuConfig.bar.tray.background ? CortetsuTokens.padding.medium : CortetsuTokens.padding.extraSmall
    readonly property int spacing: CortetsuConfig.bar.tray.background ? CortetsuTokens.spacing.medium : CortetsuTokens.spacing.extraSmall

    property bool expanded

    readonly property real nonAnimHeight: {
        if (!CortetsuConfig.bar.tray.compact)
            return layout.implicitHeight + padding * 2;
        const pad = (CortetsuConfig.bar.tray.background ? CortetsuTokens.padding.extraSmall : 0) + padding;
        if (expanded)
            return expandIcon.implicitHeight + layout.implicitHeight + spacing + pad;
        return Math.max(CortetsuConfig.bar.tray.background ? width : 0, expandIcon.implicitHeight + pad);
    }

    clip: true
    visible: height > 0

    implicitWidth: CortetsuTokens.sizes.bar.innerWidth
    implicitHeight: nonAnimHeight

    color: Qt.alpha(CortetsuColours.tPalette.m3surfaceContainer, (CortetsuConfig.bar.tray.background && items.count > 0) ? CortetsuColours.tPalette.m3surfaceContainer.a : 0)
    radius: CortetsuTokens.rounding.full

    Column {
        id: layout

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: root.padding
        spacing: CortetsuTokens.spacing.small

        opacity: root.expanded || !CortetsuConfig.bar.tray.compact ? 1 : 0

        add: Transition {
            Anim {
                properties: "scale"
                from: 0
                to: 1
                easing: CortetsuTokens.anim.standardDecel
            }
        }

        move: Transition {
            Anim {
                properties: "scale"
                to: 1
                easing: CortetsuTokens.anim.standardDecel
            }
            Anim {
                properties: "x,y"
            }
        }

        Repeater {
            id: items

            model: ScriptModel {
                values: TrayIdentity.entries(SystemTray.items.values.filter(i => i.status !== Status.Passive && !CortetsuConfig.hiddenTrayIcons.includes(i.id)))
                objectProp: "key"
            }

            TrayItem {}
        }

        Behavior on opacity {
            Anim {
                type: Anim.DefaultEffects
            }
        }
    }

    Loader {
        id: expandIcon

        asynchronous: true

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom

        active: CortetsuConfig.bar.tray.compact && items.count > 0

        sourceComponent: Item {
            implicitWidth: expandIconInner.implicitWidth
            implicitHeight: expandIconInner.implicitHeight - CortetsuTokens.padding.small

            CortetsuIcon {
                id: expandIconInner

                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: CortetsuConfig.bar.tray.background ? CortetsuTokens.padding.extraSmall : -CortetsuTokens.padding.small
                text: "expand_less"
                color: CortetsuColours.palette.m3onSurfaceVariant
                fontStyle: CortetsuTokens.font.icon.medium
                rotation: root.expanded ? 180 : 0

                Behavior on rotation {
                    Anim {}
                }

                Behavior on anchors.bottomMargin {
                    Anim {}
                }
            }
        }
    }

    Behavior on implicitHeight {
        Anim {}
    }
}

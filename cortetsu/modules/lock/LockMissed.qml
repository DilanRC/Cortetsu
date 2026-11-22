pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import QtQuick.Layouts
import "../../components"
import ".."
import "../../services"
import "../../theme"
import "../CortetsuTypography.js" as CortetsuTypography

// Who has written while the screen is locked: an app and how many, never
// what they said. Ajustes can hide even that (lockHideNotifs).
Item {
    id: root

    readonly property var apps: {
        void Notifs.revision;
        const counts = {};
        const icons = {};
        const order = [];
        for (const item of Notifs.notClosed()) {
            const name = item?.appName || qsTr("Aplicación");
            if (!(name in counts)) {
                counts[name] = 0;
                order.push(name);
                icons[name] = root.iconFor(item);
            }
            counts[name]++;
        }
        return order.slice(0, 4).map(name => ({ name, count: counts[name], icon: icons[name] }));
    }

    // The app's own icon: the one it sent, else its desktop entry's; ""
    // when neither exists (the pill then shows the initial).
    function iconFor(item: var): string {
        const sent = String(item?.appIcon ?? "");
        if (sent.startsWith("/") || sent.startsWith("file://"))
            return sent.startsWith("/") ? `file://${sent}` : sent;
        for (const name of [sent, item?.hints?.["desktop-entry"], item?.appName]) {
            const value = String(name ?? "").trim();
            if (!value)
                continue;
            const entry = DesktopEntries.heuristicLookup(value);
            const found = Quickshell.iconPath(entry?.icon || value, true);
            if (found)
                return found;
        }
        return "";
    }

    visible: !CortetsuConfig.lockHideNotifs && apps.length > 0
    implicitWidth: 320
    implicitHeight: column.implicitHeight

    // One pill per app (Nebula's notification wing): its initial in a disc,
    // its name and how many. Never what they said.
    Column {
        id: column
        width: parent.width
        spacing: 14

        Repeater {
            model: root.apps
            delegate: Item {
                id: pill
                required property var modelData
                width: column.width
                height: 72

                Rectangle {
                    anchors.fill: parent
                    radius: height / 2
                    color: Qt.alpha(CortetsuDesign.colorPrimaryContainer, 0.88)
                    border.width: 1
                    border.color: Qt.alpha(CortetsuDesign.colorPrimary, 0.3)
                }
                Rectangle {
                    id: disc
                    x: 12
                    anchors.verticalCenter: parent.verticalCenter
                    width: 48
                    height: 48
                    radius: 24
                    color: Qt.alpha(CortetsuDesign.colorWashi, 0.9)
                    Image {
                        id: appIcon
                        anchors.centerIn: parent
                        width: 32
                        height: 32
                        sourceSize.width: 64
                        sourceSize.height: 64
                        asynchronous: true
                        source: pill.modelData.icon
                        visible: status === Image.Ready
                    }
                    CortetsuText {
                        anchors.centerIn: parent
                        visible: !appIcon.visible
                        text: pill.modelData.name.slice(0, 1).toLocaleUpperCase()
                        textSize: CortetsuTypography.titleSmallPx
                        font.weight: Font.DemiBold
                        color: CortetsuDesign.colorPrimaryContainer
                    }
                }
                Column {
                    anchors.left: disc.right
                    anchors.leftMargin: 14
                    anchors.right: parent.right
                    anchors.rightMargin: 20
                    anchors.verticalCenter: parent.verticalCenter
                    CortetsuText {
                        width: parent.width
                        text: pill.modelData.name
                        textSize: CortetsuTypography.bodyPx
                        font.weight: Font.DemiBold
                        color: CortetsuDesign.colorOnPrimaryContainer
                        elide: Text.ElideRight
                    }
                    CortetsuText {
                        width: parent.width
                        text: pill.modelData.count === 1 ? qsTr("1 aviso") : qsTr("%1 avisos").arg(pill.modelData.count)
                        textSize: CortetsuTypography.labelSmallPx
                        color: Qt.alpha(CortetsuDesign.colorOnPrimaryContainer, 0.75)
                    }
                }
            }
        }
    }
}

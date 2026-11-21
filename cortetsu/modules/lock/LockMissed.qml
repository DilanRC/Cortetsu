pragma ComponentBehavior: Bound

import QtQuick
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
        const order = [];
        for (const item of Notifs.notClosed()) {
            const name = item?.appName || qsTr("Aplicación");
            if (!(name in counts)) {
                counts[name] = 0;
                order.push(name);
            }
            counts[name]++;
        }
        return order.slice(0, 4).map(name => ({ name, count: counts[name] }));
    }

    visible: !CortetsuConfig.lockHideNotifs && apps.length > 0
    implicitWidth: 300
    implicitHeight: column.implicitHeight + CortetsuDesign.spacingStandard * 2

    Rectangle {
        anchors.fill: parent
        radius: CortetsuDesign.radiusLarge
        color: Qt.alpha(CortetsuDesign.colorSurfaceGlass, 0.62)
        border.width: 1
        border.color: Qt.alpha(CortetsuDesign.colorWashi, 0.10)
    }

    ColumnLayout {
        id: column
        anchors.fill: parent
        anchors.margins: CortetsuDesign.spacingStandard
        spacing: CortetsuDesign.spacingCompact

        RowLayout {
            spacing: CortetsuDesign.spacingCompact
            CortetsuIcon {
                text: "notifications"
                iconSize: CortetsuTypography.iconSmallPx
                color: CortetsuDesign.colorPrimary
            }
            CortetsuText {
                text: qsTr("Avisos")
                textSize: CortetsuTypography.bodyPx
                font.weight: Font.DemiBold
            }
        }

        Repeater {
            model: root.apps
            delegate: RowLayout {
                required property var modelData
                Layout.fillWidth: true
                spacing: CortetsuDesign.spacingCompact
                CortetsuText {
                    Layout.fillWidth: true
                    text: modelData.name
                    textSize: CortetsuTypography.bodySmallPx
                    elide: Text.ElideRight
                }
                Rectangle {
                    implicitWidth: Math.max(implicitHeight, countText.implicitWidth + 12)
                    implicitHeight: 22
                    radius: height / 2
                    color: Qt.alpha(CortetsuDesign.colorIndicator, 0.24)
                    CortetsuText {
                        id: countText
                        anchors.centerIn: parent
                        text: String(modelData.count)
                        textSize: CortetsuTypography.labelSmallPx
                        font.weight: Font.DemiBold
                    }
                }
            }
        }
    }
}

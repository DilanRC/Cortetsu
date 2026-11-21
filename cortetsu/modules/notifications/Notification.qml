import QtQuick
import QtQuick.Layouts
import "../"
import "../../components"
import "../../services"
import "../../utils"
import "../../theme"
import "../CortetsuTypography.js" as CortetsuTypography
import "NotificationKind.js" as NotificationKind

CortetsuSurface {
    id: root

    required property var modelData
    required property var props
    required property bool expanded
    required property var screenState
    property bool hovered: false
    readonly property bool hasModelData: modelData !== null && modelData !== undefined
    readonly property bool closed: !hasModelData || modelData.closed
    readonly property int urgency: hasModelData ? modelData.urgency : 0
    readonly property string summary: hasModelData ? modelData.summary : ""
    readonly property string appName: hasModelData ? modelData.appName : ""
    readonly property string timeLabel: hasModelData ? modelData.timeStr : ""
    readonly property string imagePath: hasModelData ? modelData.image : ""
    readonly property string bodyText: hasModelData ? modelData.body : ""
    readonly property var notificationActions: hasModelData && modelData.actions ? modelData.actions : []
    readonly property bool urgent: urgency >= 2
    // The card's shape follows what the sender declares (NotificationKind.js).
    readonly property var players: Players.list
    readonly property string kind: hasModelData
        ? NotificationKind.classify(modelData, players.map(player => player.desktopEntry)) : "general"
    readonly property int progress: hasModelData ? NotificationKind.progress(modelData) : -1
    // The player that sent a media notification, for its real controls.
    readonly property var player: kind === "media"
        ? players.find(player => String(player.desktopEntry).toLowerCase()
            === String(modelData?.hints?.["desktop-entry"] ?? "").toLowerCase()) ?? null
        : null
    // Private mode shows who sent it, never what it says: no body, no
    // picture and no title, here, in the history and on the lock screen.
    readonly property bool hidden: CortetsuConfig.notificationPrivate
    readonly property string shownSummary: hidden ? qsTr("Contenido oculto") : summary
    readonly property bool showPicture: !hidden && imagePath.length > 0
    readonly property real nonAnimHeight: contentLayout.implicitHeight + CortetsuDesign.spacingComfortable * 2

    function syncInteraction(): void {
        if (root.hasModelData)
            root.modelData.interactionActive = root.hovered || root.activeFocus;
    }

    implicitHeight: nonAnimHeight
    radiusValue: CortetsuDesign.radiusMedium
    outlined: true
    focus: false
    activeFocusOnTab: true
    focused: root.activeFocus
    // Opaque: a popup sits over windows, and their text showed through.
    baseColor: root.urgent
        ? Qt.tint(CortetsuDesign.colorSurfaceHigh, Qt.alpha(CortetsuDesign.colorVermillion, 0.10))
        : root.hovered
            ? Qt.tint(CortetsuDesign.colorSurfaceHigh, Qt.alpha(CortetsuDesign.colorOnSurface, 0.04))
            : CortetsuDesign.colorSurfaceHigh
    outlineColor: root.activeFocus
        ? Qt.alpha(CortetsuDesign.colorWashi, 0.82)
        : root.urgent
            ? Qt.alpha(CortetsuDesign.colorVermillion, 0.48)
            : Qt.alpha(CortetsuDesign.colorOutlineVariant, root.hovered ? 0.40 : 0.22)
    opacity: root.closed ? 0 : 1
    scale: root.closed ? 0.985 : 1

    Behavior on opacity {
        NumberAnimation {
            duration: CortetsuDesign.motionFastMs
            easing.type: Easing.BezierSpline
            easing.bezierCurve: CortetsuDesign.easeOut
        }
    }

    Behavior on scale {
        NumberAnimation {
            duration: CortetsuDesign.motionFastMs
            easing.type: Easing.BezierSpline
            easing.bezierCurve: CortetsuDesign.easeOut
        }
    }

    onHoveredChanged: root.syncInteraction()
    onActiveFocusChanged: root.syncInteraction()

    Component.onCompleted: {
        if (root.hasModelData) {
            root.modelData.lock(root);
            root.syncInteraction();
        }
    }
    Component.onDestruction: {
        if (root.hasModelData) {
            root.modelData.interactionActive = false;
            root.modelData.unlock(root);
        }
    }

    // The card and its action row are one hover island. A child action can
    // receive the pointer while the card remains hovered, keeping Dismiss and
    // notification actions visible during the handoff.
    HoverHandler {
        id: notificationHover
        onHoveredChanged: root.hovered = hovered
    }

    Rectangle {
        anchors.left: parent.left
        anchors.leftMargin: 3
        anchors.verticalCenter: parent.verticalCenter
        visible: root.urgent
        width: 2
        height: Math.max(28, parent.height - CortetsuDesign.spacingComfortable * 2)
        color: CortetsuDesign.colorVermillion
        opacity: 0.88
    }

    MouseArea {
        id: cardMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onPressed: root.forceActiveFocus()
        onClicked: root.expanded = !root.expanded
    }

    Keys.onEnterPressed: root.expanded = !root.expanded
    Keys.onReturnPressed: root.expanded = !root.expanded
    Keys.onSpacePressed: root.expanded = !root.expanded
    Keys.onEscapePressed: if (root.hasModelData) root.modelData.close()

    ColumnLayout {
        id: contentLayout
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: CortetsuDesign.spacingComfortable
        spacing: CortetsuDesign.spacingCompact

        RowLayout {
            Layout.fillWidth: true
            spacing: CortetsuDesign.spacingStandard

            // Same badge as the hub popouts; colorIndicator keeps 3:1 (H-37).
            CortetsuIconBadge {
                Layout.preferredWidth: implicitWidth
                Layout.preferredHeight: implicitHeight
                icon: NotificationKind.icon(root.kind, root.modelData)
                iconSize: CortetsuTypography.iconMediumPx
                tone: root.urgent ? CortetsuDesign.colorVermillion : CortetsuDesign.colorIndicator
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1

                CortetsuText {
                    Layout.fillWidth: true
                    text: root.shownSummary
                    textSize: CortetsuTypography.bodyLargePx
                    wrapMode: Text.Wrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                    font.weight: Font.DemiBold
                    color: CortetsuDesign.colorOnSurface
                }

                CortetsuText {
                    Layout.fillWidth: true
                    visible: text.length > 0
                    text: root.appName || qsTr("Notificación del sistema")
                    textSize: CortetsuTypography.labelSmallPx
                    color: CortetsuDesign.colorOnSurfaceVariant
                    elide: Text.ElideRight
                }
            }

            CortetsuText {
                Layout.alignment: Qt.AlignTop
                text: root.timeLabel
                textSize: CortetsuTypography.labelSmallPx
                color: CortetsuDesign.colorOnSurfaceVariant
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: CortetsuDesign.spacingStandard

            // A message's picture is its sender: a round avatar. A capture
            // or a cover is the content: a larger tile.
            Rectangle {
                objectName: "notificationPicture"
                visible: root.showPicture && image.status !== Image.Error
                readonly property int side: root.kind === "image" ? 96 : root.kind === "message" ? 40 : 58
                Layout.preferredWidth: visible ? side : 0
                Layout.preferredHeight: visible ? (root.kind === "image" ? 64 : side) : 0
                Layout.alignment: Qt.AlignTop
                radius: root.kind === "message" ? width / 2 : CortetsuDesign.radiusSmall
                color: CortetsuDesign.colorSurfaceGlass
                clip: true

                Image {
                    id: image
                    anchors.fill: parent
                    source: root.showPicture ? root.imagePath : ""
                    sourceSize.width: 192
                    sourceSize.height: 192
                    fillMode: Image.PreserveAspectCrop
                    smooth: true
                    mipmap: true
                }
            }

            CortetsuText {
                id: body
                Layout.fillWidth: true
                text: root.hidden ? "" : root.bodyText
                textSize: CortetsuTypography.bodyPx
                maximumLineCount: root.expanded ? 8 : root.kind === "message" ? 3 : 2
                elide: Text.ElideRight
                wrapMode: Text.WordWrap
                visible: text.length > 0
                color: CortetsuDesign.colorOnSurfaceVariant
            }
        }

        // Progress the sender reports, updated in place when it replaces
        // this notification with a new value.
        RowLayout {
            objectName: "notificationProgress"
            Layout.fillWidth: true
            visible: root.kind === "progress" && root.progress >= 0
            spacing: CortetsuDesign.spacingStandard
            CortetsuProgressBar {
                Layout.fillWidth: true
                value: Math.max(0, root.progress) / 100
            }
            CortetsuText {
                text: `${Math.max(0, root.progress)} %`
                textSize: CortetsuTypography.labelSmallPx
                font.features: { "tnum": 1 }
                color: CortetsuDesign.colorOnSurfaceVariant
            }
        }

        // A player's notification: its controls, through MPRIS, only for
        // what the player says it can do.
        RowLayout {
            objectName: "notificationMediaControls"
            Layout.fillWidth: true
            visible: !!root.player
            spacing: CortetsuDesign.spacingCompact
            CortetsuButton {
                compact: true
                icon: "skip_previous"
                tooltipText: qsTr("Anterior")
                disabled: !root.player?.canGoPrevious
                onClicked: root.player?.previous()
            }
            CortetsuButton {
                compact: true
                active: true
                icon: root.player?.isPlaying ? "pause" : "play_arrow"
                tooltipText: root.player?.isPlaying ? qsTr("Pausar") : qsTr("Reproducir")
                disabled: !root.player?.canTogglePlaying
                onClicked: root.player?.togglePlaying()
            }
            CortetsuButton {
                compact: true
                icon: "skip_next"
                tooltipText: qsTr("Siguiente")
                disabled: !root.player?.canGoNext
                onClicked: root.player?.next()
            }
        }

        RowLayout {
            Layout.fillWidth: true
            visible: root.notificationActions.length > 0 || root.hovered || root.expanded || root.activeFocus
            spacing: CortetsuDesign.spacingCompact

            Repeater {
                model: root.notificationActions
                delegate: CortetsuButton {
                    required property int index
                    Layout.fillWidth: false
                    compact: true
                    label: root.notificationActions[index] ? root.notificationActions[index].text : ""
                    onClicked: if (root.notificationActions[index]) root.notificationActions[index].invoke()
                }
            }

            Item { Layout.fillWidth: true }

            CortetsuButton {
                compact: true
                label: qsTr("Descartar")
                danger: root.urgent
                onClicked: if (root.hasModelData) root.modelData.close()
            }
        }
    }
}

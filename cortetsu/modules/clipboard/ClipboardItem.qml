pragma ComponentBehavior: Bound

import QtQuick
import ".."
import "../../components"
import "../../theme"
import "../CortetsuTypography.js" as CortetsuTypography

Rectangle {
    id: root

    required property var entry
    required property bool selected

    signal activateRequested()
    signal deleteRequested()
    signal pinRequested()
    signal selectRequested()

    Accessible.role: Accessible.ListItem
    Accessible.name: root.isImage ? qsTr("Imagen %1").arg(root.fileName) : root.trimmedValue.slice(0, 120)
    Accessible.description: root.pinned ? qsTr("Fijado · %1").arg(root.recordedDisplay) : root.recordedDisplay
    Accessible.selected: root.selected

    readonly property string value:
        String(entry?.value ?? "")

    readonly property string filePath:
        String(entry?.filePath ?? "")

    readonly property bool isImage:
        filePath.length > 0 && filePath !== "null"

    readonly property bool pinned:
        Boolean(entry?.pinned ?? false)

    readonly property string recorded:
        String(entry?.recorded ?? "")

    readonly property string trimmedValue:
        value.trim()

    readonly property bool isUrl:
        !isImage &&
        /^(https?:\/\/|www\.)/i.test(trimmedValue)

    readonly property bool looksCommand:
        !isImage &&
        !isUrl &&
        /^(sudo\s|cd\s|git\s|qs\s|pkill\s|kill\s|pacman\s|yay\s|paru\s|hyprctl\s|systemctl\s|journalctl\s|docker\s|lazydocker\s|cat\s|grep\s|ls\s|cp\s|mv\s|rm\s|curl\s|wget\s|npm\s|pnpm\s|bun\s|go\s|python\s|fish\s|bash\s|sh\s)/i
            .test(trimmedValue)

    readonly property string iconName:
        isImage
            ? "image"
            : isUrl
                ? "language"
                : looksCommand
                    ? "terminal"
                    : "content_paste"

    readonly property string fileName: {
        if (!isImage)
            return "";

        const parts = filePath.split("/");
        return parts.length > 0
            ? parts[parts.length - 1]
            : filePath;
    }

    readonly property string recordedDisplay: {
        let text = recorded.replace("T", " ");
        text = text.replace(/\.\d+.*$/, "");

        const parts = text.split(" ");

        if (parts.length >= 2)
            return `${parts[0]} · ${parts[1]}`;

        return text;
    }

    readonly property color surfaceColour: CortetsuDesign.colorSurface
    readonly property color hoverColour: CortetsuDesign.colorSurfaceHigh
    readonly property color textPrimary: CortetsuDesign.colorOnSurface
    readonly property color textMuted: CortetsuDesign.colorOnSurfaceVariant
    readonly property color accent: CortetsuDesign.colorPrimary

    readonly property color accentSoft:
        Qt.alpha(accent, selected ? 0.18 : 0.11)

    implicitHeight:
        isImage ? 106 : 92

    radius: CortetsuDesign.radiusLarge

    color:
        selected
            ? Qt.alpha(accent, 0.14)
            : cardMouse.containsMouse
                ? hoverColour
                : surfaceColour

    border.width:
        selected ? 2 : 1

    border.color:
        selected
            ? Qt.alpha(accent, 0.82)
            : cardMouse.containsMouse
                ? Qt.alpha(accent, 0.24)
                : Qt.alpha(textMuted, 0.12)

    scale:
        cardMouse.containsMouse ? 1.006 : 1

    Behavior on color {
        ColorAnimation {
            duration: CortetsuDesign.motionFastMs
            easing.type: Easing.BezierSpline
            easing.bezierCurve: CortetsuDesign.easeOut
        }
    }

    Behavior on border.color {
        ColorAnimation {
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

    Rectangle {
        visible: root.selected
        anchors.left: parent.left
        anchors.leftMargin: 5
        anchors.verticalCenter: parent.verticalCenter
        width: 3
        height: parent.height - 24
        radius: width / 2
        color: root.accent
    }

    MouseArea {
        id: cardMouse

        z: 0
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons:
            Qt.LeftButton |
            Qt.MiddleButton |
            Qt.RightButton
        cursorShape: Qt.PointingHandCursor

        onPressed:
            root.selectRequested()

        onDoubleClicked: event => {
            if (event.button === Qt.LeftButton)
                root.activateRequested();
        }

        onClicked: event => {
            if (event.button === Qt.MiddleButton)
                root.deleteRequested();
            else if (event.button === Qt.RightButton)
                root.pinRequested();
            else
                root.selectRequested();
        }
    }

    Row {
        z: 1

        anchors.fill: parent
        anchors.leftMargin: 16
        anchors.rightMargin: 12
        anchors.topMargin: 10
        anchors.bottomMargin: 10
        spacing: 14

        Rectangle {
            id: previewBox

            anchors.verticalCenter: parent.verticalCenter

            width:
                root.isImage ? 84 : 54

            height:
                root.isImage ? 84 : 54

            radius:
                root.isImage
                    ? CortetsuDesign.radiusMedium
                    : CortetsuDesign.radiusLarge

            color: root.accentSoft

            border.width: 1
            border.color:
                Qt.alpha(root.accent, root.selected ? 0.38 : 0.18)

            clip: true

            Image {
                visible: root.isImage
                anchors.fill: parent
                anchors.margins: 4
                source:
                    root.isImage
                        ? `file://${root.filePath}`
                        : ""
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: false
                smooth: true
                mipmap: true
            }

            CortetsuIcon {
                visible: !root.isImage
                anchors.centerIn: parent
                text: root.iconName
                color: root.accent
                iconSize: CortetsuTypography.iconLargePx
            }
        }

        Column {
            id: copyColumn

            width:
                Math.max(
                    90,
                    parent.width -
                    previewBox.width -
                    actions.width -
                    42
                )

            anchors.verticalCenter: parent.verticalCenter
            spacing: 7

            CortetsuText {
                width: parent.width

                text:
                    root.isImage
                        ? qsTr("Imagen")
                        : root.value

                maximumLineCount:
                    root.isImage ? 1 : 2

                elide: Text.ElideRight
                wrapMode: Text.Wrap

                color:
                    root.isUrl || root.looksCommand
                        ? root.accent
                        : root.textPrimary

                textSize: CortetsuTypography.bodyPx
            }

            CortetsuText {
                width: parent.width

                text:
                    root.isImage
                        ? `${root.recordedDisplay} · ${root.fileName}`
                        : root.recordedDisplay

                maximumLineCount: 1
                elide: Text.ElideRight
                color: root.textMuted
                textSize: CortetsuTypography.labelSmallPx
            }
        }

        // Mouse shortcuts for what the keys already do on the selected item
        // (P pins, Enter copies, Supr deletes), so they stay out of the Tab
        // order instead of adding three stops per row.
        Row {
            id: actions

            anchors.verticalCenter: parent.verticalCenter
            spacing: 4

            CortetsuButton {
                compact: true
                activeFocusOnTab: false
                icon: root.pinned ? "keep" : "keep_off"
                label: ""
                active: root.pinned
                tooltipText: root.pinned ? qsTr("Soltar (P)") : qsTr("Fijar (P)")
                onClicked: {
                    root.selectRequested();
                    root.pinRequested();
                }
            }

            CortetsuButton {
                compact: true
                activeFocusOnTab: false
                icon: "content_copy"
                label: ""
                tooltipText: qsTr("Copiar (Intro)")
                onClicked: {
                    root.selectRequested();
                    root.activateRequested();
                }
            }

            CortetsuButton {
                compact: true
                activeFocusOnTab: false
                icon: "delete"
                label: ""
                tooltipText: qsTr("Borrar (Supr)")
                onClicked: {
                    root.selectRequested();
                    root.deleteRequested();
                }
            }
        }
    }
}

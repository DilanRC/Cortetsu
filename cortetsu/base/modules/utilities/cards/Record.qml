pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.components
import qs.components.controls
import qs.services
import qs.modules

CortetsuSurface {
    id: root

    required property var props
    required property ScreenState screenState
    readonly property real nonAnimHeight: btnLayout.implicitHeight + listOrControls.implicitHeight + layout.spacing + layout.anchors.margins * 2

    implicitHeight: layout.implicitHeight + layout.anchors.margins * 2

    radius: CortetsuTokens.rounding.large
    color: CortetsuColours.tPalette.m3surfaceContainer

    ColumnLayout {
        id: layout

        anchors.fill: parent
        anchors.margins: CortetsuTokens.padding.large
        spacing: CortetsuTokens.spacing.medium

        RowLayout {
            id: btnLayout

            spacing: CortetsuTokens.spacing.medium

            CortetsuSurface {
                implicitWidth: implicitHeight
                implicitHeight: {
                    const h = icon.implicitHeight + CortetsuTokens.padding.small * 2;
                    return h - (h % 2);
                }

                radius: CortetsuTokens.rounding.full
                color: CortetsuRecorder.running ? CortetsuColours.palette.m3secondary : CortetsuColours.palette.m3secondaryContainer

                CortetsuIcon {
                    id: icon

                    anchors.centerIn: parent
                    anchors.verticalCenterOffset: 1
                    text: "screen_record"
                    color: CortetsuRecorder.running ? CortetsuColours.palette.m3onSecondary : CortetsuColours.palette.m3onSecondaryContainer
                    fontStyle: CortetsuTokens.font.icon.large
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                CortetsuText {
                    Layout.fillWidth: true
                    text: qsTr("Screen Recorder")
                    font: CortetsuTokens.font.body.medium
                    elide: Text.ElideRight
                }

                CortetsuText {
                    Layout.fillWidth: true
                    text: CortetsuRecorder.paused ? qsTr("Paused") : CortetsuRecorder.running ? qsTr("Running...") : qsTr("Ready")
                    color: CortetsuColours.palette.m3onSurfaceVariant
                    font: CortetsuTokens.font.body.small
                    elide: Text.ElideRight
                    animate: true
                }
            }

            SplitButton {
                disabled: CortetsuRecorder.running

                active: menuItems.find(m => root.props.recordingMode === m.icon + m.text) ?? menuItems[0]
                menu.onItemSelected: item => root.props.recordingMode = item.icon + item.text

                menuItems: [
                    MenuItem {
                        icon: "fullscreen"
                        text: qsTr("Record fullscreen")
                        activeText: qsTr("Fullscreen")
                        onClicked: CortetsuRecorder.start()
                    },
                    MenuItem {
                        icon: "screenshot_region"
                        text: qsTr("Record region")
                        activeText: qsTr("Region")
                        onClicked: CortetsuRecorder.start(["-r"])
                    },
                    MenuItem {
                        icon: "select_to_speak"
                        text: qsTr("Record fullscreen with sound")
                        activeText: qsTr("Fullscreen")
                        onClicked: CortetsuRecorder.start(["-s"])
                    },
                    MenuItem {
                        icon: "volume_up"
                        text: qsTr("Record region with sound")
                        activeText: qsTr("Region")
                        onClicked: CortetsuRecorder.start(["-sr"])
                    }
                ]
            }
        }

        Loader {
            id: listOrControls

            property bool running: CortetsuRecorder.running

            asynchronous: true
            Layout.fillWidth: true
            Layout.preferredHeight: implicitHeight
            sourceComponent: running ? recordingControls : recordingList
            clip: Layout.preferredHeight < implicitHeight

            Behavior on Layout.preferredHeight {
                id: locHeightAnim

                enabled: false

                Anim {}
            }

            Behavior on running {
                SequentialAnimation {
                    Anim {
                        target: listOrControls
                        property: "opacity"
                        to: 0
                        type: Anim.DefaultEffects
                    }
                    PropertyAction {
                        target: locHeightAnim
                        property: "enabled"
                        value: true
                    }
                    PropertyAction {}
                    ParallelAnimation {
                        SequentialAnimation {
                            PauseAnimation {
                                duration: 100
                            }
                            PropertyAction {
                                target: locHeightAnim
                                property: "enabled"
                                value: false
                            }
                        }
                        Anim {
                            target: listOrControls
                            property: "opacity"
                            to: 1
                            type: Anim.SlowEffects
                        }
                    }
                }
            }
        }
    }

    Component {
        id: recordingList

        RecordingList {
            props: root.props
            screenState: root.screenState
        }
    }

    Component {
        id: recordingControls

        RowLayout {
            spacing: CortetsuTokens.spacing.medium

            CortetsuSurface {
                radius: CortetsuTokens.rounding.full
                color: CortetsuRecorder.paused ? CortetsuColours.palette.m3tertiary : CortetsuColours.palette.m3error

                implicitWidth: recText.implicitWidth + CortetsuTokens.padding.medium * 2
                implicitHeight: recText.implicitHeight + CortetsuTokens.padding.large

                CortetsuText {
                    id: recText

                    anchors.centerIn: parent
                    animate: true
                    text: CortetsuRecorder.paused ? "PAUSED" : "REC"
                    color: CortetsuRecorder.paused ? CortetsuColours.palette.m3onTertiary : CortetsuColours.palette.m3onError
                    font: CortetsuTokens.font.mono.small
                }

                Behavior on implicitWidth {
                    Anim {}
                }

                SequentialAnimation on opacity {
                    running: !CortetsuRecorder.paused
                    alwaysRunToEnd: true
                    loops: Animation.Infinite

                    Anim {
                        from: 1
                        to: 0
                        duration: CortetsuTokens.anim.durations.large
                        easing: CortetsuTokens.anim.emphasizedAccel
                    }
                    Anim {
                        from: 0
                        to: 1
                        duration: CortetsuTokens.anim.durations.extraLarge
                        easing: CortetsuTokens.anim.emphasizedDecel
                    }
                }
            }

            CortetsuText {
                Layout.fillWidth: true
                text: {
                    const elapsed = CortetsuRecorder.elapsed;

                    const hours = Math.floor(elapsed / 3600);
                    const mins = Math.floor((elapsed % 3600) / 60);
                    const secs = Math.floor(elapsed % 60).toString().padStart(2, "0");

                    let time;
                    if (hours > 0)
                        time = `${hours}:${mins.toString().padStart(2, "0")}:${secs}`;
                    else
                        time = `${mins}:${secs}`;

                    return qsTr("Recording for %1").arg(time);
                }
                font: CortetsuTokens.font.body.medium
                elide: Text.ElideMiddle
            }

            ButtonRow {
                spacing: CortetsuTokens.spacing.extraSmall

                IconButton {
                    shapeMorph: true
                    isRound: true
                    label.animate: true
                    icon: CortetsuRecorder.paused ? "play_arrow" : "pause"
                    isToggle: true
                    checked: CortetsuRecorder.paused
                    type: IconButton.Tonal
                    font: CortetsuTokens.font.icon.medium
                    onClicked: {
                        CortetsuRecorder.togglePause();
                        internalChecked = CortetsuRecorder.paused;
                    }

                    implicitWidth: {
                        // Ensure even size so icon is centered properly
                        const h = label.implicitHeight + CortetsuTokens.padding.large * 2;
                        if (h % 2 !== 0)
                            return h + 1;
                        return h;
                    }
                }

                IconButton {
                    shapeMorph: true
                    isRound: true
                    icon: "stop"
                    inactiveColour: CortetsuColours.palette.m3error
                    inactiveOnColour: CortetsuColours.palette.m3onError
                    font: CortetsuTokens.font.icon.medium
                    onClicked: CortetsuRecorder.stop()

                    implicitWidth: {
                        // Ensure even size so icon is centered properly
                        const h = label.implicitHeight + CortetsuTokens.padding.large * 2;
                        if (h % 2 !== 0)
                            return h + 1;
                        return h;
                    }
                }
            }
        }
    }
}

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import qs.components
import qs.components.containers
import qs.components.controls
import qs.components.filedialog
import qs.modules
import qs.services
import qs.utils

ColumnLayout {
    id: root

    required property var props
    required property ScreenState screenState

    spacing: 0

    WrapperMouseArea {
        Layout.fillWidth: true

        cursorShape: Qt.PointingHandCursor
        onClicked: root.props.recordingListExpanded = !root.props.recordingListExpanded

        RowLayout {
            spacing: CortetsuTokens.spacing.medium

            CortetsuIcon {
                Layout.alignment: Qt.AlignVCenter
                text: "list"
                fontStyle: CortetsuTokens.font.icon.large
            }

            CortetsuText {
                Layout.alignment: Qt.AlignVCenter
                Layout.fillWidth: true
                text: qsTr("Recordings")
                font: CortetsuTokens.font.body.medium
            }

            IconButton {
                icon: root.props.recordingListExpanded ? "unfold_less" : "unfold_more"
                type: IconButton.Text
                label.animate: true
                onClicked: root.props.recordingListExpanded = !root.props.recordingListExpanded
            }
        }
    }

    StyledListView {
        id: list

        model: FileSystemModel {
            path: Paths.recsdir
            nameFilters: ["recording_*.mp4"]
            sortReverse: true
        }

        Layout.fillWidth: true
        Layout.rightMargin: -CortetsuTokens.spacing.small
        implicitHeight: (CortetsuTokens.font.body.large.pointSize + CortetsuTokens.padding.small) * (root.props.recordingListExpanded ? 10 : 3)
        clip: true

        StyledScrollBar.vertical: StyledScrollBar {
            flickable: list
        }

        delegate: RowLayout {
            id: recording

            required property var modelData
            property string baseName

            anchors.left: list.contentItem.left
            anchors.right: list.contentItem.right
            anchors.rightMargin: CortetsuTokens.spacing.small
            spacing: CortetsuTokens.spacing.extraSmall

            Component.onCompleted: baseName = modelData.baseName

            CortetsuText {
                Layout.fillWidth: true
                Layout.rightMargin: CortetsuTokens.spacing.extraSmall
                text: {
                    const time = recording.baseName;
                    const matches = time.match(/^recording_(\d{4})(\d{2})(\d{2})_(\d{2})-(\d{2})-(\d{2})/);
                    if (!matches)
                        return time;
                    const date = new Date(...matches.slice(1));
                    date.setMonth(date.getMonth() - 1); // Woe (months start from 0)
                    return qsTr("Recording at %1").arg(Qt.formatDateTime(date, Qt.locale()));
                }
                color: CortetsuColours.palette.m3onSurfaceVariant
                elide: Text.ElideRight
            }

            IconButton {
                icon: "play_arrow"
                type: IconButton.Text
                onClicked: {
                    root.screenState.utilities = false;
                    root.screenState.sidebar = false;
                    CortetsuProcessLauncher.launchPersistent(
                        [...CortetsuConfig.playbackCommand, recording.modelData.path],
                        "",
                        "recording-playback"
                    );
                }
            }

            IconButton {
                icon: "folder"
                type: IconButton.Text
                onClicked: {
                    root.screenState.utilities = false;
                    root.screenState.sidebar = false;
                    CortetsuProcessLauncher.launchPersistent(
                        [...CortetsuConfig.explorerCommand, recording.modelData.path],
                        "",
                        "recording-explorer"
                    );
                }
            }

            IconButton {
                icon: "delete_forever"
                type: IconButton.Text
                label.color: CortetsuColours.palette.m3error
                stateLayer.color: CortetsuColours.palette.m3error
                onClicked: root.props.recordingConfirmDelete = recording.modelData.path
            }
        }

        add: Transition {
            Anim {
                type: Anim.DefaultEffects
                property: "opacity"
                from: 0
                to: 1
            }
        }

        remove: Transition {
            Anim {
                type: Anim.DefaultEffects
                property: "opacity"
                to: 0
            }
        }

        displaced: Transition {
            Anim {
                type: Anim.DefaultEffects
                property: "opacity"
                to: 1
            }
            Anim {
                property: "y"
            }
        }

        Loader {
            asynchronous: true
            anchors.centerIn: parent

            opacity: list.count === 0 ? 1 : 0
            active: opacity > 0

            sourceComponent: ColumnLayout {
                spacing: CortetsuTokens.spacing.small

                CortetsuIcon {
                    Layout.alignment: Qt.AlignHCenter
                    text: "scan_delete"
                    color: CortetsuColours.palette.m3outline
                    fontStyle: CortetsuTokens.font.icon.extraLarge

                    opacity: root.props.recordingListExpanded ? 1 : 0
                    scale: root.props.recordingListExpanded ? 1 : 0
                    Layout.preferredHeight: root.props.recordingListExpanded ? implicitHeight : 0

                    Behavior on opacity {
                        Anim {
                            type: Anim.DefaultEffects
                        }
                    }

                    Behavior on scale {
                        Anim {}
                    }

                    Behavior on Layout.preferredHeight {
                        Anim {}
                    }
                }

                RowLayout {
                    spacing: CortetsuTokens.spacing.medium

                    CortetsuIcon {
                        Layout.alignment: Qt.AlignHCenter
                        text: "scan_delete"
                        color: CortetsuColours.palette.m3outline

                        opacity: !root.props.recordingListExpanded ? 1 : 0
                        scale: !root.props.recordingListExpanded ? 1 : 0
                        Layout.preferredWidth: !root.props.recordingListExpanded ? implicitWidth : 0

                        Behavior on opacity {
                            Anim {
                                type: Anim.DefaultEffects
                            }
                        }

                        Behavior on scale {
                            Anim {}
                        }

                        Behavior on Layout.preferredWidth {
                            Anim {}
                        }
                    }

                    CortetsuText {
                        text: qsTr("No recordings found")
                        color: CortetsuColours.palette.m3outline
                    }
                }
            }

            Behavior on opacity {
                Anim {
                    type: Anim.DefaultEffects
                }
            }
        }

        Behavior on implicitHeight {
            Anim {}
        }
    }
}

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Qt.labs.folderlistmodel
import Quickshell
import "../../../theme"
import "../.."
import "../controls"

// The last recordings in the destination folder, newest first, each one a
// click away from the player. The folder is read only while this page is
// open; nothing here deletes a file.
SettingsGroup {
    id: root

    readonly property int shown: 6

    title: qsTr("Grabaciones recientes")
    icon: "video_library"
    detail: folder.count === 0 ? qsTr("Todavía no hay grabaciones en %1").arg(CortetsuRecorder.recordingsDir)
        : folder.count === 1 ? qsTr("1 grabación en %1").arg(CortetsuRecorder.recordingsDir)
        : qsTr("%1 grabaciones en %2").arg(folder.count).arg(CortetsuRecorder.recordingsDir)

    function stamp(modified: date): string {
        return `${CortetsuRegional.formatDate(modified, "weekdayDay", true)} · ${Qt.formatTime(modified, CortetsuRegional.clockPattern)}`;
    }

    function megabytes(bytes: real): string {
        return bytes >= 1073741824 ? qsTr("%1 GiB").arg((bytes / 1073741824).toFixed(1))
            : qsTr("%1 MiB").arg(Math.max(0.1, bytes / 1048576).toFixed(1));
    }

    FolderListModel {
        id: folder
        folder: `file://${CortetsuRecorder.recordingsDir}`
        nameFilters: ["recording_*.mp4"]
        showDirs: false
        sortField: FolderListModel.Time
    }

    Repeater {
        model: folder

        delegate: SettingActionRow {
            required property int index
            required property string fileName
            required property string filePath
            required property date fileModified
            required property real fileSize
            visible: index < root.shown
            leadingIcon: "movie"
            title: root.stamp(fileModified)
            detail: `${fileName} · ${root.megabytes(fileSize)}`
            actionLabel: qsTr("Ver")
            actionIcon: "play_arrow"
            onActivated: Quickshell.execDetached([...CortetsuConfig.playbackCommand, filePath])
        }
    }

    SettingActionRow {
        title: qsTr("Carpeta de grabaciones")
        detail: folder.count > root.shown ? qsTr("Las %1 más recientes arriba; el resto está en la carpeta").arg(root.shown) : ""
        actionLabel: qsTr("Abrir carpeta")
        actionIcon: "folder_open"
        onActivated: Quickshell.execDetached([...CortetsuConfig.explorerCommand, CortetsuRecorder.recordingsDir])
    }
}

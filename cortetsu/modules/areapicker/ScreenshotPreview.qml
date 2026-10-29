import QtQuick
import QtQuick.Layouts
import "../../components"
import "../../theme"
import "../CortetsuTypography.js" as CortetsuTypography

// The card shown after an area capture. Nothing here touches the file: each
// button asks the owner (AreaPicker) to run the action. Left alone, the
// capture is saved, so closing it by accident never loses it.
CortetsuSurface {
    id: root

    property url source
    // An action is running; the buttons wait for it.
    property bool busy: false
    property int autoSaveMs: 10000
    readonly property bool held: hover.hovered

    signal copyRequested()
    signal saveRequested()
    signal editRequested()
    signal discardRequested()

    implicitWidth: 360
    implicitHeight: column.implicitHeight + CortetsuDesign.spacingStandard * 2
    radiusValue: CortetsuDesign.radiusLarge
    baseColor: Qt.alpha(CortetsuDesign.colorSurfaceHigh, 0.96)
    outlined: true

    // Restarts on every new image: an edited capture gets the full time again.
    onSourceChanged: autoSave.restart()

    HoverHandler { id: hover }

    Timer {
        id: autoSave
        objectName: "autoSave"
        interval: root.autoSaveMs
        running: !root.held && !root.busy
        onTriggered: root.saveRequested()
    }

    ColumnLayout {
        id: column
        anchors.fill: parent
        anchors.margins: CortetsuDesign.spacingStandard
        spacing: CortetsuDesign.spacingStandard

        Image {
            objectName: "thumbnail"
            Layout.fillWidth: true
            Layout.preferredHeight: 200
            source: root.source
            cache: false
            asynchronous: true
            fillMode: Image.PreserveAspectFit
            sourceSize.width: 720
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: CortetsuDesign.spacingUnit

            CortetsuButton {
                objectName: "copy"
                Layout.fillWidth: true
                compact: true
                active: true
                icon: "content_copy"
                label: qsTr("Copiar")
                disabled: root.busy
                onClicked: root.copyRequested()
            }
            CortetsuButton {
                objectName: "save"
                Layout.fillWidth: true
                compact: true
                icon: "save"
                label: qsTr("Guardar")
                disabled: root.busy
                onClicked: root.saveRequested()
            }
            CortetsuButton {
                objectName: "edit"
                Layout.fillWidth: true
                compact: true
                icon: "edit"
                label: qsTr("Editar")
                disabled: root.busy
                onClicked: root.editRequested()
            }
            CortetsuButton {
                objectName: "discard"
                compact: true
                danger: true
                icon: "delete"
                tooltipText: qsTr("Descartar")
                disabled: root.busy
                onClicked: root.discardRequested()
            }
        }

        CortetsuText {
            Layout.fillWidth: true
            text: qsTr("Si no eliges nada, se guarda en Capturas.")
            color: CortetsuDesign.colorOutline
            font.pixelSize: CortetsuTypography.labelSmallPx
            elide: Text.ElideRight
        }
    }
}

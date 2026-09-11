pragma ComponentBehavior: Bound

import QtQuick
import Quickshell

FocusScope {
    id: root

    required property ShellScreen screen
    required property var screenState
    required property bool displayVisible

    readonly property real panelWidth: Math.min(1260, parent.width - 96)
    readonly property real panelHeight: Math.min(900, parent.height - 64)
    readonly property real panelLeft: Math.round((parent.width - panelWidth) / 2)
    readonly property real panelTop: Math.round((parent.height - panelHeight) / 2)
    readonly property real footerHeight: 120
    readonly property real footerMargin: 30

    function openDisplayManager(): void { editor.openDisplayManager(); }

    Editor {
        id: editor
        anchors.fill: parent
        screen: root.screen
        screenState: root.screenState
        displayVisible: root.displayVisible
    }

    DisplayPresets {
        id: presets
        z: 20
        width: Math.min(350, Math.max(310, root.panelWidth * 0.28))
        height: root.footerHeight
        x: root.panelLeft + root.footerMargin
        y: root.panelTop + root.panelHeight - height - root.footerMargin
        candidateOutputs: editor.candidateOutputs
        onCandidateLoaded: candidate => {
            const outputs = candidate?.outputs ?? [];
            if (!outputs.length) return;
            editor.candidateOutputs = outputs.map(item => Object.assign({}, item));
            editor.selectedIndex = 0;
            editor.planResult = ({});
            editor.planStatus = qsTr("Saved layout loaded · run Dry run before Preview");
        }
    }

    DisplayOutputControls {
        z: 20
        width: Math.min(330, Math.max(300, root.panelWidth * 0.265))
        height: root.footerHeight
        x: Math.round(root.panelLeft + (root.panelWidth - width) / 2)
        y: root.panelTop + root.panelHeight - height - root.footerMargin
        editorItem: editor
        monitor: editor.selectedLive
    }

    PreviewControls {
        id: previewControls
        z: 20
        width: Math.min(390, Math.max(350, root.panelWidth * 0.31))
        height: root.footerHeight
        x: root.panelLeft + root.panelWidth - width - root.footerMargin
        y: root.panelTop + root.panelHeight - height - root.footerMargin
        candidateOutputs: editor.candidateOutputs
    }
}

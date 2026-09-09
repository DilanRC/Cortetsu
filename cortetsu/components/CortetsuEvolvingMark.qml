pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import Quickshell
import "../modules/CortetsuDesign.js" as CortetsuDesign

Item {
    id: root

    // Rendering only. The owner of this item keeps the input surface.
    property string phase: "Ascended"
    property color monochromeColor: CortetsuDesign.colorWashi
    property color accent: "transparent"
    property bool monochrome: true
    property bool animated: true

    readonly property string phaseKey: normalizedPhase(phase)
    readonly property string phaseAssetPath:
        Quickshell.shellPath(`assets/branding/cortetsu-mark-${phaseKey.toLowerCase()}.svg`)
    readonly property color effectiveColor: monochrome ? monochromeColor : accent
    readonly property int transitionDuration: phaseKey === "Cosmic"
        ? CortetsuDesign.motionDeliberateMs
        : phaseKey === "Monster"
            ? CortetsuDesign.motionStandardMs
            : CortetsuDesign.motionFastMs
    implicitWidth: 64
    implicitHeight: 64
    width: implicitWidth
    height: implicitHeight

    function normalizedPhase(value: string): string {
        switch (String(value ?? "").toLowerCase()) {
        case "human": return "Human";
        case "awakening": return "Awakening";
        case "monster": return "Monster";
        case "cosmic": return "Cosmic";
        default: return "Ascended";
        }
    }

    function syncImmediately(): void {
        phaseTransition.stop();
        currentMark.source = phaseAssetPath;
        currentMark.opacity = 1;
        incomingMark.opacity = 0;
    }

    function evolve(): void {
        incomingMark.source = phaseAssetPath;
        if (!animated || !currentMark.source) {
            syncImmediately();
            return;
        }
        phaseTransition.restart();
    }

    Component.onCompleted: syncImmediately()
    onPhaseChanged: evolve()

    Image {
        id: currentMark
        anchors.fill: parent
        fillMode: Image.PreserveAspectFit
        sourceSize.width: Math.max(1, Math.round(root.width * 3))
        sourceSize.height: Math.max(1, Math.round(root.height * 3))
        asynchronous: false
        retainWhileLoading: true
        smooth: true
        mipmap: true

        layer.enabled: root.effectiveColor.a > 0
        layer.effect: MultiEffect {
            colorization: root.effectiveColor.a > 0 ? 1 : 0
            colorizationColor: root.effectiveColor
        }
    }

    Image {
        id: incomingMark
        anchors.fill: parent
        opacity: 0
        fillMode: Image.PreserveAspectFit
        sourceSize.width: Math.max(1, Math.round(root.width * 3))
        sourceSize.height: Math.max(1, Math.round(root.height * 3))
        asynchronous: false
        retainWhileLoading: true
        smooth: true
        mipmap: true

        layer.enabled: root.effectiveColor.a > 0
        layer.effect: MultiEffect {
            colorization: root.effectiveColor.a > 0 ? 1 : 0
            colorizationColor: root.effectiveColor
        }
    }

    SequentialAnimation {
        id: phaseTransition

        ParallelAnimation {
            NumberAnimation {
                target: currentMark
                property: "opacity"
                to: 0
                duration: root.transitionDuration
                easing.type: Easing.OutCubic
            }
            NumberAnimation {
                target: incomingMark
                property: "opacity"
                to: 1
                duration: root.transitionDuration
                easing.type: Easing.OutCubic
            }
        }

        ScriptAction {
            script: {
                currentMark.source = incomingMark.source;
                currentMark.opacity = 1;
                incomingMark.opacity = 0;
            }
        }
    }
}

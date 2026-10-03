pragma Singleton

import QtQml
import Quickshell
import "../modules"
import "../components"

// Compatibility name for upstream callers while the remaining surfaces move
// to CortetsuShellState. The state registry and component slots are owned by
// Cortetsu; this service contains no upstream service or design dependency.
Singleton {
    id: root

    property var shellRoot

    Variants {
        id: states

        model: CortetsuScreens.screens

        ScreenState {}
    }

    Variants {
        id: legacyComponents

        model: CortetsuScreens.screens

        component Components: QtObject {
            required property ShellScreen modelData

            property var background
            property var rootWindow
            property var interactionWrapper
            property var bar
            property var panels
        }

        Components {}
    }

    function anySidebarOpen(): bool {
        return CortetsuShellState.anySidebarOpen();
    }

    function forScreen(screen): var {
        return states.instances.find(state => state.modelData === screen)
            ?? CortetsuShellState.forScreen(screen)
            ?? null;
    }

    function forActive(): var {
        const monitor = CortetsuHypr.focusedMonitor;
        return states.instances.find(state => CortetsuHypr.monitorFor(state.modelData) === monitor)
            ?? CortetsuShellState.forActive()
            ?? null;
    }

    function componentsFor(screen): var {
        return legacyComponents.instances.find(component => component.modelData === screen)
            ?? CortetsuShellState.componentsFor(screen);
    }

    function componentsForActive(): var {
        const monitor = CortetsuHypr.focusedMonitor;
        return legacyComponents.instances.find(component => CortetsuHypr.monitorFor(component.modelData) === monitor)
            ?? legacyComponents.instances[0]
            ?? null;
    }

    function compatibilityComponentsFor(screen): var {
        return legacyComponents.instances.find(component => component.modelData === screen) ?? null;
    }

    component ComponentRef: QtObject {
        required property var screen
        required property string slot
        required property var component
        // ComponentRef writes legacy slots only on the compatibility object.
        // Falling back to CortetsuShellState here returns Panels/Background,
        // which intentionally do not expose those legacy properties during
        // dynamic monitor creation.
        readonly property var target: ShellState.compatibilityComponentsFor(screen)

        onTargetChanged: {
            if (target)
                target[slot] = component;
        }
        Component.onDestruction: {
            if (target && target[slot] === component)
                target[slot] = null;
        }
    }
}

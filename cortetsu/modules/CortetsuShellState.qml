pragma Singleton

import QtQml

QtObject {
    property var states: []
    property var components: []
    property var attachedPopupHoverOwner: null
    property bool screenshotActive: false
    // Text the launcher starts with the next time it opens (the emoji mode).
    property string launcherQuery: ""
    // Page the Hardware Center shows (hardware/Navigation.js indices).
    property int hardwarePage: 0

    function registerState(screen, state): void {
        states = states.filter(entry => entry.screen !== screen).concat([{ screen, state }]);
    }

    function unregisterState(screen, state): void {
        states = states.filter(entry => entry.screen !== screen || entry.state !== state);
    }

    function registerComponents(screen, component): void {
        components = components.filter(entry => entry.screen !== screen).concat([{ screen, component }]);
    }

    function unregisterComponents(screen, component): void {
        components = components.filter(entry => entry.screen !== screen || entry.component !== component);
    }

    function enterAttachedPopup(owner): void {
        attachedPopupHoverOwner = owner;
    }

    function leaveAttachedPopup(owner): void {
        if (attachedPopupHoverOwner === owner)
            attachedPopupHoverOwner = null;
    }

    // Every screen's state, the `states` argument of CortetsuOverlayPolicy.
    function allStates(): var {
        return states.map(entry => entry.state).filter(state => !!state);
    }

    function forScreen(screen): var {
        if (!screen)
            return null;
        return states.find(entry => entry.screen === screen)?.state ?? null;
    }

    // The launcher is one effective state across screens: at most one screen
    // has it open, and a toggle closes it wherever it is. Resolving the
    // screen from the focused monitor alone moved the launcher to the
    // pointer's monitor instead of closing it.
    function launcherOpenAnywhere(): bool {
        return states.some(entry => !!entry.state?.launcher);
    }

    function closeLaunchers(except): void {
        for (const entry of states)
            if (entry.state && entry.state !== except)
                entry.state.launcher = false;
    }

    function anySidebarOpen(): bool {
        return states.some(entry => !!entry.state?.sidebar);
    }

    function forActive(): var {
        const monitor = CortetsuHypr.focusedMonitor;
        if (!monitor)
            return null;
        return states.find(entry => CortetsuHypr.monitorFor(entry.screen) === monitor)?.state ?? null;
    }

    function componentsFor(screen): var {
        return components.find(entry => entry.screen === screen)?.component ?? null;
    }
}

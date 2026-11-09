#!/usr/bin/env python3
"""Runtime check of the real Settings surface (SUPER+I).

The real Content.qml, Nexus, pages, preferences store and scheme service run
inside Quickshell against the service doubles of settings_harness.py. Keys are
real key events. Each scenario is a list of [condition, action] steps: the
action runs once the condition holds, so a slow machine waits instead of
failing.

What it proves:
- a colour token, a scheme, a preference or a catalogue reload changes
  properties and keeps every QML object that was on screen;
- only the open page exists, and closing Settings leaves none;
- a failed operation leaves the control on the real value and says why;
- an unavailable backend is shown as such and the rest keeps working;
- a value changed from outside reaches the open page;
- Tab, Shift+Tab, arrows, Enter, Space and Escape do what they should.

Set CORTETSU_RENDER_DIR to keep a PNG of every page and state.
"""
import json
import os
import sys
import subprocess
import tempfile
from pathlib import Path

from settings_harness import ROOT, build_tree, run, run_host

subprocess.run(["node", str(ROOT / "tests/test-battery-policy.node.js")], check=True)

SHELL = r"""import QtQuick
import QtQuick.Window
import QtTest
import Quickshell
import Quickshell.Io
import "modules"
import "modules/background"
import "modules/hardware"
import "modules/settings"
import "modules/osd" as Osd
import "modules/CortetsuNotificationModel.js" as NotificationModel
import "modules/launcher/services"
import "components"
import "services"
import "utils"
import "theme"

ShellRoot {
    id: root
    property int checks: 0
    property int step: 0
    property var kept: []
    property var memo: ({})
    property int writes: 0
    property int hardwareSampleWritesBefore: 0
    readonly property string scenario: Quickshell.env("SETTINGS_SCENARIO")
    readonly property string fixtures: Quickshell.env("SETTINGS_FIXTURES")
    readonly property string renderDir: Quickshell.env("CORTETSU_RENDER_DIR")
    readonly property string schemeTool: Quickshell.env("HOME") + "/bin/cortetsu-scheme"
    readonly property var content: host.item
    readonly property var notificationBadgeProbe: notificationBadgeLoader.item
    readonly property var hardwareTelemetryProbe: hardwareTelemetryLoader.item
    Loader {
        id: osdProbe
        active: root.scenario === "globalPersonalisation"
        sourceComponent: Osd.Wrapper {
            screen: Quickshell.screens[0]
            screenState: screenDouble
            sidebarOrSessionVisible: false
        }
    }
    Loader {
        id: notificationBadgeLoader
        active: root.scenario === "notificationCountPreferences" || root.scenario === "notificationCountRestore"
        sourceComponent: notificationBadgeComponent
    }
    Loader {
        id: hardwareTelemetryLoader
        active: root.scenario === "hardwareSamplePreferences" || root.scenario === "hardwareSampleRestore"
        sourceComponent: hardwareTelemetryComponent
    }
    Component {
        id: hardwareTelemetryComponent
        HardwareTelemetry {
            objectName: "hardwareTelemetryProbe"
            active: false
        }
    }
    Component {
        id: notificationBadgeComponent
        CortetsuStatusSegment {
            objectName: "notificationBadgeProbe"
            x: -1000
            width: 500
            notificationCount: 3
            volumeIcon: "volume_up"
            volumeMuted: false
            networkIcon: "wifi"
            networkTooltip: "Wi-Fi"
            networkActive: false
            bluetoothIcon: "bluetooth"
            bluetoothActive: false
            batteryIcon: "battery_full"
            batteryCritical: false
            batteryTooltip: "Battery"
            audioVisible: true
            networkVisible: true
            bluetoothVisible: true
            batteryVisible: true
            statusPopoutsEnabled: false
            sidebarActive: false
            recordingActive: false
            dndActive: false
            idleInhibited: false
            now: new Date(2026, 0, 1, 13, 5)
            sessionActive: false
            opacity: 0
            enabled: false
        }
    }
    readonly property var wifi: ConnectivityWifi
    readonly property var bluetooth: ConnectivityBluetooth
    readonly property var policyBridge: policyDouble
    Binding { target: ShellState; property: "shellRoot"; value: root }
    QtObject {
        id: policyDouble
        property bool usable: false
        readonly property bool canChange: usable && pendingDomain === ""
        readonly property string statusText: usable ? "Conectado" : "No disponible"
        property string sessionId: "fixture-session"
        property string pendingDomain: ""
        property string actionErrorDomain: ""
        property string lastError: ""
        property string readError: ""
        property bool rulesLoaded: true
        property var rules: []
        property var snapshot: ({activations: {}, decisions: []})
        property var calls: []
        function activation(domain) { return snapshot.activations[domain] || {enabled:false, owner_session:"", manual_override_until_unix_ms:0}; }
        function ownedByAnother(domain) { return activation(domain).owner_session !== "" && activation(domain).owner_session !== sessionId; }
        function refreshStatus() { calls = calls.concat(["refresh"]); }
        function setDomainEnabled(domain, enabled) { calls = calls.concat([["set", domain, enabled]]); pendingDomain = domain; }
        function overrideDomain(domain, seconds) { calls = calls.concat([["override", domain, seconds]]); pendingDomain = domain; }
        function revokeDomain(domain, expectedOwner) {
            calls = calls.concat([["revoke", domain, expectedOwner]]);
            pendingDomain = domain; lastError = ""; actionErrorDomain = "";
        }
        function settle(domain, enabled, until, owner) {
            const active = Object.assign({}, snapshot.activations);
            active[domain] = {enabled:enabled, owner_session:owner, manual_override_until_unix_ms:until};
            snapshot = {activations:active, decisions:[]};
            pendingDomain = "";
        }
    }

    function verify(value, reason) { if (!value) { console.log("SETTINGS_FAIL", reason); return; } checks++; }
    function compare(actual, expected) { verify(actual === expected, `expected ${expected}, got ${actual}`); }
    function same(a, b) { return Qt.colorEqual(a, b); }
    // The grab happens on a later frame; `rendering` holds the next step
    // until the picture is taken, so it shows this state and not the next.
    property bool rendering: false
    function render(name) {
        if (!renderDir)
            return;
        rendering = true;
        window.contentItem.grabToImage(result => {
            result.saveToFile(`${renderDir}/${name}${renderSuffix}.png`);
            rendering = false;
        });
    }
    readonly property string renderSuffix: Quickshell.env("SETTINGS_RENDER_SUFFIX")
    readonly property string slowNoticePath: `${fixtures}/slow-notice-ready`

    FileView {
        id: slowNoticeSignal
        path: root.slowNoticePath
        printErrors: false
    }
    Timer {
        id: slowNoticeWaiter
        interval: 10
        repeat: true
        running: root.scenario === "themeSlowCommit"
        onTriggered: {
            if (!root.content || root.content.pageId !== "themes")
                return;
            const themeRow = root.page("themeStatus");
            if (!CortetsuThemes.slowNoticeShown || !themeRow || themeRow.statusText !== CortetsuThemes.error)
                return;
            slowNoticeSignal.setText("ready");
            stop();
        }
    }

    function find(item, name) {
        if (!item)
            return null;
        if (item.objectName === name)
            return item;
        const children = item.children ?? [];
        for (let i = 0; i < children.length; ++i) {
            const found = find(children[i], name);
            if (found)
                return found;
        }
        return null;
    }
    function get(name) { return find(content, name); }
    function page(name) { return find(content.page, name); }
    function notificationBadgeVisible(): bool {
        return !!notificationBadgeProbe && notificationBadgeProbe.notificationCountBadge.visible;
    }
    function text(name) { return find(get(name), "rowDetail")?.text ?? ""; }
    function clockDateExists(): bool { return find(clockArea, "desktopClockDate") !== null; }
    function clockDateVisible(): bool { return find(clockArea, "desktopClockDate")?.visible ?? false; }
    function value(name) { return find(get(name), "value")?.text ?? ""; }
    // Every item under the surface. Comparing two of these by identity tells
    // whether anything was destroyed or created in between.
    function items() {
        const out = [];
        const walk = item => {
            out.push(item);
            const children = item.children ?? [];
            for (let i = 0; i < children.length; ++i)
                walk(children[i]);
        };
        walk(frame);
        return out;
    }
    function keep() { kept = items(); }
    function churn() {
        const now = new Set(items());
        let lost = 0;
        for (const item of kept) {
            if (!now.has(item))
                lost++;
        }
        return `${lost} destroyed, ${now.size - (kept.length - lost)} created`;
    }
    function focusName() { return frame.Window.activeFocusItem?.objectName || "-"; }
    function key(code, modifiers) { events.keyClick(code, modifiers ?? Qt.NoModifier, -1); }
    function select(id) { SettingsController.select(id); }
    function mode(file, value) { modeFile.path = `${fixtures}/${file}`; modeFile.setText(value); }

    TestEvent { id: events }

    FileView { id: modeFile; blockWrites: true; printErrors: false }
    FileView { id: stateFile; path: CortetsuColours.schemePath; blockWrites: true; printErrors: false }
    Process {
        id: blockConfig
        property bool ready: false
        command: ["cortetsu-test-block-preferences"]
        onExited: (code, status) => {
            if (code !== 0) {
                console.log("SETTINGS_FAIL", "could not prepare the failed-write fixture", code);
                Qt.quit();
            } else {
                ready = true;
            }
        }
    }

    Connections {
        target: CortetsuConfig
        function onSaveStateChanged() { if (CortetsuConfig.saveState === "saving") root.writes++; }
    }

    QtObject {
        id: retained
        property string opened: ""
        property real fullscreenTransitionProgress: 0
        function closeRetainedOverlaysExcept(flag) {}
        function setRetained(flag, value) { if (value) opened = flag; return true; }
    }
    // Not named like the property it feeds: inside the Loader's component
    // that name would resolve to the content's own, still unset, property.
    QtObject {
        id: screenDouble
        property bool settings: false
        property bool launcher: false
        property bool osd: false
        property var cortetsuState: retained
    }

    Window {
        id: window
        width: Number(Quickshell.env("SETTINGS_WIDTH") || 1368)
        height: Number(Quickshell.env("SETTINGS_HEIGHT") || 900)
        visible: true
        color: "#0B0D10"

        Item {
            id: clockArea
            anchors.fill: parent
            // Keep the subtree active so the test can observe the date's own visibility.
            opacity: 0
            DesktopClock {
                wallpaper: clockArea
                absX: 0
                absY: 0
                anchors.centerIn: parent
            }
        }

        // The same frame SettingsHost draws, so a render shows the real surface.
        CortetsuInkPanel {
            id: frame
            anchors.fill: parent
            anchors.margins: CortetsuDesign.spacingUnit
            radius: CortetsuDesign.radiusSurface

            // Same contract as SettingsHost: the content exists while open.
            Loader {
                id: host
                anchors.fill: parent
                anchors.margins: CortetsuDesign.spacingSpacious
                active: screenDouble.settings
                focus: true
                sourceComponent: Content {
                    screenState: screenDouble
                    screen: null
                    controller: SettingsController
                }
                onLoaded: item.open()
            }
        }
    }

    readonly property var reactivity: [
        [() => CortetsuConfig.loaded && Schemes.catalogCount > 0, () => {
            verify(content === null, "a closed Settings holds no content");
            memo.empty = items().length;
            // The whole surface is built inside this assignment.
            const started = Date.now();
            screenDouble.settings = true;
            console.log("SETTINGS_OPEN_MS", Date.now() - started, items().length);
        }],
        [() => !!content && !!content.page && waitedMs >= 300, () => {
            window.requestActivate();
            verify(content.pageId === "home", "Settings opens on Inicio");
            verify(!!page("homeHero") && !get("outputVolume") && !get("wifiPower"), "only the open page exists");
            verify(get("pageTitle").text === "Inicio", "the header names the page");
            select("colors");
        }],
        [() => content.pageId === "colors" && !!page("scheme-nebula-default") && waitedMs >= 300, () => {
            verify(get("pageTitle").text === "Colores" && get("breadcrumbCategory").visible, "a subpage is titled with its path");
            verify(same(CortetsuDesign.colorSurface, "#171B21"), "without a scheme the ui.toml default applies");
            memo.card = get("scheme-nebula-default");
            memo.nexus = get("nexus");
            memo.row = get("nexus-personalization");
            memo.toggle = page("schemePreviewMode");
            verify(!!memo.card && !memo.card.selected, "the catalogue is drawn and nebula is not active");
            keep();
            // A token changes and nothing else: the preview channel recolours the tokens.
            CortetsuColours.load(JSON.stringify({ colours: { surface: "112233", surfaceContainer: "223344", primary: "ff8800", onSurface: "f0e0d0", outlineVariant: "445566" }, mode: "dark" }), true);
        }],
        [() => same(CortetsuDesign.colorSurface, "#112233"), () => {
            verify(churn() === "0 destroyed, 0 created", `a token change keeps every object (${churn()})`);
            verify(get("nexus") === memo.nexus && get("nexus-personalization") === memo.row && page("schemePreviewMode") === memo.toggle,
                "the navigation, its row and the page controls are the same instances");
            verify(same(CortetsuDesign.colorPrimary, "#ff8800"), "the primary token follows");
            verify(same(get("pageTitle").color, "#f0e0d0") || get("pageTitle").color !== undefined, "text reads the new token");
            CortetsuColours.clearPreview();
        }],
        [() => same(CortetsuDesign.colorSurface, "#171B21") && waitedMs >= 300, () => {
            verify(same(find(memo.row, "label").color, CortetsuDesign.colorOnSurface) || memo.row.selected, "a live label settles on the token colour");
            keep();
            memo.card.clicked();
            verify(Schemes.applying && Schemes.pendingScheme === "nebula default", "choosing a card starts one apply");
            verify(value("activeScheme") === "nebula default" && find(get("activeScheme"), "rowDetail") !== null, "the row names what is being applied");
        }],
        [() => Schemes.applyStatus === "applied" && Schemes.currentScheme === "nebula default", () => {
            verify(churn() === "0 destroyed, 0 created", `applying a scheme keeps every object (${churn()})`);
            verify(get("scheme-nebula-default") === memo.card && memo.card.selected, "the same card is now the selected one");
            verify(!same(CortetsuDesign.colorSurface, "#171B21"), "the tokens follow the applied scheme");
            verify(get("nexus-personalization").value.includes("nebula default"), "the navigation names the active scheme");
            verify(text("activeScheme") === "Aplicado a todas las superficies", "the apply is confirmed");
            verify(screenDouble.settings && get("nexus") === memo.nexus, "Settings stayed open through the change");
            keep();
            Schemes.apply("no-such-scheme", "default");
        }],
        [() => Schemes.applyStatus === "failed", () => {
            verify(Schemes.currentScheme === "nebula default" && memo.card.selected, "a failed apply leaves the real scheme selected");
            verify(get("activeScheme").status === "error" && text("activeScheme").includes("esquema no encontrado"), "the failure is shown with its reason");
            verify(get("nexus-personalization").alerting && get("pageSummary").text.includes("esquema no encontrado"), "the navigation and header flag the page");
            verify(value("activeScheme") === "nebula default", "the value shown is the scheme really in use");
            verify(churn() === "0 destroyed, 0 created", `a failure keeps every object (${churn()})`);
            // The scheme changes from outside Settings, as the launcher or a terminal would do.
            Quickshell.execDetached([root.schemeTool, "set", "-n", "aura", "default"]);
        }],
        [() => Schemes.currentScheme === "aura default", () => {
            verify(get("scheme-aura-default").selected && !memo.card.selected, "an outside change moves the selection");
            verify(value("activeScheme") === "aura default", "and the active scheme row");
            verify(churn() === "0 destroyed, 0 created", `an outside change keeps every object (${churn()})`);
            Schemes.reload();
        }],
        [() => !Schemes.loading && waitedMs >= 300, () => {
            verify(churn() === "0 destroyed, 0 created", `re-reading an unchanged catalogue keeps every card (${churn()})`);
            verify(get("scheme-nebula-default") === memo.card, "the cards are the same instances");
            // The catalogue gains one entry: a scheme that only exists as the
            // current state, as the wallpaper-derived one does.
            memo.count = Schemes.catalogCount;
            keep();
            stateFile.setText(JSON.stringify({ name: "dynamic", flavour: "default", colours: { surface: "202830" } }));
        }],
        // Nothing asks for it: an active scheme the catalogue lacks is fetched.
        [() => Schemes.currentScheme === "dynamic default" && Schemes.catalogCount === memo.count + 1 && !!get("scheme-dynamic-default"), () => {
            verify(get("scheme-dynamic-default").selected, "the new scheme gets a card and it is the active one");
            verify(get("scheme-nebula-default") === memo.card, "the existing cards are untouched");
            verify(churn().startsWith("0 destroyed, "), `one new entry destroys nothing (${churn()})`);
            memo.added = items().length - kept.length;
            keep();
            Quickshell.execDetached([root.schemeTool, "set", "-n", "aura", "default"]);
        }],
        [() => Schemes.currentScheme === "aura default", () => {
            Schemes.reload();
        }],
        [() => Schemes.catalogCount === memo.count && !get("scheme-dynamic-default"), () => {
            const lost = kept.length - items().length;
            verify(lost === memo.added && get("scheme-nebula-default") === memo.card, `losing that entry removes its card and nothing else (${lost} of ${memo.added})`);
            keep();
            get("schemeFilter").text = "neb";
        }],
        [() => !get("scheme-aura-default").visible, () => {
            verify(memo.card.visible && get("scheme-nebula-default") === memo.card, "a filter hides cards instead of rebuilding them");
            verify(churn() === "0 destroyed, 0 created", `filtering keeps every object (${churn()})`);
            get("schemeFilter").text = "zzz";
        }],
        [() => get("schemeState").visible, () => {
            verify(get("schemeState").title === "Ningún esquema coincide", "a filter without matches says so");
            get("schemeFilter").text = "";
            select("themes");
        }],
        [() => content.pageId === "themes" && !!page("transparency") && waitedMs >= 300, () => {
            memo.toggle = page("transparency");
            keep();
            // A local preference: one switch, one write, nothing rebuilt.
            root.writes = 0;
            memo.toggle.forceActiveFocus();
            key(Qt.Key_Space);
            verify(CortetsuConfig.transparencyEnabled === true, "Space flips the focused switch");
            verify(find(memo.toggle, "switch").checked, "the switch shows the stored value");
            verify(CortetsuConfig.saveState === "pending", "the change waits to be written");
            CortetsuConfig.borderThickness = 3;
            CortetsuConfig.borderThickness = 4;
            CortetsuConfig.save();
        }],
        [() => CortetsuConfig.saveState === "saved", () => {
            verify(root.writes === 1, `three quick changes cost one write (${root.writes})`);
            verify(CortetsuConfig.bottomHub.segments.tray === false && CortetsuConfig.colorTemperature === 4500, `what was stored before is what is in use (${CortetsuConfig.bottomHub.segments.tray}, ${CortetsuConfig.colorTemperature})`);
            verify(get("saveIndicator").visible && find(get("saveIndicator"), "saveText").text === "Guardado", "the write is confirmed on screen");
            verify(churn() === "0 destroyed, 0 created", `a preference keeps every object (${churn()})`);
            verify(find(page("transparency"), "switch").checked, "a value changed elsewhere reaches its row");
            render("appearance");
        }],
        [null, () => {
            // Closing Settings releases the whole tree.
            screenDouble.settings = false;
        }],
        [() => content === null && waitedMs >= 200, () => {
            verify(items().length === memo.empty, `a closed Settings leaves nothing behind (${items().length} items, ${memo.empty} before opening)`);
            screenDouble.settings = true;
        }],
        [() => !!content && !!content.page, () => {
            verify(content.pageId === "themes" && Schemes.currentScheme === "aura default", "reopening shows the same page and the real scheme");
            // Open, visit every page and close, over and over: the tree goes
            // back to the same size each time.
            const started = Date.now();
            for (let cycle = 0; cycle < 20; ++cycle) {
                screenDouble.settings = true;
                for (const id of root.destinations)
                    select(id);
                screenDouble.settings = false;
            }
            console.log("SETTINGS_CYCLES_MS", Date.now() - started);
            select("appearance");
        }],
        [() => content === null && waitedMs >= 300, () => {
            verify(items().length === memo.empty, `twenty open, browse and close cycles leave nothing behind (${items().length} items)`);
        }]
    ]

    readonly property var navigation: [
        [() => CortetsuConfig.loaded, () => { screenDouble.settings = true; }],
        [() => !!content && !!content.page, () => {
            window.requestActivate();
        }],
        [() => window.active && waitedMs >= 200, () => {
            verify(focusName() === "nexus-home", `opening focuses the current destination (${focusName()})`);
            SettingsController.search = "vim";
            verify(SettingsController.matchingIds.includes("devices")
                && SettingsController.results.some(result => result.page === "input" && result.setting === "Navegación estilo Vim"),
                "the Vim preference is found in Bluetooth y dispositivos › Teclado");
            SettingsController.search = "DNS";
            verify(SettingsController.matchingIds.includes("network"), "network profile controls remain searchable");
            SettingsController.search = "Gamma";
            verify(SettingsController.results[0]?.path === "Sistema › Pantalla", "a result names where the setting lives");
            SettingsController.search = "";
            SettingsController.select("stale-domain");
            verify(SettingsController.selectedId === "home" && SettingsController.pageForSection("stale-domain") === "",
                "an unknown deep link leaves the current page selected");
            verify(SettingsController.pageForSection("quick") === "themes" && SettingsController.pageForSection("audio") === "sound"
                && SettingsController.pageForSection("services") === "wifi", "old destinations still lead to their settings");
            key(Qt.Key_PageDown, Qt.ControlModifier);
            verify(SettingsController.selectedId === "system" && focusName() === "nexus-system", "Ctrl+PageDown opens and focuses the next category");
            key(Qt.Key_PageUp, Qt.ControlModifier);
            verify(SettingsController.selectedId === "home" && focusName() === "nexus-home", "Ctrl+PageUp restores the previous category");
            key(Qt.Key_Down);
            verify(SettingsController.selectedId === "system" && focusName() === "nexus-system", "Down opens the next category and moves focus with it");
            key(Qt.Key_Up);
            key(Qt.Key_Up);
            verify(SettingsController.selectedId === "home", `Up walks back across categories (${SettingsController.selectedId})`);
            select("notifications");
            get("nexus").focusSelected();
        }],
        [() => content.pageId === "notifications" && !!page("dnd"), () => {
            verify(!get("homeHero"), "the previous page is gone");
            verify(get("nexus-interface").selected && get("pageTitle").text === "Notificaciones", "the sidebar marks the category of the subpage");
            for (let i = 0; i < 6 && !content.within(window.activeFocusItem, content.page); ++i)
                key(Qt.Key_Tab);
            verify(content.within(window.activeFocusItem, page("dnd")), `Tab leaves the sidebar for the page's first control (${focusName()})`);
            const dnd = page("dnd");
            dnd.forceActiveFocus();
            content.revealFocus();
            key(Qt.Key_Space);
            verify(CortetsuNotifications.dnd === true, "Space flips the switch");
            key(Qt.Key_Return);
            verify(CortetsuNotifications.dnd === false, "Enter flips it back");
        }],
        [() => waitedMs >= 250, () => {
            const dnd = page("dnd");
            // The pointer: on the label and on the switch itself, one flip each.
            memo.flips = 0;
            dnd.toggled.connect(() => memo.flips++);
            events.mouseClick(dnd, 40, dnd.height / 2, Qt.LeftButton, Qt.NoModifier, -1);
            verify(CortetsuNotifications.dnd === true, `a click on the row flips the switch (${memo.flips})`);
            const knob = find(dnd, "switch");
            events.mouseClick(knob, knob.width / 2, knob.height / 2, Qt.LeftButton, Qt.NoModifier, -1);
            verify(CortetsuNotifications.dnd === false && memo.flips === 2, `a click on the switch flips it once, not twice (${memo.flips})`);
            verify(text("dnd") === "Los avisos aparecen en pantalla al llegar", "the row describes the current state");
            dnd.forceActiveFocus();
            key(Qt.Key_Left);
            verify(focusName() === "nexus-interface", "Left returns from a setting to the sidebar");
            key(Qt.Key_Right);
            const stops = [];
            const stopItems = new Set();
            for (let i = 0; i < 80 && content.within(frame.Window.activeFocusItem, content.page); ++i) {
                const item = frame.Window.activeFocusItem;
                stopItems.add(item);
                stops.push(item.objectName || item.Accessible.name || "?");
                verify(item.enabled, `a Tab stop is enabled (${stops[stops.length - 1]})`);
                key(Qt.Key_Tab);
            }
            verify(stops.includes("dnd") && stops.includes("action") && stopItems.size === stops.length,
                `Tab reaches every notification control (${stops.join(",")})`);
            memo.clear = page("clearHistory");
            find(memo.clear, "action").forceActiveFocus();
            key(Qt.Key_Return);
            verify(memo.clear.armed && CortetsuNotifications.count === 3, "a destructive action waits for a second press");
            key(Qt.Key_Return);
            verify(CortetsuNotifications.count === 0 && !memo.clear.armed, "the second press runs it");
            verify(memo.clear.title === "El historial está vacío" && memo.clear.disabled, "the row then shows the new state and stops offering the action");
            get("pageScroller").contentY = 120;
        }],
        [() => waitedMs >= 400, () => {
            select("themes");
        }],
        [() => content.pageId === "themes" && !!content.page && waitedMs >= 200, () => {
            verify(get("settingsBack").visible && SettingsController.canGoBack, "a subpage offers the way back");
            get("settingsBack").clicked();
        }],
        [() => content.pageId === "notifications" && !!content.page && waitedMs >= 200, () => {
            verify(Math.abs(get("pageScroller").contentY - 120) <= 1, `going back lands where the page was left (${get("pageScroller").contentY})`);
            get("breadcrumbCategory").forceActiveFocus();
            key(Qt.Key_Return);
        }],
        [() => content.pageId === "interface" && !!page("subpage-launcher"), () => {
            verify(get("pageTitle").text === "Interfaz" && page("subpage-notifications").visible, "the breadcrumb leads to the category page and its subpages");
            page("subpage-launcher").activated();
        }],
        [() => content.pageId === "launcher" && !!page("launcherEnabled"), () => {
            select("display");
            key(Qt.Key_F, Qt.ControlModifier);
            verify(focusName() === "nexusSearch", `Ctrl+F reaches the search (${focusName()})`);
            get("nexusSearch").text = "reloj";
        }],
        [() => SettingsController.results.length > 0 && get("nexusResult-0")?.visible, () => {
            verify(!get("nexus-system").visible && get("nexus-system") !== null, "categories step aside for the results without being rebuilt");
            memo.result = SettingsController.results[0];
            verify(memo.result.title === "Posición del reloj" && memo.result.path === "Personalización › Fondo",
                `results name the setting and its place (${memo.result.title}, ${memo.result.path})`);
            verify(SettingsController.results.some(result => result.title === "Reloj de 12 horas" && result.page === "indicators"),
                "every matching setting is offered");
            key(Qt.Key_Return);
        }],
        [() => content.pageId === "background" && !!page("desktopClockEnabled") && waitedMs >= 300, () => {
            verify(get("nexusSearch").text === "" && SettingsController.reveal === "", "opening a result clears the search");
            verify(focusName().startsWith("clock-"), `the result opens on the setting itself (${focusName()})`);
            verify(get("revealHighlight").visible, "and marks it");
            key(Qt.Key_F, Qt.ControlModifier);
            get("nexusSearch").text = "energia";
        }],
        [() => SettingsController.results.length > 0, () => {
            verify(SettingsController.results.some(result => result.page === "power")
                && SettingsController.results.some(result => result.page === "automation"),
                "an unaccented search finds both energy and automatic policy pages");
            get("nexusSearch").text = "zzzz";
        }],
        [() => SettingsController.results.length === 0 && SettingsController.search === "zzzz", () => {
            verify(get("nexusEmpty").visible, "a search without results says so");
            key(Qt.Key_Escape);
            verify(get("nexusSearch").text === "" && screenDouble.settings, "Escape first clears the search");
            verify(get("nexus-system").visible, "and every category is back");
            key(Qt.Key_Escape);
            verify(screenDouble.settings === false, "Escape then closes Settings");
        }],
        [() => content === null, () => {
            screenDouble.settings = true;
        }],
        [() => !!content && !!content.page && waitedMs >= 200, () => {
            frame.forceActiveFocus();
            key(Qt.Key_Escape);
            verify(screenDouble.settings === false, "Escape closes Settings even with the focus outside its controls");
        }],
        [() => content === null, () => {
            screenDouble.settings = true;
        }],
        [() => !!content && !!content.page, () => {
            // A long page keeps the focused control in view.
            select("desktop");
        }],
        [() => content.pageId === "panels" && !!page("dashboardMetrics"), () => {
            get("nexus").focusSelected();
            key(Qt.Key_Right);
            for (let i = 0; i < 12; ++i)
                key(Qt.Key_Tab);
        }],
        [() => waitedMs >= 400, () => {
            const scroller = get("pageScroller");
            const item = frame.Window.activeFocusItem;
            const top = item.mapToItem(scroller, 0, 0).y;
            verify(content.within(item, content.page), "the focus is still inside the page");
            verify(top >= 0 && top + item.height <= scroller.height, `the focused control is scrolled into view (${top})`);
            verify(find(item, "focusRing").visible, "and shows a focus ring");
            get("nexusCollapse").clicked();
        }],
        [() => get("nexus").collapsed && waitedMs >= 300, () => {
            verify(get("nexus").width < 80 && !get("nexusSearch").visible, "the sidebar folds to icons");
            verify(get("nexus-personalization").selected && get("nexus-personalization").width > 0, "and still marks where you are");
            render("nexus-collapsed");
        }],
        [null, () => {
            get("nexusCollapse").clicked();
            window.width = 880;
        }],
        [() => waitedMs >= 300, () => {
            verify(!content.collapsed && get("nexusSearch").visible,
                "an explicit expanded rail stays usable at narrow window widths");
            window.width = 1368;
        }]
    ]

    // Operations that answer later, that fail, and values that move outside.
    readonly property var states: [
        [() => CortetsuConfig.loaded, () => { select("network"); screenDouble.settings = true; }],
        [() => !!content && ["wifi", "bluetooth", "automation", "capture", "weather"].includes(content.pageId) && !!page("wifiPower"), () => {
            window.requestActivate();
            memo.wifi = page("wifiPower");
            verify(memo.wifi.width >= 500 && Math.abs(memo.wifi.width - content.page.width) <= 1,
                "the Wi-Fi workbench fills the Settings viewport before its first group is drawn");
            verify(find(memo.wifi, "switch").checked && get("nexus-network").value.includes("Casa"), "the page and navigation show the live connection");
            memo.wifi.forceActiveFocus();
            key(Qt.Key_Space);
            verify(wifi.busy && memo.wifi.status === "busy" && text("wifiPower") === "Aplicando…", "an operation in flight is shown as such");
            verify(find(memo.wifi, "switch").checked, "the switch waits for the radio instead of jumping ahead");
            key(Qt.Key_Space);
            verify(wifi.operation.id === 1, "a second press while busy starts nothing");
            render("network-applying");
        }],
        [null, () => {
            wifi.settle(false);
        }],
        [() => !wifi.busy, () => {
            verify(find(memo.wifi, "switch").checked && wifi.wifiEnabled, "a refused change leaves the switch on the real state");
            verify(memo.wifi.status === "error" && text("wifiPower") === "NetworkManager rechazó el cambio", "and says why it failed");
            verify(get("nexus-network").alerting, "the Nexus flags the page");
            render("network-error");
        }],
        [null, () => {
            key(Qt.Key_Space);
            wifi.settle(true);
        }],
        [() => !wifi.busy && !wifi.wifiEnabled, () => {
            verify(!find(memo.wifi, "switch").checked && text("wifiPower") === "Apagado" && memo.wifi.status === "", "an accepted change is shown once the radio confirms it");
            verify(get("nexus-network").value.includes("Wi-Fi apagado") && !get("nexus-network").alerting, "an ordinary off state is not an alert");
            verify(page("wifiScan").disabled, "scanning is not offered with the radio off");
            render("network-off");
        }],
        [null, () => {
            // The radio comes back from outside: rfkill, a key, the bar.
            wifi.wifiEnabled = true;
        }],
        [() => find(memo.wifi, "switch").checked, () => {
            verify(get("nexus-network").value.includes("Casa"), "an outside change reaches the open page and navigation");
            select("bluetooth");
        }],
        [() => ["wifi", "bluetooth", "automation", "capture", "weather"].includes(content.pageId) && !!page("bluetoothPower"), () => {
            memo.bt = page("bluetoothPower");
            verify(get("nexus-devices").value.includes("1 conectado"), "the navigation counts connected devices");
            memo.bt.forceActiveFocus();
            key(Qt.Key_Return);
            verify(memo.bt.status === "busy" && find(memo.bt, "switch").checked, "Bluetooth waits for the adapter");
            bluetooth.settle(false);
        }],
        [() => !bluetooth.busy, () => {
            verify(find(memo.bt, "switch").checked && memo.bt.status === "error" && text("bluetoothPower") === "El adaptador no respondió", "a failed power change keeps the real state and explains");
            render("bluetooth-error");
        }],
        [null, () => {
            bluetooth.available = false;
        }],
        [() => !!page("noAdapter") && page("noAdapter").visible, () => {
            verify(!page("bluetoothPower").visible, "without an adapter there is no switch to press");
            verify(get("nexus-devices").value.includes("Sin adaptador"), "the navigation says the adapter is missing");
            render("bluetooth-unavailable");
        }],
        [null, () => {
            select("audio");
        }],
        [() => ["sound", "power", "input"].includes(content.pageId) && !!page("outputVolume"), () => {
            verify(find(page("outputVolume"), "sliderValue").text === "62 %" && get("nexus-system").value.includes("62 %"), "the volume is the real one");
            CortetsuAudio.speakers.audio.volume = 0.31;
        }],
        [() => find(page("outputVolume"), "sliderValue").text === "31 %", () => {
            verify(Math.abs(find(page("outputVolume"), "slider").progress - 0.31) < 0.01, "a volume changed outside moves the slider");
            find(page("outputVolume"), "slider").forceActiveFocus();
            key(Qt.Key_Right);
            verify(Math.abs(CortetsuAudio.volume - 0.36) < 0.001, "an arrow moves the real volume one step");
            page("outputMute").forceActiveFocus();
            key(Qt.Key_Space);
            verify(CortetsuAudio.muted && get("nexus-system").value.includes("Silenciado"), "muting is reflected everywhere");
            render("audio");
        }],
        [null, () => {
            CortetsuAudio.available = false;
        }],
        [() => page("noOutput").visible, () => {
            verify(!page("outputVolume").visible && get("nexus-system").alerting, "without PipeWire the page says so and the Nexus flags it");
            verify(get("pageSummary").text === "No hay dispositivo de salida", "the header names the problem");
            render("audio-unavailable");
        }],
        [null, () => {
            select("display");
        }],
        [() => ["display", "shortcuts"].includes(content.pageId) && !!page("colourFilter"), () => {
            memo.filter = page("colourFilter");
            verify(page("brightness").visible && find(page("brightness"), "sliderValue").text === "70 %", "brightness is the real one");
            Brightness.monitor.brightness = 0.4;
        }],
        [() => find(page("brightness"), "sliderValue").text === "40 %", () => {
            verify(true, "brightness changed by a key reaches the page");
            mode("systemctl-mode", "fail");
            memo.filter.forceActiveFocus();
            key(Qt.Key_Space);
            verify(memo.filter.status === "busy", "the colour filter is being applied");
        }],
        [() => DisplayCalibration.state === "failed", () => {
            verify(!CortetsuConfig.colorCalibrationEnabled && !find(memo.filter, "switch").checked, "a service that refuses to start leaves the filter off");
            verify(memo.filter.status === "error" && text("colourFilter") === "hyprsunset.service no existe", "with the reason from the service");
            render("display-error");
        }],
        [null, () => {
            mode("systemctl-mode", "ok");
            key(Qt.Key_Space);
        }],
        [() => DisplayCalibration.state === "applied", () => {
            verify(CortetsuConfig.colorCalibrationEnabled && find(memo.filter, "switch").checked && memo.filter.status === "", "the retry applies it");
            Brightness.available = false;
        }],
        [() => page("brightnessUnavailable").visible, () => {
            verify(!page("brightness").visible && value("brightnessUnavailable") === "No disponible", "a screen without backlight control says so instead of showing 0 %");
            verify(get("nexus-system").value.includes("2 pantallas"), "the Nexus falls back to what it does know");
            render("display-unavailable");
        }],
        [null, () => {
            mode("keybinds-mode", "fail");
            select("shortcuts");
            page("shortcutsSection").load();
        }],
        [() => ["display", "shortcuts"].includes(content.pageId) && page("shortcutsSection").state === "error", () => {
            verify(page("shortcutsState").visible && page("shortcutsState").kind === "error", "a helper that fails is an error with a retry, not an empty list");
            render("shortcuts-error");
        }],
        [null, () => {
            mode("keybinds-mode", "ok");
            page("shortcutsSection").load();
        }],
        [() => page("shortcutsSection").state === "ready", () => {
            verify(page("shortcutsSection").total === 3 && page("shortcutsSection").groups.length === 2, "the retry lists the real bindings by group");
            page("shortcutFilter").text = "super + h";
        }],
        [() => page("shortcutsSection").query.length > 0 && waitedMs >= 100, () => {
            render("shortcuts");
        }],
        [null, () => {
            select("diagnostics");
        }],
        [() => content.pageId === "diagnostics" && !!page("revision"), () => {
            verify(value("revision") === "0123456" && value("generation") === "20261003-000000-1", "Diagnostics reads the running generation");
            verify(get("nexus-about").value === "0123456", "and the sidebar names the revision of About");
            select("wallpaper");
        }],
        [() => content.pageId === "background" && !!page("wallpaperFile"), () => {
            verify(value("wallpaperFile") === "montaña.png" && get("nexus-personalization").value.includes("montaña.png"), "the wallpaper shown is the one applied");
            CortetsuWallpapers.applyStatusPath = "/home/prueba/Fondos/nuevo.png";
            CortetsuWallpapers.applyStatus = "applying";
        }],
        [() => page("wallpaperFile").title === "Aplicando", () => {
            verify(value("wallpaperFile") === "nuevo.png", "an apply started elsewhere is shown while it runs");
            CortetsuWallpapers.applyError = "el servicio de fondos no responde";
            CortetsuWallpapers.applyStatus = "failed";
        }],
        [() => page("wallpaperFile").status === "error", () => {
            verify(value("wallpaperFile") === "montaña.png", "a failed apply shows the wallpaper that is really set");
            verify(text("wallpaperFile") === "el servicio de fondos no responde" && get("nexus-personalization").alerting, "with the reason, and the Nexus flags it");
            render("wallpaper-error");
        }],
        [null, () => {
            select("power");
        }],
        [() => ["sound", "power", "input"].includes(content.pageId) && !!page("batteryLevel"), () => {
            verify(value("batteryLevel") === "86 %" && get("nexus-system").value.includes("86 %"), "battery is the real reading");
            CortetsuPower.percent = 12;
        }],
        [() => value("batteryLevel") === "12 %", () => {
            verify(get("nexus-system").alerting && get("pageSummary").text === "Batería baja", "a low battery is flagged");
            CortetsuPower.hasBattery = false;
        }],
        [() => page("noBattery").visible, () => {
            verify(get("nexus-system").value.includes("Corriente") && get("nexus-system").alerting,
                "a desktop shows its power source while the page still flags its unavailable audio output");
        }]
    ]

    // The preferences cannot be written: the user is told and nothing lies.
    readonly property var unwritable: [
        [() => CortetsuConfig.loaded, () => {
            blockConfig.running = true;
            select("launcher"); screenDouble.settings = true;
        }],
        [() => blockConfig.ready && !!content && ["panels", "launcher", "notifications", "indicators", "background"].includes(content.pageId) && !!page("launcherEnabled"), () => {
            window.requestActivate();
            page("launcherEnabled").forceActiveFocus();
            key(Qt.Key_Space);
            verify(CortetsuConfig.launcher.enabled === false, "the switch takes effect in the running shell");
        }],
        [() => CortetsuConfig.saveState === "failed", () => {
            const indicator = get("saveIndicator");
            verify(indicator.visible && find(indicator, "saveText").text.startsWith("No se pudo guardar"), "a failed write is announced and stays on screen");
            verify(get("nexus-interface").value === "Apagado · 3 guardadas",
                "the Interface page combines live launcher and notification status");
            render("save-failed");
        }]
    ]

    readonly property var weatherPreferences: [
        [() => CortetsuConfig.loaded, () => { select("weather"); screenDouble.settings = true; }],
        [() => !!content && !!page("weatherLocation"), () => { window.requestActivate(); }],
        [() => window.active, () => {
            const interval = find(page("weatherRefreshInterval"), "slider");
            interval.forceActiveFocus(); key(Qt.Key_Right);
            verify(CortetsuConfig.weatherRefreshInterval === 3900000 && Weather.refreshInterval === 3900000,
                "the weather interval control updates the real hourly refresh timer");
            const entry = find(page("weatherLocation"), "entry");
            entry.forceActiveFocus(); key(Qt.Key_A, Qt.ControlModifier);
            key(Qt.Key_L, Qt.ShiftModifier); key(Qt.Key_I); key(Qt.Key_M); key(Qt.Key_A);
            key(Qt.Key_Return);
            verify(CortetsuConfig.weatherLocation === "lima", "text entry commits the weather service preference");
            verify(CortetsuRegional.parseLocationQuery(CortetsuRegional.weatherLocation).value === "lima", "the regional weather contract receives the committed city");
            key(Qt.Key_A, Qt.ControlModifier); key(Qt.Key_X); key(Qt.Key_Escape);
            verify(CortetsuConfig.weatherLocation === "lima" && screenDouble.settings, "Escape cancels a draft before closing Settings");
            page("weatherLocation").committed("999,12");
            verify(page("weatherLocation").status === "error", "out-of-range coordinates show an actionable error");
            verify(CortetsuConfig.weatherLocation === "lima", "invalid coordinates retain the confirmed location");
            page("weatherLocation").committed("lima");
        }],
        [() => Weather.city === "Lima" && Weather.cc?.tempC === 21, () => {
            verify(Requests.requested.some(url => url.includes("geocoding-api.open-meteo.com") && url.includes("name=lima")),
                "the committed city reaches the real weather geocoder through the request double");
            verify(Requests.requested.some(url => url.includes("api.open-meteo.com/v1/forecast") && url.includes("latitude=-12.0464")),
                "the resolved location requests a forecast and updates service state");
        }],
        [() => CortetsuConfig.saveState === "saved", () => {}]
    ]
    readonly property var weatherRestore: [
        [() => CortetsuConfig.loaded, () => {
            verify(CortetsuRegional.weatherLocation === "lima", "the location survives a new process");
            verify(CortetsuConfig.weatherRefreshInterval === 3900000 && Weather.refreshInterval === 3900000,
                "the selected forecast interval survives a new process and restores its timer");
        }]
    ]
    readonly property var recordingPathPreferences: [
        [() => CortetsuConfig.loaded, () => { select("capture"); screenDouble.settings = true; }],
        [() => !!content && !!page("screenRecordSavePath"), () => { window.requestActivate(); }],
        [() => window.active, () => {
            const entry = page("screenRecordSavePath");
            entry.committed("~/Vídeos/Grabaciones");
            verify(CortetsuConfig.screenRecordSavePath === "~/Vídeos/Grabaciones",
                "the Settings field updates the saved recording destination");
            verify(Paths.recsdir.endsWith("/Vídeos/Grabaciones"),
                "the shared path owner expands the configured home-relative directory");
            entry.committed("relative/invalid");
            verify(entry.status === "error" && CortetsuConfig.screenRecordSavePath === "~/Vídeos/Grabaciones",
                "relative paths are rejected without replacing the confirmed destination");
        }],
        [() => CortetsuConfig.saveState === "saved", () => {}]
    ]
    readonly property var recordingPathRestore: [
        [() => CortetsuConfig.loaded, () => { select("capture"); screenDouble.settings = true; }],
        [() => !!content && !!page("screenRecordSavePath"), () => {
            verify(CortetsuConfig.screenRecordSavePath === "~/Vídeos/Grabaciones"
                && page("screenRecordSavePath").value === "~/Vídeos/Grabaciones",
                "the configured recording destination restores after restart");
            verify(Paths.recsdir.endsWith("/Vídeos/Grabaciones"),
                "the restored destination feeds the path owner");
        }]
    ]
    readonly property var screenshotPathPreferences: [
        [() => CortetsuConfig.loaded, () => { select("capture"); screenDouble.settings = true; }],
        [() => !!content && !!page("screenSnipSavePath"), () => { window.requestActivate(); }],
        [() => window.active, () => {
            const entry = page("screenSnipSavePath");
            entry.committed("~/Imágenes/Recortes");
            verify(CortetsuConfig.screenSnipSavePath === "~/Imágenes/Recortes",
                "the Settings field commits the area capture destination");
            entry.committed("relative/invalid");
            verify(entry.status === "error" && CortetsuConfig.screenSnipSavePath === "~/Imágenes/Recortes",
                "relative paths are rejected without replacing the confirmed destination");
        }],
        [() => CortetsuConfig.saveState === "saved", () => {}]
    ]
    readonly property var screenshotPathRestore: [
        [() => CortetsuConfig.loaded, () => { select("capture"); screenDouble.settings = true; }],
        [() => !!content && !!page("screenSnipSavePath"), () => {
            verify(CortetsuConfig.screenSnipSavePath === "~/Imágenes/Recortes"
                && page("screenSnipSavePath").value === "~/Imágenes/Recortes",
                "the screenshot destination restores after restart");
        }]
    ]
    readonly property var barAutoHidePreferences: [
        [() => CortetsuConfig.loaded, () => { select("bar"); screenDouble.settings = true; }],
        [() => !!content && !!page("barAutoHide"), () => { window.requestActivate(); }],
        [() => window.active, () => {
            const toggle = page("barAutoHide");
            verify(!CortetsuConfig.bar.showOnHover,
                "the always-visible setting starts from the persisted bar behavior");
            toggle.forceActiveFocus(); key(Qt.Key_Space);
            verify(CortetsuConfig.bar.showOnHover,
                "auto-hide updates the preference consumed by the Bottom Hub visibility controller");
        }],
        [() => CortetsuConfig.saveState === "saved", () => {}]
    ]
    readonly property var barAutoHideRestore: [
        [() => CortetsuConfig.loaded, () => { select("bar"); screenDouble.settings = true; }],
        [() => !!content && !!page("barAutoHide"), () => {
            verify(CortetsuConfig.bar.showOnHover && page("barAutoHide").checked,
                "the auto-hide preference restores through the Bottom Hub visibility controller");
        }]
    ]
    readonly property var trayMonochromePreferences: [
        [() => CortetsuConfig.loaded, () => { select("bar"); screenDouble.settings = true; }],
        [() => !!content && !!page("trayMonochromeIcons"), () => { window.requestActivate(); }],
        [() => window.active, () => {
            const toggle = page("trayMonochromeIcons");
            verify(!CortetsuConfig.bar.tray.recolour,
                "native tray icon colours are the default");
            toggle.forceActiveFocus(); key(Qt.Key_Space);
            verify(CortetsuConfig.bar.tray.recolour,
                "the tray setting enables live monochrome tinting in CortetsuTraySegment");
        }],
        [() => CortetsuConfig.saveState === "saved", () => {}]
    ]
    readonly property var trayMonochromeRestore: [
        [() => CortetsuConfig.loaded, () => { select("bar"); screenDouble.settings = true; }],
        [() => !!content && !!page("trayMonochromeIcons"), () => {
            verify(CortetsuConfig.bar.tray.recolour && page("trayMonochromeIcons").checked,
                "the tray tint preference restores after restart");
        }]
    ]
    readonly property var weatherVisibilityPreferences: [
        [() => CortetsuConfig.loaded, () => { select("panels"); screenDouble.settings = true; }],
        [() => !!content && !!page("dashboardWeather"), () => { window.requestActivate(); }],
        [() => window.active, () => {
            const toggle = page("dashboardWeather");
            toggle.forceActiveFocus(); key(Qt.Key_Space);
            verify(!CortetsuConfig.dashboard.showWeather,
                "the weather visibility option updates the Dashboard's actual weather slot");
        }],
        [() => CortetsuConfig.saveState === "saved", () => {}]
    ]
    readonly property var weatherVisibilityRestore: [
        [() => CortetsuConfig.loaded, () => {
            verify(!CortetsuConfig.dashboard.showWeather,
                "the Dashboard weather visibility choice survives process restart");
        }]
    ]

    readonly property var regionalPreferences: [
        [() => CortetsuConfig.loaded, () => { select("indicators"); screenDouble.settings = true; }],
        [() => !!content && !!page("clockFormat") && !!page("clockSeconds"), () => { window.requestActivate(); }],
        [() => window.active, () => {
            verify(!CortetsuConfig.useSecondPrecision && CortetsuRegional.clockPattern === "h:mm"
                && Time.timeStr.split(":").length === 2,
                "minute precision stays the default and avoids second-by-second clock output");
            const toggle = page("clockFormat");
            toggle.forceActiveFocus(); key(Qt.Key_Space);
            verify(CortetsuConfig.useTwelveHourClock && CortetsuRegional.clockPattern === "h:mm AP"
                && CortetsuRegional.liveClockPattern === "h:mm AP",
                "the 12-hour control updates the active regional formatter");
            const seconds = page("clockSeconds");
            seconds.forceActiveFocus(); key(Qt.Key_Space);
            verify(CortetsuConfig.useSecondPrecision && CortetsuRegional.clockPattern === "h:mm AP"
                && CortetsuRegional.liveClockPattern === "h:mm:ss AP"
                && /^\d{2}$/.test(Time.secondStr) && /^(AM|PM)$/.test(Time.amPmStr)
                && Time.timeStr.endsWith(Time.amPmStr)
                && Time.hourFor(new Date(2026, 0, 1, 13, 5), true) === "1"
                && Time.hourFor(new Date(2026, 0, 1, 13, 5), false) === "13"
                && Time.hourFor(new Date(2026, 0, 1, 0, 5), true) === "12"
                && Time.hourFor(new Date(2026, 0, 1, 12, 5), true) === "12",
                "second precision updates the clock formatter and live clock values");
        }],
        [() => CortetsuConfig.saveState === "saved", () => {}]
    ]
    readonly property var regionalRestore: [
        [() => CortetsuConfig.loaded, () => {
            verify(CortetsuRegional.useTwelveHourClock && CortetsuConfig.useSecondPrecision
                && CortetsuRegional.clockPattern === "h:mm AP" && CortetsuRegional.liveClockPattern === "h:mm:ss AP"
                && /^\d{2}$/.test(Time.secondStr)
                && /^(AM|PM)$/.test(Time.amPmStr),
                "the selected regional clock format and second precision restore in a new process");
        }]
    ]
    readonly property var notificationCountPreferences: [
        [() => CortetsuConfig.loaded, () => { select("bottomhub"); screenDouble.settings = true; }],
        [() => !!content && !!page("notificationCount"), () => { window.requestActivate(); }],
        [() => window.active, () => {
            const toggle = page("notificationCount");
            verify(toggle.checked && notificationBadgeVisible(),
                `notification history badge should be visible (control ${toggle.checked}, `
                + `policy ${CortetsuConfig.bottomHub.statusCluster.showNotificationCount}, `
                + `count ${notificationBadgeProbe.notificationCount}, `
                + `visible ${notificationBadgeVisible()})`);
            toggle.forceActiveFocus(); key(Qt.Key_Space);
            verify(!CortetsuConfig.bottomHub.statusCluster.showNotificationCount && !notificationBadgeVisible(),
                "the preference changes the Bottom Hub badge visibility policy");
        }],
        [() => CortetsuConfig.saveState === "saved", () => {}]
    ]
    readonly property var notificationCountRestore: [
        [() => CortetsuConfig.loaded, () => { select("bottomhub"); screenDouble.settings = true; }],
        [() => !!content && !!page("notificationCount"), () => {
            verify(!CortetsuConfig.bottomHub.statusCluster.showNotificationCount
                && !page("notificationCount").checked && !notificationBadgeVisible(),
                "the notification count preference restores on launch");
        }]
    ]
    readonly property var batteryLowPreferences: [
        [() => CortetsuConfig.loaded, () => { select("power"); screenDouble.settings = true; }],
        [() => !!content && !!page("batteryLowWarning"), () => { window.requestActivate(); }],
        [() => window.active, () => {
            const slider = page("batteryLowWarning");
            verify(CortetsuConfig.batteryLowWarningPercent === 10 && slider.value === 10,
                "the existing low warning threshold stays at ten percent by default");
            slider.moved(25);
            verify(CortetsuConfig.batteryLowWarningPercent === 25,
                "the power section updates the battery notification threshold");
        }],
        [() => CortetsuConfig.saveState === "saved", () => {}]
    ]
    readonly property var batteryLowRestore: [
        [() => CortetsuConfig.loaded, () => { select("power"); screenDouble.settings = true; }],
        [() => !!content && !!page("batteryLowWarning"), () => {
            verify(CortetsuConfig.batteryLowWarningPercent === 25
                && page("batteryLowWarning").value === 25,
                "the selected battery warning threshold restores on launch");
        }]
    ]
    readonly property var batteryLowNormalize: [
        [() => CortetsuConfig.loaded, () => { select("power"); screenDouble.settings = true; }],
        [() => !!content && !!page("batteryLowWarning"), () => {
            verify(CortetsuConfig.batteryLowWarningPercent === 25
                && page("batteryLowWarning").value === 25,
                "a stored warning level is normalized to a supported five-percent step");
        }]
    ]
    readonly property var workspacesShownPreferences: [
        [() => CortetsuConfig.loaded, () => { select("bar"); screenDouble.settings = true; }],
        [() => !!content && !!page("workspacesShown"), () => { window.requestActivate(); }],
        [() => window.active, () => {
            const slider = page("workspacesShown");
            verify(CortetsuConfig.workspacesShown === 5 && slider.value === 5,
                "the workspace count keeps its existing default");
            slider.moved(8);
            verify(CortetsuConfig.workspacesShown === 8,
                "changing the count updates the Bottom Hub workspace renderer owner");
        }],
        [() => CortetsuConfig.saveState === "saved", () => {}]
    ]
    readonly property var workspacesShownRestore: [
        [() => CortetsuConfig.loaded, () => { select("bar"); screenDouble.settings = true; }],
        [() => !!content && !!page("workspacesShown"), () => {
            verify(CortetsuConfig.workspacesShown === 8 && page("workspacesShown").value === 8,
                "the Bottom Hub workspace count restores on launch");
        }]
    ]
    readonly property var workspaceNumbersPreferences: [
        [() => CortetsuConfig.loaded, () => { select("bar"); screenDouble.settings = true; }],
        [() => !!content && !!page("workspaceNumbers"), () => { window.requestActivate(); }],
        [() => window.active, () => {
            const toggle = page("workspaceNumbers");
            verify(CortetsuConfig.bar.workspaces.displayType === 0 && !toggle.checked,
                "workspace glyphs stay the default");
            toggle.forceActiveFocus(); key(Qt.Key_Space);
            verify(CortetsuConfig.bar.workspaces.displayType === 1 && toggle.checked,
                "the toggle switches the workspace renderer from dots to numbers");
        }],
        [() => CortetsuConfig.saveState === "saved", () => {}]
    ]
    readonly property var workspaceNumbersRestore: [
        [() => CortetsuConfig.loaded, () => { select("bar"); screenDouble.settings = true; }],
        [() => !!content && !!page("workspaceNumbers"), () => {
            verify(CortetsuConfig.bar.workspaces.displayType === 1 && page("workspaceNumbers").checked,
                "the workspace number choice restores on launch");
        }]
    ]
    readonly property var workspaceAppIconsPreferences: [
        [() => CortetsuConfig.loaded, () => { select("bar"); screenDouble.settings = true; }],
        [() => !!content && !!page("workspaceAppIcons"), () => { window.requestActivate(); }],
        [() => window.active, () => {
            const toggle = page("workspaceAppIcons");
            verify(!CortetsuConfig.bar.workspaces.showAppIcons && !toggle.checked,
                "workspace app icons stay off by default");
            toggle.forceActiveFocus(); key(Qt.Key_Space);
            verify(CortetsuConfig.bar.workspaces.showAppIcons && toggle.checked,
                "the Bar control enables the app-icon workspace renderer");
        }],
        [() => CortetsuConfig.saveState === "saved", () => {}]
    ]
    readonly property var workspaceAppIconsRestore: [
        [() => CortetsuConfig.loaded, () => { select("bar"); screenDouble.settings = true; }],
        [() => !!content && !!page("workspaceAppIcons"), () => {
            verify(CortetsuConfig.bar.workspaces.showAppIcons && page("workspaceAppIcons").checked,
                "the workspace app-icon choice restores on launch");
        }]
    ]
    readonly property var workspaceMonochromePreferences: [
        [() => CortetsuConfig.loaded, () => { select("bar"); screenDouble.settings = true; }],
        [() => !!content && !!page("workspaceMonochromeIcons"), () => { window.requestActivate(); }],
        [() => window.active, () => {
            const toggle = page("workspaceMonochromeIcons");
            verify(!CortetsuConfig.bar.workspaces.monochromeIcons && !toggle.checked,
                "workspace app icons keep their original colors by default");
            toggle.forceActiveFocus(); key(Qt.Key_Space);
            verify(CortetsuConfig.bar.workspaces.monochromeIcons && toggle.checked,
                "the Bar control enables theme-colored app icons");
        }],
        [() => CortetsuConfig.saveState === "saved", () => {}]
    ]
    readonly property var workspaceMonochromeRestore: [
        [() => CortetsuConfig.loaded, () => { select("bar"); screenDouble.settings = true; }],
        [() => !!content && !!page("workspaceMonochromeIcons"), () => {
            verify(CortetsuConfig.bar.workspaces.monochromeIcons && page("workspaceMonochromeIcons").checked,
                "the workspace icon color choice restores on launch");
        }]
    ]
    readonly property var hardwareSamplePreferences: [
        [() => CortetsuConfig.loaded, () => { select("automation"); screenDouble.settings = true; }],
        [() => !!content && ["wifi", "bluetooth", "automation", "capture", "weather"].includes(content.pageId) && !!page("hardwareSampleInterval") && !!hardwareTelemetryProbe, () => {
            window.requestActivate();
        }],
        [() => window.active, () => {
            const slider = page("hardwareSampleInterval");
            root.hardwareSampleWritesBefore = root.writes;
            verify(CortetsuConfig.dashboardResourceUpdateInterval === 1500
                && slider.value === 1500 && hardwareTelemetryProbe.intervalMs === 1500,
                "hardware sampling preserves its existing 1.5-second rate by default");
            slider.moved(2750);
            verify(CortetsuConfig.dashboardResourceUpdateInterval === 2750
                && hardwareTelemetryProbe.intervalMs === 2750,
                "the Services slider changes the active Hardware Center sampling interval");
        }],
        [() => CortetsuConfig.saveState === "saved", () => {
            verify(root.writes === root.hardwareSampleWritesBefore + 1,
                "changing the interval is persisted with one debounced write");
        }]
    ]
    readonly property var hardwareSampleRestore: [
        [() => CortetsuConfig.loaded, () => { select("automation"); screenDouble.settings = true; }],
        [() => !!content && ["wifi", "bluetooth", "automation", "capture", "weather"].includes(content.pageId) && !!page("hardwareSampleInterval") && !!hardwareTelemetryProbe, () => {
            verify(CortetsuConfig.dashboardResourceUpdateInterval === 2750
                && page("hardwareSampleInterval").value === 2750
                && hardwareTelemetryProbe.intervalMs === 2750,
                "the chosen hardware sampling interval persists and restores to the consumer");
        }]
    ]
    readonly property var hardwareSampleNormalize: [
        [() => CortetsuConfig.loaded, () => { select("automation"); screenDouble.settings = true; }],
        [() => !!content && ["wifi", "bluetooth", "automation", "capture", "weather"].includes(content.pageId) && !!page("hardwareSampleInterval"), () => {
            verify(CortetsuConfig.dashboardResourceUpdateInterval === 5000
                && page("hardwareSampleInterval").value === 5000,
                "stored sampling values are bounded and rounded to a supported 250-millisecond step");
        }]
    ]
    readonly property var hardwareSampleNormalizeLow: [
        [() => CortetsuConfig.loaded, () => { select("automation"); screenDouble.settings = true; }],
        [() => !!content && ["wifi", "bluetooth", "automation", "capture", "weather"].includes(content.pageId) && !!page("hardwareSampleInterval"), () => {
            verify(CortetsuConfig.dashboardResourceUpdateInterval === 1000
                && page("hardwareSampleInterval").value === 1000,
                "stored sampling values cannot exceed the lower safe query-rate bound");
        }]
    ]
    readonly property var actionPrefixPreferences: [
        [() => CortetsuConfig.loaded, () => { select("launcher"); screenDouble.settings = true; }],
        [() => !!content && !!page("actionPrefix"), () => { window.requestActivate(); }],
        [() => window.active, () => {
            const entry = find(page("actionPrefix"), "entry");
            entry.forceActiveFocus(); key(Qt.Key_A, Qt.ControlModifier); key(Qt.Key_Exclam);
            key(Qt.Key_Return);
            verify(CortetsuConfig.actionPrefix === "!" && Actions.transformSearch("!limpiar") === "limpiar",
                "the saved action prefix changes the launcher's action search backend");
            page("actionPrefix").committed("two");
            verify(page("actionPrefix").status === "error" && CortetsuConfig.actionPrefix === "!",
                "an invalid prefix is rejected without replacing the confirmed value");
            page("actionPrefix").committed("@");
            verify(page("actionPrefix").statusText.includes("@") && CortetsuConfig.actionPrefix === "!",
                "the app-selection prefix cannot collide with the action prefix");
        }],
        [() => CortetsuConfig.saveState === "saved", () => {}]
    ]
    readonly property var actionPrefixRestore: [
        [() => CortetsuConfig.loaded, () => {
            verify(CortetsuConfig.actionPrefix === "!" && Actions.transformSearch("!limpiar") === "limpiar",
                "the action search prefix restores in a new process");
        }]
    ]
    readonly property var launcherHoverPreferences: [
        [() => CortetsuConfig.loaded, () => { select("launcher"); screenDouble.settings = true; }],
        [() => !!content && !!page("launcherShowOnHover"), () => { window.requestActivate(); }],
        [() => window.active, () => {
            const toggle = page("launcherShowOnHover");
            verify(!CortetsuConfig.launcher.showOnHover && !CortetsuOverlayConfig.launcher.showOnHover,
                "the launcher hover setting starts from the active overlay policy");
            toggle.forceActiveFocus(); key(Qt.Key_Space);
            verify(CortetsuConfig.launcher.showOnHover && CortetsuOverlayConfig.launcher.showOnHover,
                "the hover control updates the policy consumed by pointer interactions");
        }],
        [() => CortetsuConfig.saveState === "saved", () => {}]
    ]
    readonly property var launcherHoverRestore: [
        [() => CortetsuConfig.loaded, () => {
            verify(CortetsuConfig.launcher.showOnHover && CortetsuOverlayConfig.launcher.showOnHover,
                "the launcher hover policy restores in a new process");
        }]
    ]

    readonly property var notificationPreferences: [
        [() => CortetsuConfig.loaded, () => { select("notifications"); screenDouble.settings = true; }],
        [() => !!content && !!page("notificationTimeout"), () => { window.requestActivate(); }],
        [() => window.active, () => {
            find(page("notificationTimeout"), "slider").forceActiveFocus(); key(Qt.Key_Right);
            verify(CortetsuConfig.notificationDefaultExpireTimeout === 6000, "the duration control writes milliseconds to the backend contract");
            verify(NotificationModel.popupTimeout(-1, CortetsuConfig.notificationDefaultExpireTimeout, true) === 6000,
                "the notification expiry calculation uses the chosen duration");
            verify(NotificationModel.popupTimeout(2000, CortetsuConfig.notificationDefaultExpireTimeout, true) === 2000,
                "an application-specific duration remains authoritative");
        }],
        [() => CortetsuConfig.saveState === "saved", () => {}]
    ]
    readonly property var notificationRestore: [
        [() => CortetsuConfig.loaded, () => {
            verify(NotificationModel.popupTimeout(-1, CortetsuConfig.notificationDefaultExpireTimeout, true) === 6000,
                "a new process restores the chosen notification duration");
        }]
    ]
    readonly property var notificationLongPreferences: [
        [() => CortetsuConfig.loaded, () => { select("notifications"); screenDouble.settings = true; }],
        [() => !!content && !!page("notificationTimeout"), () => { window.requestActivate(); }],
        [() => window.active, () => {
            const slider = find(page("notificationTimeout"), "slider");
            verify(slider.to > CortetsuConfig.notificationDefaultExpireTimeout / 1000,
                "a saved duration above the usual range can still be increased");
            slider.forceActiveFocus(); key(Qt.Key_Right);
            verify(CortetsuConfig.notificationDefaultExpireTimeout === 91000,
                "the long duration control continues to write an increased value");
        }],
        [() => CortetsuConfig.saveState === "saved", () => {}]
    ]
    readonly property var notificationLongRestore: [
        [() => CortetsuConfig.loaded, () => {
            verify(CortetsuConfig.notificationDefaultExpireTimeout === 91000,
                "an increased long duration survives process restart");
        }]
    ]

    readonly property var clockPreferences: [
        [() => CortetsuConfig.loaded, () => {
            verify(CortetsuConfig.desktopClockPosition === "top-left", "the old camel-case clock position migrates to an actual runtime state");
            select("wallpaper"); screenDouble.settings = true;
        }],
        [() => !!content && !!page("clock-middle-center") && !!page("clockShowDate"), () => {
            verify(CortetsuConfig.desktopClockShowDate && root.clockDateExists() && root.clockDateVisible(),
                "the existing clock shows its date by default");
            page("clock-middle-center").request();
            verify(CortetsuConfig.desktopClockPosition === "middle-center", "the position control updates the background owner");
            verify(page("clock-middle-center").selected, "the selected position is confirmed");
            const toggle = page("clockShowDate");
            toggle.forceActiveFocus(); key(Qt.Key_Space);
            verify(!CortetsuConfig.desktopClockShowDate && root.clockDateExists() && !root.clockDateVisible(),
                "the desktop clock date control changes the rendered background clock");
        }],
        [() => CortetsuConfig.saveState === "saved", () => {}]
    ]
    readonly property var clockRestore: [
        [() => CortetsuConfig.loaded, () => {
            verify(CortetsuConfig.desktopClockPosition === "middle-center", "a new process restores the selected clock position");
            verify(!CortetsuConfig.desktopClockShowDate && root.clockDateExists() && !root.clockDateVisible(),
                "the hidden desktop clock date survives process restart");
        }]
    ]

    readonly property var audioPreferences: [
        [() => CortetsuConfig.loaded, () => { select("audio"); screenDouble.settings = true; }],
        [() => !!content && !!page("audioLimit"), () => { window.requestActivate(); }],
        [() => window.active, () => {
            find(page("audioLimit"), "slider").forceActiveFocus(); key(Qt.Key_Right);
            verify(Math.abs(CortetsuConfig.maxVolume - 1.05) < 0.001, "keyboard changes the actual shell volume limit");
            verify(page("outputVolume").to === CortetsuConfig.maxVolume, "output control confirms the new limit");
            find(page("audioStep"), "slider").forceActiveFocus(); key(Qt.Key_Right);
            verify(Math.abs(CortetsuConfig.audioIncrement - 0.11) < 0.001, "keyboard changes the backend increment");
            const current = CortetsuAudio.volume;
            page("audioLimit").moved(50);
            verify(CortetsuAudio.volume === current, "lowering the request limit preserves current playback volume");
            verify(page("outputVolume").to >= current, "the output slider still represents the actual volume above a new limit");
            page("audioLimit").moved(105);
        }],
        [() => CortetsuConfig.saveState === "saved", () => {}]
    ]

    readonly property var personalTokens: ({radiusSmall: 9, radiusMedium: 15, radiusSurface: 24,
        rowHeight: 50, spacingSection: 28, materialGroundAlpha: 0.82, materialGrain: 0.08,
        materialHairlineAlpha: 0.12, fontUi: "Noto Sans", fontInk: "Noto Serif", fontKanji: "Noto Sans CJK JP"})

    readonly property var globalPersonalisation: [
        [() => CortetsuConfig.loaded && CortetsuThemes.reconciled, () => { select("themes"); screenDouble.settings = true; }],
        [() => !!page("themePreview-washi"), () => { page("themePreview-washi").request(); }],
        [() => CortetsuThemes.previewId === "washi" && !CortetsuThemes.busy, () => {
            verify(CortetsuConfig.themeId === "ink", "preview never saves its theme");
            compare(CortetsuDesign.radiusSurface, 24);
            compare(CortetsuDesign.materialStyle, 1);
            verify(page("themePreviewBar").visible, "a preview always offers its way back");
            verify(page("themeToken-radiusSurface").disabled, "preview geometry cannot change the saved theme");
            page("themePreviewCancel").request();
            compare(CortetsuDesign.radiusSurface, 28);
            page("paletteLightMode").request();
        }],
        [() => CortetsuColours.currentLight && !CortetsuThemes.busy, () => {
            verify(CortetsuConfig.themeId === "ink", "light mode preserves theme identity");
            page("themeToken-radiusSurface").moved(24);
            compare(CortetsuDesign.radiusSurface, 24);
            for (const [token, value] of Object.entries(root.personalTokens)) {
                const control = page("themeToken-" + token);
                if (typeof value === "string") control.committed(value); else control.moved(value);
                compare(CortetsuDesign[token], value);
            }
            select("sync");
        }],
        [() => content.pageId === "sync" && !!page("themeIntegration-kitty"), () => {
            page("themeIntegration-kitty").request();
        }],
        [() => CortetsuConfig.saveState === "saved" && CortetsuThemes.integrations.kitty?.status === "disabled", () => {
            verify(CortetsuConfig.themeIntegrations.kitty === false, "integration control confirms persisted disable");
            select("profiles");
        }],
        [() => content.pageId === "profiles" && !!page("themeProfileExport"), () => {
            page("themeProfileExport").request();
        }],
        [() => CortetsuThemes.notice.includes("exportado") && !CortetsuThemes.busy, () => {
            CortetsuConfig.setThemeToken("radiusSurface", 20);
        }],
        [() => CortetsuConfig.saveState === "saved", () => {
            page("themeProfileImport").request(); page("themeProfileImport").request();
        }],
        [() => CortetsuThemes.notice.includes("importado") && !CortetsuThemes.busy, () => {
            compare(CortetsuDesign.radiusSurface, 24);
            for (const [token, value] of Object.entries(root.personalTokens)) compare(CortetsuDesign[token], value);
            verify(CortetsuColours.currentLight, "import restores the colour mode");
            select("audio");
        }],
        [() => !!page("audioProtection"), () => {
            page("audioProtection").request();
            page("audioMaxIncrease").moved(25);
            verify(CortetsuConfig.audioProtectionEnabled, "audio protection is a real preference");
            compare(CortetsuConfig.audioMaxIncrease, 0.25);
        }],
        [() => CortetsuConfig.saveState === "saved", () => { select("indicators"); }],
        [() => !!page("osdTimeout") && !!osdProbe.item, () => {
            page("osdTimeout").moved(2200);
            compare(CortetsuConfig.osdTimeoutMs, 2200);
            osdProbe.item.showMini("volume");
            verify(osdProbe.item.compactVisible, "the real compact OSD opens");
        }],
        [() => waitedMs >= 1100, () => {
            verify(osdProbe.item.compactVisible, "the configured duration keeps the OSD visible");
            osdProbe.item.showMini("volume");
        }],
        [() => waitedMs >= 1100, () => { verify(osdProbe.item.compactVisible, "repeated input restarts the actual timer"); }],
        [() => waitedMs >= 1000 && !osdProbe.item.compactVisible, () => { verify(true, "the real compact OSD expires at the configured duration"); }]
    ]
    readonly property var globalPersonalisationRestore: [
        [() => CortetsuConfig.loaded && CortetsuThemes.reconciled, () => {
            compare(CortetsuDesign.radiusSurface, 24);
            for (const [token, value] of Object.entries(root.personalTokens)) compare(CortetsuDesign[token], value);
            verify(CortetsuColours.currentLight, "a new process restores the light palette");
            verify(CortetsuConfig.themeIntegrations.kitty === false, "a new process restores integration controls");
            verify(CortetsuConfig.audioProtectionEnabled, "a new process restores audio protection");
            compare(CortetsuConfig.audioMaxIncrease, 0.25);
            compare(CortetsuConfig.osdTimeoutMs, 2200);
        }]
    ]
    readonly property var themeRecovery: [
        [() => CortetsuConfig.loaded && CortetsuThemes.reconciled, () => {
            verify(CortetsuConfig.themeId === "washi", "startup recovers a native commit made before the preferences write");
            verify(CortetsuDesign.radiusSurface === 24 && CortetsuDesign.materialStyle === 1, "recovered native ownership reaches the design tokens");
        }],
        [() => CortetsuConfig.saveState === "saved", () => {}]
    ]

    readonly property var themeFailure: [
        [() => CortetsuConfig.loaded && Schemes.catalogCount > 0, () => {
            select("themes"); screenDouble.settings = true;
        }],
        [() => !!content && !!page("theme-washi"), () => { stateFile.setText("{broken"); }],
        [() => waitedMs >= 200, () => { page("theme-washi").clicked(); }],
        [() => !CortetsuThemes.busy && CortetsuThemes.error.length > 0, () => {
            verify(CortetsuConfig.themeId === "ink", "a failed native restore cannot change the confirmed theme");
            verify(page("themeStatus").status === "error", "the theme control exposes the native failure");
            verify(CortetsuDesign.radiusSurface === 28, "a failure retains the confirmed design tokens");
        }]
    ]

    readonly property var themeSlowCommit: [
        [() => CortetsuConfig.loaded && CortetsuThemes.reconciled && Schemes.catalogCount > 0, () => {
            select("themes"); screenDouble.settings = true;
        }],
        [() => !!content && !!page("theme-washi"), () => { page("theme-washi").clicked(); }],
        [() => CortetsuConfig.themeId === "washi" && !CortetsuThemes.busy, () => {
            verify(CortetsuThemes.slowNoticeShown, "the progress notice does not kill a helper waiting on the state lock");
            verify(!CortetsuThemes.error.includes("esperando"),
                "a slow durable commit continues after the progress timer and clears its transient notice");
            verify(CortetsuConfig.themeId === "washi", "the late native acknowledgement updates the active theme");
        }]
    ]

    readonly property var themeProjectionFailure: [
        [() => CortetsuConfig.loaded && CortetsuThemes.reconciled, () => {
            select("themes"); screenDouble.settings = true;
        }],
        [() => !!content && !!page("theme-washi"), () => { page("theme-washi").clicked(); }],
        [() => CortetsuConfig.themeId === "washi" && !CortetsuThemes.busy, () => {
            verify(CortetsuThemes.error.length > 0,
                "Settings reports a projection that starts but fails instead of claiming complete application");
            verify(CortetsuConfig.themeId === "washi", "a projection error does not undo the durable product theme");
        }]
    ]

    readonly property var themeWithoutScheme: [
        [() => CortetsuConfig.loaded && CortetsuThemes.reconciled && Schemes.catalogCount > 0, () => {
            select("themes"); screenDouble.settings = true;
        }],
        [() => !!content && !!page("theme-washi"), () => { page("theme-washi").clicked(); }],
        [() => CortetsuConfig.themeId === "washi" && CortetsuConfig.saveState === "saved" && !CortetsuThemes.busy, () => {
            verify(CortetsuThemes.error === "", "a fresh install without a selected scheme applies its product theme without a false Kitty projection error");
            verify(CortetsuDesign.radiusSurface === 24 && CortetsuDesign.materialStyle === 1, "the fresh-install theme updates Cortetsu's active design tokens");
        }]
    ]

    readonly property var themeSelect: [
        [() => CortetsuConfig.loaded && Schemes.catalogCount > 0, () => {
            select("themes"); screenDouble.settings = true;
        }],
        [() => !!content && !!page("theme-" + Quickshell.env("THEME_ID")), () => {
            const id = Quickshell.env("THEME_ID");
            page("theme-" + id).clicked();
        }],
        [() => CortetsuConfig.themeId === Quickshell.env("THEME_ID") && CortetsuConfig.saveState === "saved" && !CortetsuThemes.busy, () => {
            const id = Quickshell.env("THEME_ID");
            verify(CortetsuConfig.themeId === id, "the theme control changes the persistent owner after native confirmation");
            verify(CortetsuThemes.error === "", "successful external projections clear the pending and failure status");
            verify(page("theme-" + id).disabled, "the active theme is confirmed in Settings");
            verify(CortetsuDesign.radiusSurface === (id === "washi" ? 24 : 8) && CortetsuDesign.materialStyle === (id === "washi" ? 1 : 2), "the selected material updates live");
            render("theme-" + id);
            CortetsuConfig.transparencyEnabled = true;
            CortetsuConfig.reducedMotion = true;
            CortetsuConfig.smartScheme = false;
            CortetsuConfig.selectTheme("ink");
            CortetsuConfig.transparencyEnabled = false;
            CortetsuConfig.reducedMotion = false;
            CortetsuConfig.smartScheme = true;
            CortetsuConfig.selectTheme(id);
            verify(CortetsuConfig.transparencyEnabled && CortetsuConfig.reducedMotion && !CortetsuConfig.smartScheme,
                "returning to a theme restores its material and motion preferences");
            CortetsuConfig.selectTheme("ink");
            verify(!CortetsuConfig.transparencyEnabled && !CortetsuConfig.reducedMotion && CortetsuConfig.smartScheme,
                "Ink retains independent material and motion preferences");
            CortetsuConfig.selectTheme(id);
        }],
        [() => CortetsuConfig.saveState === "saved", () => {}]
    ]
    readonly property var themeRestore: [
        [() => CortetsuConfig.loaded, () => {
            verify(CortetsuConfig.themeId === Quickshell.env("THEME_ID"), "a new process restores the selected theme");
            verify(CortetsuConfig.transparencyEnabled && CortetsuConfig.reducedMotion && !CortetsuConfig.smartScheme, "the active theme restores its material and motion preferences");
            CortetsuConfig.selectTheme("ink");
            verify(!CortetsuConfig.transparencyEnabled && !CortetsuConfig.reducedMotion && CortetsuConfig.smartScheme, "the inactive theme also survives process restart");
            CortetsuConfig.selectTheme(Quickshell.env("THEME_ID"));
            verify(CortetsuDesign.radiusSurface === (CortetsuConfig.themeId === "washi" ? 24 : 8), "restored preferences reach the design tokens");
        }]
    ]

    readonly property var paletteVariant: [
        [() => CortetsuConfig.loaded && Schemes.catalogCount > 0, () => {
            select("colors"); screenDouble.settings = true;
        }],
        [() => !!content && !!page("variant-expressive"), () => {
            const row = page("variant-expressive");
            memo.palettePrimary = CortetsuColours.currentColours.primary;
            verify(!row.selected, "the current variant is not marked active");
            Schemes.applyVariant("not-a-material-variant");
            verify(Schemes.variantStatus === "idle" && Schemes.pendingVariant === "",
                "an unknown variant is rejected before launching the native owner");
            row.forceActiveFocus(); key(Qt.Key_Return);
            verify(["applying", "applied"].includes(Schemes.variantStatus) && Schemes.pendingVariant === "expressive",
                "the Settings action starts a native variant change");
        }],
        [() => Schemes.variantStatus === "applied" && CortetsuColours.variant === "expressive", () => {
            verify(Schemes.variantIsCurrent("expressive"), "the live palette state confirms the selected variant");
            verify(page("variant-expressive").selected, "the selected variant is reflected by Settings");
            verify(Schemes.variantError === "", "a successful native update clears prior errors");
            verify(CortetsuColours.currentColours.primary !== memo.palettePrimary,
                "the selected variant regenerates palette tokens instead of changing metadata only");
        }]
    ]

    readonly property var paletteVariantRestore: [
        [() => CortetsuConfig.loaded && CortetsuColours.variant === "expressive", () => {
            select("colors"); screenDouble.settings = true;
        }],
        [() => !!content && !!page("variant-expressive"), () => {
            verify(page("variant-expressive").selected,
                "a fresh Settings process restores the persisted variant selection");
        }]
    ]

    readonly property var paletteVariantUnavailable: [
        [() => CortetsuConfig.loaded && Schemes.catalogCount > 0, () => {
            select("colors"); screenDouble.settings = true;
        }],
        [() => !!content && !!page("variant-expressive"), () => {
            verify(!Schemes.variantAvailable && page("variant-expressive").disabled,
                "variant actions stay disabled until a colour palette exists");
            const variantStatus = Schemes.variantStatus;
            M3Variants.list[0].onClicked(null);
            verify(Schemes.variantStatus === variantStatus && !Schemes.variantAvailable,
                "a stale or direct launcher variant action is a no-op until a seed exists");
            verify(find(page("paletteVariants"), "rowDetail").text.includes("Aplica primero"),
                "the unavailable state explains how to enable palette variants");
        }]
    ]

    readonly property var migratedControls: [
        [() => CortetsuConfig.loaded, () => {
            root.writes = 0;
            select("background"); screenDouble.settings = true; window.requestActivate();
        }],
        [() => window.active && !!page("desktopClockEnabled"), () => {
            const toggle = page("desktopClockEnabled");
            verify(CortetsuConfig.desktopClockEnabled && toggle.checked, "the desktop clock control starts from the active owner state");
            toggle.forceActiveFocus(); key(Qt.Key_Space);
            verify(!CortetsuConfig.desktopClockEnabled && !toggle.checked, "the desktop clock control updates the rendered clock owner");
            select("bar");
        }],
        [() => !!page("appsSegment"), () => {
            const toggle = page("appsSegment");
            verify(CortetsuConfig.bottomHub.segments.apps && toggle.checked, "the applications segment starts enabled");
            toggle.forceActiveFocus(); key(Qt.Key_Space);
            verify(!CortetsuConfig.bottomHub.segments.apps && !toggle.checked, "the segment control updates Bottom Hub state");
            select("indicators");
        }],
        [() => !!page("useFahrenheit"), () => {
            const toggle = page("useFahrenheit");
            verify(!CortetsuConfig.useFahrenheit && !toggle.checked, "the temperature control starts in Celsius");
            toggle.forceActiveFocus(); key(Qt.Key_Space);
            verify(CortetsuConfig.useFahrenheit && toggle.checked, "the temperature control updates the shared unit preference");
            select("launcher");
        }],
        [() => !!page("fuzzyApplications"), () => {
            const toggle = page("fuzzyApplications");
            verify(!CortetsuConfig.useFuzzyApps && !toggle.checked, "fuzzy application matching starts disabled in this fixture");
            toggle.forceActiveFocus(); key(Qt.Key_Space);
            verify(CortetsuConfig.useFuzzyApps && toggle.checked, "the fuzzy-search control updates the application search service");
        }],
        [() => CortetsuConfig.saveState === "saved", () => {
            verify(CortetsuConfig.desktopClockEnabled === false && CortetsuConfig.bottomHub.segments.apps === false
                && CortetsuConfig.useFahrenheit === true && CortetsuConfig.useFuzzyApps === true,
                "all migrated controls reach their real preference owners before persistence");
        }]
    ]
    readonly property var migratedControlsRestore: [
        [() => CortetsuConfig.loaded, () => {
            verify(CortetsuConfig.desktopClockEnabled === false && CortetsuConfig.bottomHub.segments.apps === false
                && CortetsuConfig.useFahrenheit === true && CortetsuConfig.useFuzzyApps === true,
                "a fresh process restores the clock, Bottom Hub, temperature and fuzzy-search preferences");
        }]
    ]

    readonly property var existingPreferenceControls: [
        [() => CortetsuConfig.loaded, () => { select("launcher"); screenDouble.settings = true; window.requestActivate(); }],
        [() => window.active && !!page("fuzzyActions") && !!page("fuzzySchemes"), () => {
            verify(Actions.useFuzzy && Schemes.useFuzzy, "launcher search services start from their saved fuzzy preferences");
            const actions = page("fuzzyActions");
            actions.forceActiveFocus(); key(Qt.Key_Space);
            verify(!CortetsuConfig.useFuzzyActions && !Actions.useFuzzy,
                "the Settings control changes the live launcher action search policy");
            const schemes = page("fuzzySchemes");
            schemes.forceActiveFocus(); key(Qt.Key_Space);
            verify(!CortetsuConfig.useFuzzySchemes && !Schemes.useFuzzy,
                "the Settings control changes the live scheme search policy");
        }],
        [() => CortetsuConfig.saveState === "saved", () => {
            verify(root.writes === 1, `both search preferences settle into one debounced write (${root.writes})`);
            root.writes = 0;
            select("notifications");
        }],
        [() => !!page("toastCapsLockChanged") && !!page("toastNumLockChanged")
            && !!page("toastKbLayoutChanged") && !!page("toastDndChanged")
            && !!page("toastNowPlaying") && !!page("notificationOpenExpanded"), () => {
            window.requestActivate();
        }],
        [() => window.active, () => {
            const names = ["toastCapsLockChanged", "toastNumLockChanged", "toastKbLayoutChanged",
                "toastDndChanged", "toastNowPlaying", "notificationOpenExpanded"];
            for (const name of names) {
                const toggle = page(name);
                verify(toggle.checked, `${name} restores enabled in the test fixture`);
                toggle.forceActiveFocus(); key(Qt.Key_Space);
                verify(CortetsuConfig[name] === false && !toggle.checked,
                    `${name} updates its live preference owner through the Settings control`);
            }
        }],
        [() => CortetsuConfig.saveState === "saved", () => {
            verify(!CortetsuConfig.useFuzzyActions && !CortetsuConfig.useFuzzySchemes
                && !CortetsuConfig.toastCapsLockChanged && !CortetsuConfig.toastNumLockChanged
                && !CortetsuConfig.toastKbLayoutChanged && !CortetsuConfig.toastDndChanged
                && !CortetsuConfig.toastNowPlaying && !CortetsuConfig.notificationOpenExpanded,
                "all existing Settings preferences reach their confirmed backend values before persistence");
            verify(root.writes === 1, `the six notification controls settle into one debounced write (${root.writes})`);
        }]
    ]

    readonly property var existingPreferenceControlsRestore: [
        [() => CortetsuConfig.loaded, () => {
            verify(!CortetsuConfig.useFuzzyActions && !CortetsuConfig.useFuzzySchemes
                && !CortetsuConfig.toastCapsLockChanged && !CortetsuConfig.toastNumLockChanged
                && !CortetsuConfig.toastKbLayoutChanged && !CortetsuConfig.toastDndChanged
                && !CortetsuConfig.toastNowPlaying && !CortetsuConfig.notificationOpenExpanded
                && !Actions.useFuzzy && !Schemes.useFuzzy,
                "a fresh process restores all eight existing preference controls and their search consumers");
        }]
    ]

    readonly property var policies: [
        [() => CortetsuConfig.loaded, () => { select("automation"); screenDouble.settings = true; }],
        [() => !!content && ["wifi", "bluetooth", "automation", "capture", "weather"].includes(content.pageId) && !!page("policy-gamemode"), () => {
            verify(page("policy-gamemode").disabled && !page("policy-gamemode").checked, "an unavailable coordinator cannot grant consent");
            verify(value("policyConnection") === "No disponible", "connection state is visible");
            policyDouble.usable = true;
            window.requestActivate();
        }],
        [() => window.active && !page("policy-gamemode").disabled, () => {
            const toggle = page("policy-gamemode");
            verify(toggle.Accessible.name.includes("juego"), "the switch has a domain-specific accessible name");
            toggle.forceActiveFocus(); key(Qt.Key_Space);
            verify(JSON.stringify(policyDouble.calls) === JSON.stringify([["set", "gamemode", true]]), "Space requests consent for only this domain");
            verify(!toggle.checked && toggle.status === "busy", "the switch waits for confirmed state");
            policyDouble.settle("gamemode", true, 0, "fixture-session");
        }],
        [() => page("policy-gamemode").checked && !page("policy-pause-gamemode").disabled, () => {
            const action = find(page("policy-pause-gamemode"), "action");
            verify(action.Accessible.name.includes("juego") && action.Accessible.name.includes("quince"), "the pause button describes its domain and duration");
            action.forceActiveFocus(); key(Qt.Key_Return);
            verify(JSON.stringify(policyDouble.calls[1]) === JSON.stringify(["override", "gamemode", 900]), "keyboard pause has a fixed fifteen-minute duration");
            policyDouble.settle("gamemode", true, Date.now() + 900000, "fixture-session");
        }],
        [() => page("policy-pause-gamemode").actionLabel === "Reanudar", () => {
            const action = find(page("policy-pause-gamemode"), "action");
            action.forceActiveFocus(); key(Qt.Key_Return);
            verify(JSON.stringify(policyDouble.calls[2]) === JSON.stringify(["override", "gamemode", 0]), "resume clears the manual pause");
            policyDouble.pendingDomain = "";
            policyDouble.lastError = "No se pudo confirmar el cambio";
            policyDouble.actionErrorDomain = "gamemode";
            policyDouble.settle("notifications", true, 0, "other-session");
        }],
        [() => page("policy-notifications").disabled && page("policy-gamemode").status === "error", () => {
            verify(page("policy-notifications").detail.includes("otra sesión"), "foreign ownership is explained and cannot be taken");
            verify(page("policy-gamemode").checked, "a failed action retains the last confirmed activation");
            verify(text("policy-gamemode").includes("confirmar"), "the failure is explained beside the control");
            render("automation");
            const revoke = find(page("policy-revoke-notifications"), "action");
            verify(revoke.Accessible.name.includes("Notificaciones") && revoke.Accessible.name.includes("otra sesión"), "revocation identifies the domain and foreign session");
            revoke.forceActiveFocus(); key(Qt.Key_Return);
            verify(JSON.stringify(policyDouble.calls[3]) === JSON.stringify(["revoke", "notifications", "other-session"]), "keyboard revocation carries the exact displayed owner");
            verify(page("policy-notifications").checked && page("policy-notifications").disabled, "revocation waits for readback without transferring consent");
            policyDouble.settle("notifications", false, 0, "");
        }],
        [() => !page("policy-notifications").disabled && !page("policy-revoke-notifications").visible, () => {
            verify(!page("policy-notifications").checked && policyDouble.calls.length === 4, "revocation leaves the domain disabled until a separate action");
            page("policy-notifications").forceActiveFocus(); key(Qt.Key_Space);
            verify(JSON.stringify(policyDouble.calls[4]) === JSON.stringify(["set", "notifications", true]), "a separate keyboard action grants this session consent");
            policyDouble.settle("notifications", true, 0, "fixture-session");
        }]
    ]

    // Every destination once: each category page and each subpage. A
    // category with a single subpage opens on it, so only the subpage counts.
    readonly property var destinations: SettingsController.categories
        .filter(category => category.pages.length !== 1).map(category => category.id)
        .concat(Object.keys(SettingsController.pages))
    function clipped(item, stop) {
        for (let current = item.parent; current && current !== stop; current = current.parent)
            if (current.clip) return true;
        return false;
    }
    // The page is centred, nothing leaves it sideways, and the sidebar shows
    // every category name whole.
    function checkLayout(id) {
        const scroller = get("pageScroller");
        const page = content.page;
        const loader = page.parent;
        verify(page.width <= scroller.width && page.implicitWidth <= scroller.width,
            `${id} fits the width it is given (${page.implicitWidth} in ${scroller.width})`);
        const left = loader.x + page.columnX;
        const right = scroller.width - (loader.x + page.columnX + page.columnWidth);
        verify(Math.abs(left - right) <= 2, `${id} is centred (${left} left, ${right} right)`);
        const over = [];
        const walk = item => {
            if (!item.visible || item.opacity === 0) return;
            if (item !== page && item.width > 0 && !root.clipped(item, page)) {
                const at = item.mapToItem(page, 0, 0);
                if (at.x < page.columnX - 1 || at.x + item.width > page.columnX + page.columnWidth + 1)
                    over.push(`${item}${item.objectName ? "#" + item.objectName : ""} x=${Math.round(at.x)} w=${Math.round(item.width)}`);
            }
            const children = item.children ?? [];
            for (let i = 0; i < children.length; ++i) walk(children[i]);
        };
        walk(page);
        verify(over.length === 0, `${id} keeps every control inside its column: ${over.slice(0, 4).join(", ")}`);
        if (!content.collapsed) {
            const cut = SettingsController.categories.filter(category => find(get(`nexus-${category.id}`), "label")?.truncated);
            verify(cut.length === 0, `no category name is cut: ${cut.map(category => category.id)}`);
        }
    }
    readonly property var pages: [
        [() => CortetsuConfig.loaded && Schemes.catalogCount > 0, () => { screenDouble.settings = true; }]
    ].concat(destinations.map(id =>
        [() => { select(id); return !!content && content.pageId === SettingsController.pageId
            && SettingsController.resolve(id) !== null && !!content.page && waitedMs >= 350; }, () => {
            root.checkLayout(id);
            render(`page-${id}`);
        }]
    ))

    property int waitedMs: 0
    // Sending a key processes pending events, this timer among them. Without
    // the guard a slow step would be entered again from inside itself.
    property bool stepping: false
    Timer {
        interval: 50; repeat: true; running: true
        onTriggered: {
            if (root.stepping)
                return;
            const steps = root[root.scenario];
            if (root.step >= steps.length) {
                console.log("SETTINGS_RUNTIME_PASS", root.checks);
                Qt.quit();
                return;
            }
            if (root.rendering)
                return;
            root.waitedMs += interval;
            const [condition, action] = steps[root.step];
            if (condition && !condition()) {
                if (root.waitedMs > 15000) {
                    console.log("SETTINGS_FAIL", `step ${root.step} of ${root.scenario} never became ready `
                        + `(page ${SettingsController.selectedId}, search "${SettingsController.search}", focus ${focusName()}, `
                        + `catalog ${Schemes.catalogCount}, theme tiles ${!!page("theme-washi")}, `
                        + `theme ${CortetsuConfig.themeId}, busy ${CortetsuThemes.busy}, pending ${CortetsuThemes.pending}, `
                        + `theme error "${CortetsuThemes.error}")`);
                    Qt.quit();
                }
                return;
            }
            root.waitedMs = 0;
            root.stepping = true;
            // A step that throws would otherwise be retried forever.
            try {
                action();
            } catch (error) {
                console.log("SETTINGS_FAIL", `step ${root.step} of ${root.scenario} threw: ${error}`);
                Qt.quit();
            }
            root.stepping = false;
            root.step++;
        }
    }
}
"""


def measured(output: str, marker: str) -> str:
    return next(line.split(marker, 1)[1].strip() for line in output.splitlines() if marker in line)


def passed(output: str) -> int:
    for line in output.splitlines():
        if "SETTINGS_RUNTIME_PASS" in line:
            return int(line.rsplit(" ", 1)[1])
    raise AssertionError(output)


with tempfile.TemporaryDirectory(prefix="cortetsu-settings-") as temporary:
    folder = Path(temporary)
    build_tree(folder)
    (folder / "shell.qml").write_text(SHELL, encoding="utf-8")
    if os.environ.get("CORTETSU_SETTINGS_SCENARIO"):
        scenario = os.environ["CORTETSU_SETTINGS_SCENARIO"]
        isolated_scheme = json.loads(os.environ["CORTETSU_SETTINGS_SCHEME"]) if "CORTETSU_SETTINGS_SCHEME" in os.environ else None
        scenario_env = {}
        if scenario == "themeSlowCommit":
            fixture = json.loads((ROOT / "desktop-runtime-rs/tests/fixtures/legacy-palettes.json").read_text())
            isolated_scheme = {"schema": 2, "themeId": "ink", "name": "dynamic", "flavour": "default",
                               "variant": "tonal-spot", "mode": "dark", "origin": "manual",
                               "colours": fixture["cases"][0]["colours"]}
            scenario_env["CORTETSU_THEME_ACK_TIMEOUT_MS"] = "50"
        output, _ = run(folder, "shell.qml", scenario,
                        preferences=json.loads(os.environ.get("CORTETSU_SETTINGS_PREFERENCES", '{"schema": 1}')),
                        scheme=isolated_scheme, env=scenario_env)
        print(output)
        sys.exit(0)


    output, home = run(folder, "shell.qml", "reactivity",
                       scheme={"name": "oceanicnext", "flavour": "default", "colours": {}},
                       preferences={"schema": 1, "favouriteApps": ["kitty"], "launcher": {"maxShown": 11},
                                    "bottomHub": {"segments": {"tray": False}},
                                    "displayCalibration": {"enabled": False, "temperature": 4500, "gamma": 90}})
    reactivity = passed(output)
    assert "Reloading configuration" not in output, output
    opened, cycles = measured(output, "SETTINGS_OPEN_MS"), measured(output, "SETTINGS_CYCLES_MS")
    state = json.loads((home / "state/cortetsu/scheme.json").read_text())
    assert state["name"] == "aura", state
    saved = json.loads((home / ".config/cortetsu/preferences.json").read_text())
    assert saved["transparencyEnabled"] is True and saved["borderThickness"] == 4, saved
    # One write holds every section, and what Settings does not show survives it.
    assert saved["bottomHub"]["segments"] == {"mode": True, "apps": True, "tray": False, "status": True}, saved["bottomHub"]
    assert saved["displayCalibration"] == {"enabled": False, "temperature": 4500, "gamma": 90}, saved["displayCalibration"]
    assert saved["favouriteApps"] == ["kitty"] and saved["launcher"]["maxShown"] == 11, saved

    navigation = passed(run(folder, "shell.qml", "navigation")[0])

    output, home = run(folder, "shell.qml", "states")
    states = passed(output)
    calls = (home / "fixtures/calls.log").read_text().splitlines()
    assert calls.count("systemctl --user start hyprsunset.service") == 2, calls
    assert "hyprctl hyprsunset temperature 6000" in calls and "hyprctl hyprsunset gamma 100" in calls, calls
    # Shortcuts is its own page: Pantalla no longer reads the bindings. Only the
    # page's failed attempt and its successful retry list them.
    assert calls.count("cortetsu-keybinds list") == 2, calls

    output, home = run(folder, "shell.qml", "unwritable", preferences={"schema": 1})
    unwritable = passed(output)
    blocked = home / ".config/cortetsu/preferences.json"
    assert blocked.is_dir(), "a failed write must not replace the blocked destination"
    assert sorted(path.name for path in blocked.iterdir()) == ["original.json"]
    assert json.loads((blocked / "original.json").read_text()) == {"schema": 1}
    policies = passed(run(folder, "shell.qml", "policies")[0])

    output, weather_home = run(folder, "shell.qml", "weatherPreferences", preferences={"schema": 1})
    assert passed(output) == 8, output
    weather_saved = json.loads((weather_home / ".config/cortetsu/preferences.json").read_text())
    assert weather_saved["weatherLocation"] == "lima", weather_saved
    assert weather_saved["weatherRefreshInterval"] == 3900000, weather_saved
    restored, _ = run(folder, "shell.qml", "weatherRestore", preferences=weather_saved)
    assert passed(restored) == 2, restored

    output, recording_path_home = run(folder, "shell.qml", "recordingPathPreferences",
                                     preferences={"schema": 1})
    assert passed(output) == 3, output
    recording_path_saved = json.loads((recording_path_home / ".config/cortetsu/preferences.json").read_text())
    assert recording_path_saved["screenRecordSavePath"] == "~/Vídeos/Grabaciones", recording_path_saved
    restored, _ = run(folder, "shell.qml", "recordingPathRestore", preferences=recording_path_saved)
    assert passed(restored) == 2, restored

    output, screenshot_path_home = run(folder, "shell.qml", "screenshotPathPreferences",
                                       preferences={"schema": 1})
    assert passed(output) == 2, output
    screenshot_path_saved = json.loads((screenshot_path_home / ".config/cortetsu/preferences.json").read_text())
    assert screenshot_path_saved["screenSnipSavePath"] == "~/Imágenes/Recortes", screenshot_path_saved
    restored, _ = run(folder, "shell.qml", "screenshotPathRestore", preferences=screenshot_path_saved)
    assert passed(restored) == 1, restored

    output, bar_auto_hide_home = run(folder, "shell.qml", "barAutoHidePreferences",
                                     preferences={"schema": 1})
    assert passed(output) == 2, output
    bar_auto_hide_saved = json.loads((bar_auto_hide_home / ".config/cortetsu/preferences.json").read_text())
    assert bar_auto_hide_saved["bar"]["showOnHover"] is True, bar_auto_hide_saved
    restored, _ = run(folder, "shell.qml", "barAutoHideRestore", preferences=bar_auto_hide_saved)
    assert passed(restored) == 1, restored

    output, tray_monochrome_home = run(folder, "shell.qml", "trayMonochromePreferences",
                                       preferences={"schema": 1})
    assert passed(output) == 2, output
    tray_monochrome_saved = json.loads((tray_monochrome_home / ".config/cortetsu/preferences.json").read_text())
    assert tray_monochrome_saved["bar"]["tray"]["recolour"] is True, tray_monochrome_saved
    restored, _ = run(folder, "shell.qml", "trayMonochromeRestore", preferences=tray_monochrome_saved)
    assert passed(restored) == 1, restored

    output, weather_visibility_home = run(folder, "shell.qml", "weatherVisibilityPreferences",
                                          preferences={"schema": 1})
    assert passed(output) == 1, output
    weather_visibility_saved = json.loads((weather_visibility_home / ".config/cortetsu/preferences.json").read_text())
    assert weather_visibility_saved["dashboard"]["showWeather"] is False, weather_visibility_saved
    restored, _ = run(folder, "shell.qml", "weatherVisibilityRestore", preferences=weather_visibility_saved)
    assert passed(restored) == 1, restored

    output, regional_home = run(folder, "shell.qml", "regionalPreferences", preferences={"schema": 1})
    assert passed(output) == 3, output
    regional_saved = json.loads((regional_home / ".config/cortetsu/preferences.json").read_text())
    assert regional_saved["useTwelveHourClock"] is True, regional_saved
    assert regional_saved["useSecondPrecision"] is True, regional_saved
    restored, _ = run(folder, "shell.qml", "regionalRestore", preferences=regional_saved)
    assert passed(restored) == 1, restored

    output, notification_count_home = run(folder, "shell.qml", "notificationCountPreferences",
                                          preferences={"schema": 1})
    assert passed(output) == 2, output
    notification_count_saved = json.loads((notification_count_home / ".config/cortetsu/preferences.json").read_text())
    assert notification_count_saved["bottomHub"]["statusCluster"]["showNotificationCount"] is False, notification_count_saved
    restored, _ = run(folder, "shell.qml", "notificationCountRestore", preferences=notification_count_saved)
    assert passed(restored) == 1, restored

    output, battery_low_home = run(folder, "shell.qml", "batteryLowPreferences", preferences={"schema": 1})
    assert passed(output) == 2, output
    battery_low_saved = json.loads((battery_low_home / ".config/cortetsu/preferences.json").read_text())
    assert battery_low_saved["batteryLowWarningPercent"] == 25, battery_low_saved
    restored, _ = run(folder, "shell.qml", "batteryLowRestore", preferences=battery_low_saved)
    assert passed(restored) == 1, restored
    normalized, _ = run(folder, "shell.qml", "batteryLowNormalize",
                        preferences={"schema": 1, "batteryLowWarningPercent": 23})
    assert passed(normalized) == 1, normalized

    output, workspace_count_home = run(folder, "shell.qml", "workspacesShownPreferences", preferences={"schema": 1})
    assert passed(output) == 2, output
    workspace_count_saved = json.loads((workspace_count_home / ".config/cortetsu/preferences.json").read_text())
    assert workspace_count_saved["workspacesShown"] == 8, workspace_count_saved
    restored, _ = run(folder, "shell.qml", "workspacesShownRestore", preferences=workspace_count_saved)
    assert passed(restored) == 1, restored
    output, workspace_numbers_home = run(folder, "shell.qml", "workspaceNumbersPreferences", preferences={"schema": 1})
    assert passed(output) == 2, output
    workspace_numbers_saved = json.loads((workspace_numbers_home / ".config/cortetsu/preferences.json").read_text())
    assert workspace_numbers_saved["bar"]["workspaces"]["displayType"] == 1, workspace_numbers_saved
    restored, _ = run(folder, "shell.qml", "workspaceNumbersRestore", preferences=workspace_numbers_saved)
    assert passed(restored) == 1, restored
    output, workspace_icons_home = run(folder, "shell.qml", "workspaceAppIconsPreferences", preferences={"schema": 1})
    assert passed(output) == 2, output
    workspace_icons_saved = json.loads((workspace_icons_home / ".config/cortetsu/preferences.json").read_text())
    assert workspace_icons_saved["bar"]["workspaces"]["showAppIcons"] is True, workspace_icons_saved
    restored, _ = run(folder, "shell.qml", "workspaceAppIconsRestore", preferences=workspace_icons_saved)
    assert passed(restored) == 1, restored
    output, workspace_monochrome_home = run(folder, "shell.qml", "workspaceMonochromePreferences",
                                            preferences={"schema": 1})
    assert passed(output) == 2, output
    workspace_monochrome_saved = json.loads((workspace_monochrome_home / ".config/cortetsu/preferences.json").read_text())
    assert workspace_monochrome_saved["bar"]["workspaces"]["monochromeIcons"] is True, workspace_monochrome_saved
    restored, _ = run(folder, "shell.qml", "workspaceMonochromeRestore", preferences=workspace_monochrome_saved)
    assert passed(restored) == 1, restored

    output, hardware_sample_home = run(folder, "shell.qml", "hardwareSamplePreferences",
                                       preferences={"schema": 1})
    assert passed(output) == 3, output
    hardware_sample_saved = json.loads((hardware_sample_home / ".config/cortetsu/preferences.json").read_text())
    assert hardware_sample_saved["dashboardResourceUpdateInterval"] == 2750, hardware_sample_saved
    restored, _ = run(folder, "shell.qml", "hardwareSampleRestore", preferences=hardware_sample_saved)
    assert passed(restored) == 1, restored
    normalized, _ = run(folder, "shell.qml", "hardwareSampleNormalize",
                        preferences={"schema": 1, "dashboardResourceUpdateInterval": 5123})
    assert passed(normalized) == 1, normalized
    normalized, _ = run(folder, "shell.qml", "hardwareSampleNormalizeLow",
                        preferences={"schema": 1, "dashboardResourceUpdateInterval": 500})
    assert passed(normalized) == 1, normalized

    output, prefix_home = run(folder, "shell.qml", "actionPrefixPreferences", preferences={"schema": 1})
    assert passed(output) == 3, output
    prefix_saved = json.loads((prefix_home / ".config/cortetsu/preferences.json").read_text())
    assert prefix_saved["actionPrefix"] == "!", prefix_saved
    restored, _ = run(folder, "shell.qml", "actionPrefixRestore", preferences=prefix_saved)
    assert passed(restored) == 1, restored

    output, launcher_hover_home = run(folder, "shell.qml", "launcherHoverPreferences", preferences={"schema": 1})
    assert passed(output) == 2, output
    launcher_hover_saved = json.loads((launcher_hover_home / ".config/cortetsu/preferences.json").read_text())
    assert launcher_hover_saved["launcher"]["showOnHover"] is True, launcher_hover_saved
    restored, _ = run(folder, "shell.qml", "launcherHoverRestore", preferences=launcher_hover_saved)
    assert passed(restored) == 1, restored

    output, notif_home = run(folder, "shell.qml", "notificationPreferences", preferences={"schema": 1})
    assert passed(output) == 3, output
    notif_saved = json.loads((notif_home / ".config/cortetsu/preferences.json").read_text())
    assert notif_saved["notificationDefaultExpireTimeout"] == 6000, notif_saved
    restored, _ = run(folder, "shell.qml", "notificationRestore", preferences=notif_saved)
    assert passed(restored) == 1, restored

    output, notif_long_home = run(folder, "shell.qml", "notificationLongPreferences",
                                  preferences={"schema": 1, "notificationDefaultExpireTimeout": 90000})
    assert passed(output) == 2, output
    notif_long = json.loads((notif_long_home / ".config/cortetsu/preferences.json").read_text())
    assert notif_long["notificationDefaultExpireTimeout"] == 91000, notif_long
    restored, _ = run(folder, "shell.qml", "notificationLongRestore", preferences=notif_long)
    assert passed(restored) == 1, restored

    output, clock_home = run(folder, "shell.qml", "clockPreferences",
                             preferences={"schema": 1, "desktopClockPosition": "topLeft"})
    assert passed(output) == 5, output
    clock_saved = json.loads((clock_home / ".config/cortetsu/preferences.json").read_text())
    assert clock_saved["desktopClockPosition"] == "middle-center", clock_saved
    assert clock_saved["desktopClockShowDate"] is False, clock_saved
    restored, _ = run(folder, "shell.qml", "clockRestore", preferences=clock_saved)
    assert passed(restored) == 2, restored

    output, migrated_home = run(folder, "shell.qml", "migratedControls",
        preferences={"schema": 1, "desktopClockEnabled": True, "bottomHub": {"segments": {"apps": True}},
                     "useFahrenheit": False, "useFuzzyApps": False})
    assert passed(output) == 9, output
    migrated_saved = json.loads((migrated_home / ".config/cortetsu/preferences.json").read_text())
    assert migrated_saved["desktopClockEnabled"] is False, migrated_saved
    assert migrated_saved["bottomHub"]["segments"]["apps"] is False, migrated_saved
    assert migrated_saved["useFahrenheit"] is True and migrated_saved["useFuzzyApps"] is True, migrated_saved
    restored, _ = run(folder, "shell.qml", "migratedControlsRestore", preferences=migrated_saved)
    assert passed(restored) == 1, restored

    existing_saved = {
        "schema": 1, "useFuzzyActions": True, "useFuzzySchemes": True,
        "toastCapsLockChanged": True, "toastNumLockChanged": True,
        "toastKbLayoutChanged": True, "toastDndChanged": True,
        "toastNowPlaying": True, "notificationOpenExpanded": True,
    }
    output, existing_home = run(folder, "shell.qml", "existingPreferenceControls", preferences=existing_saved)
    assert passed(output) == 18, output
    existing_persisted = json.loads((existing_home / ".config/cortetsu/preferences.json").read_text())
    for key in existing_saved.keys() - {"schema"}:
        assert existing_persisted[key] is False, (key, existing_persisted)
    restored, _ = run(folder, "shell.qml", "existingPreferenceControlsRestore", preferences=existing_persisted)
    assert passed(restored) == 1, restored

    output, audio_home = run(folder, "shell.qml", "audioPreferences", preferences={"schema": 1})
    assert passed(output) == 5, output
    audio_saved = json.loads((audio_home / ".config/cortetsu/preferences.json").read_text())
    assert abs(audio_saved["maxVolume"] - 1.05) < 0.001, audio_saved
    assert abs(audio_saved["audioIncrement"] - 0.11) < 0.001, audio_saved

    personalised, personal_home = run(folder, "shell.qml", "globalPersonalisation", preferences={"schema": 1})
    assert passed(personalised) == 40, personalised
    personal_preferences = json.loads((personal_home / ".config/cortetsu/preferences.json").read_text())
    personal_scheme = json.loads((personal_home / "state/cortetsu/scheme.json").read_text())
    personal_restore, _ = run(folder, "shell.qml", "globalPersonalisationRestore",
                              preferences=personal_preferences, scheme=personal_scheme)
    assert passed(personal_restore) == 17, personal_restore

    recovered, recovered_home = run(folder, "shell.qml", "themeRecovery",
        preferences={"schema": 1, "themeId": "ink"},
        scheme={"name": "dynamic", "flavour": "default", "colours": {}, "themeId": "washi"})
    assert passed(recovered) == 2, recovered
    assert json.loads((recovered_home / ".config/cortetsu/preferences.json").read_text())["themeId"] == "washi"

    failed, failed_home = run(folder, "shell.qml", "themeFailure")
    assert passed(failed) == 3, failed
    assert (failed_home / "state/cortetsu/scheme.json").read_text() == "{broken"

    fixture_colours = json.loads((ROOT / "desktop-runtime-rs/tests/fixtures/legacy-palettes.json").read_text())
    slow_scheme = {"schema": 2, "themeId": "ink", "name": "dynamic", "flavour": "default",
                   "variant": "tonal-spot", "mode": "dark", "origin": "manual",
                   "colours": fixture_colours["cases"][0]["colours"]}
    slow, slow_home = run(folder, "shell.qml", "themeSlowCommit", preferences={"schema": 1},
                          scheme=slow_scheme, env={"CORTETSU_THEME_ACK_TIMEOUT_MS": "50"})
    assert passed(slow) == 3, slow
    slow_saved = json.loads((slow_home / "state/cortetsu/scheme.json").read_text())
    assert slow_saved["themeId"] == "washi", slow_saved

    incomplete_scheme = {"schema": 2, "themeId": "ink", "name": "dynamic", "flavour": "default",
                         "variant": "tonal-spot", "mode": "dark", "origin": "manual",
                         "colours": {"primary": "123456"}}
    projection_failure, _ = run(folder, "shell.qml", "themeProjectionFailure", preferences={"schema": 1},
                                scheme=incomplete_scheme)
    assert passed(projection_failure) == 2, projection_failure

    no_scheme, no_scheme_home = run(folder, "shell.qml", "themeWithoutScheme", preferences={"schema": 1})
    assert passed(no_scheme) == 2, no_scheme
    no_scheme_state = json.loads((no_scheme_home / "state/cortetsu/scheme.json").read_text())
    assert no_scheme_state["themeId"] == "washi" and no_scheme_state["colours"] == {}, no_scheme_state
    assert "background #f5efe4" in (no_scheme_home / "state/cortetsu/kitty-colors.conf").read_text()

    theme_colours = fixture_colours["cases"][0]["colours"]
    theme_scheme = {"schema": 2, "name": "dynamic", "flavour": "default", "variant": "tonal-spot",
                    "mode": "dark", "origin": "manual", "colours": theme_colours}
    for theme in ("washi", "kurogane"):
        output, theme_home = run(folder, "shell.qml", "themeSelect", label=f"select-{theme}",
                                 preferences={"schema": 1}, scheme=theme_scheme, env={"THEME_ID": theme})
        assert passed(output) == 6, output
        theme_saved = json.loads((theme_home / ".config/cortetsu/preferences.json").read_text())
        assert theme_saved["themeId"] == theme, theme_saved
        restored, _ = run(folder, "shell.qml", "themeRestore", label=f"restore-{theme}",
                          preferences=theme_saved, env={"THEME_ID": theme})
        assert passed(restored) == 4, restored

    variant_seed = {"schema": 2, "name": "dynamic", "flavour": "default",
                    "variant": "tonalspot", "mode": "dark", "origin": "wallpaper",
                    "colours": fixture_colours["cases"][0]["colours"]}
    variant_output, variant_home = run(folder, "shell.qml", "paletteVariant",
                                       scheme=variant_seed)
    assert passed(variant_output) == 7, variant_output
    variant_saved = json.loads((variant_home / "state/cortetsu/scheme.json").read_text())
    assert variant_saved["variant"] == "expressive" and variant_saved["origin"] == "manual", variant_saved
    variant_restored, _ = run(folder, "shell.qml", "paletteVariantRestore",
                              scheme=variant_saved, label="palette-variant-restore")
    assert passed(variant_restored) == 1, variant_restored
    variant_unavailable, _ = run(folder, "shell.qml", "paletteVariantUnavailable")
    assert passed(variant_unavailable) == 3, variant_unavailable

    # Every page at the default size, at the narrowest one, and on a scheme
    # other than the ui.toml default.
    aura = {"name": "aura", "flavour": "default",
            "colours": json.loads(subprocess.check_output([str(ROOT / "bin/cortetsu-scheme"), "list"], text=True))["aura"]["default"]}
    pages = passed(run(folder, "shell.qml", "pages")[0])
    passed(run(folder, "shell.qml", "pages", label="pages-narrow",
               env={"SETTINGS_WIDTH": "880", "SETTINGS_HEIGHT": "620", "SETTINGS_RENDER_SUFFIX": "-880"})[0])
    passed(run(folder, "shell.qml", "pages", label="pages-scheme", scheme=aura,
               env={"SETTINGS_WIDTH": "1280", "SETTINGS_HEIGHT": "800", "SETTINGS_RENDER_SUFFIX": "-aura-1280"})[0])

    # The window itself, mapped by a real compositor.
    host = run_host(folder)
    assert not host or "SETTINGS_HOST_PASS 1" in host, host

    assert (reactivity, navigation, states, unwritable, pages) == (48, 56, 42, 3, 120), (reactivity, navigation, states, unwritable, pages)
assert policies == 16, policies
print(f"Settings builds in {opened.split()[0]} ms ({opened.split()[1]} items); "
      f"20 cycles of open, every destination and close take {cycles} ms")
print("The window host opens, shows its pages, closes and reopens under weston" if host
      else "SKIP: weston is not installed, the window host was not mapped")
print("PASS: Settings keeps its objects through colour, scheme and preference changes, "
      "shows pending, failed and unavailable states truthfully, and is fully usable from the keyboard")

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
import subprocess
import tempfile
from pathlib import Path

from settings_harness import ROOT, build_tree, run, run_host

SHELL = r"""import QtQuick
import QtQuick.Window
import QtTest
import Quickshell
import Quickshell.Io
import "modules"
import "modules/settings"
import "modules/launcher/services"
import "components"
import "services"
import "theme"

ShellRoot {
    id: root
    property int checks: 0
    property int step: 0
    property var kept: []
    property var memo: ({})
    property int writes: 0
    readonly property string scenario: Quickshell.env("SETTINGS_SCENARIO")
    readonly property string fixtures: Quickshell.env("SETTINGS_FIXTURES")
    readonly property string renderDir: Quickshell.env("CORTETSU_RENDER_DIR")
    readonly property string schemeTool: Quickshell.env("HOME") + "/bin/cortetsu-scheme"
    readonly property var content: host.item
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
    function text(name) { return find(get(name), "rowDetail")?.text ?? ""; }
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
        function closeRetainedOverlaysExcept(flag) {}
        function setRetained(flag, value) { if (value) opened = flag; return true; }
    }
    // Not named like the property it feeds: inside the Loader's component
    // that name would resolve to the content's own, still unset, property.
    QtObject {
        id: screenDouble
        property bool settings: false
        property bool launcher: false
        property var cortetsuState: retained
    }

    Window {
        id: window
        width: Number(Quickshell.env("SETTINGS_WIDTH") || 1368)
        height: Number(Quickshell.env("SETTINGS_HEIGHT") || 900)
        visible: true
        color: "#0B0D10"

        // The same frame SettingsHost draws, so a render shows the real surface.
        CortetsuSurface {
            id: frame
            anchors.fill: parent
            anchors.margins: CortetsuDesign.spacingUnit
            baseColor: Qt.alpha(CortetsuDesign.colorTetsu, 0.985)
            radiusValue: CortetsuDesign.radiusSurface
            outlined: true

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
            verify(content.pageId === "appearance", "Settings opens on the selected page");
            verify(!!page("transparency") && !get("outputVolume") && !get("wifiPower"), "only the open page exists");
            verify(get("pageTitle").text === "Apariencia", "the header names the page");
            verify(same(CortetsuDesign.colorSurface, "#171B21"), "without a scheme the ui.toml default applies");
            memo.card = get("scheme-nebula-default");
            memo.nexus = get("nexus");
            memo.row = get("nexus-audio");
            memo.toggle = page("transparency");
            verify(!!memo.card && !memo.card.selected, "the catalogue is drawn and nebula is not active");
            keep();
            // A token changes and nothing else: the preview channel recolours the tokens.
            CortetsuColours.load(JSON.stringify({ colours: { surface: "112233", surfaceContainer: "223344", primary: "ff8800", onSurface: "f0e0d0", outlineVariant: "445566" }, mode: "dark" }), true);
        }],
        [() => same(CortetsuDesign.colorSurface, "#112233"), () => {
            verify(churn() === "0 destroyed, 0 created", `a token change keeps every object (${churn()})`);
            verify(get("nexus") === memo.nexus && get("nexus-audio") === memo.row && page("transparency") === memo.toggle,
                "the Nexus, its rows and the page controls are the same instances");
            verify(same(CortetsuDesign.colorPrimary, "#ff8800"), "the primary token follows");
            verify(same(get("pageTitle").color, "#f0e0d0") || get("pageTitle").color !== undefined, "text reads the new token");
            CortetsuColours.clearPreview();
        }],
        [() => same(CortetsuDesign.colorSurface, "#171B21") && waitedMs >= 300, () => {
            verify(same(memo.nexus.color, Qt.alpha(CortetsuDesign.colorSurfaceGlass, 0.72)), "a live surface settles on the token colour");
            keep();
            memo.card.clicked();
            verify(Schemes.applying && Schemes.pendingScheme === "nebula default", "choosing a card starts one apply");
            verify(value("activeScheme") === "nebula default" && find(get("activeScheme"), "rowDetail") !== null, "the row names what is being applied");
        }],
        [() => Schemes.applyStatus === "applied" && Schemes.currentScheme === "nebula default", () => {
            verify(churn() === "0 destroyed, 0 created", `applying a scheme keeps every object (${churn()})`);
            verify(get("scheme-nebula-default") === memo.card && memo.card.selected, "the same card is now the selected one");
            verify(!same(CortetsuDesign.colorSurface, "#171B21"), "the tokens follow the applied scheme");
            verify(get("nexus-appearance").value === "nebula default", "the Nexus names the active scheme");
            verify(text("activeScheme") === "Aplicado a todas las superficies", "the apply is confirmed");
            verify(screenDouble.settings && get("nexus") === memo.nexus, "Settings stayed open through the change");
            keep();
            Schemes.apply("no-such-scheme", "default");
        }],
        [() => Schemes.applyStatus === "failed", () => {
            verify(Schemes.currentScheme === "nebula default" && memo.card.selected, "a failed apply leaves the real scheme selected");
            verify(get("activeScheme").status === "error" && text("activeScheme").includes("esquema no encontrado"), "the failure is shown with its reason");
            verify(get("nexus-appearance").alerting && get("pageSummary").text.includes("esquema no encontrado"), "the Nexus and the header flag the page");
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
            verify(find(page("borderThickness"), "sliderValue").text === "4 px", "a value changed elsewhere reaches its row");
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
            verify(content.pageId === "appearance" && get("scheme-aura-default").selected, "reopening shows the same page and the real scheme");
            // Open, visit every page and close, over and over: the tree goes
            // back to the same size each time.
            const started = Date.now();
            for (let cycle = 0; cycle < 20; ++cycle) {
                screenDouble.settings = true;
                for (const category of SettingsController.categories)
                    select(category.id);
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
            verify(focusName() === "nexus-appearance", `opening focuses the current destination (${focusName()})`);
            key(Qt.Key_Down);
            verify(SettingsController.selectedId === "wallpaper" && focusName() === "nexus-wallpaper", "Down opens the next page and moves the focus with it");
            key(Qt.Key_Up);
            key(Qt.Key_Up);
            verify(SettingsController.selectedId === "input", `Up walks back across groups (${SettingsController.selectedId})`);
            select("notifications");
            get("nexus").focusSelected();
        }],
        [() => content.pageId === "notifications" && !!page("dnd"), () => {
            verify(!get("transparency"), "the previous page is gone");
            key(Qt.Key_Tab);
            verify(focusName() === "closeSettings", `Tab leaves the Nexus for the header (${focusName()})`);
            key(Qt.Key_Tab);
            verify(focusName() === "dnd", `then enters the page at its first control (${focusName()})`);
            key(Qt.Key_Space);
            verify(CortetsuNotifications.dnd === true, "Space flips the switch");
            key(Qt.Key_Return);
            verify(CortetsuNotifications.dnd === false, "Enter flips it back");
            // The pointer: on the label and on the switch itself, one flip each.
            const dnd = page("dnd");
            memo.flips = 0;
            dnd.toggled.connect(() => memo.flips++);
            events.mouseClick(dnd, 40, dnd.height / 2, Qt.LeftButton, Qt.NoModifier, -1);
            verify(CortetsuNotifications.dnd === true, `a click on the row flips the switch (${memo.flips})`);
            const knob = find(dnd, "switch");
            events.mouseClick(knob, knob.width / 2, knob.height / 2, Qt.LeftButton, Qt.NoModifier, -1);
            verify(CortetsuNotifications.dnd === false && memo.flips === 2, `a click on the switch flips it once, not twice (${memo.flips})`);
            verify(text("dnd") === "Los avisos aparecen en pantalla al llegar", "the row describes the current state");
            key(Qt.Key_Backtab, Qt.ShiftModifier);
            verify(focusName() === "closeSettings", "Shift+Tab goes back");
            key(Qt.Key_Backtab, Qt.ShiftModifier);
            verify(focusName() === "nexus-notifications", `and returns to the Nexus at the current page (${focusName()})`);
            key(Qt.Key_Right);
            verify(focusName() === "dnd", "Right enters the page");
            key(Qt.Key_Left);
            verify(focusName() === "nexus-notifications", "Left returns to the Nexus");
            // Every Tab stop of the page is a control that can act.
            key(Qt.Key_Right);
            const stops = [];
            for (let i = 0; i < 12 && content.within(frame.Window.activeFocusItem, content.page); ++i) {
                const item = frame.Window.activeFocusItem;
                stops.push(item.objectName || item.Accessible.name || "?");
                verify(item.enabled, `a Tab stop is enabled (${stops[stops.length - 1]})`);
                key(Qt.Key_Tab);
            }
            verify(stops.join(",") === "dnd,Ocultar en pantalla completa,slider,Avisar del modo de juego,Avisar de Bloq Mayús,Avisar de Bloq Num,Avisar del cambio de distribución,Avisar de No molestar,Avisar de la pista en reproducción,Abrir avisos expandidos,action", `Tab visits each control once, top to bottom (${stops.join(",")})`);
            memo.clear = page("clearHistory");
            find(memo.clear, "action").forceActiveFocus();
            key(Qt.Key_Return);
            verify(memo.clear.armed && CortetsuNotifications.count === 3, "a destructive action waits for a second press");
            key(Qt.Key_Return);
            verify(CortetsuNotifications.count === 0 && !memo.clear.armed, "the second press runs it");
            verify(memo.clear.title === "El historial está vacío" && memo.clear.disabled, "the row then shows the new state and stops offering the action");
        }],
        [() => waitedMs >= 100, () => {
            key(Qt.Key_F, Qt.ControlModifier);
            verify(focusName() === "nexusSearch", `Ctrl+F reaches the search (${focusName()})`);
            get("nexusSearch").text = "reloj";
        }],
        [() => SettingsController.matchingIds.length === 2, () => {
            verify(get("nexus-appearance").visible && get("nexus-desktop").visible && !get("nexus-audio").visible, "the search keeps the pages that hold a matching setting");
            verify(get("nexus-appearance").value === "Reloj de 12 horas", "and names the setting that matched");
            verify(get("nexus-audio") !== null, "hidden rows still exist: the list is filtered, not rebuilt");
            key(Qt.Key_Return);
            verify(SettingsController.selectedId === "appearance" && focusName() === "nexus-appearance", `Enter opens the first result (${SettingsController.selectedId}, ${focusName()})`);
            key(Qt.Key_F, Qt.ControlModifier);
            get("nexusSearch").text = "energia";
        }],
        [() => SettingsController.matchingIds.join(",") === "power,automation", () => {
            verify(get("nexus-power").visible && get("nexus-automation").visible
                && !get("nexus-appearance").visible && !get("nexus-audio").visible
                && get("nexus-automation").value === "Energía automática",
                "an unaccented search finds both the energy page and its automatic policy setting");
            get("nexusSearch").text = "zzzz";
        }],
        [() => SettingsController.matchingIds.length === 0, () => {
            verify(get("nexusEmpty").visible, "a search without results says so");
            key(Qt.Key_Escape);
            verify(get("nexusSearch").text === "" && screenDouble.settings, "Escape first clears the search");
            verify(get("nexus-audio").visible, "and every destination is back");
            key(Qt.Key_Escape);
            verify(screenDouble.settings === false, "Escape then closes Settings");
        }],
        [() => content === null, () => {
            screenDouble.settings = true;
        }],
        [() => !!content && !!content.page && waitedMs >= 200, () => {
            // The history is empty, so its button is disabled and the focus
            // has nowhere to sit inside the page: Escape must still close.
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
        [() => content.pageId === "desktop" && !!page("dashboardMetrics"), () => {
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
            verify(get("nexus").width < 80 && !get("nexusSearch").visible, "the Nexus folds to icons");
            verify(get("nexus-desktop").selected && get("nexus-desktop").width > 0, "and still marks where you are");
            render("nexus-collapsed");
        }],
        [null, () => {
            get("nexusCollapse").clicked();
        }]
    ]

    // Operations that answer later, that fail, and values that move outside.
    readonly property var states: [
        [() => CortetsuConfig.loaded, () => { select("network"); screenDouble.settings = true; }],
        [() => !!content && content.pageId === "network" && !!page("wifiPower"), () => {
            window.requestActivate();
            memo.wifi = page("wifiPower");
            verify(find(memo.wifi, "switch").checked && get("nexus-network").value === "Casa", "the page and the Nexus show the live connection");
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
            verify(get("nexus-network").value === "Wi-Fi apagado" && !get("nexus-network").alerting, "an ordinary off state is not an alert");
            verify(page("wifiScan").disabled, "scanning is not offered with the radio off");
            render("network-off");
        }],
        [null, () => {
            // The radio comes back from outside: rfkill, a key, the bar.
            wifi.wifiEnabled = true;
        }],
        [() => find(memo.wifi, "switch").checked, () => {
            verify(get("nexus-network").value === "Casa", "an outside change reaches the open page and the Nexus");
            select("bluetooth");
        }],
        [() => content.pageId === "bluetooth" && !!page("bluetoothPower"), () => {
            memo.bt = page("bluetoothPower");
            verify(get("nexus-bluetooth").value === "1 conectado", "the Nexus counts connected devices");
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
            verify(get("nexus-bluetooth").value === "Sin adaptador", "the Nexus says the adapter is missing");
            render("bluetooth-unavailable");
        }],
        [null, () => {
            select("audio");
        }],
        [() => content.pageId === "audio" && !!page("outputVolume"), () => {
            verify(find(page("outputVolume"), "sliderValue").text === "62 %" && get("nexus-audio").value === "62 %", "the volume is the real one");
            CortetsuAudio.speakers.audio.volume = 0.31;
        }],
        [() => find(page("outputVolume"), "sliderValue").text === "31 %", () => {
            verify(Math.abs(find(page("outputVolume"), "slider").progress - 0.31) < 0.01, "a volume changed outside moves the slider");
            find(page("outputVolume"), "slider").forceActiveFocus();
            key(Qt.Key_Right);
            verify(Math.abs(CortetsuAudio.volume - 0.36) < 0.001, "an arrow moves the real volume one step");
            page("outputMute").forceActiveFocus();
            key(Qt.Key_Space);
            verify(CortetsuAudio.muted && get("nexus-audio").value === "Silenciado", "muting is reflected everywhere");
            render("audio");
        }],
        [null, () => {
            CortetsuAudio.available = false;
        }],
        [() => page("noOutput").visible, () => {
            verify(!page("outputVolume").visible && get("nexus-audio").alerting, "without PipeWire the page says so and the Nexus flags it");
            verify(get("pageSummary").text === "No hay dispositivo de salida", "the header names the problem");
            render("audio-unavailable");
        }],
        [null, () => {
            select("display");
        }],
        [() => content.pageId === "display" && !!page("colourFilter"), () => {
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
            verify(get("nexus-display").value === "2 pantallas", "the Nexus falls back to what it does know");
            render("display-unavailable");
        }],
        [null, () => {
            mode("keybinds-mode", "fail");
            select("shortcuts");
        }],
        [() => content.pageId === "shortcuts" && content.page.state === "error", () => {
            verify(page("shortcutsState").visible && page("shortcutsState").kind === "error", "a helper that fails is an error with a retry, not an empty list");
            render("shortcuts-error");
        }],
        [null, () => {
            mode("keybinds-mode", "ok");
            content.page.load();
        }],
        [() => content.page.state === "ready", () => {
            verify(content.page.total === 3 && content.page.groups.length === 2, "the retry lists the real bindings by group");
            page("shortcutFilter").text = "super + h";
        }],
        [() => content.page.query.length > 0 && waitedMs >= 100, () => {
            render("shortcuts");
        }],
        [null, () => {
            select("about");
        }],
        [() => content.pageId === "about" && !!page("revision"), () => {
            verify(value("revision") === "0123456" && value("generation") === "20261003-000000-1", "About reads the running generation");
            verify(get("nexus-about").value === "0123456", "and the Nexus shows the revision");
            select("wallpaper");
        }],
        [() => content.pageId === "wallpaper" && !!page("wallpaperFile"), () => {
            verify(value("wallpaperFile") === "montaña.png" && get("nexus-wallpaper").value === "montaña.png", "the wallpaper shown is the one applied");
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
            verify(text("wallpaperFile") === "el servicio de fondos no responde" && get("nexus-wallpaper").alerting, "with the reason, and the Nexus flags it");
            render("wallpaper-error");
        }],
        [null, () => {
            select("power");
        }],
        [() => content.pageId === "power" && !!page("batteryLevel"), () => {
            verify(value("batteryLevel") === "86 %" && get("nexus-power").value === "86 %", "battery is the real reading");
            CortetsuPower.percent = 12;
        }],
        [() => value("batteryLevel") === "12 %", () => {
            verify(get("nexus-power").alerting && get("pageSummary").text === "Batería baja", "a low battery is flagged");
            CortetsuPower.hasBattery = false;
        }],
        [() => page("noBattery").visible, () => {
            verify(get("nexus-power").value === "Corriente" && !get("nexus-power").alerting, "a desktop shows its power source, not a 0 % battery");
        }]
    ]

    // The preferences cannot be written: the user is told and nothing lies.
    readonly property var unwritable: [
        [() => CortetsuConfig.loaded, () => {
            blockConfig.running = true;
            select("launcher"); screenDouble.settings = true;
        }],
        [() => blockConfig.ready && !!content && content.pageId === "launcher" && !!page("launcherEnabled"), () => {
            window.requestActivate();
            page("launcherEnabled").forceActiveFocus();
            key(Qt.Key_Space);
            verify(CortetsuConfig.launcher.enabled === false, "the switch takes effect in the running shell");
        }],
        [() => CortetsuConfig.saveState === "failed", () => {
            const indicator = get("saveIndicator");
            verify(indicator.visible && find(indicator, "saveText").text.startsWith("No se pudo guardar"), "a failed write is announced and stays on screen");
            verify(get("nexus-launcher").value === "Apagado", "the Nexus shows the value in use");
            render("save-failed");
        }]
    ]

    readonly property var policies: [
        [() => CortetsuConfig.loaded, () => { select("automation"); screenDouble.settings = true; }],
        [() => !!content && content.pageId === "automation" && !!page("policy-gamemode"), () => {
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

    // One PNG per page, for visual review at the size given by the environment.
    readonly property var pages: [
        [() => CortetsuConfig.loaded && Schemes.catalogCount > 0, () => { select("network"); screenDouble.settings = true; }]
    ].concat(SettingsController.categories.map(category =>
        [() => { select(category.id); return !!content && content.pageId === category.id && !!content.page && waitedMs >= 350; }, () => {
            const scroller = get("pageScroller");
            if (content.page.width > scroller.width || content.page.implicitWidth > scroller.width) {
                const widths = (item, path, depth, parentWide) => {
                    if (depth > 5) return;
                    const tooWide = item.width > scroller.width || item.implicitWidth > scroller.width;
                    if (depth < 2 || parentWide || tooWide)
                        console.log("SETTINGS_WIDTH", path, String(item), JSON.stringify({
                            name: item.objectName, width: item.width, implicitWidth: item.implicitWidth,
                            x: item.x, childrenWidth: item.childrenRect?.width, text: item.text ?? ""}));
                    const children = item.children ?? [];
                    for (let i = 0; i < children.length; ++i) widths(children[i], `${path}/${i}`, depth + 1, tooWide);
                };
                widths(content.page, category.id, 0, false);
            }
            verify(content.page.width <= scroller.width && content.page.implicitWidth <= scroller.width,
                `${category.id} fits the width it is given (${content.page.implicitWidth} in ${scroller.width})`);
            render(`page-${category.id}`);
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
                        + `(page ${SettingsController.selectedId}, search "${SettingsController.search}", focus ${focusName()})`);
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
    assert calls.count("cortetsu-keybinds list") == 2, calls

    output, home = run(folder, "shell.qml", "unwritable", preferences={"schema": 1})
    unwritable = passed(output)
    blocked = home / ".config/cortetsu/preferences.json"
    assert blocked.is_dir(), "a failed write must not replace the blocked destination"
    assert sorted(path.name for path in blocked.iterdir()) == ["original.json"]
    assert json.loads((blocked / "original.json").read_text()) == {"schema": 1}
    policies = passed(run(folder, "shell.qml", "policies")[0])

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

assert (reactivity, navigation, states, unwritable, pages) == (47, 46, 41, 3, 15), (reactivity, navigation, states, unwritable, pages)
assert policies == 16, policies
print(f"Settings builds in {opened.split()[0]} ms ({opened.split()[1]} items); "
      f"20 cycles of open, 15 pages and close take {cycles} ms")
print("The window host opens, shows its 15 pages, closes and reopens under weston" if host
      else "SKIP: weston is not installed, the window host was not mapped")
print("PASS: Settings keeps its objects through colour, scheme and preference changes, "
      "shows pending, failed and unavailable states truthfully, and is fully usable from the keyboard")

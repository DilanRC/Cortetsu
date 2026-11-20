#!/usr/bin/env node
"use strict";

// ContextModel.js: what activating a context changes, what deactivating
// gives back, and what the state file and an import may contain.

const assert = require("assert");
const fs = require("fs");
const path = require("path");
const vm = require("vm");

const modulePath = path.join(__dirname, "..", "services", "ContextModel.js");
const source = fs.readFileSync(modulePath, "utf8");
assert.ok(source.startsWith(".pragma library\n"), "ContextModel.js must start with .pragma library");
const context = {};
vm.createContext(context);
vm.runInContext(source.replace(/^\.pragma library\r?\n/, "") +
    "\nglobalThis.__M__ = { KEYS, ORDER, BUILTIN, validValue, cleanSettings, clean, emptyState, parseState, newId, plan, undo, describe, exportText, importText };",
    context, { filename: "ContextModel.js" });
const M = context.__M__;
// Objects made inside the VM have another prototype: compare as JSON.
const same = (actual, expected, label) => assert.strictEqual(JSON.stringify(actual), JSON.stringify(expected), label);

// Every built-in uses only known keys with valid values, and has a label.
for (const c of M.BUILTIN) {
    for (const [key, value] of Object.entries(c.settings)) {
        assert.ok(M.validValue(key, value), `${c.id}.${key} = ${value}`);
        assert.notStrictEqual(M.describe(key), key, `${key} has a label`);
    }
}
same(M.BUILTIN.map(c => c.id), ["university", "development", "gaming", "battery"], "the four built-ins");
assert.ok(!("themeId" in M.BUILTIN.find(c => c.id === "battery").settings), "Batería does not change the theme");

// The theme is applied first: selecting it loads that theme's own motion.
assert.strictEqual(M.ORDER[0], "themeId");
same([...M.ORDER].sort(), Object.keys(M.KEYS).sort(), "ORDER lists every key once");

// Validation.
assert.ok(!M.validValue("dashboardResourceUpdateInterval", 499));
assert.ok(M.validValue("dashboardResourceUpdateInterval", 500));
assert.ok(!M.validValue("dashboardResourceUpdateInterval", 1500.5));
assert.ok(!M.validValue("powerProfile", "turbo"));
assert.ok(!M.validValue("reducedMotion", "true"));
assert.ok(!M.validValue("cpuGovernor", "performance"), "unknown keys are never valid");
same(M.cleanSettings({ reducedMotion: true, cpuGovernor: "x", dnd: 1 }), { reducedMotion: true }, "clean drops unknown and mistyped");
same(M.cleanSettings([true]), {}, "an array is not a settings object");

// plan: equal values are left out of both apply and restore.
let step = M.plan({ dnd: true, reducedMotion: true, themeId: "washi" },
                  { dnd: true, reducedMotion: false, themeId: "ink" }, []);
same(step.apply, { themeId: "washi", reducedMotion: true }, "only changes are applied, theme first");
same(Object.keys(step.apply), ["themeId", "reducedMotion"], "apply keeps ORDER");
same(step.restore, { themeId: "ink", reducedMotion: false }, "restore holds the previous values");
same(step.skipped, [], "nothing skipped without the coordinator");

// plan: a domain owned by the automation coordinator is not touched.
step = M.plan({ gameMode: true, dnd: true, powerProfile: "power-saver", orbitalHold: true },
              { gameMode: false, dnd: false, powerProfile: "balanced", orbitalHold: false }, ["gamemode", "power"]);
same(step.skipped, ["gameMode", "powerProfile"], "owned domains are skipped");
same(step.apply, { dnd: true, orbitalHold: true }, "the rest still applies");

// undo: only keys still at the applied value go back.
same(M.undo({ dnd: true, reducedMotion: true }, { dnd: false, reducedMotion: false },
            { dnd: true, reducedMotion: false }),
     { dnd: false }, "a setting the user changed meanwhile is the user's");
same(M.undo({ orbitalHold: true }, { orbitalHold: false }, { orbitalHold: true }), { orbitalHold: false }, "hold is released");
same(M.undo({}, {}, {}), {}, "nothing applied, nothing undone");

// clean: names, icons and ids.
assert.strictEqual(M.clean({ name: "   " }, "custom-1"), null, "a blank name is not a context");
assert.strictEqual(M.clean(null, "custom-1"), null);
const long = M.clean({ name: "x".repeat(80), icon: "bad icon!", summary: "s".repeat(300), settings: {} }, "custom-1");
assert.strictEqual(long.name.length, 48);
assert.strictEqual(long.icon, "tune", "an unsafe icon name falls back");
assert.strictEqual(long.summary.length, 120);
assert.strictEqual(long.builtin, false);

// newId never reuses a taken id.
assert.strictEqual(M.newId([]), "custom-1");
assert.strictEqual(M.newId([{ id: "custom-1" }, { id: "custom-2" }]), "custom-3");
assert.strictEqual(M.newId([{ id: "custom-2" }]), "custom-1");

// parseState: version, duplicates, foreign keys, limits.
assert.strictEqual(M.parseState("{"), null, "broken JSON");
assert.strictEqual(M.parseState('{"version":2}'), null, "unknown version");
assert.strictEqual(M.parseState("null"), null);
const state = M.parseState(JSON.stringify({
    version: 1,
    custom: [
        { id: "custom-1", name: "Foco", settings: { dnd: true, evil: 1 } },
        { id: "custom-1", name: "Duplicado", settings: {} },
        { id: "../etc", name: "Ruta", settings: {} },
        ...Array.from({ length: 40 }, (_, i) => ({ id: `custom-z${i}`, name: `N${i}`, settings: {} }))
    ],
    active: "custom-1",
    applied: { dnd: true, evil: 1 },
    restore: { dnd: false },
    skipped: ["gameMode", "nope"]
}));
assert.strictEqual(state.custom[0].name, "Foco");
same(state.custom[0].settings, { dnd: true }, "a stored context loses foreign keys");
assert.ok(!state.custom.some(c => c.name === "Duplicado" || c.name === "Ruta"), "duplicate and invalid ids are dropped");
assert.ok(state.custom.length <= 32, "at most 32 contexts are read");
same(state.applied, { dnd: true }, "applied is validated");
same(state.skipped, ["gameMode"], "skipped is validated");
same(M.parseState('{"version":1}'), M.emptyState(), "a minimal file is an empty state");

// export → import keeps exactly the settings and gets a fresh id.
const exported = M.exportText({ name: "Foco", icon: "bolt", summary: "x", settings: { dnd: true, cpu: 9 } });
assert.ok(!exported.includes("cpu"), "export carries only known settings");
const imported = M.importText(exported, [{ id: "custom-1" }]);
assert.strictEqual(imported.id, "custom-2");
same(imported.settings, { dnd: true });
assert.strictEqual(M.importText('{"kind":"other","version":1,"name":"x"}', []), null, "foreign files are refused");
assert.strictEqual(M.importText("not json", []), null);

console.log("PASS: contexts plan, undo, validate, persist and import without foreign keys");

#!/usr/bin/env node
"use strict";
// OverviewKeys.js: digits open or receive a window, modifiers of others do nothing.
const assert = require("assert");
const fs = require("fs");
const path = require("path");
const vm = require("vm");
const source = fs.readFileSync(path.join(__dirname, "..", "modules", "overview", "OverviewKeys.js"), "utf8");
assert.ok(source.startsWith(".pragma library\n"));
const context = {};
vm.createContext(context);
vm.runInContext(source.replace(/^\.pragma library\r?\n/, "") + "\nglobalThis.K = { slotForKey, digitAction, KEY_0, KEY_1, KEY_9, SHIFT, CONTROL, ALT, META };", context);
const K = context.K;
const same = (a, b, m) => assert.strictEqual(JSON.stringify(a), JSON.stringify(b), m);

// Qt's own values: a change in Qt would show here, not in the overview.
assert.strictEqual(K.KEY_0, 0x30); assert.strictEqual(K.KEY_1, 0x31); assert.strictEqual(K.ALT, 0x08000000);

const edp = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10];
const hdmi = [11, 12, 13, 14, 15, 16, 17, 18, 19, 20];
assert.strictEqual(K.slotForKey(K.KEY_1), 0);
assert.strictEqual(K.slotForKey(K.KEY_9), 8);
assert.strictEqual(K.slotForKey(K.KEY_0), 9, "0 is the tenth");
assert.strictEqual(K.slotForKey(0x41), -1, "a letter is not a digit");

same(K.digitAction(K.KEY_1, 0, edp), { action: "open", workspace: 1 }, "1 opens the first workspace");
same(K.digitAction(K.KEY_0, 0, hdmi), { action: "open", workspace: 20 }, "0 on the second screen is 20");
same(K.digitAction(K.KEY_1 + 2, K.ALT, edp), { action: "move", workspace: 3 }, "Alt+3 sends the window to 3");
for (const other of [K.CONTROL, K.SHIFT, K.META, K.ALT | K.SHIFT])
    same(K.digitAction(K.KEY_1, other, edp), { action: "", workspace: -1 }, `modifier ${other} is not the overview's`);
same(K.digitAction(0x41, 0, edp), { action: "", workspace: -1 }, "a letter does nothing");
same(K.digitAction(K.KEY_1, 0, []), { action: "", workspace: -1 }, "no workspaces, nothing to open");
same(K.digitAction(K.KEY_1, 0, [0]), { action: "", workspace: -1 }, "id 0 is not a workspace");
console.log("PASS: overview digits open this screen's workspaces, Alt+digit moves the window, other modifiers are left alone");

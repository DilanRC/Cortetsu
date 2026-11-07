#!/usr/bin/env node
"use strict";

const assert = require("node:assert/strict");
const vm = require("node:vm");
const fs = require("node:fs");
const source = fs.readFileSync(new URL("../modules/BatteryPolicy.js", `file://${__filename}`), "utf8");
const monitor = fs.readFileSync(new URL("../modules/BatteryMonitor.qml", `file://${__filename}`), "utf8");
assert.match(monitor, /BatteryPolicy\.crossedLowWarning\(lastPercentage, percentage, CortetsuConfig\.batteryLowWarningPercent\)/);
assert.match(monitor, /percentage <= 3 && !criticalNoticeSent/);
const context = {};
vm.runInNewContext(source.replace(".pragma library", "")
    + "\nglobalThis.__exports = { crossedLowWarning };", context);
const policy = context.__exports;

assert.equal(policy.crossedLowWarning(11, 10, 10), true);
assert.equal(policy.crossedLowWarning(100, 19, 20), true);
assert.equal(policy.crossedLowWarning(20, 20, 20), false);
assert.equal(policy.crossedLowWarning(19, 15, 20), false);
assert.equal(policy.crossedLowWarning(10, 8, 10), false);
assert.equal(policy.crossedLowWarning(80, 0, 0), true);
assert.equal(policy.crossedLowWarning(80, 0, -1), false);
assert.equal(policy.crossedLowWarning(Number.NaN, 10, 10), false);
console.log("test-battery-policy.node: OK (threshold crossing and invalid inputs)");

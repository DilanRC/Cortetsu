#!/usr/bin/env node
// Read-only check of the running Hyprland against the installed layer rules.
//
//   node scripts/integration/check-live-layer-rules.cjs
//
// What it can prove: which shell surfaces exist now (`hyprctl layers -j`) and
// whether each rule of the installed generation names one of them, or names a
// surface the shell only maps on demand (area picker, border exclusions).
//
// What it cannot prove: that Hyprland has loaded those rules. Measured in a
// nested Hyprland 0.56.2 (2026-10-23): repointing `dotfiles/current` does not
// reload the config; `hyprctl reload config-only` does, and the rules then
// apply to surfaces that are already mapped (no Quickshell restart needed);
// a reload writes nothing to hyprland.log; no Lua or hyprctl call lists the
// rules in force. So when the generation is newer than the compositor, the
// verdict is RELOAD_REQUIRED unless you know a reload happened since.
// Nothing here reloads, dispatches or writes.
"use strict";
const fs = require("fs");
const path = require("path");
const { execFileSync } = require("child_process");

const home = process.env.HOME;
const current = path.join(home, ".local/share/cortetsu/dotfiles/current");
const rulesPath = path.join(current, "home/.config/hypr/hyprland/rules.lua");
// Mapped only while in use; absent from `hyprctl layers` most of the time.
const onDemand = new Set(["cortetsu-area-picker", "cortetsu-border-exclusion"]);

const layers = JSON.parse(execFileSync("hyprctl", ["layers", "-j"], { encoding: "utf8" }));
const live = new Set();
for (const monitor of Object.values(layers))
    for (const level of Object.values(monitor.levels))
        for (const layer of level) live.add(layer.namespace);

const rules = fs.readFileSync(rulesPath, "utf8");
const patterns = [...rules.matchAll(/layer_rule\(\{ match = \{ namespace = "([^"]+)" \}/g)].map(m => m[1]);
let failed = false;
for (const pattern of patterns) {
    const full = new RegExp(`^(?:${pattern})$`);
    const hits = [...live].filter(name => full.test(name));
    const shell = pattern.startsWith("cortetsu-") || pattern.startsWith("caelestia-");
    if (!shell) {
        if (hits.some(name => name.startsWith("cortetsu-"))) {
            console.log(`FAIL ${pattern}: another program's rule reaches ${hits}`);
            failed = true;
        }
        continue;
    }
    const group = pattern.match(/^(\w+)-\((.+)\)$/);
    const names = group ? group[2].split("|").map(alt => `${group[1]}-${alt}`) : [pattern];
    const unknown = names.filter(name => !live.has(name) && !onDemand.has(name));
    console.log(`${unknown.length ? "FAIL" : "OK  "} ${pattern} → live: ${hits.join(", ") || "none"}` +
        (unknown.length ? `; not a shell surface: ${unknown.join(", ")}` : ""));
    failed ||= unknown.length > 0;
}
const shellLive = [...live].filter(name => name.startsWith("cortetsu-")).sort();
console.log(`shell surfaces now: ${shellLive.join(", ")}`);

const pid = execFileSync("pgrep", ["-xo", "Hyprland"], { encoding: "utf8" }).trim();
const ticks = Number(fs.readFileSync(`/proc/${pid}/stat`, "utf8").split(") ")[1].split(" ")[19]);
const bootMs = Date.now() - Number(fs.readFileSync("/proc/uptime", "utf8").split(" ")[0]) * 1000;
const startedMs = bootMs + ticks * 10; // USER_HZ is 100 on Linux
const activatedMs = fs.lstatSync(current).mtimeMs;
const stale = activatedMs > startedMs;
console.log(`compositor started ${new Date(startedMs).toISOString()}, generation activated ${new Date(activatedMs).toISOString()}`);
console.log(failed ? "VERDICT: FAIL" : stale
    ? "VERDICT: RELOAD_REQUIRED (rules on disk are newer than the compositor; `hyprctl reload config-only` loads them)"
    : "VERDICT: PASS (the compositor started with this generation)");
process.exit(failed ? 1 : 0);

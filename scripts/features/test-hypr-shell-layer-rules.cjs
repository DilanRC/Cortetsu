// Every shell layer rule in rules.lua must match a namespace the shell creates.
// The rules once kept the upstream `caelestia-` prefix after the shell moved
// to `cortetsu-`, so they silently matched nothing.
const fs = require("fs");
const path = require("path");
const repo = path.resolve(__dirname, "../..");
const rules = fs.readFileSync(path.join(repo, "dotfiles/home/.config/hypr/hyprland/rules.lua"), "utf8");

const declared = new Set();
(function walk(dir) {
    for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
        const full = path.join(dir, entry.name);
        if (entry.isDirectory()) { if (entry.name !== "tests") walk(full); continue; }
        if (!entry.name.endsWith(".qml") || entry.name.endsWith("Fixture.qml")) continue;
        const text = fs.readFileSync(full, "utf8");
        for (const m of text.matchAll(/WlrLayershell\.namespace:\s*"([^"]+)"/g)) declared.add(m[1]);
        if (/\bStyledWindow\s*\{|component \w+:\s*StyledWindow/.test(text))
            for (const m of text.matchAll(/^\s*name:\s*"([a-z-]+)"/gm)) declared.add(`cortetsu-${m[1]}`);
    }
})(path.join(repo, "cortetsu"));

const shellRules = [...rules.matchAll(/layer_rule\(\{ match = \{ namespace = "((?:caelestia|cortetsu)-[^"]+)" \}/g)].map(m => m[1]);
if (!shellRules.length) throw new Error("no shell layer rules found");
for (const pattern of shellRules) {
    const group = pattern.match(/^(\w+)-\((.+)\)$/);
    const names = group ? group[2].split("|").map(alt => `${group[1]}-${alt}`) : [pattern];
    for (const name of names)
        if (!declared.has(name)) throw new Error(`layer rule ${pattern}: ${name} is not a shell namespace (${[...declared].sort()})`);
}
console.log(`PASS: ${shellRules.length} shell layer rules match declared namespaces`);

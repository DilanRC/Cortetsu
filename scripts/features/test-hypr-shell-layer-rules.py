"""Every shell layer rule in rules.lua must match a namespace the shell creates.

The rules once kept the upstream `caelestia-` prefix after the shell moved to
`cortetsu-`, so they silently matched nothing.
"""
from pathlib import Path
import re

repo = Path(__file__).resolve().parents[2]
rules = (repo / "dotfiles/home/.config/hypr/hyprland/rules.lua").read_text()

declared = set()
for qml in (repo / "cortetsu").rglob("*.qml"):
    if "/tests/" in str(qml) or qml.name.endswith("Fixture.qml"):
        continue
    text = qml.read_text()
    declared.update(re.findall(r'WlrLayershell\.namespace:\s*"([^"]+)"', text))
    if re.search(r"\bStyledWindow\s*\{|component \w+:\s*StyledWindow", text):
        declared.update(f"cortetsu-{n}" for n in re.findall(r'^\s*name:\s*"([a-z-]+)"', text, re.M))

shell_rules = re.findall(r'layer_rule\(\{ match = \{ namespace = "((?:caelestia|cortetsu)-[^"]+)" \}', rules)
assert shell_rules, "no shell layer rules found"
for pattern in shell_rules:
    group = re.fullmatch(r"(\w+)-\((.+)\)", pattern)
    names = [f"{group[1]}-{alt}" for alt in group[2].split("|")] if group else [pattern]
    for name in names:
        assert name in declared, f"layer rule {pattern!r}: {name} is not a shell namespace ({sorted(declared)})"
print(f"PASS: {len(shell_rules)} shell layer rules match declared namespaces")

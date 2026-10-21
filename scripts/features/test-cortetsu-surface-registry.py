#!/usr/bin/env python3
"""F1a gate: one canonical surface registry and no parallel flag lists.

The QML engine checks the behaviour in cortetsu/tests/qml/surfaces. This gate
checks what QML cannot see about itself: that the property declarations match
the registry and that no policy file keeps its own copy of a flag list.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import surface_registry as registry  # noqa: E402

ROOT = registry.ROOT
MODULES = ROOT / "cortetsu/modules"


def read(relative: str) -> str:
    return (ROOT / relative).read_text(encoding="utf-8")


surfaces = registry.load()["surfaces"]
names = registry.group("names")
retained = registry.group("retained")

# 1. The table itself: unique names, known kinds, groups derived from it.
assert len(names) == len(set(names)) == len(surfaces) == 15, names
assert {entry["kind"] for entry in surfaces} == {"retained", "transient", "chrome"}
for entry in surfaces:
    assert set(entry) == {"name", "kind", "exclusive", "ownsKeyboard", "fullscreenGuard"}, entry
    if entry["kind"] == "retained":
        assert entry["exclusive"] and entry["ownsKeyboard"] and not entry["fullscreenGuard"], entry
    if entry["kind"] == "chrome":
        assert not (entry["exclusive"] or entry["ownsKeyboard"] or entry["fullscreenGuard"]), entry
    # Every shortcut-driven panel is guarded the same way by its shortcut and by IPC.
    if entry["kind"] == "transient":
        assert entry["fullscreenGuard"], entry
# Parity with F0: OSD coexists, the bar is never part of the policy.
osd = next(entry for entry in surfaces if entry["name"] == "osd")
assert osd["kind"] == "transient" and not osd["exclusive"], osd
assert registry.group("competingWithWallpaper") == [n for n in registry.group("exclusive") if n != "wallpaperManager"]

# 2. Declarations that QML forces us to spell out must match the table.
screen_state = read("cortetsu/components/ScreenState.qml")
typed_state = read("cortetsu/modules/CortetsuScreenState.qml")
assert sorted(registry.declared_bools(screen_state)) == sorted(names), registry.declared_bools(screen_state)
assert not registry.declared_bools(screen_state, readonly=True), "ScreenState must not derive input flags"
typed_flags = [flag for flag in registry.declared_bools(typed_state, readonly=True)
               if not flag.startswith(("retainedOverlayOpen", "requires"))]
assert sorted(typed_flags) == sorted(retained), typed_flags
for flag in retained:
    assert f"readonly property bool {flag}: !!legacyState.{flag}" in typed_state, flag
for derived in ("retainedOverlayOpen", "requiresOverlayLayer", "requiresFullInputMask", "requiresWindowKeyboardFocus"):
    assert f"readonly property bool {derived}:" in typed_state, derived

# 3. Every consumer of the classification imports the registry and keeps no
#    literal list of surface names (two or more names inside one [...]).
consumers = {
    "cortetsu/modules/OverlayPolicy.js": '.import "SurfaceRegistry.js" as Surfaces',
    "cortetsu/modules/CortetsuOverlayPolicy.js": '.import "SurfaceRegistry.js" as Surfaces',
    "cortetsu/modules/CortetsuScreenState.qml": 'import "SurfaceRegistry.js" as Surfaces',
    "cortetsu/components/ScreenState.qml": 'import "../modules/SurfaceRegistry.js" as Surfaces',
    "cortetsu/modules/Shortcuts.qml": 'import "SurfaceRegistry.js" as Surfaces',
}
name_pattern = "|".join(re.escape(name) for name in names)
literal_list = re.compile(rf'\[[^\]\[]*"(?:{name_pattern})"[^\]\[]*"(?:{name_pattern})"[^\]\[]*\]')
for relative, marker in consumers.items():
    text = read(relative)
    assert marker in text, f"{relative} must import the registry"
    found = literal_list.findall(text)
    assert not found, f"{relative} keeps a parallel surface list: {found}"
    if relative.endswith((".js", "ScreenState.qml")):
        for flag in names:
            assert f'"{flag}"' not in text, f"{relative} spells {flag} itself"

# The same scan over every first-party module: a new hard-coded list of
# surfaces anywhere else must be either derived from the registry or listed
# here with the reason it is not a surface classification.
allowed = {
    # Drawer drag thresholds read per-panel config groups, not open state.
    ("cortetsu/modules/drawers/ContentWindow.qml", '["dashboard", "launcher", "session", "sidebar"]'),
    # Config migration of the launcher/sidebar sections.
    ("cortetsu/modules/CortetsuConfig.qml", '["launcher", "sidebar"]'),
}
for path in sorted(list(MODULES.rglob("*.qml")) + list(MODULES.rglob("*.js")) + list((ROOT / "cortetsu/components").rglob("*.qml"))):
    relative = path.relative_to(ROOT).as_posix()
    if relative == "cortetsu/modules/SurfaceRegistry.js" or "/tests/" in relative:
        continue
    for match in literal_list.findall(path.read_text(encoding="utf-8")):
        assert (relative, match) in allowed, f"{relative}: surface list outside the registry: {match}"

# 4. One transition path: every open goes through CortetsuOverlayPolicy, so no
#    module writes a surface flag to true itself (closing writes stay local).
policy_users = (
    "cortetsu/modules/RetainedSurfaceController.qml", "cortetsu/modules/OverviewController.qml",
    "cortetsu/modules/Shortcuts.qml", "cortetsu/modules/BottomHub.qml",
    "cortetsu/modules/settings/SettingsContext.qml", "cortetsu/modules/dashboard/Today.qml",
)
for relative in policy_users:
    assert "CortetsuOverlayPolicy.js\" as OverlayPolicy" in read(relative), f"{relative} must use the policy"
direct_open = re.compile(r"(?:setRetained|setFlag)\([^)]*,\s*true\)|\.(?:" + name_pattern + r")\s*=\s*(?:true|!)")
allowed_direct = {
    # Pointer peeks of the legacy drawer (hover at a screen edge, drag). A
    # retained surface on the same screen takes the full input mask, so these
    # cannot stack over it; a peek on another screen is not an explicit
    # request and must not close what is open there (F1a O-4).
    "cortetsu/modules/drawers/Interactions.qml",
}
for path in sorted(list(MODULES.rglob("*.qml")) + list(MODULES.rglob("*.js"))):
    relative = path.relative_to(ROOT).as_posix()
    if "/tests/" in relative or relative in allowed_direct or relative.endswith(("CortetsuOverlayPolicy.js", "CortetsuScreenState.qml")):
        continue
    found = direct_open.findall(path.read_text(encoding="utf-8"))
    assert not found, f"{relative} opens a surface around CortetsuOverlayPolicy: {found}"
for controller in ("Calendar", "Clipboard", "Display", "Hardware", "Keyboards", "Wallpaper"):
    assert "RetainedSurfaceController {" in read(f"cortetsu/modules/{controller}Controller.qml"), controller

# 5. The registry ships in every generation and its runtime test runs in both gates.
build = read("cortetsu/bin/build-runtime.sh")
cli = read("scripts/cortetsu")
assert "modules/SurfaceRegistry.js" in build
assert 'qmltestrunner -input "$REPO/cortetsu/tests/qml/surfaces"' in build
assert 'run_qml_test "cortetsu/tests/qml/surfaces"' in cli
assert '"scripts/features/test-cortetsu-surface-registry.py"' in cli
assert "test-cortetsu-surface-registry.py" in build

print(f"PASS: {len(names)} surfaces in one registry ({len(retained)} retained); no parallel lists in {len(consumers)} consumers")

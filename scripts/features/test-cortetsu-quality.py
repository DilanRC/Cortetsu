#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path
import re

repo = Path(__file__).resolve().parents[2]
modules = repo / "cortetsu/modules"

# Explicit debt: native replacements still need behavioral parity.
# Scan all first-party QML, including multiline argv arrays, not just modules.
legacy_shell_exceptions = {
    "cortetsu/modules/clipboard/Content.qml",  # wl-copy reads the image from stdin; path is $1, never shell text
}
found_shell_pipelines = set()
shell_command = re.compile(r"\[\s*['\"](?:sh|bash)['\"]\s*,\s*['\"]-c['\"]")
for group in (modules, repo / "cortetsu/components", repo / "cortetsu/services"):
    for path in group.rglob("*.qml"):
        source = path.read_text(encoding="utf-8")
        assert "sh -c" not in source, f"literal shell in QML: {path.relative_to(repo)}"
        if shell_command.search(source):
            found_shell_pipelines.add(path.relative_to(repo).as_posix())
assert found_shell_pipelines == legacy_shell_exceptions, (
    f"QML shell boundary drift: added={found_shell_pipelines - legacy_shell_exceptions}, "
    f"resolved={legacy_shell_exceptions - found_shell_pipelines}"
)

for relative in (
    "hardware/EnergyPage.qml",
    "hardware/PowerPage.qml",
    "hardware/PowerAutomationPage.qml",
):
    text = (modules / relative).read_text(encoding="utf-8")
    assert "running: root.visible" in text, f"hidden-page polling regression: {relative}"
    assert "onVisibleChanged: { if (visible) refresh(); }" in text, f"missing wake-on-visible: {relative}"

# The live display topology is built inline; its unused drag overlay was retired.
assert not (modules / "display/TopologyDragOverlay.qml").exists()
assert 'id: topologyCanvas' in (modules / "display/Editor.qml").read_text(encoding="utf-8")

hub = (modules / "HubButton.qml").read_text(encoding="utf-8")
status = (modules / "StatusPill.qml").read_text(encoding="utf-8")
surface = (modules / "CortetsuSurface.qml").read_text(encoding="utf-8")
design = (modules.parent / "theme/CortetsuDesignDefaults.js").read_text(encoding="utf-8")
visualiser = (modules / "background/Visualiser.qml").read_text(encoding="utf-8")
launcher = (modules / "launcher/Wrapper.qml").read_text(encoding="utf-8")
bottom_hub = (modules / "BottomHub.qml").read_text(encoding="utf-8")

# Shared controls remain in the tab order but must not claim focus while an
# overlay is being constructed. Otherwise the last loaded control becomes the
# keyboard owner and Escape appears to be the only way back to normal input.
components = repo / "cortetsu/components"
for relative in (
    "CortetsuButton.qml",
    "CortetsuToggle.qml",
    "CortetsuSlider.qml",
    "CortetsuChoiceCard.qml",
    "CortetsuListRow.qml",
):
    text = (components / relative).read_text(encoding="utf-8")
    assert "focus: false" in text, f"{relative} steals focus while loading"
    assert "activeFocusOnTab" in text, f"{relative} lost keyboard traversal"

hub_button = (modules / "HubButton.qml").read_text(encoding="utf-8")
assert "focus: false" in hub_button, "HubButton steals focus while loading"

interactions = (modules / "drawers/Interactions.qml").read_text(encoding="utf-8")
assert "if (false &&" not in interactions, "dead interaction branch remains"

sidebar = (modules / "sidebar/Content.qml").read_text(encoding="utf-8")
assert "onClicked: {}" not in sidebar, "interactive-looking no-op remains"
assert "disabled: true" in sidebar, "read-only notification history lacks a disabled row contract"

for consumer in (hub, status, surface):
    assert 'import "../theme"' in consumer and "CortetsuDesign.js" not in consumer
assert "CortetsuSurface" in hub
assert "CortetsuSurface" in status
assert "Colours." not in hub
assert "Colours." not in status
assert "CortetsuDesign.colorTetsu" in surface
assert "CortetsuDesign.colorIndigo" in surface
assert "CortetsuDesign.colorVermillion" in surface
assert "CortetsuDesign.hoverScale" in hub
assert hub.count("CortetsuDesign.motionFastMs") >= 2
assert "CortetsuDesign.motionStandardMs" in status
assert "hoverScale = 1.025" in design
assert "motionFastMs = 120" in design
assert "motionPanelMs = 240" in design
assert "mouse.containsMouse ? 1.06 : 1" not in hub
assert "duration: 110" not in hub
assert "root.screen?.height ?? 0" in visualiser
assert "screen?.height ?? 0" in launcher
assert "modelData?.width ?? 0" in bottom_hub

native = repo / "cortetsu/desktop-runtime-rs/src"
calendar = (native / "calendar.rs").read_text(encoding="utf-8")
pomodoro = (native / "pomodoro.rs").read_text(encoding="utf-8")
common = (native / "common.rs").read_text(encoding="utf-8")
assert 'config().join("cortetsu/calendar-client.json")' in calendar
assert 'config().join("cortetsu/calendar-selection.json")' in calendar
assert 'state().join("pomodoro.json")' in pomodoro
assert 'xdg("XDG_STATE_HOME", ".local/state").join("cortetsu")' in common
for command in ("calendar", "pomodoro"):
    launcher = (repo / f"cortetsu/bin/cortetsu-{command}").read_text(encoding="utf-8")
    assert f'exec "$BUNDLE/cortetsu-desktop-runtime" cortetsu-{command} "$@"' in launcher
    assert "python" not in launcher, f"{command} reintroduced an interpreter dependency"

# A file that says root.x without its own `id: root` silently reads the
# creator's root (shell.qml): SessionHost handed the menu an undefined lock.
import re as _re
orphans = [str(f.relative_to(repo)) for f in (repo / "cortetsu").rglob("*.qml")
           if "tests" not in f.parts and _re.search(r"\broot\.", f.read_text(encoding="utf-8"))
           and not _re.search(r"\bid:\s*root\b", f.read_text(encoding="utf-8"))]
assert not orphans, f"root. used without id: root: {orphans}"

print("PASS: Cortetsu quality gate: cold hidden pages, native visual primitives, canonical state; legacy QML shell exceptions explicitly registered")

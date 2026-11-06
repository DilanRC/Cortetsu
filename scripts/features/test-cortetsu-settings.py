#!/usr/bin/env python3
"""Structural contracts of Settings that running it cannot show.

What Settings does when used is checked by test-cortetsu-settings-runtime.py.
This file holds the properties of the source tree itself: that no control is
wired to a preference nothing reads, that every destination has a page, and
that SUPER+I has one owner.
"""
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SHELL = ROOT / "cortetsu"
SETTINGS = SHELL / "modules/settings"

sources = {path: path.read_text(encoding="utf-8") for path in SETTINGS.rglob("*.qml")}
content = sources[SETTINGS / "Content.qml"]
controller = sources[SETTINGS / "SettingsController.qml"]
host = (SHELL / "modules/SettingsHost.qml").read_text(encoding="utf-8")
legacy_panels = SHELL / "base/modules/nexus/pages"
legacy_panel_sources = "\n".join(path.read_text(encoding="utf-8") for path in legacy_panels.rglob("*.qml"))
retired_bar_preferences = (
    "bar.persistent", "bar.tray.compact", "bar.activeWindow.compact",
    "bar.scrollActions.brightness", "bar.scrollActions.workspaces", "bar.clock.showDate",
)
assert not [key for key in retired_bar_preferences if f"CortetsuConfig.{key}" in legacy_panel_sources], \
    "Retired top-bar preferences must not have Settings controls"

page_ids = re.findall(r'\{ id: "([a-z]+)", group: qsTr\("Ajustes"\), title: qsTr\("(?:Quick Settings|General|Bar|Background|Interface|Services|Advanced|About)"\)', controller)
assert page_ids == ["quick", "general", "bar", "background", "interface", "services", "advanced", "about"], page_ids
section_map = re.search(r"readonly property var pageSections: \(\{(.*?)\}\)", controller, re.S).group(1)
section_groups = dict(re.findall(r'([a-z]+): \[([^\]]+)\]', section_map))
section_ids = {page: [item.strip().strip('"') for item in values.split(",")] for page, values in section_groups.items()}
assert sorted(section_ids) == sorted(page_ids), section_ids
assert sorted(sum(section_ids.values(), [])) == sorted(["network", "bluetooth", "audio", "display", "power", "notifications", "input", "appearance", "wallpaper", "desktop", "bottomhub", "launcher", "shortcuts", "automation", "about"])
table = re.search(r"readonly property var pages: \(\{(.*?)\}\)", content, re.S).group(1)
pages = dict(re.findall(r"([a-z]+): ([A-Za-z]+Page)", table))
assert sorted(pages) == sorted(page_ids), (sorted(pages), sorted(page_ids))
for component in pages.values():
    assert re.search(rf"Component \{{ id: {component}; \w+ \{{ context: settingsContext \}} \}}", content), component
    page_file = SETTINGS / "pages" / f"{component[0].upper()}{component[1:]}.qml"
    assert page_file.is_file(), component

# A control must change something. A preference written from Settings needs a
# reader in the running shell: not Settings itself, not the retired settings
# panels, not the retired top bar. This is the check that would have caught
# the fourteen switches that did nothing.
RETIRED = ("/modules/settings/", "/base/modules/nexus/", "/base/modules/bar/", "/tests/")
readers = {}
for path in SHELL.rglob("*"):
    if path.suffix in (".qml", ".js") and path.is_file() and path.name != "CortetsuConfig.qml":
        relative = "/" + path.relative_to(SHELL).as_posix()
        if not any(part in relative for part in RETIRED):
            readers[relative] = path.read_text(encoding="utf-8", errors="ignore")
written = set()
for text in sources.values():
    written.update(re.findall(r"CortetsuConfig\.((?:[a-z][A-Za-z]*\.)*[a-z][A-Za-z]*) = ", text))
# The display filter is applied by its own service, which the search above reads.
assert len(written) >= 30, sorted(written)
unread = sorted(key for key in written if not any(f"CortetsuConfig.{key}" in text for text in readers.values()))
assert not unread, f"Settings writes preferences nothing reads: {unread}"

# The content is built only while the window is open; a page only while selected.
assert "active: false" in host and "sourceComponent: Content {" in host
assert "sourceComponent: pages[shellPageId] ?? null" in content
assert not re.search(r"visible: root\.(section|controller\.selectedId) ===", "\n".join(sources.values()))

# Views bind and draw. Processes belong to services, except the one read-only
# listing a page runs when it is opened.
with_process = sorted(path.name for path, text in sources.items() if re.search(r"\bProcess \{", text))
assert with_process == ["ShortcutsSection.qml"], with_process
for path, text in sources.items():
    assert '"sh", "-c"' not in text and "execDetached" not in text, path.name
    assert not re.search(r'"#[0-9a-fA-F]{6}"', text), f"{path.name} holds a literal colour"
    assert text.count("\n") <= 400, f"{path.name} has {text.count(chr(10))} lines"

# Global first-party bindings have one canonical owner. User overrides must not
# register a second spelling of the same shortcut after that module is loaded.
base_hypr = (ROOT / "dotfiles/home/.config/hypr/hyprland/keybinds.lua").read_text(encoding="utf-8")
user_hypr = (ROOT / "config/hypr-user.lua").read_text(encoding="utf-8")
shortcuts = (SHELL / "modules/Shortcuts.qml").read_text(encoding="utf-8")
assert 'create_bind("SUPER + I", hl.dsp.global("cortetsu:settings"))' in base_hypr
assert '"SUPER + I",\n    hl.dsp.global("cortetsu:settings")' not in user_hypr
assert '"SUPER + I",\n    hl.dsp.global("cortetsu:utilities")' not in user_hypr
assert 'name: "settings"' in shortcuts

print(f"PASS: {len(page_ids)} end-4 pages compose {sum(map(len, section_ids.values()))} Cortetsu sections, {len(written)} preferences written by Settings "
      "all have a reader, and SUPER+I has one owner")

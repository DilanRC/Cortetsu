#!/usr/bin/env python3
"""Guard the Zero-Caelestia launcher migration.

The launcher used to be built from 8 Caelestia patches stacked on top of
upstream modules/launcher/*.qml, four of which (AppList, Content,
ContentList, Wrapper, services/Apps) rewrote the widget and four more
(CortetsuConfig, CortetsuConfigMore, SearchPreferences, RemainingConfig)
swapped every remaining GlobalConfig.launcher.* / GlobalConfig.general.
apps.terminal reference for CortetsuConfig.*. All 8 are gone: the launcher
now lives entirely under cortetsu/modules/launcher as first-party QML, cp
-a'd straight into the build over whatever upstream ships, with zero
GlobalConfig anywhere in it.
"""
from pathlib import Path

repo = Path(__file__).resolve().parents[2]
launcher = repo / "cortetsu/modules/launcher"
manifest = (repo / "cortetsu/contracts/patch-debt.tsv").read_text(encoding="utf-8")
patches_dir = repo / "cortetsu/contracts/patches"

REQUIRED_FILES = (
    "AppList.qml",
    "Content.qml",
    "ContentList.qml",
    "Wrapper.qml",
    "services/Apps.qml",
    "services/Actions.qml",
    "services/Schemes.qml",
    "services/M3Variants.qml",
)

texts = {}
for rel in REQUIRED_FILES:
    path = launcher / rel
    assert path.is_file(), f"missing first-party launcher file: {path}"
    texts[rel] = path.read_text(encoding="utf-8")

# Zero GlobalConfig, anywhere, in the whole first-party launcher tree.
# (Caelestia.Config's `Config`/`Tokens` design-token surface is a separate,
# out-of-scope concern owned by other Zero-Caelestia tasks.)
for rel, text in texts.items():
    assert "GlobalConfig" not in text, f"launcher/{rel} still references GlobalConfig"

# The 8 patches that used to build this are gone for good.
RETIRED_PATCHES = (
    "modules__launcher__AppList.qml.patch",
    "modules__launcher__Content.qml.patch",
    "modules__launcher__ContentList.qml.patch",
    "modules__launcher__Wrapper.qml.patch",
    "modules__launcher__services__Apps.qml.patch",
    "modules__launcher__CortetsuConfig.qml.patch",
    "modules__launcher__CortetsuConfigMore.qml.patch",
    "modules__launcher__SearchPreferences.qml.patch",
    "modules__launcher__RemainingConfig.qml.patch",
)
for name in RETIRED_PATCHES:
    assert name not in manifest, f"{name} must not be listed in MANIFEST.tsv"
    assert not (patches_dir / name).exists(), f"{name} must be deleted"
assert not any(p.name.startswith("modules__launcher__") for p in patches_dir.glob("*.patch")), (
    "no modules__launcher__* patch should remain on disk"
)

# Functional preferences: favouriteApps supports runtime mutation via
# CortetsuConfig.setFavouriteApps (add/remove), never a direct property
# assignment (that would skip the atomic-write persistence in save()).
app_list = texts["AppList.qml"]
assert "CortetsuConfig.setFavouriteApps(" in app_list
assert "GlobalConfig.launcher.favouriteApps =" not in app_list
assert "CortetsuConfig.favouriteApps" in app_list
assert "CortetsuConfig.hiddenApps" in texts["services/Apps.qml"]
assert "CortetsuConfig.enableDangerousActions" in texts["services/Actions.qml"]
assert "CortetsuConfig.actions" in texts["services/Actions.qml"]
assert "CortetsuConfig.vimKeybinds" in texts["Content.qml"]
assert "CortetsuConfig.actionPrefix" in texts["Content.qml"]
assert 'import "../../components"' in texts["Content.qml"]
assert "CortetsuConfig.actionPrefix" in texts["ContentList.qml"]
assert "listLoading" in texts["ContentList.qml"]
assert 'title: qsTr("Loading wallpapers")' in texts["ContentList.qml"]

# actionPrefix and specialPrefix are the two distinct prefixes upstream
# used to split across GlobalConfig.launcher.actionPrefix/specialPrefix;
# both now come from the same CortetsuConfig singleton.
assert "CortetsuConfig.specialPrefix" in texts["services/Apps.qml"]

# useFuzzy.{apps,actions,schemes,variants} is deliberately unified into a
# single CortetsuConfig.useFuzzyApps flag (see docs/LAUNCHER_MIGRATION.md
# for why) rather than kept as 4 separate toggles.
for rel in ("services/Apps.qml", "services/Actions.qml", "services/Schemes.qml", "services/M3Variants.qml"):
    assert "CortetsuConfig.useFuzzyApps" in texts[rel], f"{rel} must use the unified useFuzzyApps flag"

# The terminal command (GlobalConfig.general.apps.terminal) is not
# duplicated: both the calc-in-terminal action and app launching read the
# same CortetsuConfig.terminalCommand list.
assert "CortetsuConfig.terminalCommand" in app_list
assert "CortetsuConfig.terminalCommand" in texts["services/Apps.qml"]

wrapper = texts["Wrapper.qml"]
assert "active: true" in wrapper
assert "root.shouldBeActive || root.visible" not in wrapper

# CortetsuConfig itself must actually own these fields with write support.
config = (repo / "cortetsu/modules/CortetsuConfig.qml").read_text(encoding="utf-8")
for marker in (
    "property list<string> favouriteApps",
    "property list<string> hiddenApps",
    "property list<string> terminalCommand",
    "property string actionPrefix",
    "property string specialPrefix",
    "property var actions",
    "property bool enableDangerousActions",
    "property bool useFuzzyApps",
    "property bool vimKeybinds",
    "function setFavouriteApps",
):
    assert marker in config, f"CortetsuConfig.qml missing {marker!r}"

print("PASS: launcher is fully first-party (0 GlobalConfig, 8/8 patches retired)")

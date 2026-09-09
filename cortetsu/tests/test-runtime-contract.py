#!/usr/bin/env python3
from __future__ import annotations

import json
from pathlib import Path

repo = Path(__file__).resolve().parents[2]
build = (repo / "cortetsu/bin/build-runtime.sh").read_text(encoding="utf-8")
installer = (repo / "scripts/install-cortetsu.sh").read_text(encoding="utf-8")
migration = (repo / "scripts/migrate-cortetsu-v2.sh").read_text(encoding="utf-8")
legacy_process_migration = (repo / "core/migrate_legacy_processes.py").read_text(encoding="utf-8")
wallpaper_daemon = (repo / "cortetsu/bin/cortetsu-wallpaper-color-daemon").read_text(encoding="utf-8")
wallpaper_unit = (repo / "config/systemd/user/cortetsu-wallpaper-color.service").read_text(encoding="utf-8")
rollback = (repo / "cortetsu/bin/rollback-runtime.sh").read_text(encoding="utf-8")
composer = (repo / "cortetsu/bin/compose-panels.py").read_text(encoding="utf-8")
content = (repo / "cortetsu/modules/calendar/Content.qml").read_text(encoding="utf-8")
cli = (repo / "scripts/cortetsu").read_text(encoding="utf-8")
provenance = json.loads((repo / "cortetsu/contracts/runtime-provenance.json").read_text(encoding="utf-8"))
composition = json.loads((repo / "cortetsu/contracts/composition.json").read_text(encoding="utf-8"))

assert provenance["project"] == "Cortetsu"
assert provenance["sourceOfTruth"] == "https://github.com/DilanRC/Cortetsu.git"
assert provenance["baseProvenance"] == "cortetsu/base/PROVENANCE.md"
assert composition["description"].startswith("Single staged Cortetsu")

for marker in (
    "CORTETSU_DATA_ROOT", "CORTETSU_RUNTIME_ROOT", "SOURCE_BASE",
    'cp -a "$SOURCE_BASE/." "$STAGING/"', "STAGING=", "atomic_link",
    "test-calendar-credentials.py", "test-calendar-polish.py", "test-runtime-contract.py",
    "is_managed_generation",
):
    assert marker in build, marker
assert 'cp -a "$PACKAGE_ROOT' not in build
assert "ensure-upstream.sh" not in build
assert "upstreamCommit" not in build and "upstreamTag" not in build
assert 'git -C "$UPSTREAM" archive' not in build
assert "/etc/xdg/quickshell/caelestia" not in build
assert "CAERICE_" not in build and "caerice-" not in build
assert 'cp -a "$REPO/cortetsu/services/." "$STAGING/services/"' in build
for service in ("Time.qml", "Brightness.qml", "Audio.qml", "Players.qml"):
    assert f"services/{service}" in build
assert "provenance.json" in build

for marker in (
    "scripts/migrate-cortetsu-v2.sh",
    'find "$REPO/cortetsu/bin" -maxdepth 1 -type f -name \'cortetsu-*\'',
    "cortetsu-rollback",
    'core/theme.py" check',
    'core/theme.py" adopt',
    "systemctl --user daemon-reload",
    'atomic_symlink "$REPO" "$DATA_ROOT/repository"',
    'atomic_symlink "$REPO/scripts/cortetsu" "$BIN_DIR/cortetsu"',
):
    assert marker in installer, marker
assert "install-theme-bridge.py" not in installer
assert "canonical=" not in installer
assert "sudo " not in installer
assert "legacy_state_present=0" in installer
assert 'if [[ "$legacy_state_present" == 1' in installer
assert "legacy-processes) legacy_processes_cmd" in cli
assert "screenshot) screenshot_cmd" in cli
assert "/usr/bin/caelestia" not in cli

for marker in (
    'calendar-client.json" "$CONFIG_HOME/cortetsu/calendar-client.json"',
    'pomodoro.json" "$STATE_HOME/cortetsu/pomodoro.json"',
    'for old in "$HOME"/.local/bin/caerice-*',
    'OLD_UNIT="caerice-power-auto.service"',
    'BACKUP="$DATA_ROOT/migrations/$STAMP"',
):
    assert marker in migration, marker

for marker in ("legacy-processes.lock", "DEFERRED", "NO_PROCESS_SIGNALING", "caerice-pomodoro", "caelestia-wallpaper-color-daemon"):
    assert marker in legacy_process_migration, marker
assert "pkill" not in legacy_process_migration and "killpg" not in legacy_process_migration
assert "flock -n 9" in wallpaper_daemon and "caelestia-wallpaper-color-daemon" not in wallpaper_daemon
assert "wallpaper-engine=active" in wallpaper_daemon and "wallpaper-engine=inactive" in wallpaper_daemon
assert "PartOf=graphical-session.target" in wallpaper_unit
assert "Restart=on-failure" in wallpaper_unit
assert "cortetsu-wallpaper-color-daemon" in wallpaper_unit
apply_wallpaper = (repo / "cortetsu/bin/cortetsu-apply-wallpaper-colors").read_text(encoding="utf-8")
assert "cortetsu-scheme-posthook" not in apply_wallpaper
wallpaper_service = (repo / "cortetsu/modules/CortetsuWallpapers.qml").read_text(encoding="utf-8")
assert '"cortetsu-wallpaper-colours", path' in wallpaper_service
assert '"cortetsu-wallpaper-select", target' in wallpaper_service
assert '"cortetsu-wallpaper-select", "--random", wallsdir' in wallpaper_service
assert 'cortetsu/wallpaper/path.txt' in wallpaper_service
assert "caelestia" not in wallpaper_service.lower()
nmcli = (repo / "cortetsu/base/services/Nmcli.qml").read_text(encoding="utf-8")
stack_page = (repo / "cortetsu/base/modules/nexus/common/StackPage.qml").read_text(encoding="utf-8")
assert 'name: "cortetsu.qml.services.nmcli"' in nmcli
assert 'name: "cortetsu.nexus"' in stack_page
assert 'name: "caelestia.qml.services.nmcli"' not in nmcli
assert 'name: "caelestia.nexus"' not in stack_page

for marker in (
    "atomic_link", "build.lock", "is_managed_generation", "BUILD.json",
    "previous no es una generación Cortetsu administrada",
):
    assert marker in rollback, marker
assert "ln -sfn" not in rollback

assert "required_imports" in composer and "invalid composed marker count" in composer

for marker in (
    "function onCalendarChanged()", "requestCalendarSync(true)",
    'phase === "LONG_BREAK"', "eventOccursOnDate",
):
    assert marker in content, marker

for marker in (
    "is_managed_generation", "verify_generation current", "CORTETSU_RUNTIME_ROOT",
    "theme_cmd check",
):
    assert marker in cli, marker
assert "CAERICE_" not in cli and "caerice-" not in cli

print("PASS: Cortetsu v2 canonical namespace, self-healing upstream, staged runtime, native theme ownership, migration, helpers and rollback contract")

#!/usr/bin/env python3
from __future__ import annotations

import json
from pathlib import Path

repo = Path(__file__).resolve().parents[2]
build = (repo / "cortetsu/bin/build-runtime.sh").read_text(encoding="utf-8")
installer = (repo / "scripts/install-cortetsu.sh").read_text(encoding="utf-8")
migration = (repo / "scripts/migrate-cortetsu-v2.sh").read_text(encoding="utf-8")
# The Python migrator was retired to tests/reference/ in c372e67; the live
# contract is cortetsu-platform's `migrate_legacy_processes` action.
platform_migrations = (repo / "cortetsu/platform-rs/src/migrations.rs").read_text(encoding="utf-8")
platform_main = (repo / "cortetsu/platform-rs/src/main.rs").read_text(encoding="utf-8")
legacy_process_migration = platform_migrations[platform_migrations.index("pub fn legacy("):]
legacy_process_migration = legacy_process_migration[:legacy_process_migration.index("\n}\n") + 3]
wallpaper_daemon = (repo / "cortetsu/bin/cortetsu-wallpaper-color-daemon").read_text(encoding="utf-8")
wallpaper_unit = (repo / "config/systemd/user/cortetsu-wallpaper-color.service").read_text(encoding="utf-8")
rollback = (repo / "cortetsu/bin/rollback-runtime.sh").read_text(encoding="utf-8")
# compose-panels.py became `cortetsu-platform compose-panels` in c372e67.
transforms = (repo / "cortetsu/platform-rs/src/transforms.rs").read_text(encoding="utf-8")
composer = transforms[transforms.index("fn compose(root: &Path)"):transforms.index("fn migrate_bottom(")]
content = (repo / "cortetsu/modules/calendar/Content.qml").read_text(encoding="utf-8")
cli = (repo / "scripts/cortetsu").read_text(encoding="utf-8")
provenance = json.loads((repo / "cortetsu/contracts/runtime-provenance.json").read_text(encoding="utf-8"))
composition = json.loads((repo / "cortetsu/contracts/composition.json").read_text(encoding="utf-8"))
wall_utility = json.loads((repo / "cortetsu/contracts/wall-utility.json").read_text(encoding="utf-8"))

assert provenance["project"] == "Cortetsu"
assert provenance["sourceOfTruth"] == "https://github.com/DilanRC/Cortetsu.git"
assert provenance["baseProvenance"] == "cortetsu/base/PROVENANCE.md"
assert composition["description"].startswith("Single staged Cortetsu")
assert wall_utility["schema"] == 1
assert wall_utility["id"] == "wall-utility-bcde"
assert wall_utility["configSource"] == "dotfiles/home/.config/cortetsu/ui.toml"
assert wall_utility["runtimePreferences"] == "XDG config file cortetsu/preferences.json"

for marker in (
    "CORTETSU_DATA_ROOT", "CORTETSU_RUNTIME_ROOT", "SOURCE_BASE",
    'cp -a "$SOURCE_BASE/." "$STAGING/"', "STAGING=", "atomic_link",
    # Since c372e67 the build gates on Qt Quick suites, not Python source
    # checks; this file runs in CI static validation instead.
    "qmltestrunner", "is_managed_generation",
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
assert "provenance.json" in build and "wall-utility.json" in build

# Since c372e67 the shell installer only orchestrates; links, journal and
# rollback live in cortetsu-platform (install.rs) and cortetsu-rescue.
install_rs = (repo / "cortetsu/platform-rs/src/install.rs").read_text(encoding="utf-8")
for marker in (
    "scripts/migrate-cortetsu-v2.sh",
    '"$RESCUE" helpers-stage "$native_output"',
    '"$PLATFORM" install-transaction begin',
    '"$PLATFORM" install-transaction recover',
    '"$PLATFORM" install-transaction commit',
    '"$PLATFORM" theme check --repo "$REPO"',
    '"$PLATFORM" theme adopt --repo "$REPO"',
    "systemctl --user daemon-reload",
    "Rollback completo: cortetsu rollback",
):
    assert marker in installer, marker
assert 'name == "cortetsu" || name.starts_with("cortetsu-")' in install_rs
assert 'atomic_link(&shell, &r.runtime.join("current"))' in install_rs
assert '&r.data.join("repository")' in install_rs
assert '.join(".local/bin").join(name)' in install_rs
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
assert '"migrate_legacy_processes" => migrations::legacy(&args)' in platform_main
assert 'lock(&root.join("legacy-processes.lock")' in legacy_process_migration
for forbidden in ("pkill", "killpg", "kill(", "signal", "Command::new"):
    assert forbidden not in legacy_process_migration, forbidden
# The daemon is a launcher for the native owner since c372e67; its single
# instance lock is a non-blocking flock in desktop-runtime-rs.
palette = (repo / "cortetsu/desktop-runtime-rs/src/palette.rs").read_text(encoding="utf-8")
palette_daemon = palette[palette.index("pub fn wallpaper_daemon("):]
assert 'exec "$BUNDLE/cortetsu-desktop-runtime" cortetsu-wallpaper-color-daemon "$@"' in wallpaper_daemon
assert "caelestia-wallpaper-color-daemon" not in wallpaper_daemon
assert 'lock(&dir.join("lock"), true)' in palette_daemon and "WouldBlock => return Ok(0)" in palette_daemon
assert "PartOf=graphical-session.target" in wallpaper_unit
assert "Restart=on-failure" in wallpaper_unit
assert "cortetsu-wallpaper-color-daemon" in wallpaper_unit
apply_wallpaper = (repo / "cortetsu/bin/cortetsu-apply-wallpaper-colors").read_text(encoding="utf-8")
assert "cortetsu-scheme-posthook" not in apply_wallpaper
wallpaper_service = (repo / "cortetsu/modules/CortetsuWallpapers.qml").read_text(encoding="utf-8")
assert '"cortetsu-wallpaper-colours", path' in wallpaper_service
assert '"cortetsu-wallpaper-select", target' in wallpaper_service
assert '"cortetsu-wallpaper-select", "--random", wallsdir' in wallpaper_service
assert '"cortetsu-apply-wallpaper-colors", next' in wallpaper_service
assert 'cortetsu/wallpaper/path.txt' in wallpaper_service
assert "caelestia" not in wallpaper_service.lower()
# The base Nmcli.qml and Nexus StackPage were deleted unused in e2c4dde; Wi-Fi
# joins go through utils/NetworkConnection.qml over the native Connectivity.
network_connection = (repo / "cortetsu/utils/NetworkConnection.qml").read_text(encoding="utf-8")
assert "Connectivity.wifi.connectNetwork" in network_connection
assert "Process" not in network_connection
assert "connectionParamPassword" not in network_connection
for qml in (repo / "cortetsu").rglob("*.qml"):
    text = qml.read_text(encoding="utf-8")
    assert "caelestia.qml.services.nmcli" not in text and 'name: "caelestia.nexus"' not in text, qml

# rollback-runtime.sh forwards to `cortetsu-platform system rollback`, which
# verifies before and after and moves the pointers transactionally.
system_rs = (repo / "cortetsu/platform-rs/src/system.rs").read_text(encoding="utf-8")
system_rollback = system_rs[system_rs.index('"rollback" => {'):system_rs.index('"gc" => println!(')]
assert 'exec "$BUNDLE/cortetsu-platform" system rollback "$@"' in rollback
assert "ln -sfn" not in rollback
for marker in (
    "check_mutation()", "reject_pending_promotion(", "verify()?;", "plan_rollback(&r)",
    "rollback_pointers(&r, true)", "requires explicit legacy recovery",
):
    assert marker in system_rollback, marker
assert system_rollback.count("verify()?;") == 2

assert '"compose-panels"' in platform_main and '"$PLATFORM" compose-panels "$STAGING"' in build
assert 'fail("missing import: theme")' in composer
assert "must be hosted once by RetainedSurfacesHost" in composer

# Calendar view over its service and date model (stabilization): a sync on
# opening, a manual forced sync, long breaks and multi-day events.
calendar_service = (repo / "cortetsu/modules/calendar/CalendarService.qml").read_text(encoding="utf-8")
calendar_model = (repo / "cortetsu/modules/calendar/CalendarModel.js").read_text(encoding="utf-8")
pomodoro_model = (repo / "cortetsu/modules/pomodoro/PomodoroModel.js").read_text(encoding="utf-8")
assert "onOpenChanged: if (open) requestSync(false)" in calendar_service
assert "CalendarService.requestSync(true)" in content
assert 'phase === "LONG_BREAK"' in pomodoro_model
assert "function occursOn(event, day)" in calendar_model and "CalendarModel.eventsOn(" in content

for marker in (
    "is_managed_generation", "verify_generation current", "CORTETSU_RUNTIME_ROOT",
    "theme_cmd check",
):
    assert marker in cli, marker
# The Wall Utility contract and this file left the CLI for CI static validation.
ci = (repo / ".github/workflows/cortetsu-ci.yml").read_text(encoding="utf-8")
assert "scripts/features/test-cortetsu-wall-utility-contract.py" in ci
assert "cortetsu/tests/test-runtime-contract.py" in ci
assert "CAERICE_" not in cli and "caerice-" not in cli

print("PASS: Cortetsu v2 canonical namespace, self-healing upstream, staged runtime, native theme ownership, migration, helpers and rollback contract")

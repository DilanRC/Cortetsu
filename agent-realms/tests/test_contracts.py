from __future__ import annotations

import json
import io
import argparse
import os
import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path
from unittest.mock import patch

from cortetsu_agent_realms import cli, input as vinput, runtime
from cortetsu_agent_realms import process, supervisor
from cortetsu_agent_realms.cli import parser
from cortetsu_agent_realms.paths import RealmError, RealmPaths, paths_for, validate_name
from cortetsu_agent_realms.process import lifecycle_lock
from cortetsu_agent_realms.runtime import _bwrap_prefix, _check_startable, _runtime_env, private_call, recover


ROOT = Path(__file__).resolve().parents[1]


class ContractTests(unittest.TestCase):
    def test_all_requested_cli_verbs_are_registered(self) -> None:
        expected = {"start", "stop", "status", "run", "inspect", "screenshot", "click", "key",
                    "type", "scroll", "windows", "logs", "doctor", "pause", "resume", "recover",
                    "observe", "move", "drag"}
        root = parser()
        subparsers = next(action for action in root._actions if isinstance(action, argparse._SubParsersAction))
        actual = set(subparsers.choices)
        self.assertTrue(expected.issubset(actual), sorted(expected - actual))

    def test_run_accepts_compositor_child_for_graphical_pid_visibility(self) -> None:
        args = parser().parse_args(["run", "--detach", "--compositor-child", "codex", "--",
                                    "/usr/bin/kitty", "--title", "Realm probe"])
        self.assertTrue(args.compositor_child)
        self.assertTrue(args.detach)
        self.assertEqual(args.command, ["/usr/bin/kitty", "--title", "Realm probe"])

    def test_compositor_child_run_dispatches_quoted_argv_to_private_compositor(self) -> None:
        with tempfile.TemporaryDirectory(prefix="agent-realm-compositor-child-") as directory:
            root = Path(directory)
            paths = RealmPaths("codex", root / "state", root / "home", root / "runtime",
                               root / "config", root / "log", root / "hyprlog", control=root / "state")
            meta = {"name": "codex", "state": "running", "systemd_scope_unit":
                    "agent-realm-codex-abcdef1234.scope"}
            accepted = subprocess.CompletedProcess([], 0, "ok\n", "")
            with patch.object(runtime, "paths_for", return_value=paths), \
                 patch.object(runtime, "load_meta", return_value=meta), \
                 patch.object(runtime, "process_alive", return_value=True), \
                 patch.object(runtime, "private_call", return_value=accepted) as private_call:
                result = runtime.run("codex", ["/usr/bin/kitty", "--title", "Realm probe; $(false)"],
                                     detach=True, compositor_child=True)

            self.assertEqual(result, {"pid": None, "command": ["/usr/bin/kitty", "--title",
                                                                  "Realm probe; $(false)"],
                                      "detached": True, "launch_mode": "compositor-child",
                                      "dispatch_accepted": True})
            private_call.assert_called_once_with(
                "codex", ["dispatch", "exec", "/usr/bin/kitty --title 'Realm probe; $(false)'"],
            )
            self.assertFalse((paths.state / "apps").exists())

    def test_compositor_child_run_requires_detach_and_realm_wide_limits(self) -> None:
        with tempfile.TemporaryDirectory(prefix="agent-realm-compositor-child-validation-") as directory:
            root = Path(directory)
            paths = RealmPaths("codex", root / "state", root / "home", root / "runtime",
                               root / "config", root / "log", root / "hyprlog", control=root / "state")
            meta = {"name": "codex", "state": "running", "systemd_scope_unit":
                    "agent-realm-codex-abcdef1234.scope"}
            with patch.object(runtime, "paths_for", return_value=paths), \
                 patch.object(runtime, "load_meta", return_value=meta), \
                 patch.object(runtime, "process_alive", return_value=True), \
                 patch.object(runtime, "private_call") as private_call:
                with self.assertRaisesRegex(RealmError, "requiere --detach"):
                    runtime.run("codex", ["/usr/bin/kitty"], compositor_child=True)
                with self.assertRaisesRegex(RealmError, "límites del scope del realm"):
                    runtime.run("codex", ["/usr/bin/kitty"], detach=True,
                                compositor_child=True, memory_max="1G")
            private_call.assert_not_called()

    def test_inspect_metrics_sum_all_processes_in_exact_realm_scopes(self) -> None:
        with tempfile.TemporaryDirectory(prefix="agent-realm-scope-metrics-") as directory:
            root = Path(directory)
            proc_root = root / "proc"
            proc_root.mkdir()
            session_unit = "agent-realm-codex-abcdef1234.scope"
            app_unit = "agent-realm-codex-1234567890.scope"
            unrelated_unit = "agent-realm-other-aaaaaaaaaa.scope"

            def write_process(pid: int, unit: str, user_ticks: int,
                              system_ticks: int, pss_kib: int) -> None:
                entry = proc_root / str(pid)
                entry.mkdir()
                entry.joinpath("cgroup").write_text(
                    f"0::/user.slice/user@1000.service/app.slice/{unit}\n")
                stat_fields = ["S", "1", "1", "0", "0", "0", "0", "0", "0", "0", "0",
                               str(user_ticks), str(system_ticks)]
                entry.joinpath("stat").write_text(f"{pid} (fake process) " + " ".join(stat_fields))
                entry.joinpath("smaps_rollup").write_text(f"Pss: {pss_kib} kB\n")

            write_process(101, session_unit, 4, 1, 1000)
            write_process(102, session_unit, 2, 3, 2000)
            write_process(103, app_unit, 1, 4, 3000)
            write_process(104, unrelated_unit, 50, 50, 9000)
            paths = RealmPaths("codex", root / "state", root / "home", root / "runtime",
                               root / "config", root / "log", root / "hyprlog", control=root / "state")
            app_records = paths.state / "apps"
            app_records.mkdir(parents=True)
            bad_record = app_records / "unreadable.json"
            bad_record.write_text("not json")
            meta = {"name": "codex", "systemd_scope_unit": session_unit}

            with patch.object(cli, "_realm_scope_units", return_value={app_unit}), \
                 patch.object(cli, "process_alive", return_value=True), \
                 patch.object(cli, "_find_amd_render_node", return_value=None), \
                 patch.object(cli.os, "sysconf", return_value=100):
                metrics = cli._resource_metrics(meta, paths, proc_root=proc_root)

            self.assertTrue(bad_record.exists())
            self.assertEqual(metrics["process_count"], 3)
            self.assertEqual(metrics["cpu_seconds"], 0.15)
            self.assertEqual(metrics["pss_kib"], 6000)
            self.assertEqual(metrics["resource_scope_units"], sorted({session_unit, app_unit}))

    def test_session_name_has_path_traversal_blocked(self) -> None:
        self.assertEqual(validate_name("claude-ui"), "claude-ui")
        for bad in ("..", "../host", ".hidden", "a/b", "a" * 49, ""):
            with self.subTest(name=bad), self.assertRaises(RealmError):
                validate_name(bad)

    def test_runtime_socket_path_is_short_and_does_not_include_the_session_name(self) -> None:
        paths = paths_for("realm-with-a-long-session-name", create=False)
        self.assertEqual(paths.runtime.parent, Path("/tmp"))
        self.assertNotIn(paths.name, paths.internal_runtime)
        self.assertLess(len(os.fsencode(paths.internal_runtime)), 40)
        self.assertEqual(paths.parent_runtime.parent, Path("/tmp"))
        self.assertTrue(paths.runtime.name.startswith("ar"))
        self.assertEqual(paths.parent_runtime.name, "ap" + paths.runtime.name[2:])
        # Hyprland's event socket must fit sockaddr_un (107 bytes) even with the
        # longest signature it writes; at 108 Quickshell got no Hyprland events.
        signature = "f" * 40 + "_" + "9" * 10 + "_" + "9" * 10
        socket2 = f"{paths.internal_runtime}/hypr/{signature}/.socket2.sock"
        self.assertLessEqual(len(os.fsencode(socket2)), 107, socket2)

    def test_scope_freezer_state_queries_only_the_exact_realm_unit(self) -> None:
        unit = "agent-realm-codex-abcdef1234.scope"
        result = subprocess.CompletedProcess([], 0, "frozen\n", "")
        with patch.object(process.shutil, "which", return_value="/usr/bin/systemctl"), \
             patch.object(process.subprocess, "run", return_value=result) as run:
            self.assertEqual(process.scope_freezer_state("codex", unit), "frozen")
        self.assertEqual(run.call_args.args[0], [
            "/usr/bin/systemctl", "--user", "show", unit,
            "--property=FreezerState", "--value",
        ])

    def test_scope_freezer_state_rejects_unstable_state(self) -> None:
        result = subprocess.CompletedProcess([], 0, "freezing\n", "")
        with patch.object(process.shutil, "which", return_value="/usr/bin/systemctl"), \
             patch.object(process.subprocess, "run", return_value=result):
            with self.assertRaisesRegex(RealmError, "FreezerState no es estable"):
                process.scope_freezer_state("codex", "agent-realm-codex-abcdef1234.scope")

    def test_realm_environment_does_not_inherit_host_sockets_or_secrets(self) -> None:
        with patch.dict(os.environ, {"WAYLAND_DISPLAY": "wayland-host", "DISPLAY": ":0",
                                     "DBUS_SESSION_BUS_ADDRESS": "unix:path=/run/user/1000/bus",
                                     "SSH_AUTH_SOCK": "/run/user/1000/ssh-agent", "HOME": "/home/dilan"}), \
             patch("cortetsu_agent_realms.runtime._find_amd_render_node",
                   return_value="/dev/dri/renderD129"):
            env = _runtime_env(RealmPaths("codex", Path("/state"), Path("/home"),
                                          Path("/runtime"), Path("/config"), Path("/log"), Path("/hyprlog"), control=Path("/state")),
                               wayland="wayland-7", signature="realm-signature", bus="unix:path=/private/bus")
        self.assertEqual(env["WAYLAND_DISPLAY"], "wayland-7")
        self.assertEqual(env["HYPRLAND_INSTANCE_SIGNATURE"], "realm-signature")
        self.assertEqual(env["DBUS_SESSION_BUS_ADDRESS"], "unix:path=/private/bus")
        self.assertEqual(env["HOME"], "/home/agent")
        self.assertEqual(env["PATH"], "/home/agent/.local/bin:/usr/local/bin:/usr/bin:/bin")
        self.assertNotIn("DISPLAY", env)
        self.assertNotIn("SSH_AUTH_SOCK", env)
        self.assertNotIn("SESSION_MANAGER", env)
        self.assertEqual(env["AQ_DRM_DEVICES"], "/dev/dri/renderD129")

    def test_bwrap_preserves_runtime_and_amd_render_node_paths(self) -> None:
        paths = RealmPaths("codex", Path("/state"), Path("/home"), Path("/tmp/ar-1000-abc123"),
                           Path("/config"), Path("/log"), Path("/hyprlog"), control=Path("/state"))
        with patch("cortetsu_agent_realms.runtime.shutil.which", return_value="/usr/bin/bwrap"), \
             patch("cortetsu_agent_realms.runtime._find_amd_render_node",
                   return_value="/dev/dri/renderD129"):
            args = _bwrap_prefix(paths)
        self.assertIn(["--dir", paths.internal_runtime],
                      [args[index:index + 2] for index in range(len(args) - 1)])
        self.assertIn(["--bind", str(paths.runtime), paths.internal_runtime],
                      [args[index:index + 3] for index in range(len(args) - 2)])
        self.assertIn(["--dev-bind", "/dev/dri/renderD129", "/dev/dri/renderD129"],
                      [args[index:index + 3] for index in range(len(args) - 2)])
        self.assertIn(["--ro-bind", str(paths.state), "/var/lib/agent-realm"],
                      [args[index:index + 3] for index in range(len(args) - 2)])

    def test_compositor_bwrap_mounts_private_weston_parent_and_local_shim(self) -> None:
        paths = RealmPaths("codex", Path("/state"), Path("/home"), Path("/tmp/ar-1000-abc123"),
                           Path("/config"), Path("/log"), Path("/hyprlog"), control=Path("/state"))
        shim = Path("/cache/xdg-version-shim.so")
        input_client = Path("/cache/realm-input")
        with patch("cortetsu_agent_realms.runtime.shutil.which", return_value="/usr/bin/bwrap"), \
             patch("cortetsu_agent_realms.runtime._find_amd_render_node",
                   return_value="/dev/dri/renderD129"):
            args = _bwrap_prefix(paths, die_with_parent=False, include_parent=True,
                                 readonly_state=False,
                                 version_shim=shim, input_client=input_client)
        windows = [args[index:index + 3] for index in range(len(args) - 2)]
        self.assertIn(["--bind", str(paths.parent_runtime), paths.parent_internal_runtime], windows)
        self.assertIn(["--ro-bind", str(shim), "/tmp/agent-realm-xdg-version-shim.so"], windows)
        self.assertIn(["--ro-bind", str(input_client), "/tmp/agent-realm-input-client"], windows)
        self.assertIn(["--bind", str(paths.state), "/var/lib/agent-realm"], windows)
        self.assertNotIn("--die-with-parent", args)

    def test_lifecycle_lock_serializes_independent_processes(self) -> None:
        with tempfile.TemporaryDirectory(prefix="agent-realm-lock-test-") as directory:
            root = Path(directory)
            first_marker = root / "first-entered"
            second_marker = root / "second-entered"
            source = """
import sys, time
from pathlib import Path
from cortetsu_agent_realms.paths import RealmPaths
from cortetsu_agent_realms.process import lifecycle_lock
root = Path(sys.argv[1])
paths = RealmPaths('lock-test', root / 'state', root / 'home', root / 'runtime',
                   root / 'config', root / 'log', root / 'hyprlog', control=root / 'state')
with lifecycle_lock(paths):
    Path(sys.argv[2]).write_text('entered')
    if sys.argv[3] == 'first':
        time.sleep(0.5)
"""
            env = os.environ.copy()
            env["PYTHONPATH"] = str(ROOT / "src")
            first = subprocess.Popen([sys.executable, "-c", source, directory,
                                      str(first_marker), "first"], env=env,
                                     stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
            deadline = time.monotonic() + 2
            while not first_marker.exists() and time.monotonic() < deadline:
                time.sleep(0.01)
            self.assertTrue(first_marker.exists(), first.stderr.read().decode() if first.poll() is not None else "")
            second = subprocess.Popen([sys.executable, "-c", source, directory,
                                       str(second_marker), "second"], env=env,
                                      stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
            time.sleep(0.12)
            self.assertFalse(second_marker.exists(), "second process entered before the first released its lock")
            first.wait(timeout=3)
            second.wait(timeout=3)
            first_error = first.stderr.read().decode()
            second_error = second.stderr.read().decode()
            first.stderr.close()
            second.stderr.close()
            self.assertEqual(first.returncode, 0, first_error)
            self.assertEqual(second.returncode, 0, second_error)
            self.assertTrue(second_marker.exists())

    def test_cleanup_stops_all_exact_realm_scopes_with_corrupt_app_record(self) -> None:
        with tempfile.TemporaryDirectory(prefix="agent-realm-cleanup-test-") as directory:
            root = Path(directory)
            state = root / "state"
            app_dir = state / "apps"
            app_dir.mkdir(parents=True)
            bad_record = app_dir / "1234.json"
            bad_record.write_text("{")
            app_unit = "agent-realm-codex-1234567890.scope"
            compositor_unit = "agent-realm-codex-abcdef1234.scope"
            paths = RealmPaths("codex", state, root / "home", root / "runtime",
                               root / "config", root / "log", root / "hyprlog", control=state)
            (state / "session.json").write_text(json.dumps({
                "name": "codex", "schema": 1, "systemd_scope_unit": compositor_unit,
            }))
            with patch.object(process, "_realm_scope_units", return_value={app_unit}), \
                 patch.object(process, "control_scope") as stop_scope, \
                 patch.object(process, "process_alive", return_value=False):
                with self.assertRaisesRegex(RealmError, "sin unidad o identidad"):
                    process.cleanup_groups(paths)
                self.assertCountEqual(stop_scope.call_args_list, [
                    unittest.mock.call("codex", app_unit, "stop"),
                    unittest.mock.call("codex", compositor_unit, "stop"),
                ])
                self.assertTrue(bad_record.exists())
            self.assertTrue(bad_record.exists())

    def test_cleanup_handles_well_formed_json_with_wrong_record_shape(self) -> None:
        with tempfile.TemporaryDirectory(prefix="agent-realm-cleanup-test-") as directory:
            root = Path(directory)
            state = root / "state"
            app_dir = state / "apps"
            app_dir.mkdir(parents=True)
            bad_record = app_dir / "1234.json"
            bad_record.write_text("[]\n")
            app_unit = "agent-realm-codex-1234567890.scope"
            compositor_unit = "agent-realm-codex-abcdef1234.scope"
            paths = RealmPaths("codex", state, root / "home", root / "runtime",
                               root / "config", root / "log", root / "hyprlog", control=state)
            (state / "session.json").write_text(json.dumps({
                "name": "codex", "schema": 1, "systemd_scope_unit": compositor_unit,
            }))
            with patch.object(process, "_realm_scope_units", return_value={app_unit}), \
                 patch.object(process, "control_scope") as stop_scope, \
                 patch.object(process, "process_alive", return_value=False):
                with self.assertRaisesRegex(RealmError, "sin unidad o identidad"):
                    process.cleanup_groups(paths)
                self.assertEqual(stop_scope.call_count, 2)
                self.assertTrue(bad_record.exists())
            self.assertTrue(bad_record.exists())

    def test_cleanup_stops_known_scopes_before_reporting_invalid_app_unit(self) -> None:
        with tempfile.TemporaryDirectory(prefix="agent-realm-invalid-unit-") as directory:
            root = Path(directory)
            state = root / "state"
            app_dir = state / "apps"
            app_dir.mkdir(parents=True)
            bad_record = app_dir / "1234.json"
            bad_record.write_text('{"systemd_scope_unit":"external.scope"}\n')
            app_unit = "agent-realm-codex-1234567890.scope"
            compositor_unit = "agent-realm-codex-abcdef1234.scope"
            paths = RealmPaths("codex", state, root / "home", root / "runtime",
                               root / "config", root / "log", root / "hyprlog", control=state)
            (state / "session.json").write_text(json.dumps({
                "name": "codex", "schema": 1, "systemd_scope_unit": compositor_unit,
            }))
            with patch.object(process, "_realm_scope_units", return_value={app_unit}), \
                 patch.object(process, "control_scope") as stop_scope, \
                 patch.object(process, "process_alive", return_value=False):
                with self.assertRaisesRegex(RealmError, "sin unidad o identidad"):
                    process.cleanup_groups(paths)
                self.assertEqual(stop_scope.call_count, 2)
                self.assertTrue(bad_record.exists())

    def test_cleanup_rejects_non_integer_legacy_process_identity(self) -> None:
        with tempfile.TemporaryDirectory(prefix="agent-realm-invalid-pid-") as directory:
            root = Path(directory)
            state = root / "state"
            app_dir = state / "apps"
            app_dir.mkdir(parents=True)
            record = app_dir / "1234.json"
            record.write_text(json.dumps({"pid": float("inf"), "start_time": 1}) + "\n")
            unit = "agent-realm-codex-1234567890.scope"
            paths = RealmPaths("codex", state, root / "home", root / "runtime",
                               root / "config", root / "log", root / "hyprlog", control=state)
            (state / "session.json").write_text(json.dumps({
                "name": "codex", "schema": 1,
                "systemd_scope_unit": "agent-realm-codex-abcdef1234.scope",
            }))
            with patch.object(process, "_realm_scope_units", return_value={unit}), \
                 patch.object(process, "control_scope") as stop_scope, \
                 patch.object(process, "process_alive", return_value=False):
                with self.assertRaisesRegex(RealmError, "sin unidad o identidad"):
                    process.cleanup_groups(paths)
            self.assertEqual(stop_scope.call_count, 2)
            self.assertTrue(record.exists())

    def test_failed_app_registration_stops_scope_even_if_temp_unlink_fails(self) -> None:
        with tempfile.TemporaryDirectory(prefix="agent-realm-run-rollback-") as directory:
            root = Path(directory)
            state = root / "state"
            state.mkdir()
            paths = RealmPaths("codex", state, root / "home", root / "runtime",
                               root / "config", root / "log", root / "hyprlog", control=state)
            meta = {"name": "codex", "schema": 1, "state": "running", "limits": {}}
            proc = unittest.mock.Mock(pid=1234)
            unit = "agent-realm-codex-1234567890.scope"
            original_unlink = Path.unlink
            events = []

            def fail_temp_unlink(path: Path, *args, **kwargs):
                if path.name.endswith(".json.tmp"):
                    events.append("unlink")
                    raise PermissionError("denied")
                return original_unlink(path, *args, **kwargs)

            with patch("cortetsu_agent_realms.runtime.paths_for", return_value=paths), \
                 patch("cortetsu_agent_realms.process.paths_for", return_value=paths), \
                 patch.object(runtime, "load_meta", return_value=meta), \
                 patch.object(runtime, "process_alive", return_value=True), \
                 patch.object(runtime, "realm_bwrap", return_value=["/usr/bin/bwrap", "--"]), \
                 patch.object(runtime, "_scope_command", return_value=(["/usr/bin/bwrap", "--"], unit)), \
                 patch.object(runtime.subprocess, "Popen", return_value=proc), \
                 patch.object(runtime, "proc_start_time", return_value=1), \
                 patch.object(runtime, "_manager_env", return_value={}), \
                 patch.object(runtime, "_stop_failed_app_scope", side_effect=lambda *_: events.append("stop")), \
                 patch.object(Path, "write_text", side_effect=OSError("disk full")), \
                 patch.object(Path, "unlink", new=fail_temp_unlink):
                with self.assertRaisesRegex(RealmError, "no se pudo retirar el temporal"):
                    runtime.run("codex", ["true"], detach=True)
            self.assertEqual(events, ["stop", "unlink"])

    def test_start_refuses_corrupt_metadata_and_does_not_touch_runtime(self) -> None:
        with tempfile.TemporaryDirectory(prefix="agent-realm-start-guard-") as directory:
            root = Path(directory)
            state = root / "state"
            state.mkdir()
            runtime = root / "runtime"
            runtime.mkdir()
            marker = runtime / "existing-socket-marker"
            marker.write_text("keep until recover")
            (state / "session.json").write_text("{\n")
            paths = RealmPaths("codex", state, root / "home", runtime,
                               root / "config", root / "log", root / "hyprlog", control=state)
            with self.assertRaisesRegex(RealmError, "metadatos dañados"):
                _check_startable(paths)
            self.assertTrue(marker.exists())

    def test_start_refuses_orphan_scope_without_session_metadata(self) -> None:
        with tempfile.TemporaryDirectory(prefix="agent-realm-start-guard-") as directory:
            root = Path(directory)
            state = root / "state"
            state.mkdir()
            paths = RealmPaths("codex", state, root / "home", root / "runtime",
                               root / "config", root / "log", root / "hyprlog", control=state)
            with patch("cortetsu_agent_realms.runtime._realm_scope_units",
                       return_value={"agent-realm-codex-1234567890.scope"}):
                with self.assertRaisesRegex(RealmError, "sin metadatos; ejecuta recover"):
                    _check_startable(paths)

    def test_start_refuses_active_scope_when_metadata_is_stale_or_invalid(self) -> None:
        with tempfile.TemporaryDirectory(prefix="agent-realm-start-stale-scope-") as directory:
            root = Path(directory)
            state = root / "state"
            state.mkdir()
            paths = RealmPaths("codex", state, root / "home", root / "runtime",
                               root / "config", root / "log", root / "hyprlog", control=state)
            (state / "session.json").write_text(json.dumps({
                "name": "codex", "schema": 1, "systemd_scope_unit": "invalid.scope",
            }))
            unit = "agent-realm-codex-1234567890.scope"

            def scope_alive(meta):
                return meta.get("systemd_scope_unit") == unit

            with patch("cortetsu_agent_realms.runtime.paths_for", return_value=paths), \
                 patch("cortetsu_agent_realms.process.paths_for", return_value=paths), \
                 patch("cortetsu_agent_realms.runtime._realm_scope_units", return_value={unit}), \
                 patch("cortetsu_agent_realms.runtime.process_alive", side_effect=scope_alive):
                with self.assertRaisesRegex(RealmError, "scopes activos.*ejecuta recover"):
                    _check_startable(paths)

    def test_recover_cleans_exact_scopes_after_metadata_corruption(self) -> None:
        with tempfile.TemporaryDirectory(prefix="agent-realm-recover-test-") as directory:
            root = Path(directory)
            state = root / "state"
            state.mkdir()
            runtime = root / "ar-1000-test"
            runtime.mkdir()
            (runtime / "wayland-1").write_text("stale")
            parent_runtime = runtime.with_name(runtime.name.replace("ar-", "ap-", 1))
            parent_runtime.mkdir()
            (parent_runtime / "wayland-parent").write_text("stale")
            (state / "session.json").write_text("{\n")
            paths = RealmPaths("codex", state, root / "home", runtime,
                               root / "config", root / "log", root / "hyprlog", control=state)
            unit = "agent-realm-codex-1234567890.scope"
            with patch("cortetsu_agent_realms.process.paths_for", return_value=paths), \
                 patch("cortetsu_agent_realms.runtime.paths_for", return_value=paths), \
                 patch.object(process, "_realm_scope_units", return_value={unit}), \
                 patch.object(process, "control_scope") as stop_scope, \
                 patch.object(process, "process_alive", return_value=False):
                result = recover("codex")
            self.assertEqual(result["state"], "recovered")
            stop_scope.assert_called_once_with("codex", unit, "stop")
            self.assertEqual(list(runtime.iterdir()), [])
            self.assertEqual(list(parent_runtime.iterdir()), [])
            recovered = json.loads((state / "session.json").read_text())
            self.assertEqual(recovered["state"], "recovered")

    def test_recover_handles_non_object_and_mistyped_metadata(self) -> None:
        for raw_metadata in ('[]\n', '{"name":"codex","schema":1,"leader_pid":"bad"}\n'):
            with self.subTest(metadata=raw_metadata), tempfile.TemporaryDirectory(
                    prefix="agent-realm-recover-shape-") as directory:
                root = Path(directory)
                state = root / "state"
                state.mkdir()
                runtime = root / "ar-1000-test"
                runtime.mkdir()
                marker = runtime / "wayland-1"
                marker.write_text("stale")
                (state / "session.json").write_text(raw_metadata)
                paths = RealmPaths("codex", state, root / "home", runtime,
                                   root / "config", root / "log", root / "hyprlog", control=state)
                unit = "agent-realm-codex-1234567890.scope"
                with patch("cortetsu_agent_realms.process.paths_for", return_value=paths), \
                     patch("cortetsu_agent_realms.runtime.paths_for", return_value=paths), \
                     patch.object(process, "_realm_scope_units", return_value={unit}), \
                     patch.object(process, "control_scope") as stop_scope:
                    result = recover("codex")
                self.assertEqual(result["state"], "recovered")
                stop_scope.assert_called_once_with("codex", unit, "stop")
                self.assertFalse(marker.exists())

    def test_recover_preserves_app_record_without_safe_process_identity(self) -> None:
        for record_data in ('{"systemd_scope_unit":"external.scope"}\n', "{\n", "{}\n",
                            '{"command":["legacy-app"]}\n'):
            with self.subTest(record=record_data), tempfile.TemporaryDirectory(
                    prefix="agent-realm-recover-app-record-") as directory:
                root = Path(directory)
                state = root / "state"
                app_dir = state / "apps"
                app_dir.mkdir(parents=True)
                bad_record = app_dir / "1234.json"
                bad_record.write_text(record_data)
                runtime_dir = root / "ar-1000-test"
                runtime_dir.mkdir()
                paths = RealmPaths("codex", state, root / "home", runtime_dir,
                                   root / "config", root / "log", root / "hyprlog", control=state)
                app_unit = "agent-realm-codex-1234567890.scope"
                compositor_unit = "agent-realm-codex-abcdef1234.scope"
                (state / "session.json").write_text(json.dumps({
                    "name": "codex", "schema": 1, "systemd_scope_unit": compositor_unit,
                }))
                with patch("cortetsu_agent_realms.process.paths_for", return_value=paths), \
                     patch("cortetsu_agent_realms.runtime.paths_for", return_value=paths), \
                     patch.object(process, "_realm_scope_units", return_value={app_unit}), \
                     patch.object(process, "control_scope") as stop_scope, \
                     patch.object(process, "process_alive", return_value=False):
                    with self.assertRaisesRegex(RealmError, "registro de app"):
                        process.app_groups(paths)
                    with self.assertRaisesRegex(RealmError, "sin unidad o identidad"):
                        recover("codex")
                self.assertEqual(stop_scope.call_count, 2)
                self.assertTrue(bad_record.exists())

    def test_app_groups_preserves_records_without_safe_identity(self) -> None:
        with tempfile.TemporaryDirectory(prefix="agent-realm-app-record-") as directory:
            root = Path(directory)
            state = root / "state"
            app_dir = state / "apps"
            app_dir.mkdir(parents=True)
            paths = RealmPaths("codex", state, root / "home", root / "runtime",
                               root / "config", root / "log", root / "hyprlog", control=state)
            (app_dir / "array.json").write_text("[]\n")
            (app_dir / "bad-pid.json").write_text('{"pid":"bad","start_time":1}\n')
            (app_dir / "empty.json").write_text("{}\n")
            (app_dir / "broken.json").write_text("{\n")
            with self.assertRaisesRegex(RealmError, "registro de app"):
                process.app_groups(paths)
            self.assertCountEqual([path.name for path in app_dir.iterdir()],
                                 ["array.json", "bad-pid.json", "empty.json", "broken.json"])

    def test_load_meta_converts_invalid_utf8_to_realm_error(self) -> None:
        with tempfile.TemporaryDirectory(prefix="agent-realm-meta-encoding-") as directory:
            root = Path(directory)
            state = root / "state"
            state.mkdir()
            paths = RealmPaths("codex", state, root / "home", root / "runtime",
                               root / "config", root / "log", root / "hyprlog", control=state)
            (state / process.META_NAME).write_bytes(b"\xff\xfe")
            with self.assertRaisesRegex(RealmError, "metadatos dañados"):
                process.load_meta(paths)

    def test_app_groups_preserves_invalid_utf8_record(self) -> None:
        with tempfile.TemporaryDirectory(prefix="agent-realm-app-encoding-") as directory:
            root = Path(directory)
            app_dir = root / "state" / "apps"
            app_dir.mkdir(parents=True)
            record = app_dir / "invalid-utf8.json"
            record.write_bytes(b"\xff\xfe")
            paths = RealmPaths("codex", root / "state", root / "home", root / "runtime",
                               root / "config", root / "log", root / "hyprlog", control=root / "state")
            with self.assertRaisesRegex(RealmError, "registro de app ilegible"):
                process.app_groups(paths)
            self.assertTrue(record.exists())

    def test_pause_rejects_unresolved_app_before_freezing_compositor(self) -> None:
        with tempfile.TemporaryDirectory(prefix="agent-realm-pause-record-") as directory:
            root = Path(directory)
            state = root / "state"
            app_dir = state / "apps"
            app_dir.mkdir(parents=True)
            record = app_dir / "unknown.json"
            record.write_text("{}\n")
            paths = RealmPaths("codex", state, root / "home", root / "runtime",
                               root / "config", root / "log", root / "hyprlog", control=state)
            meta = {"name": "codex", "schema": 1, "state": "running", "systemd_scope_unit":
                    "agent-realm-codex-abcdef1234.scope"}
            with patch("cortetsu_agent_realms.runtime.paths_for", return_value=paths), \
                 patch("cortetsu_agent_realms.process.paths_for", return_value=paths), \
                 patch.object(runtime, "load_meta", return_value=meta), \
                 patch.object(runtime, "process_alive", return_value=True), \
                 patch.object(runtime, "control_scope") as control_scope:
                with self.assertRaisesRegex(RealmError, "sin unidad o identidad segura"):
                    runtime.pause("codex", True)
            control_scope.assert_not_called()
            self.assertTrue(record.exists())

    def test_pause_rejects_unregistered_active_scope_before_freezing_compositor(self) -> None:
        with tempfile.TemporaryDirectory(prefix="agent-realm-pause-unregistered-") as directory:
            root = Path(directory)
            state = root / "state"
            (state / "apps").mkdir(parents=True)
            paths = RealmPaths("codex", state, root / "home", root / "runtime",
                               root / "config", root / "log", root / "hyprlog", control=state)
            compositor_unit = "agent-realm-codex-abcdef1234.scope"
            orphan_unit = "agent-realm-codex-1234567890.scope"
            meta = {"name": "codex", "schema": 1, "state": "running",
                    "systemd_scope_unit": compositor_unit}

            def scope_is_active(candidate: dict[str, str]) -> bool:
                return candidate.get("systemd_scope_unit") in {compositor_unit, orphan_unit}

            with patch("cortetsu_agent_realms.runtime.paths_for", return_value=paths), \
                 patch("cortetsu_agent_realms.process.paths_for", return_value=paths), \
                 patch.object(runtime, "load_meta", return_value=meta), \
                 patch.object(runtime, "process_alive", side_effect=scope_is_active), \
                 patch.object(runtime, "_realm_scope_units", return_value={compositor_unit, orphan_unit}), \
                 patch.object(runtime, "control_scope") as control_scope:
                with self.assertRaisesRegex(RealmError, "apps activas sin registro persistido"):
                    runtime.pause("codex", True)
            control_scope.assert_not_called()

    def test_resume_thaws_unregistered_active_scope_before_compositor(self) -> None:
        with tempfile.TemporaryDirectory(prefix="agent-realm-resume-unregistered-") as directory:
            root = Path(directory)
            state = root / "state"
            (state / "apps").mkdir(parents=True)
            paths = RealmPaths("codex", state, root / "home", root / "runtime",
                               root / "config", root / "log", root / "hyprlog", control=state)
            compositor_unit = "agent-realm-codex-abcdef1234.scope"
            orphan_unit = "agent-realm-codex-1234567890.scope"
            meta = {"name": "codex", "schema": 1, "state": "paused",
                    "systemd_scope_unit": compositor_unit}

            def scope_is_active(candidate: dict[str, str]) -> bool:
                return candidate.get("systemd_scope_unit") in {compositor_unit, orphan_unit}

            with patch("cortetsu_agent_realms.runtime.paths_for", return_value=paths), \
                 patch("cortetsu_agent_realms.process.paths_for", return_value=paths), \
                 patch.object(runtime, "load_meta", return_value=meta), \
                 patch.object(runtime, "process_alive", side_effect=scope_is_active), \
                 patch.object(runtime, "_realm_scope_units", return_value={compositor_unit, orphan_unit}), \
                 patch.object(runtime, "scope_freezer_state", return_value="frozen"), \
                 patch.object(runtime, "control_scope") as control_scope, \
                 patch.object(runtime, "save_meta") as save_meta:
                result = runtime.pause("codex", False)

            self.assertEqual(result["state"], "running")
            self.assertEqual(
                control_scope.call_args_list,
                [unittest.mock.call("codex", orphan_unit, "thaw"),
                 unittest.mock.call("codex", compositor_unit, "thaw")],
            )
            save_meta.assert_called_once_with(paths, meta)

    def test_resume_thaws_scopes_even_if_app_record_is_corrupt(self) -> None:
        with tempfile.TemporaryDirectory(prefix="agent-realm-resume-corrupt-record-") as directory:
            root = Path(directory)
            state = root / "state"
            app_dir = state / "apps"
            app_dir.mkdir(parents=True)
            record = app_dir / "interrupted.json"
            record.write_text("{\n")
            paths = RealmPaths("codex", state, root / "home", root / "runtime",
                               root / "config", root / "log", root / "hyprlog", control=state)
            compositor_unit = "agent-realm-codex-abcdef1234.scope"
            orphan_unit = "agent-realm-codex-1234567890.scope"
            meta = {"name": "codex", "schema": 1, "state": "paused",
                    "systemd_scope_unit": compositor_unit}

            def scope_is_active(candidate: dict[str, str]) -> bool:
                return candidate.get("systemd_scope_unit") in {compositor_unit, orphan_unit}

            with patch("cortetsu_agent_realms.runtime.paths_for", return_value=paths), \
                 patch("cortetsu_agent_realms.process.paths_for", return_value=paths), \
                 patch.object(runtime, "load_meta", return_value=meta), \
                 patch.object(runtime, "process_alive", side_effect=scope_is_active), \
                 patch.object(runtime, "_realm_scope_units", return_value={compositor_unit, orphan_unit}), \
                 patch.object(runtime, "scope_freezer_state", return_value="frozen"), \
                 patch.object(runtime, "control_scope") as control_scope, \
                 patch.object(runtime, "save_meta"):
                result = runtime.pause("codex", False)

            self.assertEqual(result["state"], "running")
            self.assertEqual(
                control_scope.call_args_list,
                [unittest.mock.call("codex", orphan_unit, "thaw"),
                 unittest.mock.call("codex", compositor_unit, "thaw")],
            )
            self.assertTrue(record.exists())

    def test_repeated_pause_and_resume_skip_scopes_already_at_target(self) -> None:
        with tempfile.TemporaryDirectory(prefix="agent-realm-idempotent-pause-resume-") as directory:
            root = Path(directory)
            state = root / "state"
            (state / "apps").mkdir(parents=True)
            paths = RealmPaths("codex", state, root / "home", root / "runtime",
                               root / "config", root / "log", root / "hyprlog", control=state)
            compositor_unit = "agent-realm-codex-abcdef1234.scope"
            app_unit = "agent-realm-codex-1234567890.scope"
            for paused, session_state, freezer_state, expected in (
                    (True, "paused", "frozen", "paused"),
                    (False, "running", "running", "running")):
                with self.subTest(state=session_state):
                    meta = {"name": "codex", "schema": 1, "state": session_state,
                            "systemd_scope_unit": compositor_unit}
                    with patch("cortetsu_agent_realms.runtime.paths_for", return_value=paths), \
                         patch("cortetsu_agent_realms.process.paths_for", return_value=paths), \
                         patch.object(runtime, "load_meta", return_value=meta), \
                         patch.object(runtime, "process_alive", return_value=True), \
                         patch.object(runtime, "app_groups", return_value=[
                             {"systemd_scope_unit": app_unit}]), \
                         patch.object(runtime, "_realm_scope_units",
                                      return_value={compositor_unit, app_unit}), \
                         patch.object(runtime, "scope_freezer_state", return_value=freezer_state), \
                         patch.object(runtime, "control_scope") as control_scope, \
                         patch.object(runtime, "save_meta"):
                        result = runtime.pause("codex", paused)
                    self.assertEqual(result["state"], expected)
                    control_scope.assert_not_called()

    def test_pause_rolls_back_scopes_if_metadata_write_fails_once(self) -> None:
        with tempfile.TemporaryDirectory(prefix="agent-realm-pause-meta-rollback-") as directory:
            root = Path(directory)
            state = root / "state"
            (state / "apps").mkdir(parents=True)
            paths = RealmPaths("codex", state, root / "home", root / "runtime",
                               root / "config", root / "log", root / "hyprlog", control=state)
            compositor_unit = "agent-realm-codex-abcdef1234.scope"
            app_unit = "agent-realm-codex-1234567890.scope"
            meta = {"name": "codex", "schema": 1, "state": "running",
                    "systemd_scope_unit": compositor_unit}
            with patch("cortetsu_agent_realms.runtime.paths_for", return_value=paths), \
                 patch("cortetsu_agent_realms.process.paths_for", return_value=paths), \
                 patch.object(runtime, "load_meta", return_value=meta), \
                 patch.object(runtime, "process_alive", return_value=True), \
                 patch.object(runtime, "app_groups", return_value=[
                     {"systemd_scope_unit": app_unit}]), \
                 patch.object(runtime, "_realm_scope_units",
                              return_value={compositor_unit, app_unit}), \
                 patch.object(runtime, "scope_freezer_state", return_value="running"), \
                 patch.object(runtime, "control_scope") as control_scope, \
                 patch.object(runtime, "save_meta", side_effect=[OSError("target write"), None]) as save_meta:
                with self.assertRaisesRegex(RealmError, "se restauró el estado previo"):
                    runtime.pause("codex", True)

            self.assertEqual(meta["state"], "running")
            self.assertEqual(control_scope.call_count, 4)
            self.assertEqual(save_meta.call_count, 2)

    def test_pause_reports_when_transition_error_metadata_cannot_be_saved(self) -> None:
        with tempfile.TemporaryDirectory(prefix="agent-realm-pause-meta-error-") as directory:
            root = Path(directory)
            state = root / "state"
            (state / "apps").mkdir(parents=True)
            paths = RealmPaths("codex", state, root / "home", root / "runtime",
                               root / "config", root / "log", root / "hyprlog", control=state)
            compositor_unit = "agent-realm-codex-abcdef1234.scope"
            app_unit = "agent-realm-codex-1234567890.scope"
            meta = {"name": "codex", "schema": 1, "state": "running",
                    "systemd_scope_unit": compositor_unit}
            save_error = OSError("injected metadata write failure")
            with patch("cortetsu_agent_realms.runtime.paths_for", return_value=paths), \
                 patch("cortetsu_agent_realms.process.paths_for", return_value=paths), \
                 patch.object(runtime, "load_meta", return_value=meta), \
                 patch.object(runtime, "process_alive", return_value=True), \
                 patch.object(runtime, "app_groups", return_value=[
                     {"systemd_scope_unit": app_unit}]), \
                 patch.object(runtime, "_realm_scope_units",
                              return_value={compositor_unit, app_unit}), \
                 patch.object(runtime, "scope_freezer_state", return_value="running"), \
                 patch.object(runtime, "control_scope") as control_scope, \
                 patch.object(runtime, "save_meta", side_effect=save_error) as save_meta:
                with self.assertRaisesRegex(RealmError, "no se pudo guardar el estado transition-error"):
                    runtime.pause("codex", True)

            self.assertEqual(meta["state"], "transition-error")
            self.assertEqual(control_scope.call_count, 4)
            self.assertEqual(save_meta.call_count, 3)

    def test_pause_rolls_back_frozen_apps_if_compositor_freeze_fails(self) -> None:
        with tempfile.TemporaryDirectory(prefix="agent-realm-pause-rollback-") as directory:
            root = Path(directory)
            state = root / "state"
            app_dir = state / "apps"
            app_dir.mkdir(parents=True)
            paths = RealmPaths("codex", state, root / "home", root / "runtime",
                               root / "config", root / "log", root / "hyprlog", control=state)
            compositor_unit = "agent-realm-codex-abcdef1234.scope"
            app_unit = "agent-realm-codex-1234567890.scope"
            app_record = {"systemd_scope_unit": app_unit}
            meta = {"name": "codex", "schema": 1, "state": "running",
                    "systemd_scope_unit": compositor_unit}
            calls = []

            def control(name: str, unit: str, action: str) -> None:
                calls.append((name, unit, action))
                if unit == compositor_unit and action == "freeze":
                    raise RealmError("injected compositor freeze error")

            with patch("cortetsu_agent_realms.runtime.paths_for", return_value=paths), \
                 patch("cortetsu_agent_realms.process.paths_for", return_value=paths), \
                 patch.object(runtime, "load_meta", return_value=meta), \
                 patch.object(runtime, "process_alive", return_value=True), \
                 patch.object(runtime, "app_groups", return_value=[app_record]), \
                 patch.object(runtime, "_realm_scope_units", return_value={compositor_unit, app_unit}), \
                 patch.object(runtime, "scope_freezer_state", return_value="running"), \
                 patch.object(runtime, "control_scope", side_effect=control), \
                 patch.object(runtime, "save_meta") as save_meta:
                with self.assertRaisesRegex(RealmError, "se restauró el estado previo"):
                    runtime.pause("codex", True)

            self.assertEqual(meta["state"], "running")
            self.assertEqual(calls, [
                ("codex", app_unit, "freeze"),
                ("codex", compositor_unit, "freeze"),
                ("codex", compositor_unit, "thaw"),
                ("codex", app_unit, "thaw"),
            ])
            save_meta.assert_called_once_with(paths, meta)

    def test_pause_rolls_back_apps_before_propagating_keyboard_interrupt(self) -> None:
        with tempfile.TemporaryDirectory(prefix="agent-realm-pause-interrupt-") as directory:
            root = Path(directory)
            state = root / "state"
            (state / "apps").mkdir(parents=True)
            paths = RealmPaths("codex", state, root / "home", root / "runtime",
                               root / "config", root / "log", root / "hyprlog", control=state)
            compositor_unit = "agent-realm-codex-abcdef1234.scope"
            app_unit = "agent-realm-codex-1234567890.scope"
            meta = {"name": "codex", "schema": 1, "state": "running",
                    "systemd_scope_unit": compositor_unit}
            calls = []

            def control(name: str, unit: str, action: str) -> None:
                calls.append((name, unit, action))
                if unit == compositor_unit and action == "freeze":
                    raise KeyboardInterrupt()

            with patch("cortetsu_agent_realms.runtime.paths_for", return_value=paths), \
                 patch("cortetsu_agent_realms.process.paths_for", return_value=paths), \
                 patch.object(runtime, "load_meta", return_value=meta), \
                 patch.object(runtime, "process_alive", return_value=True), \
                 patch.object(runtime, "app_groups", return_value=[{"systemd_scope_unit": app_unit}]), \
                 patch.object(runtime, "_realm_scope_units", return_value={compositor_unit, app_unit}), \
                 patch.object(runtime, "scope_freezer_state", return_value="running"), \
                 patch.object(runtime, "control_scope", side_effect=control), \
                 patch.object(runtime, "save_meta") as save_meta:
                with self.assertRaises(KeyboardInterrupt):
                    runtime.pause("codex", True)

            self.assertEqual(meta["state"], "running")
            self.assertEqual(calls, [
                ("codex", app_unit, "freeze"),
                ("codex", compositor_unit, "freeze"),
                ("codex", compositor_unit, "thaw"),
                ("codex", app_unit, "thaw"),
            ])
            save_meta.assert_called_once_with(paths, meta)

    def test_resume_rolls_back_thawed_apps_if_compositor_thaw_fails(self) -> None:
        with tempfile.TemporaryDirectory(prefix="agent-realm-resume-rollback-") as directory:
            root = Path(directory)
            state = root / "state"
            (state / "apps").mkdir(parents=True)
            paths = RealmPaths("codex", state, root / "home", root / "runtime",
                               root / "config", root / "log", root / "hyprlog", control=state)
            compositor_unit = "agent-realm-codex-abcdef1234.scope"
            app_unit = "agent-realm-codex-1234567890.scope"
            meta = {"name": "codex", "schema": 1, "state": "paused",
                    "systemd_scope_unit": compositor_unit}
            calls = []

            def control(name: str, unit: str, action: str) -> None:
                calls.append((name, unit, action))
                if unit == compositor_unit and action == "thaw":
                    raise RealmError("injected compositor thaw error")

            def scope_is_active(candidate: dict[str, str]) -> bool:
                return candidate.get("systemd_scope_unit") in {compositor_unit, app_unit}

            with patch("cortetsu_agent_realms.runtime.paths_for", return_value=paths), \
                 patch("cortetsu_agent_realms.process.paths_for", return_value=paths), \
                 patch.object(runtime, "load_meta", return_value=meta), \
                 patch.object(runtime, "process_alive", side_effect=scope_is_active), \
                 patch.object(runtime, "_realm_scope_units", return_value={compositor_unit, app_unit}), \
                 patch.object(runtime, "scope_freezer_state", return_value="frozen"), \
                 patch.object(runtime, "control_scope", side_effect=control), \
                 patch.object(runtime, "save_meta") as save_meta:
                with self.assertRaisesRegex(RealmError, "se restauró el estado previo"):
                    runtime.pause("codex", False)

            self.assertEqual(meta["state"], "paused")
            self.assertEqual(calls, [
                ("codex", app_unit, "thaw"),
                ("codex", compositor_unit, "thaw"),
                ("codex", compositor_unit, "freeze"),
                ("codex", app_unit, "freeze"),
            ])
            save_meta.assert_called_once_with(paths, meta)

    def test_pause_marks_transition_error_when_rollback_fails(self) -> None:
        with tempfile.TemporaryDirectory(prefix="agent-realm-transition-error-") as directory:
            root = Path(directory)
            state = root / "state"
            (state / "apps").mkdir(parents=True)
            paths = RealmPaths("codex", state, root / "home", root / "runtime",
                               root / "config", root / "log", root / "hyprlog", control=state)
            compositor_unit = "agent-realm-codex-abcdef1234.scope"
            app_unit = "agent-realm-codex-1234567890.scope"
            meta = {"name": "codex", "schema": 1, "state": "running",
                    "systemd_scope_unit": compositor_unit}

            def control(name: str, unit: str, action: str) -> None:
                if (unit, action) in {(compositor_unit, "freeze"), (compositor_unit, "thaw")}:
                    raise RealmError("injected transition failure")

            with patch("cortetsu_agent_realms.runtime.paths_for", return_value=paths), \
                 patch("cortetsu_agent_realms.process.paths_for", return_value=paths), \
                 patch.object(runtime, "load_meta", return_value=meta), \
                 patch.object(runtime, "process_alive", return_value=True), \
                 patch.object(runtime, "app_groups", return_value=[{"systemd_scope_unit": app_unit}]), \
                 patch.object(runtime, "_realm_scope_units", return_value={compositor_unit, app_unit}), \
                 patch.object(runtime, "scope_freezer_state", return_value="running"), \
                 patch.object(runtime, "control_scope", side_effect=control), \
                 patch.object(runtime, "save_meta") as save_meta:
                with self.assertRaisesRegex(RealmError, "transition-error"):
                    runtime.pause("codex", True)

            self.assertEqual(meta["state"], "transition-error")
            self.assertIn("injected transition failure", meta["transition_error"])
            save_meta.assert_called_once_with(paths, meta)

    def test_app_groups_keeps_live_legacy_process_visible_to_inspect(self) -> None:
        with tempfile.TemporaryDirectory(prefix="agent-realm-legacy-inspect-") as directory:
            root = Path(directory)
            state = root / "state"
            app_dir = state / "apps"
            app_dir.mkdir(parents=True)
            record = app_dir / "1234.json"
            data = {"pid": 1234, "start_time": 98765, "command": ["legacy-app"]}
            record.write_text(json.dumps(data) + "\n")
            paths = RealmPaths("codex", state, root / "home", root / "runtime",
                               root / "config", root / "log", root / "hyprlog", control=state)
            with patch.object(process, "same_process", return_value=True):
                self.assertEqual(process.app_groups(paths), [data])
            self.assertTrue(record.exists())

    def test_pause_rejects_live_legacy_group_before_freezing_compositor(self) -> None:
        with tempfile.TemporaryDirectory(prefix="agent-realm-pause-legacy-") as directory:
            root = Path(directory)
            state = root / "state"
            app_dir = state / "apps"
            app_dir.mkdir(parents=True)
            record = app_dir / "1234.json"
            record.write_text(json.dumps({"pid": 1234, "start_time": 98765}) + "\n")
            paths = RealmPaths("codex", state, root / "home", root / "runtime",
                               root / "config", root / "log", root / "hyprlog", control=state)
            meta = {"name": "codex", "schema": 1, "state": "running", "systemd_scope_unit":
                    "agent-realm-codex-abcdef1234.scope"}
            with patch("cortetsu_agent_realms.runtime.paths_for", return_value=paths), \
                 patch("cortetsu_agent_realms.process.paths_for", return_value=paths), \
                 patch.object(runtime, "load_meta", return_value=meta), \
                 patch.object(runtime, "process_alive", return_value=True), \
                 patch.object(process, "same_process", return_value=True), \
                 patch.object(runtime, "control_scope") as control_scope:
                with self.assertRaisesRegex(RealmError, "app legacy.*no se puede pausar"):
                    runtime.pause("codex", True)
            control_scope.assert_not_called()
            self.assertTrue(record.exists())

    def test_supervisor_waits_for_persistent_pointer_ready(self) -> None:
        with tempfile.TemporaryDirectory(prefix="agent-realm-pointer-test-") as directory:
            log_path = Path(directory) / "pointer.log"
            stdout = io.BytesIO(b"READY\n")
            proc = unittest.mock.Mock(stdout=stdout, pid=123)
            with patch.object(supervisor.subprocess, "Popen", return_value=proc) as popen, \
                 patch.object(supervisor.select, "select", return_value=([stdout], [], [])):
                started, log_handle = supervisor._launch_virtual_pointer(
                    "/tmp/input-client", {"WAYLAND_DISPLAY": "wayland-9"}, log_path, 1)
            self.assertIs(started, proc)
            self.assertEqual(popen.call_args.args[0], ["/tmp/input-client", "keep"])
            self.assertEqual(popen.call_args.kwargs["env"], {"WAYLAND_DISPLAY": "wayland-9"})
            log_handle.close()

    def test_supervisor_rejects_pointer_without_ready_and_cleans_it(self) -> None:
        with tempfile.TemporaryDirectory(prefix="agent-realm-pointer-test-") as directory:
            log_path = Path(directory) / "pointer.log"
            log_path.write_text("pointer initialization failed\n")
            stdout = io.BytesIO(b"")
            proc = unittest.mock.Mock(stdout=stdout, pid=123, returncode=9)
            proc.poll.return_value = 9
            with patch.object(supervisor.subprocess, "Popen", return_value=proc), \
                 patch.object(supervisor.select, "select", return_value=([stdout], [], [])), \
                 patch.object(supervisor, "_terminate") as terminate:
                with self.assertRaisesRegex(RuntimeError, "código 9"):
                    supervisor._launch_virtual_pointer(
                        "/tmp/input-client", {"WAYLAND_DISPLAY": "wayland-9"}, log_path, 1)
            terminate.assert_called_once_with(proc)
            self.assertTrue(stdout.closed)

    def test_supervisor_closes_persistent_pointer_pipe_after_termination(self) -> None:
        stdout = unittest.mock.Mock()
        proc = unittest.mock.Mock(stdout=stdout)
        with patch.object(supervisor, "_terminate") as terminate:
            supervisor._stop_virtual_pointer(proc)
        terminate.assert_called_once_with(proc)
        stdout.close.assert_called_once_with()

    def test_supervisor_detects_pointer_exit_after_ready(self) -> None:
        proc = unittest.mock.Mock(returncode=17)
        proc.poll.return_value = 17
        with self.assertRaisesRegex(RuntimeError, "puntero virtual terminó.*17"):
            supervisor._check_virtual_pointer(proc)

    def test_all_ipc_requests_use_explicit_realm_signature(self) -> None:
        paths = RealmPaths("codex", Path("/state"), Path("/home"), Path("/runtime"),
                           Path("/config"), Path("/log"), Path("/hyprlog"), control=Path("/state"))
        meta = {"name": "codex", "schema": 1, "state": "running", "leader_pid": os.getpid(),
                "leader_start_time": 0, "signature": "realm-123", "wayland_display": "wayland-8"}
        fake_result = subprocess.CompletedProcess([], 0, "[]", "")
        with patch("cortetsu_agent_realms.runtime.paths_for", return_value=paths), \
             patch("cortetsu_agent_realms.runtime.load_meta", return_value=meta), \
             patch("cortetsu_agent_realms.runtime.process_alive", return_value=True), \
             patch("cortetsu_agent_realms.runtime.shutil.which", return_value="/usr/bin/hyprctl"), \
             patch("cortetsu_agent_realms.runtime._require_realm_ipc_socket"), \
             patch("cortetsu_agent_realms.runtime.subprocess.run", return_value=fake_result) as run:
            private_call("codex", ["-j", "monitors"])
        command = run.call_args.args[0]
        self.assertEqual(command, ["/usr/bin/hyprctl", "-i", "realm-123", "-j", "monitors"])
        self.assertEqual(run.call_args.kwargs["env"]["WAYLAND_DISPLAY"], "wayland-8")

    def test_ipc_refuses_missing_or_forged_realm_socket_before_running_hyprctl(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            runtime_dir = Path(directory)
            paths = RealmPaths("codex", runtime_dir, runtime_dir, runtime_dir, runtime_dir,
                               runtime_dir, runtime_dir, control=runtime_dir)
            meta = {"name": "codex", "schema": 1, "state": "running", "signature": "abc_1",
                    "wayland_display": "wayland-1"}
            with patch("cortetsu_agent_realms.runtime.paths_for", return_value=paths), \
                 patch("cortetsu_agent_realms.runtime.load_meta", return_value=meta), \
                 patch("cortetsu_agent_realms.runtime.process_alive", return_value=True), \
                 patch("cortetsu_agent_realms.runtime.subprocess.run") as run:
                with self.assertRaisesRegex(RealmError, "socket IPC propio"):
                    private_call("codex", ["-j", "monitors"])
                (runtime_dir / "hypr" / "abc_1").mkdir(parents=True)
                (runtime_dir / "hypr" / "abc_1" / ".socket.sock").symlink_to("/run/user/1000/hypr")
                with self.assertRaisesRegex(RealmError, "no es un socket propio"):
                    private_call("codex", ["-j", "monitors"])
                meta["signature"] = "../../host"
                with self.assertRaisesRegex(RealmError, "firma IPC"):
                    private_call("codex", ["-j", "monitors"])
            run.assert_not_called()

    def test_pointer_action_order_matches_compiled_protocol_client(self) -> None:
        paths = RealmPaths("codex", Path("/state"), Path("/home"), Path("/runtime"),
                           Path("/config"), Path("/log"), Path("/hyprlog"), control=Path("/state"))
        with patch("cortetsu_agent_realms.input._screen", return_value=(-40, 10, 1400, 800)), \
             patch("cortetsu_agent_realms.input.virtual_input_binary", return_value=Path("/tmp/realm-input")), \
             patch("cortetsu_agent_realms.input._load", return_value={"signature": "s", "wayland_display": "wayland-1"}), \
             patch("cortetsu_agent_realms.input._realm_env", return_value={}), \
             patch("cortetsu_agent_realms.input.subprocess.run",
                   return_value=subprocess.CompletedProcess([], 0, "", "")) as run:
            vinput.click(paths, 10, 50, "right", 2)
            self.assertEqual(run.call_args.args[0], ["/tmp/realm-input", "click", "50", "40", "1400", "800", "right", "2"])
            vinput.drag(paths, 10, 50, 100, 120, "left")
            self.assertEqual(run.call_args.args[0], ["/tmp/realm-input", "drag", "50", "40", "140", "110", "1400", "800", "left"])

    def test_default_virtual_text_uses_a_small_character_delay(self) -> None:
        paths = RealmPaths("codex", Path("/state"), Path("/home"), Path("/runtime"),
                           Path("/config"), Path("/log"), Path("/hyprlog"), control=Path("/state"))
        result = subprocess.CompletedProcess([], 0, "", "")
        with patch("cortetsu_agent_realms.input.shutil.which", return_value="/usr/bin/wtype"), \
             patch("cortetsu_agent_realms.input._load", return_value={"signature": "realm-1"}), \
             patch("cortetsu_agent_realms.input._realm_env", return_value={"WAYLAND_DISPLAY": "wayland-9"}), \
             patch("cortetsu_agent_realms.input.subprocess.run", return_value=result) as run:
            vinput.type_text(paths, "private text")
        self.assertEqual(run.call_args.args[0], ["/usr/bin/wtype", "-s", "50", "-P", "Shift_L", "-p", "Shift_L",
                                                 "-d", "5", "--", "private text"])
        self.assertEqual(run.call_args.kwargs["env"], {"WAYLAND_DISPLAY": "wayland-9"})

    def test_explicit_zero_text_delay_omits_invalid_wtype_zero_option(self) -> None:
        paths = RealmPaths("codex", Path("/state"), Path("/home"), Path("/runtime"),
                           Path("/config"), Path("/log"), Path("/hyprlog"), control=Path("/state"))
        result = subprocess.CompletedProcess([], 0, "", "")
        with patch("cortetsu_agent_realms.input.shutil.which", return_value="/usr/bin/wtype"), \
             patch("cortetsu_agent_realms.input._load", return_value={"signature": "realm-1"}), \
             patch("cortetsu_agent_realms.input._realm_env", return_value={"WAYLAND_DISPLAY": "wayland-9"}), \
             patch("cortetsu_agent_realms.input.subprocess.run", return_value=result) as run:
            vinput.type_text(paths, "private text", 0)
        self.assertEqual(run.call_args.args[0], ["/usr/bin/wtype", "-s", "50", "-P", "Shift_L", "-p", "Shift_L",
                                                 "--", "private text"])

    def test_virtual_key_waits_for_keyboard_keymap_before_first_event(self) -> None:
        paths = RealmPaths("codex", Path("/state"), Path("/home"), Path("/runtime"),
                           Path("/config"), Path("/log"), Path("/hyprlog"), control=Path("/state"))
        with patch("cortetsu_agent_realms.input.shutil.which", return_value="/usr/bin/wtype"), \
             patch("cortetsu_agent_realms.input._load", return_value={"signature": "realm-1"}), \
             patch("cortetsu_agent_realms.input._realm_env", return_value={"WAYLAND_DISPLAY": "wayland-9"}), \
             patch("cortetsu_agent_realms.input.subprocess.run",
                   return_value=subprocess.CompletedProcess([], 0, "", "")) as run:
            vinput.key(paths, "CTRL+L")
        self.assertEqual(run.call_args.args[0], ["/usr/bin/wtype", "-s", "50", "-P", "Shift_L", "-p", "Shift_L",
                                                 "-M", "ctrl", "-k", "L", "-m", "ctrl"])
        self.assertEqual(run.call_args.kwargs["env"], {"WAYLAND_DISPLAY": "wayland-9"})

    def test_virtual_pointer_client_builds_without_system_package_install(self) -> None:
        with tempfile.TemporaryDirectory(prefix="agent-realm-test-") as directory:
            output = Path(directory) / "realm-input"
            result = subprocess.run(["/bin/bash", str(ROOT / "scripts/build-virtual-input.sh"), str(output)],
                                    capture_output=True, text=True, timeout=30)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertTrue(os.access(output, os.X_OK))
            usage = subprocess.run([str(output)], capture_output=True, text=True, timeout=2)
            self.assertEqual(usage.returncode, 2)
            self.assertIn("click", usage.stderr)
            self.assertIn("keep", usage.stderr)

    def test_weston_protocol_shim_builds_without_system_package_install(self) -> None:
        with tempfile.TemporaryDirectory(prefix="agent-realm-shim-test-") as directory:
            output = Path(directory) / "xdg-version-shim.so"
            result = subprocess.run(["/bin/bash", str(ROOT / "scripts/build-xdg-version-shim.sh"), str(output)],
                                    capture_output=True, text=True, timeout=30)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertTrue(output.is_file())
            self.assertTrue(os.access(output, os.X_OK))


if __name__ == "__main__":
    unittest.main()

from __future__ import annotations

import json
import os
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from cortetsu_agent_realms import process
from cortetsu_agent_realms.paths import RealmPaths, paths_for


def _paths(root: Path) -> RealmPaths:
    return RealmPaths("codex", root / "state", root / "home", root / "runtime",
                      root / "state" / "hyprland.conf", root / "state" / "supervisor.log",
                      root / "state" / "hyprland.log", control=root / "control")


class TrustBoundaryTests(unittest.TestCase):
    def test_host_records_live_outside_the_mounted_state_tree(self) -> None:
        with tempfile.TemporaryDirectory() as d, patch.dict(os.environ, {"XDG_STATE_HOME": d}):
            p = paths_for("codex")
            for host_owned in (process.meta_path(p), p.control / "apps", p.config, p.log):
                self.assertNotIn(p.state, host_owned.parents)

    def test_forged_report_cannot_inject_pids_units_or_foreign_sockets(self) -> None:
        with tempfile.TemporaryDirectory() as d:
            p = _paths(Path(d))
            p.state.mkdir()
            (p.state / process.REPORT_NAME).write_text(json.dumps({
                "name": "codex", "state": "starting", "signature": "abc_123",
                "wayland_display": "wayland-1",
                "dbus_session_bus_address": "unix:path=/run/user/1000/bus",
                "leader_pid": 1, "systemd_scope_unit": "init.scope"}))
            report = process.load_realm_report(p)
            self.assertEqual(report, {"state": "starting", "signature": "abc_123",
                                      "wayland_display": "wayland-1"})

    def test_report_rejects_path_like_endpoints(self) -> None:
        with tempfile.TemporaryDirectory() as d:
            p = _paths(Path(d))
            p.state.mkdir()
            for sig, disp in (("../../hypr", "wayland-1"), ("abc", "/run/user/1000/wayland-0")):
                with self.subTest(sig=sig, disp=disp):
                    (p.state / process.REPORT_NAME).write_text(json.dumps(
                        {"name": "codex", "signature": sig, "wayland_display": disp}))
                    self.assertNotIn("signature", process.load_realm_report(p))

    def test_report_keeps_only_the_private_bus_and_strips_escapes(self) -> None:
        with tempfile.TemporaryDirectory() as d:
            p = _paths(Path(d))
            p.state.mkdir()
            (p.state / process.REPORT_NAME).write_text(json.dumps({
                "name": "codex", "state": "failed", "error": "boom\x1b]0;pwn\x07",
                "signature": "abc", "wayland_display": "wayland-1",
                "dbus_session_bus_address": f"unix:path={p.runtime}/bus"}))
            report = process.load_realm_report(p)
            self.assertEqual(report["dbus_session_bus_address"], f"unix:path={p.runtime}/bus")
            self.assertEqual(report["error"], "boom]0;pwn")

    def test_untrusted_reads_refuse_symlinks_and_fifos(self) -> None:
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            secret = root / "secret"
            secret.write_text("host secret")
            (root / "link").symlink_to(secret)
            os.mkfifo(root / "fifo")
            for name in ("link", "fifo"):
                with self.subTest(name=name), self.assertRaises(OSError):
                    process.read_untrusted(root / name)
            big = root / "big"
            big.write_bytes(b"x" * 100 + b"tail")
            self.assertEqual(process.read_untrusted(big, 4), "tail")

    def test_legacy_session_layout_is_refused_not_ignored(self) -> None:
        with tempfile.TemporaryDirectory() as d:
            p = _paths(Path(d))
            p.state.mkdir()
            (p.state / process.META_NAME).write_text("{}")
            with self.assertRaisesRegex(Exception, "formato anterior"):
                process.load_meta(p)

    def test_report_for_another_realm_or_garbage_is_ignored(self) -> None:
        with tempfile.TemporaryDirectory() as d:
            p = _paths(Path(d))
            p.state.mkdir()
            self.assertIsNone(process.load_realm_report(p))
            (p.state / process.REPORT_NAME).write_text('{"name": "claude", "state": "failed"}')
            self.assertIsNone(process.load_realm_report(p))
            (p.state / process.REPORT_NAME).write_text("not json")
            self.assertIsNone(process.load_realm_report(p))


class SupervisionTests(unittest.TestCase):
    def test_supervisor_presence_reads_exact_scope_and_argv(self) -> None:
        from cortetsu_agent_realms.process import supervisor_present as _supervisor_present
        unit = "agent-realm-codex-abcdef1234.scope"
        with tempfile.TemporaryDirectory() as d:
            proc = Path(d)
            for pid, cg, argv in (("10", unit, b"Hyprland\0-c\0x"),
                                  ("11", "other.scope", b"python\0-m\0cortetsu_agent_realms.supervisor"),
                                  ("13", unit, b"/usr/bin/bwrap\0--clearenv\0--\0/usr/bin/python\0-m\0"
                                               b"cortetsu_agent_realms.supervisor\0")):
                (proc / pid).mkdir()
                (proc / pid / "cgroup").write_text(f"0::/user.slice/app.slice/{cg}\n")
                (proc / pid / "cmdline").write_bytes(argv)
            self.assertFalse(_supervisor_present(unit, proc))
            (proc / "12").mkdir()
            (proc / "12" / "cgroup").write_text(f"0::/app.slice/{unit}\n")
            (proc / "12" / "cmdline").write_bytes(b"/usr/bin/python\0-m\0cortetsu_agent_realms.supervisor\0")
            self.assertTrue(_supervisor_present(unit, proc))


    def test_status_reports_degraded_when_supervisor_is_gone(self) -> None:
        from cortetsu_agent_realms import cli
        meta = {"name": "codex", "schema": 1, "state": "running",
                "systemd_scope_unit": "agent-realm-codex-abcdef1234.scope"}
        with patch.object(cli, "process_alive", return_value=True), \
             patch.object(cli, "supervisor_present", return_value=False), \
             patch.object(cli, "_hypr_json", return_value=[{"name": "HEADLESS-1"}]):
            status = cli._status(meta)
        self.assertEqual((status["state"], status["supervised"], status["ipc_reachable"]),
                         ("degraded", False, True))
        self.assertEqual(meta["state"], "running")


if __name__ == "__main__":
    unittest.main()

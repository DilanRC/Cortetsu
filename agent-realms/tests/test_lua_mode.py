from __future__ import annotations

import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from cortetsu_agent_realms import runtime
from cortetsu_agent_realms.paths import RealmPaths

TRICKY = 'a"b\\c\nñ\x01]] $(false)'


class LuaModeTests(unittest.TestCase):
    def test_lua_string_is_plain_ascii_with_decimal_escapes(self) -> None:
        literal = runtime.lua_string(TRICKY)
        self.assertTrue(literal.isascii())
        self.assertNotIn("\n", literal)
        self.assertEqual(literal.count('"'), 2)

    @unittest.skipUnless(shutil.which("lua"), "lua no está instalado")
    def test_lua_string_round_trips_through_real_lua(self) -> None:
        out = subprocess.run(["lua", "-e", f"io.write({runtime.lua_string(TRICKY)})"],
                             capture_output=True, check=True).stdout
        self.assertEqual(out.decode(), TRICKY)

    def test_both_config_formats_silence_the_start_hyprland_watchdog_notice(self) -> None:
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            paths = RealmPaths("codex", root, root, root, root / "hyprland.conf", root, root, control=root)
            for lua in (False, True):
                runtime._write_hypr_config(paths, 1280, 800, None, lua)
                text = runtime.config_file(paths, lua).read_text()
                self.assertIn("disable_watchdog_warning = true", text)

    def test_compositor_child_uses_lua_dispatch_when_realm_is_lua(self) -> None:
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            paths = RealmPaths("codex", root / "state", root / "home", root / "runtime",
                               root / "c.conf", root / "log", root / "hyprlog", control=root / "ctl")
            meta = {"name": "codex", "state": "running", "config_format": "lua",
                    "systemd_scope_unit": "agent-realm-codex-abcdef1234.scope"}
            ok = subprocess.CompletedProcess([], 0, "ok\n", "")
            with patch.object(runtime, "paths_for", return_value=paths), \
                 patch.object(runtime, "load_meta", return_value=meta), \
                 patch.object(runtime, "process_alive", return_value=True), \
                 patch.object(runtime, "private_call", return_value=ok) as call:
                runtime.run("codex", ["kitty", "--title", "x;y"], detach=True, compositor_child=True)
            expected = f"hl.dsp.exec_cmd({runtime.lua_string('kitty --title ' + chr(39) + 'x;y' + chr(39))})"
            call.assert_called_once_with("codex", ["dispatch", expected])

    def test_lua_config_is_written_beside_the_hyprlang_one(self) -> None:
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            paths = RealmPaths("codex", root / "state", root / "home", root / "runtime",
                               root / "hyprland.conf", root / "log", root / "hyprlog", control=root)
            runtime._write_hypr_config(paths, 1280, 800, None, lua=True)
            text = runtime.config_file(paths, True).read_text()
            self.assertIn('mode = "1280x800@60"', text)
            self.assertFalse(paths.config.exists())


if __name__ == "__main__":
    unittest.main()

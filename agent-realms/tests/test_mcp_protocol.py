"""MCP wire contract over stdio: the bytes Claude Code or Codex exchange with agent-realm-mcp.

Needs the project venv (scripts/setup-mcp-venv.sh); skipped otherwise. No realm is
started: the bound realm is absent and autostart is off, so lifecycle errors are
exercised without touching Hyprland.
"""
from __future__ import annotations

import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from mcp_wire import Server  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]
VENV_PYTHON = ROOT / ".venv/bin/python"


def _sdk_available() -> bool:
    if not VENV_PYTHON.exists():
        return False
    return subprocess.run([str(VENV_PYTHON), "-c", "import mcp.server.mcpserver"],
                          capture_output=True).returncode == 0


FULL_TOOLS = {"realm_status", "realm_diagnose", "realm_logs", "realm_start", "realm_stop", "screenshot",
              "wait_for_change", "window_list", "window_focus", "window_close", "app_list", "app_launch",
              "app_close", "pointer", "keyboard", "services_status", "services_simulate"}
OBSERVE_TOOLS = {"realm_status", "realm_diagnose", "realm_logs", "screenshot", "wait_for_change",
                 "window_list", "app_list", "services_status"}


@unittest.skipUnless(_sdk_available(), "requires .venv with mcp (scripts/setup-mcp-venv.sh)")
class McpProtocolTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory(prefix="agent-realm-mcp-")
        self.config = Path(self.tmp.name) / "config"
        (self.config / "cortetsu-agent-realms").mkdir(parents=True, mode=0o700)
        self.config.chmod(0o700)
        self.profiles = self.config / "cortetsu-agent-realms" / "profiles.json"
        self.write_profiles({
            "tester": {"realm": "mcp-test-absent", "capabilities": ["observe", "control", "admin"],
                       "autostart": False},
            "viewer": {"realm": "mcp-test-viewer", "capabilities": ["observe"], "autostart": False},
        })
        self.servers: list[Server] = []

    def tearDown(self) -> None:
        for server in self.servers:
            if server.proc.poll() is None:
                server.close()
        self.tmp.cleanup()

    def write_profiles(self, profiles: dict) -> None:
        self.profiles.write_text(json.dumps({"schema": 1, "profiles": profiles}))
        self.profiles.chmod(0o600)

    def start(self, profile: str = "tester") -> Server:
        server = Server(str(self.config), profile, str(Path(self.tmp.name) / "state"))
        self.servers.append(server)
        return server

    def test_handshake_with_current_and_older_protocol_versions(self) -> None:
        for version in ("2025-06-18", "2025-11-25", "2025-03-26"):
            server = self.start()
            result = server.handshake(version)["result"]
            self.assertEqual(result["protocolVersion"], version)
            self.assertEqual(result["serverInfo"]["name"], "cortetsu-agent-realms")
            self.assertIn("tools", result["capabilities"])
            self.assertIn("frame_id", result["instructions"])
            server.close()

    def test_tool_discovery_and_schemas_never_take_a_realm_name(self) -> None:
        server = self.start()
        server.handshake()
        tools = server.request("tools/list")["result"]["tools"]
        self.assertEqual({t["name"] for t in tools}, FULL_TOOLS)
        for tool in tools:
            schema = tool["inputSchema"]
            self.assertEqual(schema["type"], "object")
            self.assertTrue(tool.get("description"), tool["name"])
            for forbidden in ("name", "realm", "signature", "instance"):
                self.assertNotIn(forbidden, schema.get("properties", {}), tool["name"])
        by_name = {t["name"]: t for t in tools}
        self.assertTrue(by_name["screenshot"]["annotations"]["readOnlyHint"])
        self.assertTrue(by_name["realm_stop"]["annotations"]["destructiveHint"])
        pointer = by_name["pointer"]["inputSchema"]["properties"]
        self.assertEqual(set(pointer["action"]["enum"]),
                         {"move", "click", "double_click", "drag", "scroll"})

    def test_observe_only_profile_exposes_and_accepts_only_observation(self) -> None:
        server = self.start("viewer")
        server.handshake()
        names = {t["name"] for t in server.request("tools/list")["result"]["tools"]}
        self.assertEqual(names, OBSERVE_TOOLS)
        for name, arguments in (("pointer", {"action": "click", "x": 1, "y": 1}),
                                ("realm_start", {}), ("keyboard", {"action": "type", "value": "x"})):
            reply = server.call(name, arguments)
            failed = "error" in reply or reply.get("result", {}).get("isError")
            self.assertTrue(failed, f"{name} must not run for an observe-only profile: {reply}")

    def test_invalid_arguments_are_rejected_before_any_backend_call(self) -> None:
        server = self.start()
        server.handshake()
        cases = [("pointer", {"action": "explode", "x": 1, "y": 1}),
                 ("pointer", {"action": "click", "x": -5, "y": 1}),
                 ("pointer", {"action": "click", "x": 1}),
                 ("window_focus", {"address": "address:0x1; rm -rf /"}),
                 ("keyboard", {"action": "type", "value": ""}),
                 ("app_launch", {"argv": []}),
                 ("app_close", {"app_id": 1}),
                 ("screenshot", {"monitor": "../../host"}),
                 ("realm_logs", {"tail": 100000}),
                 ("services_simulate", {"action": "apply", "scenario": "../../etc"}),
                 ("services_simulate", {"action": "event", "event": "reboot-host"}),
                 ("wait_for_change", {"timeout_s": 3600})]
        for name, arguments in cases:
            reply = server.call(name, arguments)
            failed = "error" in reply or reply.get("result", {}).get("isError")
            self.assertTrue(failed, f"{name} {arguments} was accepted: {reply}")

    def test_lifecycle_errors_are_structured_and_status_never_starts(self) -> None:
        server = self.start()
        server.handshake()
        status = server.call("realm_status")["result"]
        self.assertFalse(status.get("isError"))
        self.assertEqual(status["structuredContent"]["state"], "absent")
        self.assertEqual(status["structuredContent"]["binding"]["realm"], "mcp-test-absent")
        for name, arguments in (("screenshot", {}), ("window_list", {}),
                                ("pointer", {"action": "move", "x": 1, "y": 1})):
            result = server.call(name, arguments)["result"]
            self.assertTrue(result["isError"], name)
            error = result["structuredContent"]["error"]
            self.assertEqual(error["code"], "realm_absent", name)
            self.assertIn("realm_start", error["hint"])
        state_dir = Path(self.tmp.name) / "state" / "cortetsu-agent-realms-control" / "mcp-test-absent"
        self.assertFalse((state_dir / "session.json").exists(), "no realm may be created implicitly")

    def test_unknown_or_tampered_profiles_refuse_to_start(self) -> None:
        server = self.start("nobody")
        self.assertNotEqual(server.proc.wait(timeout=10), 0)
        self.assertIn("no existe el perfil", server.close())
        self.profiles.chmod(0o666)
        server = self.start("tester")
        self.assertNotEqual(server.proc.wait(timeout=10), 0)
        self.assertIn("sin escritura de grupo u otros", server.close())
        self.profiles.chmod(0o600)
        self.write_profiles({"a": {"realm": "same"}, "b": {"realm": "same"}})
        server = self.start("a")
        self.assertNotEqual(server.proc.wait(timeout=10), 0)
        self.assertIn("comparten el realm", server.close())

    def test_reconnection_gets_the_same_binding(self) -> None:
        first = self.start()
        first.handshake()
        binding = first.call("realm_status")["result"]["structuredContent"]["binding"]
        first.close()
        second = self.start()
        second.handshake()
        self.assertEqual(second.call("realm_status")["result"]["structuredContent"]["binding"], binding)

    def test_unknown_method_and_garbage_keep_the_server_alive(self) -> None:
        server = self.start()
        server.handshake()
        self.assertIn("error", server.request("tools/explode"))
        server.send({"jsonrpc": "2.0", "method": "notifications/cancelled",
                     "params": {"requestId": 999, "reason": "test"}})
        self.assertEqual(server.call("realm_status")["result"]["structuredContent"]["state"], "absent")


@unittest.skipUnless(_sdk_available(), "requires .venv with mcp (scripts/setup-mcp-venv.sh)")
class ClientConfigTests(unittest.TestCase):
    """The committed client configs launch a working server, exactly as Claude Code or Codex would."""

    def _launch_as_client(self, command: str, args: list[str], profile_realm: str) -> set[str]:
        with tempfile.TemporaryDirectory() as tmp:
            folder = Path(tmp) / "cortetsu-agent-realms"
            folder.mkdir(mode=0o700)
            profile = args[args.index("--profile") + 1]
            (folder / "profiles.json").write_text(json.dumps({"schema": 1, "profiles": {
                profile: {"realm": profile_realm, "capabilities": ["observe", "control", "admin"],
                          "autostart": False}}}))
            (folder / "profiles.json").chmod(0o600)
            # Exactly the client's launch: same argv, run from the repo root.
            server = Server(tmp, profile, tmp, command=[command, *args], cwd=ROOT)
            try:
                self.assertEqual(server.handshake()["result"]["serverInfo"]["name"], "cortetsu-agent-realms")
                return {t["name"] for t in server.request("tools/list")["result"]["tools"]}
            finally:
                server.close()

    def test_claude_project_config(self) -> None:
        config = json.loads((ROOT / ".mcp.json").read_text())
        server = config["mcpServers"]["agent-realms"]
        self.assertEqual(server["type"], "stdio")
        self.assertFalse(Path(server["command"]).is_absolute(), "no absolute paths in shared config")
        self.assertEqual(server["args"], ["--profile", "claude"])
        self.assertEqual(self._launch_as_client(server["command"], server["args"], "claude"), FULL_TOOLS)

    def test_codex_project_config(self) -> None:
        import tomllib
        config = tomllib.loads((ROOT / ".codex/config.toml").read_text())
        server = config["mcp_servers"]["agent-realms"]
        self.assertEqual(set(server) - {"command", "args", "startup_timeout_sec", "tool_timeout_sec"}, set())
        self.assertFalse(Path(server["command"]).is_absolute())
        self.assertEqual(server["args"], ["--profile", "codex"])
        self.assertEqual(self._launch_as_client(server["command"], server["args"], "codex"), FULL_TOOLS)


if __name__ == "__main__":
    unittest.main()

"""Contracts for the client-facing realm API and profile bindings (stdlib only)."""
from __future__ import annotations

import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from cortetsu_agent_realms import agent as agent_mod
from cortetsu_agent_realms import profiles
from cortetsu_agent_realms.agent import AgentError, RealmAgent
from cortetsu_agent_realms.auth import Capability
from cortetsu_agent_realms.capture import Frame, Monitor
from cortetsu_agent_realms.paths import RealmError

FULL = frozenset(Capability)
MON = Monitor("HEADLESS-2", 0, 0, 1280, 800, 1.0, True)
SESSION = "agent-realm-claude-0123456789.scope:42"


def make_agent(caps=FULL, **kwargs) -> RealmAgent:
    return RealmAgent(profiles.Profile("claude", "claude", frozenset(caps), **kwargs))


def half_frame(frame_id: str = "f1", monitor: Monitor = MON) -> Frame:
    return Frame(data=b"", realm="claude", monitor=monitor, region=(0.0, 0.0, 1280.0, 800.0),
                 delivered=(640, 400), image_format="png", frame_id=frame_id, session=SESSION)


class CoordinateTests(unittest.TestCase):
    def setUp(self) -> None:
        self.agent = make_agent()
        self.agent._frames["f1"] = half_frame()
        self.patches = [patch.object(agent_mod.cap, "monitors", return_value=[MON]),
                        patch.object(agent_mod, "load_meta", return_value={
                            "systemd_scope_unit": "agent-realm-claude-0123456789.scope", "leader_start_time": 42}),
                        patch.object(agent_mod, "paths_for")]
        for p in self.patches:
            p.start()

    def tearDown(self) -> None:
        for p in self.patches:
            p.stop()

    def test_downscaled_frame_pixels_map_back_to_desktop(self) -> None:
        frame = half_frame()
        self.assertEqual(frame.scale, 0.5)
        self.assertEqual(frame.original, (1280, 800))
        self.assertEqual(frame.metadata()["delivered_resolution"], [640, 400])
        self.assertEqual(self.agent._to_desktop(320, 200, "f1"), (640, 400))
        self.assertEqual(self.agent._to_desktop(639, 399, "f1"), (1278, 798))

    def test_region_and_monitor_offset_and_hidpi_are_applied(self) -> None:
        hidpi = Monitor("HEADLESS-3", 1280, 0, 2560, 1600, 2.0)
        frame = Frame(data=b"", realm="claude", monitor=hidpi, region=(1380.0, 100.0, 400.0, 200.0),
                      delivered=(800, 400), image_format="png", frame_id="r", session=SESSION)
        self.assertEqual(frame.original, (800, 400))
        self.assertEqual(frame.to_desktop(400, 200), (1580, 200))

    def test_points_outside_the_image_are_refused_not_clamped(self) -> None:
        for x, y in ((640, 10), (10, 400), (-1, 5)):
            with self.assertRaises(AgentError) as ctx:
                self.agent._to_desktop(x, y, "f1")
            self.assertEqual(ctx.exception.code, "out_of_bounds")

    def test_unknown_frame_and_stale_frames_are_refused(self) -> None:
        with self.assertRaises(AgentError) as ctx:
            self.agent._to_desktop(1, 1, "nope")
        self.assertEqual(ctx.exception.code, "unknown_frame")
        resized = Monitor("HEADLESS-2", 0, 0, 1920, 1080, 1.0, True)
        with patch.object(agent_mod.cap, "monitors", return_value=[resized]):
            with self.assertRaises(AgentError) as ctx:
                self.agent._to_desktop(1, 1, "f1")
        self.assertEqual(ctx.exception.code, "stale_frame")
        with patch.object(agent_mod, "load_meta", return_value={"systemd_scope_unit": "x", "leader_start_time": 1}):
            with self.assertRaises(AgentError) as ctx:
                self.agent._to_desktop(1, 1, "f1")
        self.assertEqual(ctx.exception.code, "stale_frame")

    def test_focus_flag_change_does_not_invalidate_a_frame(self) -> None:
        unfocused = Monitor("HEADLESS-2", 0, 0, 1280, 800, 1.0, False)
        with patch.object(agent_mod.cap, "monitors", return_value=[unfocused]):
            self.assertEqual(self.agent._to_desktop(10, 10, "f1"), (20, 20))

    def test_desktop_coordinates_must_land_on_a_monitor(self) -> None:
        self.assertEqual(self.agent._to_desktop(1279, 799, None), (1279, 799))
        with self.assertRaises(AgentError) as ctx:
            self.agent._to_desktop(1280, 10, None)
        self.assertEqual(ctx.exception.code, "out_of_bounds")

    def test_frame_registry_is_bounded(self) -> None:
        with patch.object(self.agent, "ensure_ready"), \
             patch.object(agent_mod.cap, "capture", side_effect=lambda *a, **k: half_frame(os.urandom(4).hex())):
            for _ in range(agent_mod.MAX_FRAMES + 5):
                self.agent.screenshot()
        self.assertEqual(len(self.agent._frames), agent_mod.MAX_FRAMES)

    def test_pointer_uses_mapped_coordinates_for_click_and_drag(self) -> None:
        with patch.object(self.agent, "ensure_ready"), \
             patch.object(agent_mod.vinput, "click") as click, \
             patch.object(agent_mod.vinput, "drag") as drag:
            self.agent.pointer("double_click", 100, 50, frame_id="f1")
            self.agent.pointer("drag", 0, 0, frame_id="f1", x2=320, y2=200)
        self.assertEqual(click.call_args.args[1:], (200, 100, "left", 2))
        self.assertEqual(drag.call_args.args[1:], (0, 0, 640, 400, "left"))


class LifecycleTests(unittest.TestCase):
    def test_explicitly_stopped_realm_is_not_restarted(self) -> None:
        agent = make_agent()
        with patch.object(agent, "lifecycle", return_value={"state": "stopped", "alive": False}), \
             patch.object(agent, "start") as start:
            with self.assertRaises(AgentError) as ctx:
                agent.ensure_ready()
        self.assertEqual(ctx.exception.code, "realm_stopped")
        start.assert_not_called()

    def test_absent_realm_autostarts_only_when_profile_allows(self) -> None:
        agent = make_agent()
        with patch.object(agent, "lifecycle", return_value={"state": "absent", "alive": False}), \
             patch.object(agent, "start", return_value={"state": "running"}) as start:
            agent.ensure_ready()
        start.assert_called_once()
        manual = make_agent(autostart=False)
        with patch.object(manual, "lifecycle", return_value={"state": "absent", "alive": False}):
            with self.assertRaises(AgentError) as ctx:
                manual.ensure_ready()
        self.assertEqual(ctx.exception.code, "realm_absent")

    def test_healthy_realm_is_reused_without_a_second_start(self) -> None:
        calls = []
        agent = RealmAgent(profiles.Profile("claude", "claude", FULL), start_fn=lambda *a, **k: calls.append(a))
        with patch.object(agent, "lifecycle", return_value={"state": "running", "alive": True}):
            self.assertTrue(agent.start()["reused"])
        self.assertEqual(calls, [])

    def test_concurrent_start_by_another_client_is_reused(self) -> None:
        def racing_start(*_a, **_k):
            raise RealmError("la sesión 'claude' ya está activa")
        agent = RealmAgent(profiles.Profile("claude", "claude", FULL), start_fn=racing_start)
        states = iter([{"state": "absent", "alive": False}, {"state": "running", "alive": True}])
        with patch.object(agent, "lifecycle", side_effect=lambda: next(states)):
            self.assertTrue(agent.start()["reused"])
        self.assertFalse(agent.started_here)

    def test_crashed_realm_is_recovered_before_start(self) -> None:
        started = []
        agent = RealmAgent(profiles.Profile("claude", "claude", FULL, lifecycle="ephemeral",
                                            start={"width": 1024}),
                           start_fn=lambda name, **kw: started.append((name, kw)))
        states = iter([{"state": "stale", "alive": False}, {"state": "running", "alive": True}])
        with patch.object(agent, "lifecycle", side_effect=lambda: next(states)), \
             patch.object(agent_mod.runtime, "recover") as recover:
            self.assertFalse(agent.start()["reused"])
        recover.assert_called_once_with("claude")
        self.assertEqual(started, [("claude", {"ephemeral": True, "width": 1024})])
        self.assertTrue(agent.started_here)

    def test_alive_but_degraded_realm_is_not_started_twice(self) -> None:
        agent = make_agent()
        with patch.object(agent, "lifecycle", return_value={"state": "degraded", "alive": True}):
            with self.assertRaises(AgentError) as ctx:
                agent.start()
        self.assertEqual(ctx.exception.code, "realm_degraded")

    def test_capabilities_are_enforced(self) -> None:
        viewer = make_agent({Capability.OBSERVE})
        viewer.require(Capability.OBSERVE)
        for needed in (Capability.CONTROL, Capability.ADMIN):
            with self.assertRaises(AgentError) as ctx:
                viewer.require(needed)
            self.assertEqual(ctx.exception.code, "forbidden")


class WindowAndAppTests(unittest.TestCase):
    def _agent_with_window(self, config_format: str) -> RealmAgent:
        agent = make_agent()
        agent.windows = lambda: {"windows": [{"address": "0xabc"}]}  # type: ignore[method-assign]
        agent.lifecycle = lambda: {"state": "running", "config_format": config_format}  # type: ignore
        return agent

    def test_window_dispatch_matches_config_language(self) -> None:
        ok = subprocess.CompletedProcess([], 0, "ok", "")
        for config, focus, close in (
                ("hyprlang", ["dispatch", "focuswindow", "address:0xabc"],
                 ["dispatch", "closewindow", "address:0xabc"]),
                ("lua", ["dispatch", 'hl.dsp.focus({ window = "address:0xabc" })'],
                 ["dispatch", 'hl.dsp.window.close({ window = "address:0xabc" })'])):
            agent = self._agent_with_window(config)
            with patch.object(agent_mod.runtime, "private_call", return_value=ok) as call, \
                 patch.object(agent, "_active_address", return_value="0xabc"):
                self.assertTrue(agent.focus_window("0xabc")["focused"])
                agent.close_window("0xabc")
            self.assertEqual([c.args[1] for c in call.call_args_list], [focus, close])

    def test_window_addresses_are_validated_and_must_exist(self) -> None:
        agent = self._agent_with_window("lua")
        with patch.object(agent_mod.runtime, "private_call") as call:
            for bad in ('0xabc" }) hl.dsp.exec_cmd("x', "abc", "0xABC"):
                with self.assertRaises(AgentError) as ctx:
                    agent.focus_window(bad)
                self.assertEqual(ctx.exception.code, "invalid_argument")
            with self.assertRaises(AgentError) as ctx:
                agent.close_window("0xdef")
            self.assertEqual(ctx.exception.code, "not_found")
        call.assert_not_called()

    def test_launch_validates_argv_and_returns_app_id(self) -> None:
        agent = make_agent()
        with patch.object(agent, "ensure_ready"), \
             patch.object(agent_mod.runtime, "run", return_value={"pid": 4321}) as run:
            for bad in ([], [""], ["a\0b"], ["x"] * 65):
                with self.assertRaises(AgentError):
                    agent.launch(bad)
            self.assertEqual(agent.launch(["kitty"])["app_id"], 4321)
            self.assertIsNone(agent.launch(["kitty"], compositor_child=True)["app_id"])
        self.assertEqual(run.call_args_list[0].kwargs, {"detach": True, "compositor_child": False})

    def test_backend_errors_are_classified(self) -> None:
        self.assertEqual(agent_mod.classify(RealmError("x")).code, "backend_error")
        self.assertEqual(agent_mod.classify(subprocess.TimeoutExpired(["grim"], 5)).code, "backend_timeout")
        self.assertEqual(agent_mod.classify(KeyError("secret")).as_dict()["error"]["message"], "KeyError")


class ProfileFileTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.dir = Path(self.tmp.name) / "cortetsu-agent-realms"
        self.dir.mkdir(mode=0o700)
        self.path = self.dir / "profiles.json"

    def tearDown(self) -> None:
        self.tmp.cleanup()

    def write(self, data: object, mode: int = 0o600) -> None:
        self.path.write_text(json.dumps(data))
        self.path.chmod(mode)

    def test_valid_profiles_load(self) -> None:
        self.write({"schema": 1, "profiles": {
            "claude": {"realm": "claude", "capabilities": ["observe", "control", "admin"]},
            "codex": {"realm": "codex", "capabilities": ["observe"], "lifecycle": "ephemeral",
                      "start": {"width": 1024, "lua": True}}}})
        loaded = profiles.load_all(self.path)
        self.assertEqual(loaded["codex"].capabilities, {Capability.OBSERVE})
        self.assertEqual(loaded["codex"].start, {"width": 1024, "lua": True})

    def test_insecure_or_malformed_profile_files_are_refused(self) -> None:
        good = {"schema": 1, "profiles": {"claude": {"realm": "claude"}}}
        bad_documents = [
            {"schema": 2, "profiles": {}},
            {"schema": 1, "profiles": {"claude": {"realm": "../host"}}},
            {"schema": 1, "profiles": {"claude": {"realm": "claude", "capabilities": ["root"]}}},
            {"schema": 1, "profiles": {"claude": {"realm": "claude", "command": "sh"}}},
            {"schema": 1, "profiles": {"claude": {"realm": "claude", "start": {"compositor": "/tmp/x"}}}},
            {"schema": 1, "profiles": {"claude": {"realm": "claude", "start": {"width": "1e9"}}}},
            {"schema": 1, "profiles": {"a": {"realm": "x"}, "b": {"realm": "x"}}},
        ]
        for document in bad_documents:
            self.write(document)
            with self.assertRaises(RealmError, msg=document):
                profiles.load_all(self.path)
        self.write(good, mode=0o620)
        with self.assertRaisesRegex(RealmError, "sin escritura"):
            profiles.load_all(self.path)
        self.path.unlink()
        target = Path(self.tmp.name) / "elsewhere.json"
        target.write_text(json.dumps(good))
        target.chmod(0o600)
        self.path.symlink_to(target)
        with self.assertRaisesRegex(RealmError, "symlink"):
            profiles.load_all(self.path)
        self.path.unlink()
        self.write(good)
        self.dir.chmod(0o777)
        try:
            with self.assertRaisesRegex(RealmError, "directorio propio"):
                profiles.load_all(self.path)
        finally:
            self.dir.chmod(0o700)

    def test_save_keeps_other_profiles_and_refuses_shared_realms(self) -> None:
        profiles.save_profile("claude", {"realm": "claude"}, self.path)
        profiles.save_profile("codex", {"realm": "codex"}, self.path)
        with self.assertRaisesRegex(RealmError, "ya pertenece"):
            profiles.save_profile("intruder", {"realm": "claude"}, self.path)
        self.assertEqual(set(profiles.load_all(self.path)), {"claude", "codex"})
        self.assertEqual(self.path.stat().st_mode & 0o777, 0o600)
        self.assertTrue(profiles.remove_profile("codex", self.path))
        self.assertEqual(set(profiles.load_all(self.path)), {"claude"})


if __name__ == "__main__":
    unittest.main()

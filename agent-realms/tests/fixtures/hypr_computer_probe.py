#!/usr/bin/env python3
"""Run the reviewed hypr-computer HEAD entirely inside an agent-realm session."""

from __future__ import annotations

import json
import io
import os
import subprocess
import sys
import time
from pathlib import Path

from PIL import Image, ImageChops


sys.path.insert(0, "/workspace/src")

from hypr_computer import agentdesk, hypr, screen, target
from hypr_computer.agentinput import AgentInput
from hypr_computer.target import Target
from hypr_computer.wlvirt import Connection, ScreenCopy


def private_instances() -> list[dict[str, object]]:
    root = Path(os.environ["XDG_RUNTIME_DIR"]) / "hypr"
    instances = []
    for lock in root.glob("*/hyprland.lock"):
        try:
            pid_text, socket_name = lock.read_text().splitlines()[:2]
            instance = lock.parent.name
            timestamp = int(instance.split("_", 2)[1])
            instances.append({"instance": instance, "time": timestamp,
                              "pid": int(pid_text), "wl_socket": socket_name})
        except (OSError, ValueError, IndexError):
            continue
    return instances


def wait_for(predicate, timeout: float = 8, interval: float = 0.05) -> bool:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if predicate():
            return True
        time.sleep(interval)
    return False


def events(path: Path) -> list[dict[str, object]]:
    if not path.exists():
        return []
    rows = []
    for line in path.read_text().splitlines():
        try:
            rows.append(json.loads(line))
        except json.JSONDecodeError:
            continue
    return rows


def capture_image(env: dict[str, str]) -> Image.Image:
    captured = subprocess.run(["/usr/bin/grim", "-t", "png", "-"], env=env,
                              capture_output=True, timeout=15, check=True)
    return Image.open(io.BytesIO(captured.stdout)).convert("RGB")


def changed_pixel_fraction(a: Image.Image, b: Image.Image) -> float:
    if a.size != b.size:
        return 1.0
    diff = ImageChops.difference(a, b).convert("L").tobytes()
    return sum(value > 8 for value in diff) / len(diff)


def changed_byte_fraction(a: bytes, b: bytes) -> float:
    if len(a) != len(b):
        return 1.0
    return sum(left != right for left, right in zip(a, b)) / len(a)


def frame_clock_source() -> str:
    return '''import gi, time
gi.require_version("Gtk", "4.0")
from gi.repository import Gtk, GLib
app = Gtk.Application(application_id="dev.cortetsu.agentrealm.frameclock")
def activate(app):
    window = Gtk.ApplicationWindow(application=app, title="Nested frame clock")
    label = Gtk.Label(label="starting")
    window.set_child(label)
    window.present()
    def tick():
        label.set_text(f"FRAME {time.monotonic_ns()}")
        return GLib.SOURCE_CONTINUE
    GLib.timeout_add(100, tick)
app.connect("activate", activate)
app.run(None)
'''


def main() -> int:
    # Preserve the enclosing realm's endpoints before target.activate switches
    # hypr-computer's implicit IPC target to the nested compositor.
    host_env = os.environ.copy()
    host_sig = os.environ["HYPRLAND_INSTANCE_SIGNATURE"]
    host_wayland = os.environ["WAYLAND_DISPLAY"]
    host_runtime = os.environ["XDG_RUNTIME_DIR"]
    if not host_sig or not host_wayland.startswith("wayland-"):
        raise RuntimeError("the test requires the enclosing realm's explicit IPC and Wayland endpoints")

    agentdesk._instances = private_instances
    home = Path.home()
    log_path = home / "hypr-computer-events.jsonl"
    clock_path = home / "hypr-computer-frame-clock.py"
    app_log = (home / "hypr-computer-testapp.log").open("w")
    clock_log = (home / "hypr-computer-clock.log").open("w")
    viewer_log = (home / "hypr-computer-viewer.log").open("w")
    log_path.unlink(missing_ok=True)
    clock_path.write_text(frame_clock_source())

    desk = None
    app = None
    clock = None
    viewer = None
    agent_input = None
    result: dict[str, object] = {
        "project_head": "cd00962d7faf3a5059827994fbe746783695787f",
        "parent_signature": host_sig,
        "parent_wayland": host_wayland,
        "instance_discovery": "private XDG_RUNTIME_DIR hyprland.lock files; no ambient hyprctl instances call",
    }
    try:
        desk, note = agentdesk.start(name="agent-realm-hypr-computer-probe", width=1024, height=768,
                                     viewer="none", host_sig=host_sig, host_wayland=host_wayland)
        result.update({"nested_signature": desk.sig, "nested_wayland": desk.wl_socket,
                       "nested_pid": desk.pid, "start_note": note})
        target.activate(Target("agent", desk.name, desk.wl_socket, desk.sig, desk.dbus))
        result["parent_socket_matches_signature"] = hypr._socket_path(host_sig).endswith(
            f"/hypr/{host_sig}/.socket.sock")
        result["nested_socket_matches_signature"] = hypr._socket_path(desk.sig).endswith(
            f"/hypr/{desk.sig}/.socket.sock")

        app_env = desk.env
        app = subprocess.Popen(["/usr/bin/python", "/workspace/tests/testapp.py", str(log_path)],
                               stdin=subprocess.DEVNULL, stdout=app_log,
                               stderr=subprocess.STDOUT, env=app_env, close_fds=True)
        if not wait_for(lambda: any(e.get("ev") == "ready" for e in events(log_path))):
            raise RuntimeError("hypr-computer GTK test app did not start")
        clients: list[dict[str, object]] = []
        def find_test_window() -> bool:
            clients[:] = [c for c in hypr.query("clients", inst=desk.sig)
                          if "hypr-computer test" in str(c.get("title", ""))]
            return bool(clients)
        if not wait_for(find_test_window):
            raise RuntimeError(f"hypr-computer test window did not map: {hypr.query('clients', inst=desk.sig)}; "
                               f"testapp log: {(home / 'hypr-computer-testapp.log').read_text()}")
        client = clients[0]
        result["nested_monitor_geometry"] = hypr.query("monitors", inst=desk.sig)
        result["test_window"] = {"at": client["at"], "size": client["size"],
                                 "title": client["title"]}
        address = client["address"]
        hypr.request(f"dispatch focuswindow address:{address}", inst=desk.sig)
        agent_input = AgentInput(desk.wl_socket, app_env, "us", "", (0, 0, desk.width, desk.height))
        # Bind the reference implementation's own virtual pointer before asking
        # the compositor for current wl_seat capabilities.
        agent_input.ptr
        wayland_info = subprocess.run(["/usr/bin/wayland-info"], env=desk.env,
                                      capture_output=True, text=True, timeout=10).stdout
        seat_lines = []
        in_seat = False
        for line in wayland_info.splitlines():
            if "interface: 'wl_seat'" in line:
                in_seat = True
            elif in_seat and line.startswith("interface:"):
                break
            if in_seat:
                seat_lines.append(line.strip())
        result["seat_info"] = " | ".join(seat_lines)
        screen.grab(output="AGENT-1").save(home / "hypr-computer-before-input.png")

        x, y = client["at"]
        # A single window fills the headless output, making these points relative
        # to the reference GTK fixture rather than a neighboring test window.
        # Hyprland's first-run update dialog can cover the fixture's scroll list;
        # this click dismisses its lower-right Thanks button when it is present.
        agent_input.move_to(x + 964, y + 518, duration=0)
        agent_input.click()
        time.sleep(0.2)
        screen.grab(output="AGENT-1").save(home / "hypr-computer-after-update-dialog.png")
        agent_input.move_to(x + 180, y + 25, duration=0)
        cursor_after_move = hypr.query("cursorpos", inst=desk.sig)
        agent_input.click()
        typed = "HYPR_COMPUTER_PRIVATE_INPUT"
        agent_input.type_text(typed, delay=0.02)
        keyboard_exact = wait_for(lambda: any(e.get("ev") == "entry" and e.get("text") == typed
                                               for e in events(log_path)), timeout=5)
        agent_input.press_combo("Return")
        agent_input.move_to(x + 180, y + 180, duration=0)
        cursor_over_pad = hypr.query("cursorpos", inst=desk.sig)
        agent_input.click()
        click_observed = wait_for(lambda: any(e.get("ev") == "press" for e in events(log_path)), timeout=3)
        after_click_events = events(log_path)
        agent_input.move_to(x + 180, y + 180, duration=0)
        agent_input.button("left", True)
        agent_input.move_to(x + 240, y + 230, duration=0.3, steps=8)
        agent_input.button("left", False)
        drag_observed = wait_for(lambda: any(e.get("ev") == "drag-end" for e in events(log_path)), timeout=3)
        after_drag_events = events(log_path)
        scroll_attempts = []
        for label, sx, sy in (("list", x + 200, y + 350), ("pad", x + 180, y + 180)):
            agent_input.move_to(sx, sy, duration=0.15)
            time.sleep(0.15)
            cursor_at_scroll = hypr.query("cursorpos", inst=desk.sig)
            before_scroll_count = len(events(log_path))
            agent_input.scroll(dy=2)
            scroll_seen = wait_for(
                lambda: any(e.get("ev") in {"scroll", "list-scroll"}
                            for e in events(log_path)[before_scroll_count:]), timeout=3)
            scroll_attempts.append({"target": label, "cursor": cursor_at_scroll, "observed": scroll_seen})
            if scroll_seen:
                break
        time.sleep(0.2)
        screen.grab(output="AGENT-1").save(home / "hypr-computer-after-input.png")
        input_events = events(log_path)
        result["cursor_after_move"] = cursor_after_move
        result["cursor_over_pad"] = cursor_over_pad
        result["scroll_attempts"] = scroll_attempts
        result["input_observed"] = {
            "ready": any(e.get("ev") == "ready" for e in input_events),
            "typed_exact": keyboard_exact,
            "click": click_observed and any(e.get("ev") == "press" for e in after_click_events),
            "drag": drag_observed and any(e.get("ev") == "drag-end" for e in after_drag_events),
            "scroll": any(attempt["observed"] for attempt in scroll_attempts),
            "event_count": len(input_events),
            "event_types": sorted({str(e.get("ev")) for e in input_events}),
            "latest_entry": next((e.get("text") for e in reversed(input_events) if e.get("ev") == "entry"), None),
            "pointer_events": [e for e in input_events if e.get("ev") in {"press", "release", "drag-begin",
                                                                             "drag-end", "scroll", "list-scroll"}],
        }

        # Add a changing graphical client only after input coordinates are tested.
        clock = subprocess.Popen(["/usr/bin/python", str(clock_path)], stdin=subprocess.DEVNULL,
                                 stdout=clock_log, stderr=subprocess.STDOUT,
                                 env=app_env, close_fds=True)
        if not wait_for(lambda: any("Nested frame clock" in str(c.get("title", ""))
                                   for c in hypr.query("clients", inst=desk.sig))):
            raise RuntimeError("the changing GTK frame clock did not map")
        time.sleep(0.4)
        frame_a = screen.grab(output="AGENT-1")
        time.sleep(0.5)
        frame_b = screen.grab(output="AGENT-1")
        frame_a.save(home / "hypr-computer-frame-a.png")
        frame_b.save(home / "hypr-computer-frame-b.png")
        result["frame_a_size"] = frame_a.size
        result["frame_b_size"] = frame_b.size
        result["moving_frames_differ"] = screen.changed_fraction(frame_a, frame_b)

        # Compare the reference viewer's exact Wayland screencopy protocol with
        # the GTK viewer presentation. This separates compositor capture from UI redraw.
        copy_conn = Connection(desk.wl_socket)
        reused_buffer_frames = []
        reused_buffer_error = None
        try:
            screen_copy = ScreenCopy(copy_conn)
            for i in range(6):
                if i:
                    time.sleep(0.5)
                copied = screen_copy.capture(with_damage=bool(i), timeout=10)
                reused_buffer_frames.append(copied[0] if copied else b"")
        except Exception as exc:
            reused_buffer_error = repr(exc)
        finally:
            copy_conn.close()
        result["screencopy_frame_sample"] = {
            "reused_buffer": {
                "capture_count": len(reused_buffer_frames),
                "byte_lengths": [len(frame) for frame in reused_buffer_frames],
                "adjacent_changed_fraction": [changed_byte_fraction(a, b)
                                               for a, b in zip(reused_buffer_frames,
                                                               reused_buffer_frames[1:])],
            }
        }
        if reused_buffer_error:
            result["screencopy_frame_sample"]["reused_buffer_error"] = reused_buffer_error
        fresh_buffer_frames = []
        try:
            for i in range(6):
                if i:
                    time.sleep(0.5)
                fresh_conn = Connection(desk.wl_socket)
                try:
                    fresh_copy = ScreenCopy(fresh_conn)
                    copied = fresh_copy.capture(with_damage=False, timeout=10)
                    fresh_buffer_frames.append(copied[0] if copied else b"")
                finally:
                    fresh_conn.close()
            result.setdefault("screencopy_frame_sample", {})["fresh_buffer"] = {
                "capture_count": len(fresh_buffer_frames),
                "byte_lengths": [len(frame) for frame in fresh_buffer_frames],
                "adjacent_changed_fraction": [changed_byte_fraction(a, b)
                                               for a, b in zip(fresh_buffer_frames, fresh_buffer_frames[1:])],
            }
        except Exception as exc:
            result.setdefault("screencopy_frame_sample", {})["fresh_buffer_error"] = repr(exc)

        (home / "hypr-computer-probe-results.json").write_text(json.dumps(result, indent=2) + "\n")

        nested_focus_before_viewer = hypr.query("activewindow", inst=desk.sig) or {}
        # The upstream viewer's close handler stops the desk; both it and the desk
        # remain confined to this realm during this negative contract check.
        viewer_env = host_env.copy()
        viewer_env["WAYLAND_DISPLAY"] = host_wayland
        viewer_env["HYPRLAND_INSTANCE_SIGNATURE"] = host_sig
        viewer_env["XDG_RUNTIME_DIR"] = host_runtime
        viewer_env["PYTHONPATH"] = "/workspace/src"
        viewer = subprocess.Popen(["/workspace/.venv/bin/python", "-m", "hypr_computer.viewer", desk.name],
                                  stdin=subprocess.DEVNULL, stdout=viewer_log,
                                  stderr=subprocess.STDOUT, env=viewer_env, cwd="/workspace", close_fds=True)
        viewer_client = None
        def find_viewer_window() -> bool:
            nonlocal viewer_client
            clients = hypr.query("clients", inst=host_sig)
            viewer_client = next((c for c in clients if c.get("pid") == viewer.pid or
                                  "Agent desktop" in str(c.get("title", ""))), None)
            return viewer_client is not None
        if not wait_for(find_viewer_window):
            raise RuntimeError(f"hypr-computer viewer did not map into the private parent realm; "
                               f"exit={viewer.poll()} clients={hypr.query('clients', inst=host_sig)} "
                               f"log={(home / 'hypr-computer-viewer.log').read_text()}")
        hypr.request(f"dispatch focuswindow address:{viewer_client['address']}", inst=host_sig)
        parent_active = hypr.query("activewindow", inst=host_sig) or {}
        nested_active = hypr.query("activewindow", inst=desk.sig) or {}
        result["focus_isolation"] = {
            "parent_active_title": parent_active.get("title"),
            "parent_active_address": parent_active.get("address"),
            "viewer_address": viewer_client.get("address"),
            "nested_focus_before_viewer_title": nested_focus_before_viewer.get("title"),
            "nested_focus_before_viewer_address": nested_focus_before_viewer.get("address"),
            "nested_active_title": nested_active.get("title"),
            "nested_active_address": nested_active.get("address"),
            "parent_active_is_viewer": parent_active.get("address") == viewer_client.get("address"),
            "nested_focus_unchanged_while_viewer_active":
                nested_focus_before_viewer.get("address") == nested_active.get("address"),
        }
        time.sleep(1.5)
        vx, vy = viewer_client["at"]
        vw, vh = viewer_client["size"]
        viewer_box = (vx, vy, vx + vw, vy + vh)
        viewer_crops = []
        viewer_images = []
        viewer_sample_started = time.monotonic()
        for i in range(6):
            if i:
                time.sleep(0.5)
            image = capture_image(viewer_env)
            viewer_images.append(image)
            viewer_crops.append(image.crop(viewer_box))
        viewer_images[0].save(home / "hypr-computer-viewer-open.png")
        viewer_images[-1].save(home / "hypr-computer-viewer-late.png")
        viewer_diffs = [changed_pixel_fraction(a, b) for a, b in zip(viewer_crops, viewer_crops[1:])]
        result["viewer_frame_sample"] = {
            "capture_count": len(viewer_images),
            "duration_seconds": round(time.monotonic() - viewer_sample_started, 3),
            "adjacent_changed_fraction": viewer_diffs,
            "all_adjacent_frames_changed": all(diff > 0 for diff in viewer_diffs),
        }
        # Ask the explicitly selected private parent compositor to close this
        # viewer. GTK receives the same close-request path as its titlebar button.
        hypr.request(f"dispatch closewindow address:{viewer_client['address']}", inst=host_sig)
        viewer.wait(timeout=12)
        result["viewer_exit_code"] = viewer.returncode
        wait_for(lambda: not desk.alive(), timeout=8)
        result["desk_alive_after_viewer_close"] = desk.alive()
        result["viewer_close_stops_desk"] = not desk.alive()
        result["probe_completed"] = True
        result["acceptance_checks"] = {
            "nested_hyprland_started": bool(desk.pid and result.get("nested_monitor_geometry")),
            "parent_and_nested_sockets_match_their_signatures":
                result["parent_socket_matches_signature"] and result["nested_socket_matches_signature"],
            "nested_cursor_and_pointer_seat_observed": bool(result.get("cursor_after_move")) and
                "capabilities: pointer" in result.get("seat_info", ""),
            "independent_graphical_app_mapped": "hypr-computer test" in result.get("test_window", {}).get("title", ""),
            "keyboard_click_drag_scroll_observed": all(result["input_observed"][key]
                                                        for key in ("typed_exact", "click", "drag", "scroll")),
            "nested_focus_isolated_from_viewer_focus":
                result["focus_isolation"]["parent_active_is_viewer"] and
                result["focus_isolation"]["nested_focus_unchanged_while_viewer_active"],
            "direct_screencopy_frames_changed": result.get("screencopy_frame_sample", {}).get(
                "reused_buffer", {}).get("adjacent_changed_fraction") and all(
                    diff > 0 for diff in result["screencopy_frame_sample"]["reused_buffer"][
                        "adjacent_changed_fraction"]),
            "viewer_frames_changed": result["viewer_frame_sample"]["all_adjacent_frames_changed"],
            "session_survived_viewer_close": result["desk_alive_after_viewer_close"],
        }
        result["acceptance_passed"] = all(result["acceptance_checks"].values())

        (home / "hypr-computer-probe-results.json").write_text(json.dumps(result, indent=2) + "\n")
        print(json.dumps(result, ensure_ascii=False))
        return 0 if result["acceptance_passed"] else 1
    finally:
        if agent_input is not None:
            agent_input.close()
        for proc in (app, clock, viewer):
            if proc is not None and proc.poll() is None:
                proc.terminate()
                try:
                    proc.wait(timeout=2)
                except subprocess.TimeoutExpired:
                    proc.kill()
                    proc.wait(timeout=2)
        if desk is not None:
            agentdesk.stop(desk)
        (home / "hypr-computer-probe-results.json").write_text(json.dumps(result, indent=2) + "\n")
        app_log.close()
        clock_log.close()
        viewer_log.close()


if __name__ == "__main__":
    raise SystemExit(main())

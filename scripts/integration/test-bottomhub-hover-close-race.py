#!/usr/bin/env python3
"""Re-entering the active attached popout cancels its in-flight close."""
from __future__ import annotations

import json
import os
from pathlib import Path
import sys
import tempfile
import time

sys.path.insert(0, str(Path(__file__).resolve().parent))
import launcher_harness as H  # noqa: E402


def popup_state(session: H.Session, monitor: str) -> dict:
    result = session.ipc("bottomHub", "inspect")
    assert result.returncode == 0, result.stderr
    states = json.loads(result.stdout)
    return next(state for state in states if state["screen"] == monitor)


def find_network_trigger(session: H.Session, monitor: str) -> tuple[int, int]:
    output = next(item for item in session.monitors() if item["name"] == monitor)
    scale = output["scale"]
    logical_width = round(output["width"] / scale)
    logical_height = round(output["height"] / scale)
    y = output["y"] + logical_height - 30
    # The status cluster is right aligned. Sweep its plausible horizontal band
    # in sub-icon steps, using the popup's reported mode as the hit-test result.
    for local_x in range(min(1200, logical_width - 1), max(0, logical_width - 480), -12):
        x = output["x"] + local_x
        session.move(x, y)
        time.sleep(0.14)
        state = popup_state(session, monitor)
        if state["popup"] == "network" and state["open"] and not state["closing"]:
            return x, y
    raise AssertionError(
        f"network hover target not found near its status-cluster position: "
        f"{popup_state(session, monitor)} output={output}"
    )


def main() -> int:
    if not os.environ.get("WAYLAND_DISPLAY"):
        print("SKIP: requiere una sesión Wayland para anidar Hyprland")
        return 0
    missing = H.missing_tools()
    if missing:
        print(f"SKIP: faltan {', '.join(missing)}")
        return 0

    old_path = os.environ["PATH"]
    with tempfile.TemporaryDirectory(prefix="cz-hover-race-", dir="/tmp") as tmp:
        session = H.Session(Path(tmp))
        # Hyprland probes PCI inventory at startup. A test-local no-op keeps
        # that unrelated probe from waking the laptop's runtime-suspended GPU.
        lspci = session.base / "bin/lspci"
        lspci.write_text("#!/bin/sh\nexit 0\n", encoding="utf-8")
        lspci.chmod(0o755)
        hypr_config = session.home / ".config/hypr/hyprland.lua"
        config = hypr_config.read_text(encoding="utf-8")
        scale_one = 'hl.monitor({ output = "HEADLESS-2", mode = "1280x720", position = "auto-right", scale = 1 })'
        scale_two = 'hl.monitor({ output = "HEADLESS-2", mode = "1280x720", position = "auto-right", scale = 1.25 })'
        assert scale_one in config, "nested test config no longer declares HEADLESS-2 at scale 1"
        hypr_config.write_text(config.replace(scale_one, scale_two, 1), encoding="utf-8")
        os.environ["PATH"] = f"{session.base / 'bin'}:{old_path}"
        try:
            session.start(outputs=3)
            session.start_client()
            first, second = session.headless()[:2]
            monitor = first
            session.focus_monitor(monitor)
            find_network_trigger(session, monitor)
            active = (session.hjson("activewindow") or {}).get("class")
            assert active == "cortetsu-probe", f"hover changed keyboard focus from the client: {active}"
            first_state = popup_state(session, monitor)
            output = next(item for item in session.monitors() if item["name"] == monitor)

            # Crossing the trigger-to-popup gap transfers hover ownership and
            # keeps the existing close grace from dismissing the surface.
            popup_point = (
                output["x"] + first_state["anchor"],
                output["y"] + first_state["tray"]["popupY"]
                + first_state["tray"]["popupHeight"] // 2,
            )
            session.move(*popup_point)
            time.sleep(0.35)
            inside = popup_state(session, monitor)
            assert inside["open"] and not inside["closing"], inside
            active = (session.hjson("activewindow") or {}).get("class")
            assert active == "cortetsu-probe", f"crossing into the popout changed keyboard focus: {active}"

            # Leaving the popup releases its hover ownership and closes on the
            # existing grace interval.
            session.move(100, 100)
            time.sleep(0.5)
            H.wait_for(lambda: not popup_state(session, monitor)["open"], "popup closes after pointer exit")
            # Clicking outside also leaves the hover island and lets its normal
            # grace complete; no recovery timer is needed.
            find_network_trigger(session, monitor)
            session.click(100, 100)
            time.sleep(0.5)
            H.wait_for(lambda: not popup_state(session, monitor)["open"], "outside click closes the popup")

            # A control opened on the second output takes ownership cleanly.
            H.wait_for(
                lambda: any(item["name"] == second and item["scale"] == 1.25 for item in session.monitors()),
                "second output changes to 1.25 scale",
            )
            # Cross straight from an open popup on the first output to the
            # second output's trigger: the first must not stay open.
            find_network_trigger(session, first)
            H.wait_for(lambda: popup_state(session, first)["open"], "first output popup open")
            session.focus_monitor(second)
            second_trigger = find_network_trigger(session, second)
            time.sleep(0.45)
            states = [popup_state(session, name) for name in (first, second)]
            assert states[1]["popup"] == "network" and states[1]["open"], states
            assert sum(bool(state["open"]) for state in states) == 1, states
            geometry = states[1]["tray"]
            assert geometry["popupY"] >= 0
            assert geometry["popupY"] + geometry["popupHeight"] <= geometry["screenHeight"], geometry
            monitor = second
            trigger = second_trigger

            session.move(100, 100)
            closed = session.ipc("bottomHub", "closeControl")
            assert closed.returncode == 0, closed.stderr
            closing = popup_state(session, monitor)
            assert closing["closing"] and closing["open"], closing

            outputs = session.monitors()
            layout_width = max(item["x"] + item["width"] for item in outputs)
            layout_height = max(item["y"] + item["height"] for item in outputs)
            reentered_at = time.monotonic()
            session.send(f"move {trigger[0]} {trigger[1]} {layout_width} {layout_height}")
            immediate = popup_state(session, monitor)
            observation_time = time.monotonic() - reentered_at
            assert observation_time < 0.10, (
                f"race observation inconclusive: sampled after {observation_time:.3f}s; "
                "the open dwell is 0.120s"
            )
            assert immediate["popup"] == "network" and immediate["open"] and not immediate["closing"], immediate
            time.sleep(0.25)
            settled = popup_state(session, monitor)
            assert settled["popup"] == "network" and settled["open"] and not settled["closing"], settled
        except BaseException:
            log_path = Path(tmp) / "logs/qs.log"
            log = log_path.read_text(errors="replace") if log_path.exists() else ""
            sys.stderr.write("\n".join(line for line in log.splitlines()
                                         if "WARN" in line or "ERROR" in line)[-3000:] + "\n")
            raise
        finally:
            try:
                session.stop()
            finally:
                os.environ["PATH"] = old_path

    print("PASS: re-entering the active attached popout cancels its close; one attached popup across outputs")
    return 0


if __name__ == "__main__":
    sys.exit(main())

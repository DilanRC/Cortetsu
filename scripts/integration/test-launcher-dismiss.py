#!/usr/bin/env python3
"""The launcher opens and closes with Super, Escape and the pointer.

Runs the composed Cortetsu shell in a nested Hyprland with the repository's
Lua keybinds, two outputs, a terminal client and a virtual keyboard/pointer
(see launcher_harness.py). Super goes through Hyprland's real SUPER_L release
bind and global-shortcut path. After every close the test types into the
terminal to prove the keyboard came back and nothing invisible holds it.

    python3 scripts/integration/test-launcher-dismiss.py [--cycles N]
    ONLY=other_monitor python3 scripts/integration/test-launcher-dismiss.py
"""
from __future__ import annotations

import argparse
import os
from pathlib import Path
import sys
import tempfile
import time

sys.path.insert(0, str(Path(__file__).resolve().parent))
import launcher_harness as H  # noqa: E402

SETTLE = 0.5


def settle() -> None:
    time.sleep(SETTLE)


class Contract:
    def __init__(self, session: H.Session, sink: Path):
        self.s = session
        self.sink = sink
        self.monitors = session.headless()
        self.home = self.monitors[0]
        self.typed = 0

    def states(self) -> dict[str, bool]:
        return self.s.launcher_states()

    def assert_closed_everywhere(self, label: str) -> None:
        states = self.states()
        assert not any(states.values()), f"{label}: launcher still open {states}"
        # The keyboard is back in the application: a key typed now reaches it.
        self.s.focus_monitor(self.home)
        before = self.sink.read_text()
        self.s.tap(H.KEY_A)
        try:
            H.wait_for(lambda: len(self.sink.read_text()) > len(before), f"{label}: key reached the client", timeout=3)
        except AssertionError as exc:
            window = (self.s.hjson("activewindow") or {}).get("class")
            raise AssertionError(f"{exc}; activewindow={window} focused={self.s.focused_monitor()} "
                                 f"states={self.states()}") from None
        self.typed += 1

    def open_on(self, monitor: str) -> None:
        self.s.focus_monitor(monitor)
        self.s.tap(H.KEY_LEFTMETA)
        settle()
        states = self.states()
        assert states[monitor] and sum(states.values()) == 1, f"Super did not open only on {monitor}: {states}"
        self.s.focus_monitor(monitor)
        # The search field has focus: typing filters without clicking first.
        self.s.tap(H.KEY_E)
        settle()

    def panel_point(self, monitor: str, dy: int = 0) -> tuple[int, int]:
        m = next(item for item in self.s.monitors() if item["name"] == monitor)
        return m["x"] + m["width"] // 2, m["y"] + m["height"] // 2 + dy

    def wiggle(self, monitor: str) -> None:
        x, y = self.panel_point(monitor)
        for step in range(12):
            self.s.move(x - 60 + step * 10, y - 30 + step * 5)
            time.sleep(0.03)

    # scenarios ---------------------------------------------------------
    def super_closes(self) -> None:
        self.open_on(self.home)
        self.s.tap(H.KEY_LEFTMETA)
        settle()
        self.assert_closed_everywhere("Super")

    def super_after_mouse(self) -> None:
        self.open_on(self.home)
        self.wiggle(self.home)
        self.s.tap(H.KEY_LEFTMETA)
        settle()
        self.assert_closed_everywhere("mouse + Super")

    def escape_after_mouse(self) -> None:
        self.open_on(self.home)
        self.wiggle(self.home)
        self.s.tap(H.KEY_ESC)
        settle()
        self.assert_closed_everywhere("mouse + Escape")

    def escape_after_typing(self) -> None:
        self.open_on(self.home)
        for key in (H.KEY_A, H.KEY_E, H.KEY_A):
            self.s.tap(key)
        self.s.tap(H.KEY_ESC)
        settle()
        self.assert_closed_everywhere("type + Escape")

    def escape_after_arrows(self) -> None:
        self.open_on(self.home)
        for key in (H.KEY_DOWN, H.KEY_RIGHT, H.KEY_RIGHT):
            self.s.tap(key)
        self.s.tap(H.KEY_ESC)
        settle()
        self.assert_closed_everywhere("arrows + Escape")

    def escape_after_result_interaction(self) -> None:
        self.open_on(self.home)
        x, y = self.panel_point(self.home, dy=40)
        self.s.move(x, y)                      # hover selects a result
        self.s.send(f"button {H.BTN_LEFT + 1} 1")  # right click: toggles a favourite, does not launch
        self.s.send(f"button {H.BTN_LEFT + 1} 0")
        settle()
        assert self.states()[self.home], "right click on a result closed the launcher"
        self.s.focus_monitor(self.home)
        self.s.tap(H.KEY_ESC)
        settle()
        self.assert_closed_everywhere("result interaction + Escape")

    def choosing_an_app_closes(self) -> None:
        before = self.s.launches.read_text() if self.s.launches.exists() else ""
        self.open_on(self.home)
        self.s.tap(H.KEY_ESC)  # clear the "e" filter path: reopen with an empty query
        settle()
        self.s.focus_monitor(self.home)
        self.s.tap(H.KEY_LEFTMETA)
        settle()
        self.s.click(*self.panel_point(self.home, dy=40))
        settle()
        H.wait_for(lambda: self.s.launches.exists() and self.s.launches.read_text() != before, "app launched", timeout=3)
        self.assert_closed_everywhere("choose app")

    def click_outside_closes(self) -> None:
        self.open_on(self.home)
        m = next(item for item in self.s.monitors() if item["name"] == self.home)
        self.s.click(m["x"] + 6, m["y"] + m["height"] - 6)
        settle()
        self.assert_closed_everywhere("click outside")

    def other_monitor(self) -> None:
        if len(self.monitors) < 2:
            return
        first, second = self.monitors[:2]
        # Open on one screen, move the pointer to the other: Super closes it
        # instead of moving it there.
        self.open_on(first)
        self.s.focus_monitor(second)
        self.s.tap(H.KEY_LEFTMETA)
        settle()
        self.assert_closed_everywhere("Super with the pointer on the other monitor")
        # Escape with the pointer on the other monitor.
        self.open_on(first)
        self.s.focus_monitor(second)
        self.s.tap(H.KEY_ESC)
        settle()
        self.assert_closed_everywhere("Escape with the pointer on the other monitor")
        # The IPC toggle used by scripts and BottomHub never leaves two open.
        self.open_on(first)
        self.s.focus_monitor(second)
        result = self.s.ipc("drawers", "toggle", "launcher")
        assert result.returncode == 0, result.stderr
        settle()
        self.assert_closed_everywhere("drawers toggle from the other monitor")
        # Opening on the second screen closes it on the first.
        self.open_on(first)
        self.s.focus_monitor(second)
        self.s.ipc("drawers", "toggle", "launcher")  # closes
        settle()
        self.open_on(second)
        states = self.states()
        assert [name for name, is_open in states.items() if is_open] == [second], states
        self.s.focus_monitor(second)
        self.s.tap(H.KEY_ESC)
        settle()
        self.assert_closed_everywhere("Escape on the second monitor")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--cycles", type=int, default=2)
    args = parser.parse_args()
    if not os.environ.get("WAYLAND_DISPLAY"):
        print("SKIP: requiere una sesión Wayland para anidar Hyprland")
        return 0
    missing = H.missing_tools() + ([] if H.shutil.which("kitty") else ["kitty"])
    if missing:
        print(f"SKIP: faltan {', '.join(missing)}")
        return 0
    with tempfile.TemporaryDirectory(prefix="czl", dir="/tmp") as tmp:
        session = H.Session(Path(tmp))
        try:
            session.start(outputs=3)
            session.focus_monitor(session.headless()[0])
            contract = Contract(session, session.start_client())
            session.tap(H.KEY_A)  # the client owns the keyboard before the first open
            H.wait_for(lambda: contract.sink.read_text(), "client focus", timeout=5)
            scenarios = [
                contract.super_closes, contract.super_after_mouse, contract.escape_after_mouse,
                contract.escape_after_typing, contract.escape_after_arrows,
                contract.escape_after_result_interaction, contract.click_outside_closes,
                contract.choosing_an_app_closes, contract.other_monitor,
            ]
            for cycle in range(args.cycles):
                for scenario in [s for s in scenarios if os.environ.get("ONLY", s.__name__) == s.__name__]:
                    try:
                        scenario()
                    except AssertionError as exc:
                        raise AssertionError(f"cycle {cycle + 1}, {scenario.__name__}: {exc}") from None
            # Rapid open/close cycles: no state may stick.
            session.focus_monitor(contract.home)
            for _ in range(10):
                session.tap(H.KEY_LEFTMETA)
                time.sleep(0.25)
                session.tap(H.KEY_LEFTMETA)
                time.sleep(0.25)
            settle()
            contract.assert_closed_everywhere("rapid cycles")
        except BaseException:
            log = (Path(tmp) / "logs/qs.log").read_text(errors="replace")
            sys.stderr.write("\n".join(line for line in log.splitlines() if "WARN" in line or "ERROR" in line)[-3000:] + "\n")
            raise
        finally:
            session.stop()
    print(f"PASS: launcher closes with Super, Escape and outside click in {args.cycles} cycles on two headless monitors; "
          f"keyboard returned to the application after every close ({contract.typed} checks)")
    return 0


if __name__ == "__main__":
    sys.exit(main())

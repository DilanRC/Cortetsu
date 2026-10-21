#!/usr/bin/env python3
"""Stabilization contracts (O-1, O-2, O-3, calendar), observed in nested Hyprland.

    ONLY=o2,o3 REPEAT=20 python3 scripts/integration/ws2_run.py --timeout 1800 OUT/s.log -- \
        python3 docs/migration/stabilization/tools/stab_contracts.py CHECKOUT OUT/stab.json

Builds on the F1a matrix (docs/migration/F1a/tools/nested_contracts.py), whose
O-2 and O-3 rows only recorded what happened. Here every row asserts the
contract, so the same script fails on main and passes on the fix. CHECKOUT is
the repository whose shell is composed; the harness comes from that checkout
and this tool from wherever it is run, so it can be pointed at main.

Scenarios (ONLY= selects, REPEAT= repeats the selection):
  o1        each retained surface, then each other one on the other screen
  o2        every path to the sidebar (IPC, SUPER+N, Bottom Hub IPC) over
            Hardware, on the same and the other screen; every transient panel
            over Hardware; OSD coexists; fullscreen blocks opening only
  o3        Wallpaper Manager, then the sidebar by each path: one result
  calendar  moves between screens, toggles, Escape, one sync per opening
  focus     the keyboard returns to the client after each transition
  bellfs    (ONLY=bellfs) fullscreen: a bell-spot click over Hardware does not
            open the sidebar; it leaves the client without the keyboard in
            this harness (also on 63bb651), so it runs last and on its own
  bell      a pointer click on the Bottom Hub bell through the retained scrim:
            one click opens the sidebar; elsewhere it only dismisses, on a
            panel it does nothing, over Overview it does nothing. BELL="x y"
            gives the point when the checkout has no `bottomHub
            notificationsButton` (main), so the same click runs there
"""
from __future__ import annotations

import json
import os
from pathlib import Path
import sys
import tempfile
import time

CHECKOUT = Path(sys.argv[1]).resolve()
OUT = Path(sys.argv[2]).resolve()
sys.path.insert(0, str(CHECKOUT / "scripts/integration"))
sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "F1a/tools"))
import launcher_harness as H  # noqa: E402
from f0_session import F0Session  # noqa: E402

# nested_contracts reads its argv at import time; it gets the same two paths.
import nested_contracts as F1a  # noqa: E402

KEY_N = 49
PANELS = ("launcher", "session", "dashboard", "utilities", "settings", "sidebar")


class Run(F1a.Run):
    def flags(self) -> dict[str, list[str]]:
        return self.open_flags()

    def toggle_sidebar(self, path: str) -> None:
        if path == "ipc":
            self.s.ipc("drawers", "toggle", "sidebar")
        elif path == "super+n":
            self.s.chord(H.KEY_LEFTMETA, KEY_N)
        elif path == "bottomhub":
            self.s.ipc("bottomHub", "notifications")
        time.sleep(0.4)

    def sync_calls(self) -> int:
        return sum(1 for line in self.sink_calls().splitlines() if line.startswith("cortetsu-calendar sync"))

    def sink_calls(self) -> str:
        return self.s.stub_calls.read_text(errors="replace")

    # O-1 -----------------------------------------------------------------
    def o1(self) -> None:
        for first in F1a.RETAINED:
            for second in F1a.RETAINED:
                if first == second:
                    continue
                self.reset()
                self.open(first, self.m1)
                self.open(second, self.m2)
                flags = self.flags()
                self.check("o1", f"{first} then {second}, other screen",
                           flags == {self.m1: [], self.m2: [F1a.RETAINED[second]]}, flags)

    # O-2 -----------------------------------------------------------------
    def o2(self) -> None:
        for path in ("ipc", "super+n", "bottomhub"):
            for where, monitor in (("same screen", self.m1), ("other screen", self.m2)):
                self.reset()
                self.open("hardware", self.m1)
                self.s.focus_monitor(monitor)
                self.toggle_sidebar(path)
                flags = self.flags()
                expected = {self.m1: [], self.m2: []}
                expected[monitor] = ["sidebar"]
                self.check("o2", f"hardware then sidebar by {path}, {where}", flags == expected, flags)
                self.s.focus_monitor(monitor)
                self.toggle_sidebar(path)
                flags = self.flags()
                self.check("o2", f"sidebar by {path} closes it again, {where}", flags == {self.m1: [], self.m2: []}, flags)
        for panel in PANELS:
            self.reset()
            self.open("hardware", self.m1)
            self.s.ipc("drawers", "toggle", panel)
            time.sleep(0.4)
            flags = self.flags()
            self.check("o2", f"hardware then drawers toggle {panel}", flags == {self.m1: [panel], self.m2: []}, flags)
            self.open("hardware", self.m1)
            flags = self.flags()
            self.check("o2", f"drawers toggle {panel} then hardware", flags == {self.m1: ["hardware"], self.m2: []}, flags)
        self.reset()
        self.open("hardware", self.m1)
        self.s.ipc("drawers", "toggle", "osd")
        time.sleep(0.3)
        flags = self.flags()
        self.check("o2", "osd coexists with hardware", flags == {self.m1: ["hardware", "osd"], self.m2: []}, flags)
        # Fullscreen on the client's screen: opening the sidebar there is ignored
        # by every path, closing is not.
        self.reset()
        self.s.focus_monitor(self.home)
        self.s.hyprctl("dispatch", 'hl.dsp.focus({ window = "class:cortetsu-probe" })')
        self.s.hyprctl("dispatch", 'hl.dsp.window.fullscreen({ mode = "fullscreen" })')
        time.sleep(0.6)
        for path in ("ipc", "super+n", "bottomhub"):
            self.s.focus_monitor(self.home)
            self.toggle_sidebar(path)
            self.s.focus_monitor(self.home)
            seen = self.s.ipc("drawers", "isOpen", "sidebar").stdout.strip()
            self.check("o2", f"fullscreen: sidebar by {path} does not open", seen == "0", seen)
            if seen == "1":
                self.s.ipc("drawers", "toggle", "sidebar")
        self.s.hyprctl("dispatch", 'hl.dsp.window.fullscreen({ mode = "fullscreen" })')
        time.sleep(0.4)

    # O-3 -----------------------------------------------------------------
    def o3(self) -> None:
        for path in ("ipc", "super+n", "bottomhub"):
            self.reset()
            self.open("wallpapermanager", self.m1)
            self.s.focus_monitor(self.m1)
            self.toggle_sidebar(path)
            time.sleep(0.4)  # a cleared focus grab closed the sidebar 20-40 ms after opening
            flags = self.flags()
            self.check("o3", f"wallpaper then sidebar by {path}", flags == {self.m1: ["sidebar"], self.m2: []}, flags)

    # Calendar ------------------------------------------------------------
    def calendar(self) -> None:
        self.reset()
        before = self.sync_calls()
        self.open("calendar", self.m1)
        time.sleep(0.5)
        self.check("calendar", "one sync per opening", self.sync_calls() - before == 1, self.sync_calls() - before)
        self.open("calendar", self.m2)
        flags = self.flags()
        self.check("calendar", "open on the other screen moves it", flags == {self.m1: [], self.m2: ["calendar"]}, flags)
        self.check("calendar", "it holds the keyboard there", not self.key_reaches_client(stay=self.m2), "")
        self.s.focus_monitor(self.m1)
        self.s.ipc("calendar", "toggle")
        time.sleep(0.3)
        flags = self.flags()
        self.check("calendar", "toggle from the other screen closes it", flags == {self.m1: [], self.m2: []}, flags)
        self.check("calendar", "keyboard back in the client after toggle", self.key_reaches_client(), "")
        self.open("calendar", self.m2)
        self.s.focus_monitor(self.m2)
        self.s.tap(H.KEY_ESC)
        self.check("calendar", "Escape closes it on its screen", self.wait(lambda: not self.is_open("calendar")),
                   self.flags())
        self.check("calendar", "keyboard back in the client after Escape", self.key_reaches_client(), "")
        before = self.sync_calls()
        for _ in range(5):
            self.open("calendar", self.m1)
            self.s.ipc("calendar", "close")
        time.sleep(0.5)
        self.check("calendar", "five openings, at most five syncs", self.sync_calls() - before <= 5,
                   self.sync_calls() - before)

    # Bottom Hub bell through the scrim (a pointer click, never IPC) ----------
    def bell_point(self, monitor: str | None = None) -> tuple[int, int]:
        self.s.focus_monitor(monitor or self.m1)
        self.s.ipc("bottomHub", "show")
        if os.environ.get("BELL"):
            x, y = os.environ["BELL"].split()
            return int(x), int(y)
        read = lambda: self.s.ipc("bottomHub", "notificationsButton").stdout.split()
        H.wait_for(lambda: read() and read() == (time.sleep(0.5) or read()), "bell geometry settled", timeout=10)
        x, y, w, h = map(float, read())
        return int(x + w / 2), int(y + h / 2)

    def sidebar_screens(self) -> list[str]:
        """Screens with the sidebar open, read without moving focus (flags() does)."""
        return [row["screen"] for row in json.loads(self.s.ipc("bottomHub", "inspect").stdout) if row["sidebar"]]

    def bell(self) -> None:
        point = self.bell_point()
        self.checks.append({"scenario": "bell", "check": "bell centre", "result": "INFO", "seen": point})
        closed = {self.m1: [], self.m2: []}
        sidebar = {self.m1: ["sidebar"], self.m2: []}
        self.reset()
        self.s.click(*point)
        self.check("bell", "nothing open: one click opens the sidebar", self.wait(lambda: self.flags() == sidebar),
                   self.flags())
        self.s.click(*point)
        self.check("bell", "nothing open: a second click closes it", self.wait(lambda: self.flags() == closed),
                   self.flags())
        # Observation, not a contract (main and 63bb651 behave the same): after
        # any path the sidebar's window holds the keyboard only on demand, so
        # Escape does not reach it until the sidebar is clicked.
        for label, action in (("a bell click, nothing open", lambda: self.s.click(*point)),
                              ("bottomHub notifications over hardware", lambda: self.toggle_sidebar("bottomhub")),
                              ("SUPER+N over hardware", lambda: self.toggle_sidebar("super+n"))):
            self.reset()
            if "hardware" in label:
                self.open("hardware", self.m1)
                self.s.focus_monitor(self.m1)
            action()
            time.sleep(0.6)
            opened = self.sidebar_screens() == [self.m1]
            self.s.tap(H.KEY_ESC)
            closes = opened and self.wait(lambda: self.flags() == closed, timeout=1.5)
            self.checks.append({"scenario": "bell", "check": f"observed: Escape closes the sidebar opened by {label}",
                                "result": "INFO", "seen": {"opened": opened, "escape_closes": closes}})
        for target in [t for t in F1a.RETAINED if t not in ("overview", "wallpapermanager")]:
            self.reset()
            self.open(target, self.m1)
            self.s.click(*point)
            time.sleep(0.6)  # O-3: a cleared focus grab closed the sidebar 20-40 ms after opening
            flags = self.flags()
            self.check("bell", f"{target}: one click on the bell leaves only the sidebar", flags == sidebar, flags)
            self.s.click(*point)
            self.check("bell", f"{target}: a second click closes it", self.wait(lambda: self.flags() == closed),
                       self.flags())
            self.check("bell", f"{target}: keyboard back in the client", self.key_reaches_client(), "")
        # Wallpaper's panel is min(height - 48, 760) tall: at 720p it covers
        # the bell, so the click belongs to the panel; at 1080p it does not.
        self.reset()
        self.open("wallpapermanager", self.m1)
        self.s.click(*point)
        time.sleep(0.6)
        self.check("bell", "wallpaper at 720p: its panel covers the bell and keeps the click",
                   self.flags() == {self.m1: ["wallpaperManager"], self.m2: []}, self.flags())
        monitor = next(m for m in self.s.monitors() if m["name"] == self.m1)
        self.reset()
        self.open("hardware", self.m1)
        self.s.click(monitor["x"] + 12, monitor["y"] + monitor["height"] // 2)
        time.sleep(0.5)
        self.check("bell", "hardware: a click elsewhere on the scrim only dismisses", self.flags() == closed,
                   self.flags())
        self.open("hardware", self.m1)
        self.s.click(monitor["x"] + monitor["width"] // 2, monitor["y"] + monitor["height"] // 2)
        time.sleep(0.5)
        self.check("bell", "hardware: a click on the panel keeps it open",
                   self.flags() == {self.m1: ["hardware"], self.m2: []}, self.flags())
        self.reset()
        self.open("overview", self.m1)
        self.s.click(*point)
        time.sleep(0.5)
        self.check("bell", "overview: the bell click does not open the sidebar",
                   "sidebar" not in self.flags()[self.m1], self.flags())
        self.reset()
        self.open("hardware", self.m1)
        self.s.ipc("drawers", "toggle", "osd")
        time.sleep(0.3)
        self.s.click(*point)
        time.sleep(0.6)
        flags = self.flags()
        self.check("bell", "hardware and OSD: the bell click leaves the sidebar (the OSD follows SUPER+N)",
                   "sidebar" in flags[self.m1] and "hardware" not in flags[self.m1], flags)
        self.reset()
        self.s.hyprctl("eval", f'hl.monitor({{ output = "{self.m1}", mode = "1920x1080", position = "auto-right", scale = 1 }})')
        time.sleep(1.0)
        big = self.bell_point()
        self.open("wallpapermanager", self.m1)
        self.s.click(*big)
        time.sleep(0.6)
        self.check("bell", f"wallpaper at 1080p: one click on the bell {big} leaves only the sidebar",
                   self.flags() == sidebar, self.flags())
        self.s.hyprctl("eval", f'hl.monitor({{ output = "{self.m1}", mode = "1280x720", position = "auto-right", scale = 1 }})')
        time.sleep(1.0)

    def bellfs(self) -> None:
        # Fullscreen on the client's screen: Hardware still opens (SUPER+H),
        # but the bell click must not open the sidebar over it.
        self.reset()
        home_bell = self.bell_point(self.home)
        self.s.hyprctl("dispatch", 'hl.dsp.focus({ window = "class:cortetsu-probe" })')
        self.s.hyprctl("dispatch", 'hl.dsp.window.fullscreen({ mode = "fullscreen" })')
        time.sleep(0.6)
        self.open("hardware", self.home)
        self.s.click(*home_bell)
        time.sleep(0.6)
        self.s.focus_monitor(self.home)
        seen = self.s.ipc("drawers", "isOpen", "sidebar").stdout.strip()
        self.check("bellfs", "fullscreen: a bell-spot click over Hardware does not open the sidebar", seen == "0", seen)
        if seen == "1":
            self.s.ipc("drawers", "toggle", "sidebar")
        self.s.ipc("hardware", "close")
        self.s.hyprctl("dispatch", 'hl.dsp.focus({ window = "class:cortetsu-probe" })')
        self.s.hyprctl("dispatch", 'hl.dsp.window.fullscreen({ mode = "fullscreen" })')
        time.sleep(0.4)
        probe = next((c for c in self.s.hjson("clients") or [] if c.get("class") == "cortetsu-probe"), {})
        # Leaving fullscreen leaves no window focused (main does the same);
        # focus the client as a click on it would.
        self.s.hyprctl("dispatch", 'hl.dsp.focus({ window = "class:cortetsu-probe" })')
        # Observation: here the key does not reach the client, also on
        # 63bb651 and without the click (harness, not the bell).
        self.checks.append({"scenario": "bellfs", "check": "observed: keyboard in the client after leaving fullscreen",
                            "result": "INFO", "seen": {"reaches": self.key_reaches_client(),
                                                       "fullscreen": probe.get("fullscreen"), "flags": self.flags()}})

    def focus(self) -> None:
        for path in ("ipc", "super+n"):
            self.reset()
            self.open("hardware", self.m1)
            self.toggle_sidebar(path)
            self.toggle_sidebar(path)
            self.check("focus", f"hardware, sidebar by {path}, closed: keyboard in the client",
                       self.key_reaches_client(), self.flags())
        self.reset()
        self.open("wallpapermanager", self.m1)
        self.s.ipc("wallpapermanager", "close")
        time.sleep(0.3)
        self.check("focus", "wallpaper closed: keyboard in the client", self.key_reaches_client(), self.flags())


def main() -> int:
    result = {"checkout": str(CHECKOUT), "date": time.strftime("%FT%T%z")}
    with tempfile.TemporaryDirectory(prefix="czf", dir="/tmp") as tmp:
        session = F0Session(Path(tmp))
        try:
            session.start(outputs=3)
            sink = session.start_client()
            # The shell runs its helpers from ~/.local/bin by absolute path;
            # point them at the logging stubs so a sync attempt is observable.
            local_bin = session.home / ".local/bin"
            local_bin.mkdir(parents=True, exist_ok=True)
            for helper in ("cortetsu-calendar", "cortetsu-pomodoro"):
                (local_bin / helper).symlink_to(session.base / "bin" / helper)
            run = Run(session, sink)
            result["monitors"] = {"client": run.home, "m1": run.m1, "m2": run.m2}
            warnings_before = len(F1a.qml_problems(session.logs / "qs.log"))
            scenarios = [run.o1, run.o2, run.o3, run.calendar, run.focus, run.bell]
            if os.environ.get("ONLY"):
                scenarios.append(run.bellfs)
            only = [name for name in os.environ.get("ONLY", "").split(",") if name]
            if only:
                scenarios = [s for s in scenarios if s.__name__ in only]
            for scenario in scenarios * int(os.environ.get("REPEAT", "1")):
                try:
                    scenario()
                except Exception as exc:  # recorded, the remaining scenarios still run
                    run.check(scenario.__name__, "scenario raised", False, repr(exc)[:300])
            run.reset()
            flags = run.flags()
            run.check("final", "every flag closed on every screen", flags == {run.m1: [], run.m2: []}, flags)
            run.check("final", "keyboard in the client", run.key_reaches_client(), "")
            result["checks"] = run.checks
            problems = F1a.qml_problems(session.logs / "qs.log")
            result["qml_warnings_startup"] = problems[:warnings_before]
            result["qml_warnings_during_run"] = problems[warnings_before:]
            (OUT.parent / f"{OUT.stem}-qs.log").write_text((session.logs / "qs.log").read_text(errors="replace"))
        finally:
            session.stop()
            result["leftover_pids"] = session.sweep()
            result["runtime_dir_removed"] = not session.runtime.exists()
    OUT.write_text(json.dumps(result, indent=1, ensure_ascii=False))
    fails = [c for c in result.get("checks", []) if c["result"] == "FAIL"]
    print(f"{len(result.get('checks', []))} checks, {len(fails)} FAIL")
    for c in fails:
        print("FAIL", c["scenario"], c["check"], json.dumps(c["seen"], ensure_ascii=False)[:200])
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())

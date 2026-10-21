#!/usr/bin/env python3
"""Physical multimonitor QA of the stabilization contracts on the real session.

    YDOTOOL_SOCKET=/run/user/1000/<sock> python3 physical_qa.py SHELL_DIR OUT.json [scenario,...]

Same contracts as stab_contracts.py (O-1, O-2, O-3, calendar, focus), driven on
the real Hyprland with two physical monitors instead of the nested harness:
- the shell is the one at SHELL_DIR (`qs ipc -p`);
- keys come from ydotool (a uinput keyboard, the same path as a real key);
- keyboard ownership is observed by typing `a` and checking whether it reaches
  a sink terminal (class cortetsu-qa-sink-<monitor>) on that monitor's sink
  workspace. A key is only typed when the focused window is a sink, so no key
  ever lands in a personal window.

Scenarios: a1 (calendar exclusivity), a2 (exclusivity across surfaces),
a3 (sidebar paths over Hardware/Wallpaper, REPEAT_O3 times), a4 (fullscreen),
b1 (one physical click on the Bottom Hub bell through the retained scrim;
clicks are uinput button events from ydotool at the bell that the shell
reports through `bottomHub notificationsButton`).
"""
from __future__ import annotations

import json
import os
import subprocess
import sys
import time
from pathlib import Path

SHELL = sys.argv[1]
OUT = Path(sys.argv[2])
ONLY = sys.argv[3].split(",") if len(sys.argv) > 3 else ["a1", "a2", "a3", "a4"]
SINK_DIR = OUT.parent / "sinks"
HYPRCTL = "/usr/bin/hyprctl"

KEY = {"super": 125, "shift": 42, "esc": 1, "a": 30, "n": 49, "h": 35, "c": 46, "tab": 15, "w": 17, "o": 24}
RETAINED = {"hardware": "hardware", "display": "displayManager", "clipboard": "clipboard", "keyboards": "keyboards",
            "wallpapermanager": "wallpaperManager", "overview": "overview", "calendar": "calendar"}
TRANSIENT = ("launcher", "session", "dashboard", "utilities", "settings", "sidebar")
FLAGS = TRANSIENT + ("overview", "calendar", "wallpaperManager", "clipboard", "hardware", "displayManager",
                     "keyboards", "osd")
SINK_WS = {"eDP-1": 10, "HDMI-A-1": 20}


def run(*argv: str) -> subprocess.CompletedProcess:
    return subprocess.run(argv, capture_output=True, text=True, timeout=10)


def hypr(*args: str) -> str:
    return run(HYPRCTL, *args).stdout


def hjson(what: str):
    return json.loads(hypr(what, "-j") or "null")


def dispatch(lua: str) -> None:
    out = hypr("dispatch", lua).strip()
    assert out == "ok", f"{lua}: {out}"


def ipc(target: str, method: str, *args: str) -> str:
    return run("qs", "ipc", "-p", SHELL, "call", target, method, *args).stdout.strip()


def keys(*names: str) -> None:
    """Press the keys in order and release them in reverse, like a chord."""
    seq = [f"{KEY[n]}:1" for n in names] + [f"{KEY[n]}:0" for n in reversed(names)]
    done = run("ydotool", "key", "-d", "30", *seq)
    # A key that never left would make every "holds the keyboard" check pass.
    assert done.returncode == 0, f"ydotool failed: {done.stderr.strip()}"
    time.sleep(0.35)


def wait(predicate, timeout: float = 3.0) -> bool:
    end = time.monotonic() + timeout
    while time.monotonic() < end:
        if predicate():
            return True
        time.sleep(0.1)
    return predicate()


class QA:
    def __init__(self) -> None:
        mons = {m["name"]: m for m in hjson("monitors")}
        assert set(SINK_WS) <= set(mons), mons.keys()
        self.mons = mons
        self.int, self.ext = "eDP-1", "HDMI-A-1"
        self.checks: list[dict] = []
        self.scenario = ""

    # observation -------------------------------------------------------
    def check(self, name: str, ok: bool, seen=None) -> bool:
        row = {"t": time.strftime("%T"), "scenario": self.scenario, "check": name,
               "result": "PASS" if ok else "FAIL", "seen": seen}
        self.checks.append(row)
        with open(OUT.parent / "results.jsonl", "a") as log:
            log.write(json.dumps(row, ensure_ascii=False) + "\n")
        return ok

    def focus(self, monitor: str) -> None:
        m = self.mons[monitor]
        dispatch(f"hl.dsp.cursor.move({{ x = {m['x'] + m['width'] // 2}, y = {m['y'] + m['height'] // 2} }})")
        dispatch(f'hl.dsp.focus({{ monitor = "{monitor}" }})')
        # Monitor focus alone leaves the keyboard on the last window of the
        # other monitor in this session; focus that monitor's sink, as a click would.
        dispatch(f'hl.dsp.focus({{ window = "class:^(cortetsu-qa-sink-{monitor})$" }})')
        assert wait(lambda: next(x for x in hjson("monitors") if x["name"] == monitor)["focused"]), monitor
        time.sleep(0.15)

    def flags_on(self, monitor: str) -> list[str]:
        self.focus(monitor)
        return [f for f in FLAGS if ipc("drawers", "isOpen", f) == "1"]

    def flags(self) -> dict[str, list[str]]:
        return {m: self.flags_on(m) for m in (self.int, self.ext)}

    def is_open(self, target: str) -> bool:
        return ipc(target, "isOpen") == "true"

    def sink(self, monitor: str) -> Path:
        return SINK_DIR / f"{monitor}.txt"

    def key_reaches_client(self, monitor: str, expect: bool) -> bool:
        """Type `a` with `monitor` focused. expect=True: True when it reached
        that monitor's sink. expect=False: True when it reached any sink (a
        surface holding the keyboard swallows it and both stay unchanged)."""
        self.focus(monitor)
        active = (hjson("activewindow") or {}).get("class", "")
        assert active.startswith("cortetsu-qa-sink-"), f"refusing to type into {active}"
        sinks = [self.sink(m) for m in (self.int, self.ext)]
        before = [p.stat().st_size for p in sinks]
        keys("a")
        if expect:
            target = self.sink(monitor)
            return wait(lambda: target.stat().st_size > before[sinks.index(target)], timeout=3.0)
        return wait(lambda: any(p.stat().st_size > b for p, b in zip(sinks, before)), timeout=1.5)

    def reset(self) -> None:
        for monitor in (self.int, self.ext):
            self.focus(monitor)
            for target in RETAINED:
                ipc(target, "close")
            for flag in TRANSIENT + ("osd",):
                if ipc("drawers", "isOpen", flag) == "1":
                    ipc("drawers", "toggle", flag)
        time.sleep(0.4)

    def open(self, target: str, monitor: str) -> bool:
        self.focus(monitor)
        ipc(target, "open")
        return wait(lambda: self.is_open(target))

    def both(self):
        return ((self.int, self.ext), (self.ext, self.int))

    # A1 ----------------------------------------------------------------
    def a1(self) -> None:
        for first, second in self.both():
            tag = f"hardware@{first} -> calendar@{second}"
            self.reset()
            self.focus(first)
            keys("super", "h")
            self.check(f"{tag}: SUPER+H opens hardware", wait(lambda: self.is_open("hardware")), self.flags())
            self.check(f"{tag}: hardware holds the keyboard", not self.key_reaches_client(first, False))
            self.focus(second)
            keys("super", "shift", "c")
            ok = wait(lambda: self.is_open("calendar"))
            flags = self.flags()
            self.check(f"{tag}: SUPER+SHIFT+C opens calendar", ok, flags)
            self.check(f"{tag}: hardware closed, calendar only on {second}",
                       flags == {first: [], second: ["calendar"]}, flags)
            self.check(f"{tag}: calendar holds the keyboard", not self.key_reaches_client(second, False))
            self.focus(second)
            keys("esc")
            self.check(f"{tag}: Escape closes calendar", wait(lambda: not self.is_open("calendar")), self.flags())
            self.check(f"{tag}: keyboard back in the client ({second})", self.key_reaches_client(second, True))
            self.check(f"{tag}: keyboard back in the client ({first})", self.key_reaches_client(first, True))

    # A2 ----------------------------------------------------------------
    def a2(self) -> None:
        for first, second in self.both():
            for a in RETAINED:
                for b in RETAINED:
                    if a == b:
                        continue
                    self.reset()
                    self.open(a, first)
                    self.open(b, second)
                    flags = self.flags()
                    self.check(f"{a}@{first} then {b}@{second}", flags == {first: [], second: [RETAINED[b]]}, flags)
            for panel in TRANSIENT:
                self.reset()
                self.open("hardware", first)
                self.focus(second)
                ipc("drawers", "toggle", panel)
                time.sleep(0.4)
                flags = self.flags()
                self.check(f"hardware@{first} then drawers toggle {panel}@{second}",
                           flags == {first: [], second: [panel]}, flags)
                self.open("hardware", first)
                flags = self.flags()
                self.check(f"{panel}@{second} then hardware@{first}", flags == {first: ["hardware"], second: []}, flags)
            self.reset()
            self.open("hardware", first)
            self.focus(first)
            ipc("drawers", "toggle", "osd")
            time.sleep(0.3)
            flags = self.flags()
            self.check(f"osd coexists with hardware on {first}", flags[first] == ["hardware", "osd"] and not flags[second],
                       flags)
            # Moving: open on the other screen moves the surface there.
            self.reset()
            self.open("hardware", first)
            self.open("hardware", second)
            flags = self.flags()
            self.check(f"hardware reopened on {second} moves it", flags == {first: [], second: ["hardware"]}, flags)
            self.check(f"hardware moved to {second} holds the keyboard there", not self.key_reaches_client(second, False))
            self.reset()
            self.check(f"after reset keyboard in client ({first})", self.key_reaches_client(first, True))

    # A3 ----------------------------------------------------------------
    def sidebar(self, path: str) -> None:
        if path == "ipc":
            ipc("drawers", "toggle", "sidebar")
        elif path == "super+n":
            keys("super", "n")
        elif path == "bottomhub-ipc":
            ipc("bottomHub", "notifications")
        time.sleep(0.45)

    def a3(self) -> None:
        repeat = int(os.environ.get("REPEAT_O3", "20"))
        for monitor in (self.int, self.ext):
            for surface in ("hardware", "wallpapermanager"):
                for path in ("ipc", "super+n", "bottomhub-ipc"):
                    results = []
                    for _ in range(repeat if surface == "wallpapermanager" else 3):
                        self.reset()
                        self.open(surface, monitor)
                        self.focus(monitor)
                        self.sidebar(path)
                        time.sleep(0.4)  # O-3 closed the sidebar 20-40 ms after opening
                        results.append(self.flags())
                    good = [r for r in results if r == {monitor: ["sidebar"], self.other(monitor): []}]
                    self.check(f"{surface}@{monitor} then sidebar by {path} x{len(results)}",
                               len(good) == len(results), [r for r in results if r not in good][:3])
                    self.focus(monitor)
                    self.sidebar(path)
                    flags = self.flags()
                    self.check(f"sidebar by {path} closes it on {monitor}", flags == {self.int: [], self.ext: []}, flags)
                    self.check(f"keyboard in the client after sidebar by {path} ({monitor})",
                               self.key_reaches_client(monitor, True))

    def other(self, monitor: str) -> str:
        return self.ext if monitor == self.int else self.int

    # B1 ----------------------------------------------------------------
    def bell(self, monitor: str) -> tuple[int, int]:
        self.focus(monitor)
        x, y, w, h = map(float, ipc("bottomHub", "notificationsButton").split())
        return int(x + w / 2), int(y + h / 2)

    def click(self, point: tuple[int, int]) -> None:
        dispatch(f"hl.dsp.cursor.move({{ x = {point[0]}, y = {point[1]} }})")
        time.sleep(0.15)
        done = run("ydotool", "click", "0xC0")
        assert done.returncode == 0, f"ydotool failed: {done.stderr.strip()}"
        time.sleep(0.6)  # O-3: a cleared grab closed the sidebar 20-40 ms after opening

    def sidebar_screens(self) -> list[str]:
        """Read without moving focus (flags() focuses every monitor)."""
        return [r["screen"] for r in json.loads(ipc("bottomHub", "inspect") or "[]") if r["sidebar"]]

    def b1(self) -> None:
        for monitor, other in self.both():
            point = self.bell(monitor)
            self.check(f"{monitor}: bell at {point}", True, point)
            closed = {monitor: [], other: []}
            for target in ("hardware", "wallpapermanager", "clipboard", "display", "keyboards", "calendar"):
                self.reset()
                self.open(target, monitor)
                self.click(point)
                flags = self.flags()
                self.check(f"{target}@{monitor}: one click on the bell leaves only the sidebar",
                           flags == {monitor: ["sidebar"], other: []}, flags)
                self.click(point)
                self.check(f"{target}@{monitor}: a second click closes it", wait(lambda: self.flags() == closed),
                           self.flags())
                self.check(f"{target}@{monitor}: keyboard back in the client", self.key_reaches_client(monitor, True))
            m = self.mons[monitor]
            self.reset()
            self.open("hardware", monitor)
            self.click((m["x"] + 12, m["y"] + m["height"] // 2))
            self.check(f"hardware@{monitor}: a click elsewhere on the scrim only dismisses", self.flags() == closed,
                       self.flags())
            self.open("hardware", monitor)
            self.click((m["x"] + m["width"] // 2, m["y"] + m["height"] // 2))
            self.check(f"hardware@{monitor}: a click on the panel keeps it open",
                       self.flags() == {monitor: ["hardware"], other: []}, self.flags())
            self.reset()
            self.open("hardware", monitor)
            self.focus(monitor)
            ipc("drawers", "toggle", "osd")
            self.click(point)
            flags = self.flags()
            self.check(f"hardware+osd@{monitor}: the bell leaves the sidebar, hardware closed",
                       "sidebar" in flags[monitor] and "hardware" not in flags[monitor], flags)
            # Escape after a bell click: observed, not a contract (nested: no).
            self.reset()
            self.click(point)
            opened = self.sidebar_screens() == [monitor]
            run("ydotool", "key", "-d", "30", "1:1", "1:0")
            time.sleep(0.5)
            row = {"opened": opened, "escape_closes": self.sidebar_screens() == []}
            self.checks.append({"t": time.strftime("%T"), "scenario": self.scenario, "result": "INFO",
                                "check": f"{monitor}: Escape after a bell click", "seen": row})
            # Fullscreen: SUPER+H still opens Hardware; the bell spot must not open the sidebar.
            self.reset()
            self.fullscreen(monitor, True)
            self.focus(monitor)
            keys("super", "h")
            opened = wait(lambda: self.is_open("hardware"))
            self.click(point)
            seen = self.sidebar_screens()
            self.check(f"fullscreen {monitor}: hardware open, bell-spot click does not open the sidebar",
                       opened and monitor not in seen, {"hardware": opened, "sidebar": seen})
            if monitor in seen:
                self.focus(monitor)
                ipc("drawers", "toggle", "sidebar")
            self.reset()
            self.fullscreen(monitor, False)
            self.check(f"after B1 keyboard in client ({monitor})", self.key_reaches_client(monitor, True))

    # A4 ----------------------------------------------------------------
    def fullscreen(self, monitor: str, on: bool) -> bool:
        """on: Hyprland fullscreen mode 2 (what the guard reads, `fullscreen > 1`);
        off: mode 0. The sinks start maximized (mode 1) in this session."""
        self.focus(monitor)
        mode = lambda: int((hjson("activewindow") or {}).get("fullscreen") or 0)  # noqa: E731
        want = 2 if on else 0
        for _ in range(3):
            if mode() == want:
                break
            if on or mode() == 2:
                dispatch('hl.dsp.window.fullscreen({ mode = "fullscreen" })')
            else:
                dispatch('hl.dsp.window.fullscreen({ mode = "maximized" })')
            time.sleep(0.4)
        return wait(lambda: mode() == want)

    def a4(self) -> None:
        for monitor in (self.int, self.ext):
            self.reset()
            self.check(f"fullscreen on ({monitor})", self.fullscreen(monitor, True))
            for path in ("ipc", "super+n", "bottomhub-ipc"):
                self.focus(monitor)
                self.sidebar(path)
                seen = self.flags_on(monitor)
                self.check(f"fullscreen {monitor}: sidebar by {path} does not open", "sidebar" not in seen, seen)
                if "sidebar" in seen:
                    ipc("drawers", "toggle", "sidebar")
            self.focus(monitor)
            ipc("drawers", "toggle", "osd")
            seen = self.flags_on(monitor)
            self.check(f"fullscreen {monitor}: drawers toggle osd is guarded", "osd" not in seen, seen)
            if "osd" in seen:
                ipc("drawers", "toggle", "osd")
            self.focus(monitor)
            keys("super", "h")
            opened = wait(lambda: self.is_open("hardware"), 1.5)
            self.check(f"fullscreen {monitor}: SUPER+H (always allowed) opens hardware", opened, self.flags_on(monitor))
            ipc("hardware", "close")
            self.check(f"fullscreen {monitor}: closing hardware works", wait(lambda: not self.is_open("hardware")))
            self.check(f"fullscreen {monitor}: keyboard in the client", self.key_reaches_client(monitor, True))
            self.check(f"fullscreen off ({monitor})", self.fullscreen(monitor, False))
            # Closing stays allowed: open, go fullscreen, close by each path.
            for path in ("ipc", "super+n", "bottomhub-ipc"):
                self.reset()
                self.focus(monitor)
                ipc("drawers", "toggle", "sidebar")
                time.sleep(0.4)
                opened = "sidebar" in self.flags_on(monitor)
                self.fullscreen(monitor, True)
                still = "sidebar" in self.flags_on(monitor)
                self.focus(monitor)
                self.sidebar(path)
                seen = self.flags_on(monitor)
                self.check(f"fullscreen {monitor}: sidebar open before fullscreen closes by {path}",
                           opened and "sidebar" not in seen, {"opened": opened, "after_fs": still, "after": seen})
                self.fullscreen(monitor, False)
            # OSD coexists with a retained surface (its legitimate exception).
            self.reset()
            self.open("calendar", monitor)
            self.focus(monitor)
            ipc("drawers", "toggle", "osd")
            seen = self.flags_on(monitor)
            self.check(f"osd coexists with calendar on {monitor}", sorted(seen) == ["calendar", "osd"], seen)
            self.reset()
            self.check(f"after A4 keyboard in client ({monitor})", self.key_reaches_client(monitor, True))


def main() -> int:
    qa = QA()
    result = {"shell": SHELL, "start": time.strftime("%FT%T%z"), "monitors": list(qa.mons)}
    for name in ONLY:
        qa.scenario = name
        try:
            getattr(qa, name)()
        except Exception as exc:  # recorded; the next scenario still runs
            qa.check("scenario raised", False, repr(exc)[:300])
    qa.scenario = "final"
    qa.reset()
    flags = qa.flags()
    qa.check("every flag closed on every screen", flags == {qa.int: [], qa.ext: []}, flags)
    result["checks"] = qa.checks
    result["end"] = time.strftime("%FT%T%z")
    OUT.write_text(json.dumps(result, indent=1, ensure_ascii=False))
    fails = [c for c in qa.checks if c["result"] == "FAIL"]
    print(f"{len(qa.checks)} checks, {len(fails)} FAIL")
    for c in fails:
        print("FAIL", c["scenario"], c["check"], json.dumps(c["seen"], ensure_ascii=False)[:240])
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())

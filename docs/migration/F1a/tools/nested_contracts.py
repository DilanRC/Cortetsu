#!/usr/bin/env python3
"""F1a functional contracts of the surface states, observed in nested Hyprland.

    python3 scripts/integration/ws2_run.py --timeout 1200 OUT/contracts.log -- \
        python3 docs/migration/F1a/tools/nested_contracts.py CHECKOUT OUT/contracts.json

CHECKOUT is the repository whose shell is composed (main for "before", the
F1a branch for "after"); the harness itself is imported from that checkout.
The same script runs on both so the before/after matrix is observed, not
assumed. Every check records PASS/FAIL with what was seen and never aborts
the run. Outputs: WAYLAND-1 plus HEADLESS-1/2; scenarios use the headless
ones, which have their own frame clock. Nothing reaches the desktop session.
"""
from __future__ import annotations

import json
import os
from pathlib import Path
import re
import sys
import tempfile
import time

CHECKOUT = Path(sys.argv[1]).resolve()
OUT = Path(sys.argv[2]).resolve()
sys.path.insert(0, str(CHECKOUT / "scripts/integration"))
import launcher_harness as H  # noqa: E402
from f0_session import F0Session  # noqa: E402

# IPC target -> state flag, the seven retained surfaces.
RETAINED = {"hardware": "hardware", "display": "displayManager", "clipboard": "clipboard", "keyboards": "keyboards",
            "wallpapermanager": "wallpaperManager", "overview": "overview", "calendar": "calendar"}
FLAGS = ("launcher", "session", "dashboard", "utilities", "settings", "sidebar", "overview", "calendar",
         "wallpaperManager", "clipboard", "hardware", "displayManager", "keyboards", "osd", "bar")
KEY_LEFTCTRL, KEY_K, KEY_H = 29, 37, 35


class Run:
    def __init__(self, session: F0Session, sink: Path):
        self.s, self.sink = session, sink
        self.m1, self.m2 = session.headless()[:2]
        self.home = session.focused_monitor()
        self.checks: list[dict] = []

    # observation ---------------------------------------------------------
    def check(self, scenario: str, name: str, ok: bool, seen) -> bool:
        self.checks.append({"scenario": scenario, "check": name, "result": "PASS" if ok else "FAIL", "seen": seen})
        return ok

    def flags_on(self, monitor: str) -> dict[str, str]:
        self.s.focus_monitor(monitor)
        return {flag: self.s.ipc("drawers", "isOpen", flag).stdout.strip() for flag in FLAGS}

    def open_flags(self) -> dict[str, list[str]]:
        result = {}
        for monitor in (self.m1, self.m2):
            result[monitor] = [flag for flag, value in self.flags_on(monitor).items() if value == "1"]
        return result

    def is_open(self, target: str) -> bool:
        return self.s.ipc(target, "isOpen").stdout.strip() == "true"

    def wait(self, predicate, timeout: float = 3.0) -> bool:
        try:
            H.wait_for(predicate, "", timeout=timeout)
            return True
        except AssertionError:
            return False

    def key_reaches_client(self, stay: str | None = None) -> bool:
        """`hyprctl activelayer` does not exist in Hyprland 0.56: keyboard
        ownership is observed by where a typed key lands."""
        self.s.focus_monitor(stay or self.home)
        before = len(self.sink.read_text())
        self.s.tap(H.KEY_A)
        return self.wait(lambda: len(self.sink.read_text()) > before, timeout=1.5 if stay else 3.0)

    def reset(self) -> None:
        for monitor in (self.m1, self.m2):
            self.s.focus_monitor(monitor)
            for target in RETAINED:
                self.s.ipc(target, "close")
            for flag in FLAGS[:6] + ("osd",):
                if self.s.ipc("drawers", "isOpen", flag).stdout.strip() == "1":
                    self.s.ipc("drawers", "toggle", flag)
        time.sleep(0.3)

    def open(self, target: str, monitor: str) -> bool:
        self.s.focus_monitor(monitor)
        self.s.ipc(target, "open")
        return self.wait(lambda: self.is_open(target))

    # scenarios -----------------------------------------------------------
    def retained_open_close(self) -> None:
        for target, flag in RETAINED.items():
            for monitor, other in ((self.m1, self.m2), (self.m2, self.m1)):
                label = f"{target}@{monitor}"
                self.reset()
                opened = self.check("open-escape", f"{label} opens", self.open(target, monitor), self.is_open(target))
                self.check("focus", f"{label} holds the keyboard (a key does not reach the client)",
                           not self.key_reaches_client(stay=monitor), "key reached the client")
                flags = self.open_flags()
                self.check("monitor", f"{label} only on its screen", flags == {monitor: [flag], other: []}, flags)
                if opened:
                    self.s.focus_monitor(monitor)
                    self.s.tap(H.KEY_ESC)
                    self.check("open-escape", f"{label} Escape closes", self.wait(lambda: not self.is_open(target)),
                               self.is_open(target))
                self.check("focus", f"{label} keyboard back in the client", self.key_reaches_client(), "")

    def retained_exclusive(self) -> None:
        for first in RETAINED:
            for second in RETAINED:
                if first == second:
                    continue
                for where, monitor in (("same screen", self.m1), ("other screen", self.m2)):
                    self.reset()
                    self.open(first, self.m1)
                    self.open(second, monitor)
                    flags = self.open_flags()
                    opened = [f for values in flags.values() for f in values]
                    self.check("exclusive", f"{first} then {second}, {where}", opened == [RETAINED[second]], flags)

    def cross_kind(self) -> None:
        for panel in ("launcher", "session", "dashboard", "utilities", "settings", "sidebar", "osd"):
            self.reset()
            self.open("hardware", self.m1)
            self.s.ipc("drawers", "toggle", panel)
            time.sleep(0.3)
            self.check("cross-kind", f"hardware then drawers toggle {panel}", True, self.open_flags())
            self.reset()
            self.s.focus_monitor(self.m1)
            self.s.ipc("drawers", "toggle", panel)
            time.sleep(0.2)
            self.open("hardware", self.m1)
            self.check("cross-kind", f"drawers toggle {panel} then hardware", True, self.open_flags())

    def wallpaper(self) -> None:
        for other in ("hardware", "overview"):
            self.reset()
            self.open("wallpapermanager", self.m1)
            self.open(other, self.m2)
            flags = self.open_flags()
            self.check("wallpaper", f"wallpaper then {other} on the other screen",
                       flags == {self.m1: [], self.m2: [RETAINED[other]]}, flags)
        self.reset()
        self.open("wallpapermanager", self.m1)
        self.s.ipc("drawers", "toggle", "sidebar")
        time.sleep(0.4)
        flags = self.open_flags()
        self.check("wallpaper", "sidebar closes the wallpaper manager", flags[self.m1] == ["sidebar"], flags)

    def monitor_change(self) -> None:
        self.reset()
        self.open("hardware", self.m1)
        self.s.focus_monitor(self.m2)
        self.s.ipc("hardware", "toggle")
        time.sleep(0.3)
        flags = self.open_flags()
        self.check("monitor", "toggle from the other screen closes it", flags == {self.m1: [], self.m2: []}, flags)
        self.open("hardware", self.m1)
        self.open("hardware", self.m2)
        flags = self.open_flags()
        self.check("monitor", "open on the newly focused screen moves it",
                   flags == {self.m1: [], self.m2: ["hardware"]}, flags)
        self.reset()
        self.open("overview", self.m1)
        self.s.focus_monitor(self.m2)
        self.s.ipc("overview", "toggle")
        time.sleep(0.3)
        self.check("monitor", "overview toggle from the other screen", True, self.open_flags())

    def shortcuts(self) -> None:
        def chord(*keys: int) -> None:
            for key in keys:
                self.s.send(f"key {key} 1")
                time.sleep(0.03)
            for key in reversed(keys):
                self.s.send(f"key {key} 0")
                time.sleep(0.03)
        for label, keys, target in (("SUPER+CTRL+K", (H.KEY_LEFTMETA, KEY_LEFTCTRL, KEY_K), "keyboards"),
                                    ("SUPER+H", (H.KEY_LEFTMETA, KEY_H), "hardware")):
            self.reset()
            self.s.focus_monitor(self.m1)
            chord(*keys)
            self.check("shortcut", f"{label} opens {target}", self.wait(lambda: self.is_open(target)), self.open_flags())
            self.s.focus_monitor(self.m1)
            chord(*keys)
            self.check("shortcut", f"{label} closes {target}", self.wait(lambda: not self.is_open(target)),
                       self.open_flags())
            self.check("shortcut", f"{label} keyboard back in the client", self.key_reaches_client(), "")

    def outside_click(self) -> None:
        for target in ("hardware", "clipboard", "calendar"):
            self.reset()
            self.open(target, self.m1)
            monitor = next(m for m in self.s.monitors() if m["name"] == self.m1)
            self.s.click(monitor["x"] + 12, monitor["y"] + monitor["height"] // 2)
            time.sleep(0.5)
            self.check("outside-click", f"{target} after a click at the screen edge", True, self.open_flags())

    def fullscreen(self) -> None:
        self.reset()
        self.open("hardware", self.home)
        self.s.hyprctl("dispatch", 'hl.dsp.focus({ window = "class:cortetsu-probe" })')
        self.s.hyprctl("dispatch", 'hl.dsp.window.fullscreen({ mode = "fullscreen" })')
        time.sleep(0.6)
        fs = any(c.get("fullscreen") for c in self.s.hjson("clients") or [] if c.get("class") == "cortetsu-probe")
        self.check("fullscreen", "fullscreen closes the retained surface", fs and not self.is_open("hardware"),
                   {"client_fullscreen": fs, "hardware_open": self.is_open("hardware")})
        self.s.hyprctl("dispatch", 'hl.dsp.window.fullscreen({ mode = "fullscreen" })')
        time.sleep(0.4)

    def names(self) -> None:
        self.reset()
        self.s.focus_monitor(self.m1)
        listed = sorted(self.s.ipc("drawers", "list").stdout.split())
        self.check("names", "drawers list", True, listed)
        for bogus in ("bogus", "retainedOverlayOpen", "requiresFullInputMask", "dashboardTab"):
            self.check("names", f"drawers isOpen {bogus}", True, self.s.ipc("drawers", "isOpen", bogus).stdout.strip())
            rc = self.s.ipc("drawers", "toggle", bogus)
            self.check("names", f"drawers toggle {bogus} leaves every flag closed", not any(self.open_flags().values()),
                       {"rc": rc.returncode, "stderr": rc.stderr.strip()[-160:]})

    def final_state(self) -> None:
        self.reset()
        flags = self.open_flags()
        self.check("final", "every flag closed on every screen", flags == {self.m1: [], self.m2: []}, flags)
        self.check("final", "keyboard in the client", self.key_reaches_client(), "")


def qml_problems(log: Path) -> list[str]:
    lines = [re.sub(r"\x1b\[[0-9;]*m", "", l) for l in log.read_text(errors="replace").splitlines()]
    return [l for l in lines if ("WARN" in l or "ERROR" in l) and "Process failed to start" not in l]


def main() -> int:
    result = {"checkout": str(CHECKOUT), "date": time.strftime("%FT%T%z")}
    with tempfile.TemporaryDirectory(prefix="czf", dir="/tmp") as tmp:
        session = F0Session(Path(tmp))
        try:
            session.start(outputs=3)
            sink = session.start_client()
            run = Run(session, sink)
            result["monitors"] = {"client": run.home, "m1": run.m1, "m2": run.m2}
            warnings_before = len(qml_problems(session.logs / "qs.log"))
            scenarios = [run.retained_open_close, run.retained_exclusive, run.cross_kind, run.wallpaper,
                         run.monitor_change, run.shortcuts, run.outside_click, run.fullscreen, run.names,
                         run.final_state]
            # ONLY=wallpaper,names REPEAT=10 reruns a subset, to tell flakes from regressions.
            only = [name for name in os.environ.get("ONLY", "").split(",") if name]
            if only:
                scenarios = [s for s in scenarios if s.__name__ in only]
            for scenario in scenarios * int(os.environ.get("REPEAT", "1")):
                try:
                    scenario()
                except Exception as exc:  # recorded, the remaining scenarios still run
                    run.check(scenario.__name__, "scenario raised", False, repr(exc)[:300])
            result["checks"] = run.checks
            problems = qml_problems(session.logs / "qs.log")
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
    return 0


if __name__ == "__main__":
    sys.exit(main())

#!/usr/bin/env python3
"""Keyring dialogs end to end: the composed shell in a nested Hyprland,
cortetsu-prompter and a real gnome-keyring on the session's private bus, and
a virtual keyboard. Nothing reaches the desktop session or its keyring.

1. `secret-tool store` with no keyring: the dialog asks for a new password
   twice; typing it, Enter, the same again and Enter creates the keyring.
2. After `secret-tool lock`, `secret-tool lookup` opens the unlock dialog: a
   wrong password brings the warning back on the same dialog, the right one
   returns the secret.
3. Locked again, Escape cancels: the lookup returns nothing.
After each dialog no Cortetsu layer keeps the keyboard.

    python3 scripts/integration/ws2_run.py --workspace 4 LOG -- \\
        python3 scripts/integration/test-secret-prompt.py

Set CORTETSU_RENDER_DIR to keep a PNG of each dialog.
"""
from __future__ import annotations

import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time

sys.path.insert(0, str(Path(__file__).resolve().parent))
import launcher_harness as H  # noqa: E402

RUNTIME_BIN = H.REPO / "cortetsu/desktop-runtime-rs/target/release/cortetsu-desktop-runtime"
RENDER_DIR = os.environ.get("CORTETSU_RENDER_DIR", "")
LAYER = "cortetsu-secret-prompt"
# evdev codes for the letters typed
KEYS = {"a": 30, "s": 31, "d": 32, "f": 33, "g": 34, "h": 35, "j": 36, "k": 37, "l": 38}
KEY_ESC, KEY_RETURN = H.KEY_ESC, H.KEY_RETURN


def prompt_layers(s: H.Session) -> list[str]:
    found = []
    for monitor, data in (s.hjson("layers") or {}).items():
        for level in data.get("levels", {}).values():
            found += [monitor for layer in level if layer.get("namespace") == LAYER]
    return found


def type_text(s: H.Session, text: str) -> None:
    for char in text:
        s.tap(KEYS[char])
        time.sleep(0.04)


def shot(s: H.Session, monitor: str, name: str) -> None:
    if RENDER_DIR and shutil.which("grim"):
        subprocess.run(["grim", "-o", monitor, f"{RENDER_DIR}/secret-prompt-{name}.png"], env=s.env(), timeout=10)


def main() -> int:
    if missing := H.missing_tools() + [t for t in ("gnome-keyring-daemon", "secret-tool") if not shutil.which(t)]:
        print(f"SKIP falta: {missing}")
        return 0
    assert RUNTIME_BIN.exists(), f"construye {RUNTIME_BIN} (cargo build --release)"
    base = Path(tempfile.mkdtemp(prefix="cortetsu-secret-prompt-"))
    s = H.Session(base)
    helpers = []
    try:
        s.start(outputs=2)
        env = s.env()
        target = s.headless()[0]
        s.focus_monitor(target)

        keyring = subprocess.Popen(
            ["gnome-keyring-daemon", "--foreground", "--components=secrets",
             f"--control-directory={s.runtime}/keyring"],
            env=env, stdout=subprocess.DEVNULL, stderr=(s.logs / "keyring.log").open("w"), start_new_session=True)
        prompter = subprocess.Popen(
            [str(RUNTIME_BIN), "cortetsu-prompter"],
            env=dict(env, CORTETSU_SHELL_PATH=str(s.shell_dir), CORTETSU_PROMPTER_IDLE_MS="120000"),
            stdout=subprocess.DEVNULL, stderr=(s.logs / "prompter.log").open("w"), start_new_session=True)
        helpers += [prompter, keyring]

        def owned(name: str) -> bool:
            out = subprocess.run(["dbus-send", f"--bus={s.bus_address}", "--print-reply",
                                  "--dest=org.freedesktop.DBus", "/org/freedesktop/DBus",
                                  "org.freedesktop.DBus.NameHasOwner", f"string:{name}"],
                                 capture_output=True, text=True, env=env)
            return "boolean true" in out.stdout
        H.wait_for(lambda: owned("org.gnome.keyring.SystemPrompter"), "el prompter ocupa su nombre")
        H.wait_for(lambda: owned("org.freedesktop.secrets"), "gnome-keyring")

        def tool(*args: str, stdin: str = "") -> subprocess.Popen:
            proc = subprocess.Popen(["secret-tool", *args], env=env, stdin=subprocess.PIPE,
                                    stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
            proc.stdin.write(stdin)
            proc.stdin.close()
            return proc

        def dialog_open() -> None:
            H.wait_for(lambda: prompt_layers(s) == [target], f"diálogo en {target}")
            time.sleep(0.6)

        def dialog_closed(what: str) -> None:
            H.wait_for(lambda: not prompt_layers(s), f"el diálogo se cierra tras {what}")

        checks = 0

        # 1. New keyring: the password twice.
        store = tool("store", "--label=Prueba", "service", "cortetsu-test", stdin="s3cret")
        dialog_open()
        shot(s, target, "new")
        type_text(s, "asdf")
        s.tap(KEY_RETURN)
        time.sleep(0.2)
        type_text(s, "asdf")
        s.tap(KEY_RETURN)
        assert store.wait(20) == 0, store.stderr.read()
        dialog_closed("crear el llavero")
        checks += 1

        # 2. Unlock: wrong, then right, on the same dialog.
        assert tool("lock").wait(10) == 0
        lookup = tool("lookup", "service", "cortetsu-test")
        dialog_open()
        type_text(s, "ghjk")
        s.tap(KEY_RETURN)
        time.sleep(1.5)
        assert prompt_layers(s) == [target], "the dialog stays open after a wrong password"
        assert lookup.poll() is None, "lookup must still wait"
        shot(s, target, "retry")
        type_text(s, "asdf")
        s.tap(KEY_RETURN)
        assert lookup.wait(20) == 0, lookup.stderr.read()
        assert lookup.stdout.read() == "s3cret"
        dialog_closed("desbloquear")
        checks += 1

        # 3. Escape cancels.
        assert tool("lock").wait(10) == 0
        refused = tool("lookup", "service", "cortetsu-test")
        dialog_open()
        s.tap(KEY_ESC)
        refused.wait(20)
        assert refused.stdout.read() == "", "a cancelled unlock reveals nothing"
        dialog_closed("Escape")
        checks += 1

        log = (s.logs / "qs.log").read_text(errors="replace")
        bad = [line for line in log.splitlines() if "SecretPrompt" in line and ("WARN" in line or "ERROR" in line)]
        assert not bad, "\n".join(bad)
        print(f"SECRET_PROMPT_PASS {checks} escenarios en {target}")
        return 0
    finally:
        for proc in helpers:
            if proc.poll() is None:
                proc.terminate()
                try:
                    proc.wait(5)
                except subprocess.TimeoutExpired:
                    proc.kill()
        s.stop()
        if os.environ.get("KEEP"):
            print(f"logs: {s.logs}")
        else:
            shutil.rmtree(base, ignore_errors=True)


if __name__ == "__main__":
    sys.exit(main())

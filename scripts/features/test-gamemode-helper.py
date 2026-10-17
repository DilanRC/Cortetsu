#!/usr/bin/env python3
"""cortetsu-gamemode state machine against a fake hyprctl with injected faults.

The fake keeps every option in a JSON store (the "effective" Hyprland state)
and reads a fault plan: a queue of eval outcomes (ok / fail / partial / slow)
and a getoption switch. Each case asserts the store, not only the helper's
JSON, and the reply: enabled is true only in ACTIVE.
The nested-Hyprland twin is scripts/features/test-gamemode-runtime.py.
"""
import json
import os
import subprocess
import tempfile
import time
from pathlib import Path

HELPER = Path(__file__).resolve().parents[2] / "cortetsu/bin/cortetsu-gamemode"
FAKE = r'''#!/usr/bin/env python3
import json, os, re, sys, time
store, plan_path = os.environ["FAKE_HYPR_STORE"], os.environ["FAKE_HYPR_PLAN"]
options, plan = json.load(open(store)), json.load(open(plan_path))
cmd = sys.argv[1]
if plan.get("getoption") == "fail" and cmd != "eval":
    sys.exit("socket closed")
if cmd == "keyword":
    value = sys.argv[3]
    options[sys.argv[2]] = (value == "1" if isinstance(options[sys.argv[2]], bool)
                            else value if " " in value or sys.argv[2].startswith("general:gaps_") else int(value))
    if sys.argv[2].startswith("general:gaps_") and " " not in value:
        options[sys.argv[2]] = " ".join([value] * 4)
    json.dump(options, open(store, "w"))
elif cmd == "getoption":
    value = options[sys.argv[2]]
    key = "bool" if isinstance(value, bool) else "css" if isinstance(value, str) else "int"
    print(json.dumps({"option": sys.argv[2], key: value, "set": True}))
elif cmd == "eval":
    outcome = plan["eval"].pop(0) if plan.get("eval") else "ok"
    json.dump(plan, open(plan_path, "w"))
    if outcome == "fail":
        sys.exit("error: unknown config key")
    if outcome == "slow":
        time.sleep(1)
    tree = json.loads(re.sub(r"(\w+) = ", r'"\1": ', sys.argv[2][len("hl.config("):-1]))
    pairs = []
    def walk(node, prefix):
        for key, value in node.items():
            if isinstance(value, dict):
                walk(value, prefix + key + ":")
            else:
                pairs.append((prefix + key, value))
    walk(tree, "")
    for done, (name, value) in enumerate(pairs):
        if outcome == "partial" and done == 3:
            json.dump(options, open(store, "w"))
            sys.exit("error: partial apply")
        if name.startswith("general:gaps_") and isinstance(value, int):
            value = " ".join([str(value)] * 4)  # Hyprland reports gaps as css
        options[name] = value
    json.dump(options, open(store, "w"))
'''
USER = {"animations:enabled": True, "decoration:shadow:enabled": True, "decoration:blur:enabled": True,
        "general:gaps_in": "5 5 5 5", "general:gaps_out": "4 8 12 16", "general:border_size": 2,
        "decoration:rounding": 15, "general:allow_tearing": False, "misc:vrr": 1}
GAME_VALUES = {"decoration:rounding": 0, "general:gaps_out": "0 0 0 0", "animations:enabled": False}

with tempfile.TemporaryDirectory(prefix="cortetsu-gamemode-helper-") as tmp:
    root = Path(tmp)
    store, plan, state = root / "options.json", root / "plan.json", root / "cortetsu-gamemode-test.json"
    (root / "hyprctl").write_text(FAKE)
    (root / "hyprctl").chmod(0o755)
    env = {**os.environ, "XDG_RUNTIME_DIR": tmp, "HYPRLAND_INSTANCE_SIGNATURE": "test",
           "CORTETSU_HYPRCTL": str(root / "hyprctl"), "FAKE_HYPR_STORE": str(store), "FAKE_HYPR_PLAN": str(plan)}

    def reset(options: dict = USER) -> None:
        store.write_text(json.dumps(options))
        plan.write_text("{}")
        state.unlink(missing_ok=True)

    def faults(**kwargs) -> None:
        plan.write_text(json.dumps(kwargs))

    def run(action: str, ok: bool = True, *flags: str) -> dict:
        done = subprocess.run(["python3", str(HELPER), action, *flags], env=env, capture_output=True, text=True,
                              timeout=30)
        reply = json.loads(done.stdout)
        assert (done.returncode == 0) == ok == reply["ok"], (action, done)
        assert reply["enabled"] == (reply["state"] == "ACTIVE"), reply
        return reply

    def options() -> dict:
        return json.loads(store.read_text())

    def is_game() -> bool:
        return all(options()[name] == value for name, value in GAME_VALUES.items())

    # Enable writes the game values and nothing else; disable restores all.
    reset()
    assert run("status")["state"] == "INACTIVE" and run("disable")["state"] == "INACTIVE"
    assert run("enable") == {"state": "ACTIVE", "enabled": True, "ok": True, "error": None}
    assert is_game() and options()["misc:vrr"] == 1
    assert json.loads(state.read_text())["original"]["general:gaps_out"] == [4, 8, 12, 16]
    assert run("enable")["state"] == "ACTIVE", "a repeated enable is a no-op"
    assert json.loads(state.read_text())["original"]["decoration:rounding"] == 15, "first snapshot kept"
    assert run("disable")["state"] == "INACTIVE" and options() == USER and not state.exists()

    # Eval fails outright: nothing changed, so INACTIVE with the error.
    reset()
    faults(eval=["fail"])
    reply = run("enable", ok=False)
    assert reply["state"] == "INACTIVE" and "unknown config key" in reply["error"], reply
    assert options() == USER and not state.exists()

    # Half the options written, then an error: rolled back to the user's values.
    reset()
    faults(eval=["partial"])
    reply = run("enable", ok=False)
    assert reply["state"] == "INACTIVE" and "rolled back" in reply["error"], reply
    assert options() == USER and not state.exists()

    # Originals cannot be read: nothing is written, no transaction left.
    reset()
    faults(getoption="fail")
    assert run("enable", ok=False)["state"] == "INACTIVE"
    assert options() == USER and not state.exists()

    # Partial apply and the rollback fails too: RECOVERY_REQUIRED keeps
    # the originals, enable refuses, recover retries and restores them.
    reset()
    faults(eval=["partial", "fail"])
    reply = run("enable", ok=False)
    assert reply["state"] == "RECOVERY_REQUIRED" and not reply["enabled"] and "rollback failed" in reply["error"]
    assert options() != USER and state.exists()
    assert run("status")["state"] == "RECOVERY_REQUIRED", "status does not modify"
    assert run("enable", ok=False)["state"] == "RECOVERY_REQUIRED", "enable must not overwrite the snapshot"
    faults(eval=["fail"])
    assert run("recover", ok=False)["state"] == "RECOVERY_REQUIRED" and state.exists()
    assert run("recover")["state"] == "INACTIVE" and options() == USER and not state.exists()

    # Restore fails on disable: kept for retry; a later disable finishes.
    reset()
    run("enable")
    faults(eval=["fail"])
    assert run("disable", ok=False)["state"] == "RECOVERY_REQUIRED" and is_game()
    assert run("disable")["state"] == "INACTIVE" and options() == USER

    # Interrupted APPLYING / RESTORING (a killed helper): recover finishes.
    for stuck in ("APPLYING", "RESTORING"):
        reset()
        run("enable")
        data = json.loads(state.read_text())
        state.write_text(json.dumps(dict(data, state=stuck)))
        assert run("status")["state"] == stuck and not run("status")["enabled"]
        assert run("recover")["state"] == "INACTIVE" and options() == USER, stuck

    # A corrupt file is UNKNOWN and is never deleted or overwritten.
    reset()
    state.write_text("{not json")
    assert run("status")["state"] == "UNKNOWN"
    assert run("enable", ok=False)["state"] == "UNKNOWN" and run("disable", ok=False)["state"] == "UNKNOWN"
    assert state.read_text() == "{not json" and options() == USER

    # Hyprland not answering: a stored ACTIVE is reported UNKNOWN, not on.
    reset()
    run("enable")
    faults(getoption="fail")
    assert run("status")["state"] == "UNKNOWN"
    faults()
    run("disable")

    # The hyprlang backend (--keyword) follows the same contract.
    reset()
    assert run("enable", True, "--keyword")["state"] == "ACTIVE" and is_game() and options()["misc:vrr"] == 1
    assert run("disable", True, "--keyword")["state"] == "INACTIVE" and options() == USER

    # Rounding changed from Settings while on is kept; the rest is restored.
    reset()
    run("enable")
    store.write_text(json.dumps(dict(options(), **{"decoration:rounding": 7})))
    run("disable")
    assert options() == dict(USER, **{"decoration:rounding": 7})

    # Disable starts while enable is inside its slow eval; the lock
    # orders them and the user's values come back.
    reset()
    faults(eval=["slow"])
    enabling = subprocess.Popen(["python3", str(HELPER), "enable"], env=env, stdout=subprocess.PIPE, text=True)
    deadline = time.monotonic() + 10
    while not state.exists():
        assert time.monotonic() < deadline, "enable never wrote its transaction"
        time.sleep(0.01)
    assert json.loads(state.read_text())["state"] == "APPLYING"
    disabled = run("disable")
    enabling.communicate(timeout=30)
    assert disabled["state"] == "INACTIVE" and options() == USER, f"an overlapping disable lost values: {options()}"

    # Quick on/off/on/off bursts end consistent: ACTIVE with game values or INACTIVE with the user's.
    for _ in range(4):
        racers = [subprocess.Popen(["python3", str(HELPER), action], env=env, stdout=subprocess.PIPE, text=True)
                  for action in ("enable", "disable", "enable", "disable")]
        for racer in racers:
            racer.communicate(timeout=30)
        final = run("status")["state"]
        assert (final == "ACTIVE" and is_game()) or (final == "INACTIVE" and options() == USER), (final, options())
        run("disable")
        assert options() == USER

print("PASS: game mode only reports ACTIVE after a verified apply; failures roll back or stay recoverable")

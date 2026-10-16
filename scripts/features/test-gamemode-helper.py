#!/usr/bin/env python3
"""cortetsu-gamemode serialises enable and disable.

A fake hyprctl keeps options in a JSON file and takes a second per `eval`,
which opens the window a quick on/off hits: disable reading the snapshot
while enable is still applying. Without the lock the snapshot is deleted and
the game values stay with nothing to restore.
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
store = os.environ["FAKE_HYPR_STORE"]
options = json.load(open(store))
cmd = sys.argv[1]
if cmd == "getoption":
    value = options[sys.argv[2]]
    key = "bool" if isinstance(value, bool) else "css" if isinstance(value, str) else "int"
    print(json.dumps({"option": sys.argv[2], key: value, "set": True}))
elif cmd == "eval":
    time.sleep(1)
    tree = json.loads(re.sub(r"(\w+) = ", r'"\1": ', sys.argv[2][len("hl.config("):-1]))
    def walk(node, prefix):
        for key, value in node.items():
            if isinstance(value, dict):
                walk(value, prefix + key + ":")
            elif key.startswith("gaps_") and isinstance(value, int):
                options[prefix + key] = " ".join([str(value)] * 4)  # Hyprland reports gaps as css
            else:
                options[prefix + key] = value
    walk(tree, "")
    json.dump(options, open(store, "w"))
'''
USER = {"animations:enabled": True, "decoration:shadow:enabled": True, "decoration:blur:enabled": True,
        "general:gaps_in": "5 5 5 5", "general:gaps_out": "4 8 12 16", "general:border_size": 2,
        "decoration:rounding": 15, "general:allow_tearing": False}

with tempfile.TemporaryDirectory(prefix="cortetsu-gamemode-helper-") as tmp:
    root = Path(tmp)
    store = root / "options.json"
    store.write_text(json.dumps(USER))
    (root / "hyprctl").write_text(FAKE)
    (root / "hyprctl").chmod(0o755)
    env = {**os.environ, "XDG_RUNTIME_DIR": tmp, "HYPRLAND_INSTANCE_SIGNATURE": "test",
           "CORTETSU_HYPRCTL": str(root / "hyprctl"), "FAKE_HYPR_STORE": str(store)}

    def run(action: str) -> dict:
        return json.loads(subprocess.run(["python3", str(HELPER), action], env=env, capture_output=True, text=True,
                                         check=True, timeout=30).stdout)

    def options() -> dict:
        return json.loads(store.read_text())

    assert run("enable") == {"enabled": True}
    assert options()["decoration:rounding"] == 0 and options()["general:gaps_out"] == "0 0 0 0"
    assert run("disable") == {"enabled": False}
    assert options() == USER, options()

    enabling = subprocess.Popen(["python3", str(HELPER), "enable"], env=env, stdout=subprocess.PIPE, text=True)
    deadline = time.monotonic() + 10
    while not (root / "cortetsu-gamemode-test.json").exists():
        assert time.monotonic() < deadline, "enable never wrote its snapshot"
        time.sleep(0.01)
    disabled = run("disable")  # starts while enable is inside its slow eval
    enabling.communicate(timeout=30)
    assert disabled == {"enabled": False} and options() == USER, \
        f"an overlapping disable lost the user's values: {options()}"

    bad = dict(env, HYPRLAND_INSTANCE_SIGNATURE="test", CORTETSU_HYPRCTL="/bin/false")
    failed = subprocess.run(["python3", str(HELPER), "enable"], env=bad, capture_output=True, text=True, timeout=30)
    assert failed.returncode == 1 and json.loads(failed.stdout) == {"enabled": False}, failed

print("PASS: game mode enable/disable are serialised; an overlapping disable restores the user's values")

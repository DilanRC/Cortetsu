import json
import os
import shutil
import subprocess
import tempfile
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
colours = (REPO / "cortetsu/services/CortetsuColours.qml").read_text(encoding="utf-8")
assert 'import "../theme/CortetsuDesignDefaults.js" as Defaults' in colours
assert 'target: CortetsuDesign' in colours

script = Path(__file__).resolve().parents[2] / "cortetsu/bin/cortetsu-scheme"
with tempfile.TemporaryDirectory() as directory:
    # The live compositor must not be reloaded by a test run.
    env = {**os.environ, "XDG_STATE_HOME": directory, "XDG_CONFIG_HOME": str(Path(directory) / "config"),
           "CORTETSU_SKIP_RELOAD": "1"}
    live_scheme = Path(env["XDG_CONFIG_HOME"]) / "hypr/scheme/current.lua"
    live_scheme.parent.mkdir(parents=True)
    live_scheme.write_text("return {}\n", encoding="utf-8")
    runtime = Path(directory) / "runtime/current/theme"
    shutil.copytree(REPO / "cortetsu/theme", runtime)
    shipped = {path.name: path.read_bytes() for path in runtime.iterdir()}
    env["CORTETSU_RUNTIME_ROOT"] = str(Path(directory) / "runtime")
    subprocess.run([str(script), "set", "-v", "expressive"], env=env, check=True)
    result = subprocess.run([str(script), "get", "-nfv"], env=env, check=True, text=True, capture_output=True)
    assert result.stdout.splitlines() == ["dynamic", "default", "expressive"]
    listed = subprocess.run([str(script), "list"], env=env, check=True, text=True, capture_output=True)
    catalog = json.loads(listed.stdout)
    assert sum(len(flavours) for flavours in catalog.values()) >= 24
    assert "aura" in catalog and "default" in catalog["aura"]
    subprocess.run([str(script), "set", "-n", "aura", "default"], env=env, check=True)
    selected = json.loads((Path(directory) / "cortetsu/scheme.json").read_text(encoding="utf-8"))
    assert selected["name"] == "aura"
    assert selected["colours"]["primary"] == catalog["aura"]["default"]["primary"]
    live = live_scheme.read_text(encoding="utf-8")
    assert f'primary = "{catalog["aura"]["default"]["primary"].lstrip("#")}"' in live
    assert 'surfaceContainer =' in live and 'onSurfaceVariant =' in live
    # Selecting a scheme never rewrites the promoted generation; the shell
    # reads scheme.json at runtime (test-cortetsu-theme-reactive-runtime.py).
    assert {path.name: path.read_bytes() for path in runtime.iterdir()} == shipped

    # With the palette file present, Hyprland re-reads its config and nothing
    # else: a full reload would also re-apply every monitor.
    fake_bin = Path(directory) / "fake-bin"
    fake_bin.mkdir()
    calls = Path(directory) / "hyprctl-calls"
    (fake_bin / "hyprctl").write_text(f'#!/bin/sh\nprintf "%s\\n" "$*" >> "{calls}"\n', encoding="utf-8")
    (fake_bin / "hyprctl").chmod(0o755)
    reloading = {key: value for key, value in env.items() if key != "CORTETSU_SKIP_RELOAD"}
    reloading["PATH"] = f'{fake_bin}:{env["PATH"]}'
    subprocess.run([str(script), "set", "-n", "nebula", "default"], env=reloading, check=True)
    assert calls.read_text(encoding="utf-8").splitlines() == ["reload config-only"], calls.read_text()
    missing = subprocess.run([str(script), "set", "-n", "no-such-scheme", "default"], env=reloading,
                             text=True, capture_output=True)
    assert missing.returncode == 1 and "esquema no encontrado" in missing.stderr
    assert calls.read_text(encoding="utf-8").splitlines() == ["reload config-only"], "a failed set reloads nothing"
    assert json.loads((Path(directory) / "cortetsu/scheme.json").read_text(encoding="utf-8"))["name"] == "nebula"

    installed = Path(directory) / "bin/cortetsu-scheme"
    installed.parent.mkdir()
    shutil.copy2(script, installed)
    installed_catalog = subprocess.run(
        [str(installed), "list"],
        env={**env, "CORTETSU_REPOSITORY": str(REPO)},
        check=True,
        text=True,
        capture_output=True,
    )
    assert sum(len(flavours) for flavours in json.loads(installed_catalog.stdout).values()) >= 24
print("PASS: Cortetsu scheme state is first-party and XDG-scoped")

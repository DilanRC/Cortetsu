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
    selected_variant = json.loads((Path(directory) / "cortetsu/scheme.json").read_text(encoding="utf-8"))
    assert selected_variant["schema"] == 2 and selected_variant["origin"] == "manual"
    assert selected_variant["lastSelection"] == {
        "name": "dynamic", "flavour": "default", "variant": "expressive"
    }
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
    assert selected["schema"] == 2
    assert selected["origin"] == "manual"
    assert selected["lastSelection"] == {"name": "aura", "flavour": "default"}
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
    shutil.copy2(REPO / "dist/native/cortetsu-desktop-runtime", installed.parent)
    installed_catalog = subprocess.run(
        [str(installed), "list"],
        env={**env, "CORTETSU_RESOURCE_ROOT": str(REPO / "cortetsu")},
        check=True,
        text=True,
        capture_output=True,
    )
    assert sum(len(flavours) for flavours in json.loads(installed_catalog.stdout).values()) >= 24

    # The wallpaper application path records its authority in the same state
    # file read by Quickshell and the startup watcher.
    home = Path(directory) / "home"
    bin_dir = home / ".local/bin"
    bin_dir.mkdir(parents=True)
    colours = bin_dir / "cortetsu-wallpaper-colours"
    colours.write_text(
        '#!/bin/sh\nprintf \'{"name":"dynamic","flavour":"default","mode":"dark","variant":"tonal-spot","colours":{"primary":"#123456"}}\\n\'\n',
        encoding="utf-8",
    )
    colours.chmod(0o755)
    shutil.copy2(REPO / "cortetsu/bin/cortetsu-scheme", bin_dir / "cortetsu-scheme")
    shutil.copy2(REPO / "dist/native/cortetsu-desktop-runtime", bin_dir / "cortetsu-desktop-runtime")
    wallpaper = Path(directory) / "wallpaper.png"
    wallpaper.write_bytes(b"fake image input")
    state_dir = Path(directory) / "cortetsu"
    state_dir.mkdir(exist_ok=True)
    (state_dir / "scheme.json").write_text(
        json.dumps({"schema": 2, "name": "dynamic", "origin": "wallpaper", "colours": {"primary": "#654321"}}),
        encoding="utf-8",
    )
    apply_env = {**env, "HOME": str(home), "CORTETSU_RESOURCE_ROOT": str(REPO / "cortetsu")}
    subprocess.run(
        [str(REPO / "cortetsu/bin/cortetsu-apply-wallpaper-colors"), str(wallpaper)],
        env=apply_env,
        check=True,
    )
    dynamic = json.loads((Path(directory) / "cortetsu/scheme.json").read_text(encoding="utf-8"))
    assert dynamic["schema"] == 2
    assert dynamic["origin"] == "wallpaper"
    assert dynamic["colours"]["primary"] == "#123456"
print("PASS: Cortetsu scheme state is first-party and XDG-scoped")

#!/usr/bin/env python3
"""Render the eight real Settings pages across themes and display conditions.

Uses the runtime interaction fixture without executing its full scenario suite.
The output directory is explicit; all application state remains temporary.
"""
import argparse
import ast
import json
import os
import subprocess
import tempfile
from pathlib import Path

from settings_harness import REPO, ROOT, build_tree, run


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=False)
    source = Path(__file__).with_name("test-cortetsu-settings-runtime.py")
    tree = ast.parse(source.read_text())
    shell = next(ast.literal_eval(node.value) for node in tree.body
                 if isinstance(node, ast.Assign) and any(
                     isinstance(target, ast.Name) and target.id == "SHELL" for target in node.targets))
    with tempfile.TemporaryDirectory(prefix="cortetsu-visual-") as temporary:
        folder = Path(temporary)
        build_tree(folder)
        (folder / "shell.qml").write_text(shell)
        seed = folder / "palette-state"
        config = seed / "config/cortetsu"
        config.mkdir(parents=True)
        (config / "preferences.json").write_text(json.dumps({"themeIntegrations": {
            "hyprland": False, "kitty": False, "gtk": False, "qt": False}}))
        native = os.environ.get("CORTETSU_SETTINGS_NATIVE_ROOT")
        command = ([str(Path(native) / "cortetsu-desktop-runtime"), "cortetsu-scheme"]
                   if native else [str(ROOT / "bin/cortetsu-scheme")])
        palette_env = {**os.environ, "HOME": str(seed), "XDG_CONFIG_HOME": str(seed / "config"),
            "XDG_STATE_HOME": str(seed / "state"), "XDG_DATA_HOME": str(seed / "data"),
            "CORTETSU_REPO_ROOT": str(REPO), "CORTETSU_SKIP_RELOAD": "1", "GSETTINGS_BACKEND": "keyfile"}
        scheme_path = seed / "state/cortetsu/scheme.json"
        subprocess.run(command + ["reset-theme"], env=palette_env, check=True, capture_output=True)
        for theme in ("ink", "washi", "kurogane"):
            subprocess.run(command + ["theme", theme], env=palette_env, check=True, capture_output=True)
            subprocess.run(command + ["reset-theme"], env=palette_env, check=True, capture_output=True)
            base = json.loads(scheme_path.read_text())
            subprocess.run(command + ["set", "-n", "aura", "default"], env=palette_env,
                           check=True, capture_output=True)
            schemes = {}
            for mode in ("dark", "light"):
                subprocess.run(command + ["set", "--mode", mode], env=palette_env,
                               check=True, capture_output=True)
                schemes[mode] = json.loads(scheme_path.read_text())
            for variant, width, height, scale, transparent, reduced in (
                ("default", 1368, 900, "1", False, False),
                ("narrow", 880, 620, "1", False, True),
                ("fractional", 1100, 720, "1.25", True, False),
                ("transparent", 1368, 900, "1", True, True),
                ("aura-dark", 1368, 900, "1", False, False),
                ("aura-light", 1368, 900, "1", False, True),
            ):
                label = f"{theme}-{variant}"
                scheme = schemes[variant.removeprefix("aura-")] if variant.startswith("aura-") else base
                output, _ = run(folder, "shell.qml", "pages", label=label,
                    preferences={"schema": 1, "themeId": theme,
                                 "transparencyEnabled": transparent, "reducedMotion": reduced},
                    scheme=scheme,
                    env={"CORTETSU_RENDER_DIR": str(args.out.resolve()),
                         "SETTINGS_RENDER_SUFFIX": "-" + label,
                         "SETTINGS_WIDTH": str(width), "SETTINGS_HEIGHT": str(height),
                         "QT_SCALE_FACTOR": scale})
                assert "SETTINGS_RUNTIME_PASS 8" in output, output
                (args.out / f"{label}.log").write_text(output)
                print("PASS", label, flush=True)
    images = list(args.out.glob("*.png"))
    assert len(images) == 144, len(images)
    print(f"PASS: {len(images)} Settings screenshots; visual inspection remains required")


if __name__ == "__main__":
    main()

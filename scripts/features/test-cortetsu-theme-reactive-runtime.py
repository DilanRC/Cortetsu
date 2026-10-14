#!/usr/bin/env python3
"""Runtime check that a scheme change recolours live surfaces without a reload.

The real CortetsuColours, design tokens and CortetsuSurface run against a
temporary state directory. `cortetsu-scheme set` is run for real against that
directory and a throwaway runtime tree, which must stay byte-identical.
"""
import hashlib
import json
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
ROOT = REPO / "cortetsu"

CONFIG = """pragma Singleton
import QtQuick
QtObject { property bool transparencyEnabled: false }
"""

SHELL = """import QtQuick
import Quickshell
import "components"
import "services"
import "theme"

ShellRoot {
    id: root
    property int checks: 0
    property int step: 0
    property int created: 0
    readonly property var colours: CortetsuColours
    readonly property string scheme: Quickshell.env("CORTETSU_TEST_SCHEME")
    function verify(value, reason) { if (!value) { console.log("THEME_FAIL", reason); return; } checks++; }
    function same(a, b) { return Qt.colorEqual(a, b); }

    CortetsuSurface { id: surface; baseColor: CortetsuDesign.colorSurface; Component.onCompleted: root.created++ }
    Rectangle { id: tinted; color: Qt.alpha(CortetsuDesign.colorPrimary, 0.5) }

    Timer {
        interval: 400; repeat: true; running: true
        onTriggered: {
            root.step++;
            if (root.step === 1) {
                root.verify(root.same(CortetsuDesign.colorSurface, "#171B21"), "without a scheme the ui.toml default applies");
                root.verify(root.same(surface.color, "#171B21"), "a surface starts on the default token");
                Quickshell.execDetached([root.scheme, "set", "-n", "nebula", "default"]);
            } else if (root.step === 3) {
                root.verify(CortetsuColours.scheme === "nebula", "the colour service follows the state file");
                root.verify(!root.same(CortetsuDesign.colorSurface, "#171B21"), "the token follows the scheme");
                root.verify(root.same(surface.color, CortetsuDesign.colorSurface), "a live surface repaints");
                root.verify(root.same(tinted.color, Qt.alpha(CortetsuDesign.colorPrimary, 0.5)), "derived colours repaint");
                root.verify(root.same(CortetsuDesign.colorVermillion, "#D64B32"), "semantic danger keeps its ui.toml value");
                root.verify(root.created === 1, "nothing was recreated");
                CortetsuColours.load(JSON.stringify({ colours: { surface: "112233" }, mode: "dark" }), true);
                root.verify(root.same(CortetsuDesign.colorSurface, "#112233"), "a preview palette reaches the tokens");
                CortetsuColours.clearPreview();
                root.verify(!root.same(CortetsuDesign.colorSurface, "#112233"), "clearing the preview restores the scheme");
                root.verify(root.same(CortetsuDesign.role("surface", "#010203"), CortetsuDesign.colorSurface), "roles resolve through one function");
                CortetsuDesign.scheme = { surface: "not-a-colour" };
                root.verify(root.same(CortetsuDesign.colorSurface, "#171B21"), "an invalid value falls back to the default");
                console.log("THEME_RUNTIME_PASS", root.checks);
                Qt.quit();
            }
        }
    }
}
"""


def tree_hash(folder: Path) -> str:
    digest = hashlib.sha256()
    for path in sorted(folder.rglob("*")):
        if path.is_file():
            digest.update(str(path.relative_to(folder)).encode())
            digest.update(path.read_bytes())
    return digest.hexdigest()


with tempfile.TemporaryDirectory(prefix="cortetsu-theme-reactive-") as temporary:
    folder = Path(temporary)
    for name in ("components", "theme"):
        shutil.copytree(ROOT / name, folder / name)
    (folder / "services").mkdir()
    (folder / "modules").mkdir()
    shutil.copy(ROOT / "services/CortetsuColours.qml", folder / "services/CortetsuColours.qml")
    shutil.copy(ROOT / "modules/CortetsuTypography.js", folder / "modules/CortetsuTypography.js")
    (folder / "modules/CortetsuConfig.qml").write_text(CONFIG)
    (folder / "shell.qml").write_text(SHELL)
    runtime = folder / "runtime-root"
    shutil.copytree(ROOT / "theme", runtime / "current/theme")
    shutil.copytree(ROOT / "modules", runtime / "current/modules")
    before = tree_hash(runtime)
    # An installed system always has a state file; start from one without colours.
    (folder / "state/cortetsu").mkdir(parents=True)
    (folder / "state/cortetsu/scheme.json").write_text('{"name": "dynamic", "colours": {}}\n')
    env = {**os.environ, "QT_QPA_PLATFORM": "offscreen", "XDG_STATE_HOME": str(folder / "state"),
           "XDG_CONFIG_HOME": str(folder / "config"), "CORTETSU_RUNTIME_ROOT": str(runtime),
           "CORTETSU_TEST_SCHEME": str(ROOT / "bin/cortetsu-scheme")}
    result = subprocess.run(["quickshell", "-p", str(folder / "shell.qml")], env=env,
                            capture_output=True, text=True, timeout=30)
    output = result.stdout + result.stderr
    assert result.returncode == 0, output
    assert "THEME_FAIL" not in output, output
    assert "THEME_RUNTIME_PASS 12" in output, output
    for marker in ("TypeError", "ReferenceError", "Reloading configuration"):
        assert marker not in output, output
    state = json.loads((folder / "state/cortetsu/scheme.json").read_text())
    assert state["name"] == "nebula" and state["colours"]["surface"], state
    assert tree_hash(runtime) == before, "cortetsu-scheme set must not write inside a runtime generation"

source = (ROOT / "bin/cortetsu-scheme").read_text(encoding="utf-8")
for retired in ("shell\", \"reload", "runtime_design_path", "CortetsuDesign"):
    assert retired not in source, retired

print("PASS: scheme changes repaint live surfaces in place and never touch the promoted generation")

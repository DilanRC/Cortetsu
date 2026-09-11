import json
import os
import shutil
import subprocess
import tempfile
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
colours = (REPO / "cortetsu/services/CortetsuColours.qml").read_text(encoding="utf-8")
assert 'import "../modules/CortetsuDesign.js" as CortetsuDesign' in colours

script = Path(__file__).resolve().parents[2] / "cortetsu/bin/cortetsu-scheme"
with tempfile.TemporaryDirectory() as directory:
    env = {**os.environ, "XDG_STATE_HOME": directory}
    subprocess.run([str(script), "set", "-v", "expressive"], env=env, check=True)
    result = subprocess.run([str(script), "get", "-nfv"], env=env, check=True, text=True, capture_output=True)
    assert result.stdout.splitlines() == ["dynamic", "default", "expressive"]
    listed = subprocess.run([str(script), "list"], env=env, check=True, text=True, capture_output=True)
    catalog = json.loads(listed.stdout)
    assert sum(len(flavours) for flavours in catalog.values()) >= 24
    assert "aura" in catalog and "default" in catalog["aura"]

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

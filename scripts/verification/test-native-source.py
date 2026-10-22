#!/usr/bin/env python3
"""Source/package gates for the native runtime; does not install anything."""
from __future__ import annotations
import hashlib
import json
from pathlib import Path
import re
import tomllib

ROOT = Path(__file__).resolve().parents[2]
manifest = tomllib.loads((ROOT / "cortetsu.toml").read_text())
assert manifest["schema"] == 4
assert manifest["project"]["stage"] == "native-runtime-generations"
assert manifest["system"]["components"] == ["shell", "dotfiles", "helpers"]
assert manifest["identity"]["canonical_command"] == "cortetsu"
archive = ROOT / "tests/reference/python-runtime"
frozen = json.loads((archive / "MANIFEST.json").read_text())
assert len(frozen["files"]) == 49
for item in frozen["files"]:
    assert hashlib.sha256((archive / item["path"]).read_bytes()).hexdigest() == item["sha256"], item["path"]

names = set()
for line in (ROOT / "cortetsu/native-helpers.tsv").read_text().splitlines():
    if not line or line.startswith("#"):
        continue
    name, binary, dispatcher = line.split("\t")
    assert name not in names
    names.add(name)
    source = (ROOT / "cortetsu/bin" / name).read_text()
    assert source.startswith("#!/usr/bin/env bash\n")
    assert f'exec "$BUNDLE/{binary}" ' in source
    assert not re.search(r"\bpython[0-9.]*\b", source)
assert len(names) >= 28

for folder in (ROOT / "core", ROOT / "cortetsu/bin", ROOT / "cortetsu/services"):
    if not folder.exists():
        continue
    for path in folder.rglob("*"):
        if not path.is_file() or "__pycache__" in path.parts or any(p.startswith(".") for p in path.relative_to(folder).parts):
            continue
        assert path.suffix != ".py", path
        assert not path.read_bytes()[:128].split(b"\n")[0].startswith((b"#!/usr/bin/env python", b"#!/usr/bin/python")), path
packages = tomllib.loads((ROOT / "packages/arch.toml").read_text())
for group in packages["group"].values():
    assert not any(p == "python" or p.startswith("python-") for p in group.get("packages", []))
for path in ("scripts/install-cortetsu.sh", "scripts/cortetsu", "cortetsu/bin/build-runtime.sh"):
    assert not re.search(r"(^|\s)python3\s", (ROOT / path).read_text(), re.M), path
print(f"PASS: {len(names)} stable native entrypoints; zero runtime Python; {len(frozen['files'])} exact archived test oracles")

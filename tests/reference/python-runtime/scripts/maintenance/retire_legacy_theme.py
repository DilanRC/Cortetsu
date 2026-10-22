#!/usr/bin/env python3
from __future__ import annotations

import os
import shutil
from datetime import datetime, timezone
from pathlib import Path

TARGETS = (
    Path(".config/kitty/caelestia-theme.conf"),
    Path(".config/caelestia/templates/kitty-cortetsu.conf"),
    Path(".local/state/caelestia/theme/kitty-cortetsu.conf"),
)


def data_root() -> Path:
    return Path(os.environ.get("CORTETSU_DATA_ROOT", Path.home() / ".local/share/cortetsu")).expanduser()


def backup_one(source: Path, destination: Path) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    if source.is_symlink():
        try:
            resolved = source.resolve(strict=True)
        except OSError:
            os.symlink(os.readlink(source), destination)
        else:
            if resolved.is_file():
                shutil.copy2(resolved, destination)
            else:
                os.symlink(os.readlink(source), destination)
    elif source.is_file():
        shutil.copy2(source, destination)
    else:
        raise RuntimeError(f"no se retira automáticamente un directorio u objeto especial: {source}")


def main() -> int:
    home = Path.home()
    existing = [home / rel for rel in TARGETS if (home / rel).exists() or (home / rel).is_symlink()]
    if not existing:
        print("Cortetsu legacy theme: already retired")
        return 0

    stamp = datetime.now(timezone.utc).strftime("%Y%m%d-%H%M%S")
    backup = data_root() / "migrations" / stamp / "retired-theme"
    retired = 0
    for target in existing:
        rel = target.relative_to(home)
        destination = backup / rel
        backup_one(target, destination)
        if target.is_symlink() or target.is_file():
            target.unlink()
        retired += 1
        print(f"RETIRED legacy-theme={target}")

    print(f"BACKUP retired-theme={backup}")
    print(f"Cortetsu legacy theme: retired={retired}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

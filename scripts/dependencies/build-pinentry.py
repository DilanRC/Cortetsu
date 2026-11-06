#!/usr/bin/env python3
"""Build the reviewed pinentry 1.3.3 fix into an explicit, unused file."""
from __future__ import annotations

import argparse
import hashlib
import os
from pathlib import Path
import shutil
import subprocess
import tarfile
import tempfile

SHA256 = "c2970f16d6afb66ecddfca767d743936c86239bff936eed7fd7597a678414b63"
ROOT = Path(__file__).resolve().parents[2]


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--archive", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args()
    if args.out.exists() or args.out.is_symlink():
        parser.error("--out must name an unused file")
    if hashlib.sha256(args.archive.read_bytes()).hexdigest() != SHA256:
        parser.error("archive is not the reviewed pinentry 1.3.3 tarball")
    output = args.out.absolute()
    with tempfile.TemporaryDirectory(prefix="cortetsu-pinentry-build-") as temporary:
        build = Path(temporary)
        with tarfile.open(args.archive) as archive:
            archive.extractall(build, filter="data")
        source = build / "pinentry-1.3.3"
        subprocess.run(["patch", "--batch", "--forward", "-p1", "-i",
                        str(ROOT / "cortetsu/patches/pinentry-1.3.3-session-bus.patch")],
                       cwd=source, check=True)
        subprocess.run(["./configure", "--disable-pinentry-qt", "--disable-pinentry-qt5",
                        "--disable-pinentry-gtk2", "--disable-pinentry-fltk",
                        "--disable-pinentry-tty", "--disable-pinentry-curses",
                        "--enable-fallback-curses", "--enable-pinentry-gnome3"],
                       cwd=source, check=True)
        subprocess.run(["make", "-j2"], cwd=source, check=True)
        with output.open("xb") as target:
            with (source / "gnome3/pinentry-gnome3").open("rb") as binary:
                shutil.copyfileobj(binary, target)
            os.fchmod(target.fileno(), 0o755)
    print(output)


if __name__ == "__main__":
    main()

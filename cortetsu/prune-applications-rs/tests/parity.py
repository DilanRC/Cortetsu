#!/usr/bin/env python3
"""Compare frozen Python and the native application quarantiner."""
from __future__ import annotations

import os
from pathlib import Path
import subprocess
import tempfile
import sys

REPO = Path(__file__).resolve().parents[3]
PYTHON = REPO / 'tests/reference/python-runtime/cortetsu/bin/cortetsu-prune-applications'
RUST = REPO / 'cortetsu/prune-applications-rs/target/release/cortetsu-prune-applications-rs'

FIXTURES = {
    'valid-absolute.desktop': '[Desktop Entry]\nType=Application\nName=Valid\nExec=/bin/true\n',
    'valid-relative.desktop': '[Desktop Entry]\nName=Valid 2\nExec=env FOO=bar sh -c "echo ok"\n',
    'missing.desktop': '[Desktop Entry]\nType=Application\nName=Missing\nExec=not-a-real-cortetsu-binary-2940283\n',
    'unclosed-quote.desktop': '[Desktop Entry]\nExec=\'unterminated\n',
    'field-code.desktop': '[Desktop Entry]\nExec=%u\n',
    'empty-exec.desktop': '[Desktop Entry]\nName=No command\n',
    'unrecognized.desktop': '[Desktop Entry]\nType=Link\nExec=does-not-exist\n',
    'outside-section.desktop': '[Not An App]\nType=Application\nExec=does-not-exist\n',
    'duplicate.desktop': '[Desktop Entry]\nExec=/bin/true\nExec=missing-replaced-last\n',
    'commented.desktop': '[Desktop Entry]\n# comment\nExec=/bin/true\n',
    'colon.desktop': '[Desktop Entry]\nExec: /bin/true\n',
    'default.desktop': '[DEFAULT]\nExec=/bin/true\n[Desktop Entry]\nName=Inherited\n',
    'default-link.desktop': '[DEFAULT]\nType=Link\n[Desktop Entry]\nExec=does-not-exist\n',
    'indented-keys.desktop': '[Desktop Entry]\n  Name=Indented\n  Exec=/bin/true\n',
    'bad-before.desktop': 'not a section\n[Desktop Entry]\nExec=does-not-exist\n',
    'bad-after.desktop': '[Desktop Entry]\nExec=does-not-exist\n[Other]\nmalformed line\n',
    'section-comment.desktop': '[Desktop Entry] # trailing comment\nExec=/bin/true\n',
    'dollar-escape.desktop': '[Desktop Entry]\nExec="literal\\$binary"\n',
    'multiline.desktop': '[Desktop Entry]\nExec=env\n  /bin/true\n',
}


def call(executable: Path, root: Path, *args: str) -> subprocess.CompletedProcess[str]:
    env = os.environ.copy()
    env['HOME'] = str(root)
    env['XDG_DATA_HOME'] = str(root / 'data')
    env['PATH'] = str(root / 'commands') + os.pathsep + env.get('PATH', '')
    return subprocess.run(([sys.executable, str(executable)] if executable == PYTHON else [str(executable)]) + list(args), env=env, text=True,
                          capture_output=True, check=False, timeout=8)


def files(root: Path, location: str) -> set[str]:
    return {p.name for p in (root / 'data' / location).glob('*.desktop')}


with tempfile.TemporaryDirectory(prefix='cortetsu-prune-parity-') as tmp:
    base = Path(tmp)
    roots = [base / 'python', base / 'rust']
    for root in roots:
        apps = root / 'data/applications'
        apps.mkdir(parents=True)
        commands = root / 'commands'
        commands.mkdir()
        program = commands / 'literal\\$binary'
        program.write_text('#!/bin/sh\nexit 0\n')
        program.chmod(0o700)
        for name, body in FIXTURES.items():
            (apps / name).write_text(body, encoding='utf-8')
    if not RUST.is_file():
        raise SystemExit('Build Rust helper before running parity')
    results = [call(exe, root, '--dry-run') for exe, root in zip([PYTHON, RUST], roots)]
    assert all(result.returncode == 0 for result in results), results
    detected = [sorted(Path(line).name for line in result.stdout.splitlines()) for result in results]
    assert detected[0] == detected[1], detected
    expected = {'missing.desktop', 'unclosed-quote.desktop', 'field-code.desktop',
                'empty-exec.desktop', 'duplicate.desktop'}
    assert set(detected[0]) == expected, detected
    assert files(roots[0], 'applications') == files(roots[1], 'applications')
    results = [call(exe, root) for exe, root in zip([PYTHON, RUST], roots)]
    assert all(result.returncode == 0 for result in results), results
    assert files(roots[0], 'applications') == files(roots[1], 'applications')
    assert files(roots[0], 'cortetsu/quarantine/applications') == expected
    assert files(roots[1], 'cortetsu/quarantine/applications') == expected
    results = [call(exe, root) for exe, root in zip([PYTHON, RUST], roots)]
    assert [r.stdout.strip() for r in results] == ['No hay entradas de usuario rotas.'] * 2

print('PASS: Python/Rust application quarantine parity with isolated XDG homes')

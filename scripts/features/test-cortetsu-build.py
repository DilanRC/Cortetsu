#!/usr/bin/env python3
"""Native E2E gate: real installer, two sealed schema2 generations and rollback.

Python is only this test driver. Every child installer/CLI runs with a whitelist
PATH containing no Python interpreter. Qt Quick Test remains real and mandatory;
only systemctl is replaced to isolate the fixture from the host user manager.
"""
from __future__ import annotations
import argparse
import json
import os
import shutil
import subprocess
import tempfile
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]

def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument('--native-bundle', type=Path, default=REPO / 'dist/native')
    parser.add_argument('--qml-runner', type=Path, default=Path('/usr/lib/qt6/bin/qmltestrunner'))
    args = parser.parse_args()
    bundle = args.native_bundle.resolve()
    if not (bundle / 'cortetsu-platform').is_file():
        subprocess.run([str(REPO / 'scripts/build-native.sh')], cwd=REPO, check=True,
                       env={**os.environ, 'CORTETSU_NATIVE_OUTPUT': str(bundle)})
    assert args.qml_runner.is_file(), 'Qt Quick Test is required for the native installation gate'
    with tempfile.TemporaryDirectory(prefix='cortetsu-native-e2e-') as temporary:
        root = Path(temporary)
        fixture = root / 'repository'
        shutil.copytree(REPO, fixture, symlinks=True,
                        ignore=shutil.ignore_patterns('.git', 'target', 'dist', '__pycache__', '.pytest_cache'))
        home, data, runtime = root / 'home', root / 'data', root / 'runtime'
        home.mkdir(); runtime.mkdir()
        unmanaged = root / 'unmanaged-runtime'; unmanaged.mkdir()
        (unmanaged / 'shell.qml').write_text('// archived pre-v2 runtime\n')
        (runtime / 'current').symlink_to(unmanaged, target_is_directory=True)
        commands = root / 'commands'; commands.mkdir()
        for name in ('bash', 'sh', 'readlink', 'dirname', 'mkdir', 'mktemp', 'rm', 'chmod',
                     'cp', 'flock', 'git', 'date', 'find', 'sort', 'install', 'mv', 'tr',
                     'awk', 'sed', 'timeout', 'grep', 'tar', 'gzip', 'head', 'ln', 'cut',
                     'stat', 'uname', 'sleep'):
            path = shutil.which(name)
            assert path, f'missing installation dependency: {name}'
            (commands / name).symlink_to(path)
        control = commands / 'systemctl'
        control.write_text('''#!/bin/sh
printf '%s\\n' "$*" >> "$CORTETSU_SYSTEMCTL_LOG"
case "$*" in
  *is-enabled*|*is-active*|*'cat mako.service'*) exit 1 ;;
  *'show -p Transient'*) printf 'no\\n' ;;
esac
exit 0
''')
        control.chmod(0o755)
        assert shutil.which('python3', path=str(commands)) is None
        assert shutil.which('python', path=str(commands)) is None
        env = {**os.environ, 'HOME': str(home), 'PATH': str(commands),
               'XDG_CONFIG_HOME': str(home / '.config'),
               'XDG_DATA_HOME': str(home / '.local/share'),
               'XDG_STATE_HOME': str(home / '.local/state'),
               'XDG_CACHE_HOME': str(home / '.cache'),
               'XDG_RUNTIME_DIR': str(root / 'xdg-runtime'),
               'CORTETSU_DATA_ROOT': str(data), 'CORTETSU_RUNTIME_ROOT': str(runtime),
               'CORTETSU_REPO_ROOT': str(fixture), 'CORTETSU_REPOSITORY': str(fixture),
               'CORTETSU_QMLTESTRUNNER': str(args.qml_runner.resolve()),
               'CORTETSU_SKIP_RELOAD': '1', 'CORTETSU_SYSTEMCTL_LOG': str(root / 'systemctl.log')}
        for key in ('QT_QPA_PLATFORMTHEME', 'DBUS_SESSION_BUS_ADDRESS', 'WAYLAND_DISPLAY',
                    'DISPLAY', 'HYPRLAND_INSTANCE_SIGNATURE', 'CORTETSU_RESOURCE_ROOT',
                    'CORTETSU_INSTALL_TRANSACTION', 'CORTETSU_NATIVE_OUTPUT'):
            env.pop(key, None)
        Path(env['XDG_RUNTIME_DIR']).mkdir(mode=0o700)
        installer = fixture / 'scripts/install-cortetsu.sh'
        cli = home / '.local/bin/cortetsu'
        def run(*arguments: str | Path, success: bool = True) -> subprocess.CompletedProcess[str]:
            result = subprocess.run(list(map(str, arguments)), cwd=fixture, env=env,
                                    text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
            if result.returncode != 0 and success:
                raise AssertionError(f'failed {arguments!r}:\n{result.stdout}')
            if not success:
                assert result.returncode != 0, f'unexpected success: {arguments!r}'
            return result
        def install(success: bool = True) -> None:
            result = run(installer, '--native-bundle', bundle, success=success)
            print(result.stdout, end='')
        def pointers() -> dict[str, Path]:
            return {name: (path / label).resolve(strict=True)
                    for name, path, label in (
                        ('system', data / 'system', 'current'), ('shell', runtime, 'current'),
                        ('dotfiles', data / 'dotfiles', 'current'), ('helpers', data / 'helpers', 'current'))}
        def resource() -> Path:
            return Path(run(home / '.local/bin/cortetsu-resource-root').stdout.strip())
        def verify() -> None:
            run(cli, 'verify'); run(home / '.local/bin/cortetsu-rescue', 'verify')
        install()
        a = pointers()
        assert (runtime / 'legacy-previous').resolve(strict=True) == unmanaged
        assert not (runtime / 'previous').exists()
        assert resource() == a['shell']
        payload = json.loads((a['system'] / 'SYSTEM.json').read_text())
        assert payload['schema'] == 2 and payload['nativeRuntime'] is True
        assert payload['helpersManifestSha256'] and payload['shellManifestSha256']
        assert (a['shell'] / 'data/emojis.txt').is_file()
        verify()
        run(home / '.local/bin/cortetsu-scheme', 'set', '-n', 'aura', 'default')
        selected_scheme = (home / '.local/state/cortetsu/scheme.json').read_bytes()
        assert json.loads(selected_scheme)['name'] == 'aura'
        install()
        b = pointers()
        assert all(a[key] != b[key] for key in a), (a, b)
        assert (data / 'system/previous').resolve(strict=True) == a['system']
        assert resource() == b['shell']
        assert (home / '.local/state/cortetsu/scheme.json').read_bytes() == selected_scheme
        verify()
        for file in (b['helpers'] / 'cortetsu-resource-root', b['shell'] / 'components/CortetsuButton.qml'):
            before = file.read_bytes()
            file.write_bytes(before + b'\n// deliberate test corruption\n')
            run(cli, 'verify', success=False)
            run(home / '.local/bin/cortetsu-rescue', 'verify', success=False)
            file.write_bytes(before)
        verify()
        run(cli, 'rollback')
        assert pointers() == a
        assert resource() == a['shell']
        assert (data / 'system/previous').resolve(strict=True) == b['system']
        assert (home / '.local/state/cortetsu/scheme.json').read_bytes() == selected_scheme
        verify()
        # A real error after helper/shell activation must trigger the EXIT undo
        # journal and restore every pointer; no host service was invoked yet.
        ui = fixture / 'dotfiles/home/.config/cortetsu/ui.toml'
        ui_before = ui.read_bytes()
        ui.write_bytes(b'not valid TOML = [')
        install(success=False)
        assert pointers() == a
        assert resource() == a['shell']
        assert json.loads((data / 'install-journal.json').read_text())['phase'] == 'RECOVERED'
        ui.write_bytes(ui_before)
        verify()
        run(cli, 'recover')
        assert pointers() == a
        service_calls=(root / 'systemctl.log').read_text()
        assert 'restart cortetsu-wallpaper-color.service' in service_calls
        assert 'restart cortetsu-shell.service' not in service_calls
        print('PASS: native installation, two schema2 generations, sealed assets/helpers, all-layer rollback and failed-install recovery without Python on PATH')

if __name__ == '__main__':
    main()

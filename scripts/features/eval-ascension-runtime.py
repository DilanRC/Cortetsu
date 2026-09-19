#!/usr/bin/env python3
"""Opt-in live popup eval. Drives the desktop; saves evidence in /tmp.

Pass threshold: every connected monitor passes open, Tab, Escape, rapid
reopen and final close. Images require human visual review separately.
"""
import json
import subprocess
import tempfile
import time
from pathlib import Path


def run(*args):
    return subprocess.check_output(args, text=True).strip()


runtime = str(Path.home() / '.config/quickshell/cortetsu/current')


def ipc(*args):
    return run('qs', 'ipc', '-p', runtime, 'call', 'bottomHub', *args)


def state(name):
    return next(s for s in json.loads(ipc('inspect')) if s['screen'] == name)


def key(code):
    run('ydotool', 'key', '--key-delay', '0', f'{code}:1', f'{code}:0')


monitors = json.loads(run('hyprctl', 'monitors', '-j'))
cursor = json.loads(run('hyprctl', 'cursorpos', '-j'))
evidence = Path(tempfile.mkdtemp(prefix='cortetsu-ascension-eval-'))
results = []
try:
    for monitor in monitors:
        name = monitor['name']
        run('hyprctl', 'dispatch', 'movecursor', str(monitor['x'] + 500), str(monitor['y'] + 400))
        time.sleep(.15)
        ipc('control', 'network')
        time.sleep(.25)
        assert state(name)['open'] and state(name)['focus'], state(name)
        key(15)  # Tab
        run('grim', '-o', name, str(evidence / f'{name}-focus.png'))
        key(1)  # Escape
        ipc('control', 'bluetooth')  # Before the previous exit finishes.
        time.sleep(.3)
        current = state(name)
        assert current['open'] and not current['closing'] and current['popup'] == 'bluetooth', current
        run('grim', '-o', name, str(evidence / f'{name}-reopen.png'))
        key(1)
        time.sleep(.25)
        assert not state(name)['open'], state(name)
        results.append({'screen': name, 'open_focus_tab_reopen_close': 'PASS'})
finally:
    run('hyprctl', 'dispatch', 'movecursor', str(cursor['x']), str(cursor['y']))
    (evidence / 'results.json').write_text(json.dumps(results, indent=2) + '\n')
print(json.dumps({'results': results, 'evidence': str(evidence)}, indent=2))

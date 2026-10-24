from pathlib import Path
import re

root = Path(__file__).resolve().parents[2]
source = (root / 'cortetsu/modules/CortetsuHypr.qml').read_text(encoding='utf-8')
assert re.search(r'function\s+onRawEvent\s*\(\s*event\s*\)\s*:\s*void\s*\{', source), (
    'Hyprland raw-event handler is missing'
)
assert re.search(r'HyprEventPolicy\.refreshPlan\s*\(\s*name\s*\)', source), (
    'raw-event handler does not use the event policy'
)
for flag, call in (
    ('refreshMonitors', 'Hyprland.refreshMonitors'),
    ('refreshWorkspaces', 'Hyprland.refreshWorkspaces'),
    ('refreshToplevels', 'root.refreshToplevelsFromEvent'),
):
    assert re.search(
        rf'if\s*\(\s*plan\.{flag}\s*\)\s*{re.escape(call)}\s*\(', source
    ), f'raw-event handler does not wire plan.{flag} to {call}'
assert not re.search(r'name\s*\.includes\s*\(\s*["\']window["\']\s*\)', source), (
    'raw-event handler still classifies title aliases through includes("window")'
)
print('PASS: raw Hyprland event handling delegates refresh decisions to the tested policy')

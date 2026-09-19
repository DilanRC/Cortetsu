# Cortetsu Ascension

Branch: `ascension/product-elevation`. Original baseline: `032a37a`.
Status: WORKING. This is an incremental product elevation, not a new migration.

## Runtime baseline, 2026-09-06

Repository tests and promoted generation verification passed. Doctor had no
required failures. The shell was active with NRestarts=0 and ExecMainStatus=0.
Two real outputs were available: a 144 Hz laptop panel and a 60 Hz HDMI output.
Mako had acquired the notification bus during earlier shell failures. Stopping
its already-disabled user service allowed the running shell to acquire the
bus immediately; a real notify-send toast confirmed delivery. No package or
notification preference was removed.

Visual inspection covered the hub, launcher, utilities/quick settings,
notification toast/center, network, audio, Bluetooth, battery, keyboard, lock
indicators, active-window/details and overview. Baseline PNGs are local under
`/tmp/cortetsu-ascension-*.png`; desktop captures can contain private content
and are not committed. Tray/submenu and OSD remain to inspect.

Observed gaps: popup scale collapses to zero; stale close can dismiss a rapid
reopen; Audio devotes excessive height to outputs; lock indicator labels are
missing; overview cards overflow the available height; notification removal
does not retain delegates through exit motion. Tooltips now share one
first-party contract across BottomHub, the application rail, the tray and
status pills.

## First checkpoint: popup lifetime and motion

Opening explicitly cancels pending close, including detached-to-attached
handoff. Screen-space anchor calculations are unchanged. Entry uses the
existing standard token and exit uses the fast token; closing retains content
and anchor for that same exit duration. Travel is 12 px, scale stays between
0.975 and 1, and opacity handles disappearance. Hover and press have distinct
feedback. CortetsuAnim now respects fast/default/slow spatial and effect types.

`bottomHub inspect` is a read-only IPC snapshot for monitor ownership, popup
lifetime and root focus. `test-ascension-motion.js` runs actual opening function
bodies against a deterministic timer fixture. It catches the original stale
close even when hasCurrent is already true. Run the live eval explicitly:

```sh
python3 scripts/features/eval-ascension-runtime.py
```

This drives Tab/Escape and rapid reopen on each connected output, restores the
cursor, writes screenshots/results to a unique /tmp directory and fails unless
all monitor cases pass. It does not substitute screenshots for motion review
or claim that root focus proves every descendant focus state.

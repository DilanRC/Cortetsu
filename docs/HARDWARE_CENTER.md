# Cortetsu Hardware Center

Branch: `feature/hardware-center`

## Goal

Native, theme-adaptive hardware dashboard opened with `Super+H`. It lives inside
Caelestia's existing drawer `ContentWindow`, so mouse/touchpad/keyboard input
uses the same native surface as Launcher, Overview and Clipboard.

## Resource model

- `HardwareController.qml` is always loaded and only tracks open/close state.
- `hardware/Wrapper.qml` keeps `Content.qml` loaded on each screen. The page
  shown is created on demand and destroyed when another tab is selected.
- `hardware/HardwareTelemetry.qml` is the only source of main telemetry. It owns
  the probe process, its timer, the reading and the histories; pages bind to it
  and start nothing themselves.
- Main telemetry samples every 1500 ms while the panel is visible and not at all
  while it is closed. The last reading and its histories are kept for reopening.
- A sample carries the five most active processes. Only the Processes page asks
  for the whole table, which is about 98 % of a full sample (125 KB against 4 KB).
- `status` is `loading`, `live`, `stale` (a run failed, an older reading is still
  shown) or `error` (no run has produced a reading). A run that outlives four
  intervals is ended and reported as a failure.
- Power and Energy pages use an on-demand power helper only while those pages exist.
- Automatic AC/battery switching is separate and **disabled by default**. It
  starts `cortetsu-power-auto.service` only after explicit user opt-in on page 7.

## Pages

1. **Resumen** — the verdict first, then the machine. See "Summary page" below.
2. **Rendimiento** — CPU, memory, network, disk and one graph per GPU, each with its scale and min/average/max. The newest sample sits at the right edge and a short history starts there instead of being stretched. CPU cycles Total → Núcleo 0 → Núcleo 1…; memory toggles cache/swap.
3. **Procesos** — sortable table (CPU, memory, PID, name) over every readable process, multi-term search, list freeze, `Up`/`Down`/`PageUp`/`PageDown` selection and a detail panel with Pausar/Reanudar, Interrumpir, Terminar and Forzar cierre. Forzar cierre needs a second press within four seconds.
4. **Sensores** — temperatures against their limits, load per core, fan RPM and battery readings. A sensor the machine does not expose says so instead of showing zero.
5. **E/S** — root filesystem, block devices with throughput, IOPS and totals, and the network interface with rates, totals, IPv4, MAC and Wi-Fi data.
6. **Energía** — Power Profiles choice (three options, the active one marked), CPU driver/governor/EPP/platform profile, AC and battery state, and one panel per GPU.
7. **Automatización** — optional AC/battery/low-battery profile rules, the low-battery threshold, current state and the last five events. Disabled until explicitly enabled.
8. **Consumo** — battery/CPU/GPU power figures and their histories, battery energy and health, and the estimated remaining or charge time when the kernel exposes enough data.
9. **Atajos** — installed-app search, launcher metadata, application icons, direct reassignment and confirmed deletion with automatic snapshots.
10. **Arranque** — inventory of XDG autostart, user/system systemd units, Hyprland Lua startup callbacks and Cortetsu-owned processes, filtered by source and state chips. XDG user entries and manageable user units can be disabled for future logins; system units and source-owned entries are read only.

Every page is built from the same three pieces: `Panel.qml` (the glass
surface), `FactRow.qml` (label and value, "No disponible" when the value is
empty) and `HistoryGraph.qml`. Values go through `Format.js`, so an unknown
reading never renders as `0` or `NaN`. Lists that follow a reading use an
index or a keyed `ScriptModel`, so rows update in place.

Keyboard: `1`–`9` switches current pages, `0` opens Arranque, `R` refreshes main telemetry and `Esc` closes.
`Tab` walks the header buttons, the tabs and then every block of the page in
reading order; `Enter`, `Return` or `Space` activates the focused one.
There is also an explicit close button. Clicking empty space inside the panel does
not close it; only clicking outside the panel, `Esc`, the close button or
`Super+H` closes/toggles it.

Arranque scans when its page opens or when **Actualizar** is selected. It shows
system services read only and keeps XDG global files untouched by writing a
user override. User systemd toggles affect the next login; an active process is
left running. Active user services offer a separate **Detener ahora** action
with explicit confirmation. Every successful action is re-scanned and recorded
without copying command arguments into the history.

Cortetsu process starts are declared by component in
`cortetsu/bin/cortetsu-startup`, with startup phase, condition, command and live
execution state kept separately. The drift test covers bound `running` states,
`Component.onCompleted` starts, startup timers, detached commands and helper
calls reached from those startup callbacks. Each producer marks its registry
entry in QML. Dynamic commands that cannot be matched exactly show an unknown
execution state. On-demand queries stay labeled as on-demand and are excluded
from autostart counts.
`enabled` is persistent and `enabled-runtime` is temporary. `linked` and
`linked-runtime` only make a unit available through a symlink; they do not
enable automatic start, so Arranque labels them as linked and groups them with
special, non-toggleable states. `static`, `indirect`, `generated`, `transient`
and `alias` are also non-toggleable. Target relationships are shown as
installation configuration only for `enabled` or `enabled-runtime` units.
`TriggeredBy` shows possible socket/timer/path activators without claiming they
caused a past run. Startup inventory refreshes on demand and Hardware Center
telemetry polling stops when the panel closes.

For read-only systemd inspection, use `show`, `is-enabled`, `list-unit-files`,
`cat` and `list-dependencies`. Never use `systemctl enable --dry-run` or
`systemctl disable --dry-run` as read-only checks; those operations can change
unit symlinks.

Keybind changes are written only to the user's Caelestia files. Every change
creates a snapshot under `~/.local/share/cortetsu/upstream/snapshots/keybinds/`.
If Hyprland rejects the reload or the new combination is missing, the helper
restores the previous files automatically.

## Summary page

It answers four questions in this order: is everything fine, how is the machine
now, does anything need attention, and where to go to act on it.

1. **Verdict.** `Health.js` evaluates the reading against fixed limits and
   returns a level and a list of issues. Each issue names the metric, its value
   and the page that explains it; the page owns the wording. The strip reads
   "Todo en orden" when nothing is flagged, and otherwise lists each issue as a
   row that opens its page. A reading that stopped updating is announced there
   with a retry.
2. **Load.** CPU usage with temperature, frequency, load average and the last
   two minutes of history, then one row per detected GPU.
3. **Capacity.** Memory and root disk as levels: how full, how much, what is left.
4. **Busiest processes.** Up to five, with CPU and resident memory.
5. **Context.** Power profile and battery, active network and its rates, fan speeds.

Every block opens the page that explains it. The destination is named on hover
and on keyboard focus.

Limits, as `[warning, critical]`:

| Metric | Limit | Opens |
| --- | --- | --- |
| CPU temperature | 90 / 97 °C | Sensores |
| GPU temperature, per GPU | 85 / 92 °C | Sensores |
| Memory in use | 90 / 96 % | Procesos |
| Root disk in use | 90 / 96 % | E/S |
| Battery while discharging | 20 / 10 % | Energía |

They sit above what this laptop reaches under ordinary load. A missing sensor is
never an issue, and a missing reading is never drawn as zero: the figure is left
out and the rest of the line closes up.

Updates are incremental. A new reading changes bound properties; the page, the
GPU rows and the process rows are not rebuilt. Issue rows are created only when
the number of issues changes.

States: first reading (loading), no reading (error with retry), stale (last
reading dimmed, retry in the verdict strip) and live.

## Telemetry

`~/.local/bin/cortetsu-hardware-probe [--top-processes N]` provides:

- CPU total/per-core usage, average frequency, package temperature and governor.
- RAM used/available/cache/buffers plus swap.
- Root filesystem usage.
- Physical block-device throughput, IOPS and cumulative read/write totals, with model/serial where exposed by sysfs.
- AMD telemetry from `/sys/class/drm`.
- NVIDIA telemetry from `nvidia-smi` when available.
- Battery percentage/status/power.
- Active network interface, RX/TX rates/totals, IPv4/MAC and Wi-Fi SSID/signal/link bitrate when available.
- Exposed fan RPM values.
- All readable `/proc` processes with instantaneous CPU deltas, RAM, user, state, threads, parent PID, elapsed time and command line. The UI performs filtering/sorting locally so PID/name/command searches can find idle processes too. With `--top-processes N` only the N most active are emitted; every process is still scanned so the next sample has correct deltas. `process_count` always reports the number scanned.
- Host, kernel, uptime and load average.

`~/.local/bin/cortetsu-hardware-power` provides:

- `powerprofilesctl` backend/current/available/degraded state.
- AC sources and battery energy, health, voltage, draw and runtime estimates.
- CPU scaling driver, governor, EPP, frequency range, ACPI platform profile and package power if hwmon exposes it.
- AMD runtime/performance/power state.
- NVIDIA P-state, clocks, temperature, draw and power limit when available.

All unavailable fields degrade to `null`/empty values rather than aborting the UI.

## Safe power controls

Manual and automatic profile changes are strictly limited to:

- `power-saver`
- `balanced`
- `performance`

Hardware Center does not write governors, EPP, platform profiles, GPU clocks,
voltages or GPU power limits directly. It delegates supported profile changes to
`powerprofilesctl` and verifies the resulting profile.

## Automatic power rules

Automation uses:

- `~/.local/bin/cortetsu-power-auto`
- `~/.local/bin/cortetsu-power-auto-control`
- `~/.config/systemd/user/cortetsu-power-auto.service`
- `~/.config/cortetsu/power-auto.json`
- `~/.local/state/cortetsu/power-auto-events.jsonl`

Defaults:

- AC: `performance`
- Battery: `balanced`
- Battery <= 25%: `power-saver`
- Poll: 4 seconds
- Enabled: `false`

`Apply current rule once` works while automation is disabled and does not enable
the background service. Event history is capped by the watcher and can be cleared
from the UI.

## btop relationship

The interaction model takes inspiration from btop resource histories, process
filter/sort/detail/signal controls, network auto-scaling, disk I/O and sensors.
No btop C++/terminal UI source is vendored or launched. Cortetsu uses its own
`/proc`/`/sys` collectors and native QML.

Reference: https://github.com/aristocratos/btop

## Theme

The UI reads `CortetsuDesign.*` tokens and `CortetsuTypography.js` sizes, so it
follows the active scheme without a reload. No independent accent palette is
maintained.

## Install / update

First installation:

```fish
cd ~/Cortetsu
git switch feature/hardware-center
git pull --ff-only
bash scripts/features/install-hardware-center.sh
```

Development update after native integration already exists:

```fish
cd ~/Cortetsu
git pull --ff-only
bash scripts/features/update-hardware-center.sh
```

Both paths validate telemetry/helpers. The full installer snapshots native files
before changing them. Neither path enables automatic power switching by itself.

## Validation / diagnostics

Repository + helper validation:

```fish
python3 scripts/features/validate-hardware-center.py
```

Summary page behaviour, with a scripted probe and no access to this machine's
readings (set `CORTETSU_RENDER_DIR` to keep a PNG of each state):

```fish
python3 scripts/features/test-cortetsu-hardware-home-runtime.py
```

Live installation, hashes, probes, IPC, systemd and QML log check:

```fish
python3 scripts/features/diagnose-hardware-center.py
```

The feature is considered merge-ready when validation is `OK`, live hashes match,
all eight pages open without QML errors, process controls work on a disposable
process, profile switching verifies, and Auto remains opt-in across an update.

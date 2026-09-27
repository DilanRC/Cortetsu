# Cortetsu Hardware Center

Branch: `feature/hardware-center`

## Goal

Native, theme-adaptive hardware dashboard opened with `Super+H`. It lives inside
Caelestia's existing drawer `ContentWindow`, so mouse/touchpad/keyboard input
uses the same native surface as Launcher, Overview and Clipboard.

## Resource model

- `HardwareController.qml` is always loaded and only tracks open/close state.
- `hardware/Wrapper.qml` owns a `Loader` whose `active` state follows the panel.
- Main telemetry, graphs and page QML exist only while Hardware Center is open.
- Main telemetry refreshes every 1500 ms while open.
- Power and Energy pages use an on-demand power helper only while those pages exist.
- Closing Hardware Center destroys the polling/UI tree.
- Automatic AC/battery switching is separate and **disabled by default**. It
  starts `cortetsu-power-auto.service` only after explicit user opt-in on page 7.

## Pages

1. **Overview** — CPU, RAM, root storage, AMD/NVIDIA GPUs, battery/network and cooling. CPU can switch `% / GHz`; memory defaults to GiB and can switch `GiB / %`.
2. **Performance** — rolling CPU/RAM/network/NVMe/GPU graphs with visible scales and min/average/max. CPU cycles Total → Core 0 → Core 1…; RAM toggles cache/swap history.
3. **Processes** — live table, multi-term filtering, CPU/RAM/PID sorting, `123 / %`, list freeze, detail view and Pause/Resume, Interrupt, Terminate and Force kill controls. Search operates on every readable process from `/proc`, including sleeping/low-CPU processes rather than only the most active rows.
4. **Sensors** — per-core CPU load, CPU/GPU thermals and power, fan RPM and battery sensor data.
5. **I/O** — root filesystem and physical block-device throughput, IOPS and totals plus network rates/totals, IPv4, MAC and Wi-Fi metadata.
6. **Power** — manual Power Profiles switching plus CPU driver/governor/EPP/platform profile, AC/battery state, AMD runtime power state and NVIDIA P-state/clocks/power.
7. **Auto** — optional AC/battery/low-battery profile rules with verified actions and a small persistent event history. Automation remains disabled until explicitly enabled.
8. **Energy** — rolling battery/CPU/AMD/NVIDIA power histories, battery energy/health and estimated remaining/charge time when the kernel exposes enough data.
9. **Keybinds** — installed-app search, automatic launcher metadata, real application icons, direct reassignment and confirmed deletion with automatic snapshots.
10. **Inicio** — inventory of XDG autostart, user/system systemd units, Hyprland Lua startup callbacks and Cortetsu-owned processes. XDG user entries and manageable user units can be disabled for future logins; system units and source-owned entries are read only.

Keyboard: `1`–`9` switches current pages, `0` opens Inicio, `R` refreshes main telemetry and `Esc` closes.
There is also an explicit close button. Clicking empty space inside the panel does
not close it; only clicking outside the panel, `Esc`, the close button or
`Super+H` closes/toggles it.

Inicio scans when its page opens or when **Actualizar** is selected. It shows
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
`enabled`/`linked` are persistent;
`enabled-runtime`/`linked-runtime` are temporary; states such as `static`,
`indirect`, `generated`, `transient` and `alias` are not toggleable. Target
relationships are described as installation configuration. `TriggeredBy`
shows possible socket/timer/path activators without claiming they caused a past
run. Startup inventory refreshes on demand and Hardware Center telemetry polling
stops when the panel closes.

Keybind changes are written only to the user's Caelestia files. Every change
creates a snapshot under `~/.local/share/cortetsu/upstream/snapshots/keybinds/`.
If Hyprland rejects the reload or the new combination is missing, the helper
restores the previous files automatically.

## Telemetry

`~/.local/bin/cortetsu-hardware-probe` provides:

- CPU total/per-core usage, average frequency, package temperature and governor.
- RAM used/available/cache/buffers plus swap.
- Root filesystem usage.
- Physical block-device throughput, IOPS and cumulative read/write totals, with model/serial where exposed by sysfs.
- AMD telemetry from `/sys/class/drm`.
- NVIDIA telemetry from `nvidia-smi` when available.
- Battery percentage/status/power.
- Active network interface, RX/TX rates/totals, IPv4/MAC and Wi-Fi SSID/signal/link bitrate when available.
- Exposed fan RPM values.
- All readable `/proc` processes with instantaneous CPU deltas, RAM, user, state, threads, parent PID, elapsed time and command line. The UI performs filtering/sorting locally so PID/name/command searches can find idle processes too.
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

The UI uses `Colours.palette.*`, `Colours.tPalette.*` where appropriate and
`Tokens.*`; no independent accent palette is maintained.

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

Live installation, hashes, probes, IPC, systemd and QML log check:

```fish
python3 scripts/features/diagnose-hardware-center.py
```

The feature is considered merge-ready when validation is `OK`, live hashes match,
all eight pages open without QML errors, process controls work on a disposable
process, profile switching verifies, and Auto remains opt-in across an update.

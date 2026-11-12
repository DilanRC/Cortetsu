# Cortetsu Display Manager

The display manager lives in **Settings → Sistema → Pantalla**
(views in `cortetsu/modules/settings/display/`, the logic that runs the tools in
`cortetsu/services/Display*.qml`). There is no separate editor surface:
`Super+Shift+O`, the IPC target `display` (`qs ipc call display open`) and the
launcher's "Pantallas" action keep the `displayManager` surface key, and
`modules/display/Wrapper.qml` turns that request into Settings opened on that
page on the same screen.

## Page

| File | Role |
|---|---|
| `DisplayPage.qml` | Composition: arrangement, selected output, brightness and colour, apply, diagnostics, saved arrangements. |
| `DisplayModel.qml` | Live inventory (`cortetsu-display-probe`), the proposal being edited, dry run (`cortetsu-display-plan`). |
| `DisplayTransaction.qml` | Preview 15 s → Conservar / Revertir → Guardar, through `cortetsu-display-transaction` and `cortetsu-display-persist`. |
| `DisplayArrangement.qml` | Outputs drawn to scale; click selects, drag moves with edge snapping, Left/Right change the selection. |
| `DisplayPresetStore.qml` | Named arrangements (`cortetsu-display-presets`); loading one only fills the proposal. |
| `DisplayLayout.js` | Pure helpers (modes, resolutions, rates, rotation, snapping, reflow, quick layouts), tested by `scripts/features/test-settings-display-layout.mjs`. |

What the page offers is what the probe reports. Resolutions and refresh rates
are the output's own `available_modes`; VRR appears only where
`vrr_capable` is `true`; HDR, wide gamut and 10-bit stay hidden while the probe
reports them as unknown. Saturation is offered on every output Hyprland has
active; NVIDIA outputs also offer Digital Vibrance through nVibrant.

Previsualizar first runs the dry-run planner and previews only an accepted
proposal. Changing the proposal after Conservar requires a new preview before
Guardar is offered.

## Saturation per output

- **Every output, any GPU** (eDP-1 and DP-1 on AMD, HDMI-A-1 on NVIDIA):
  `cortetsu-display-vibrance` generates the screen shader Hyprland runs on
  every output. The shader receives `wl_output` (the Hyprland monitor id),
  so it holds one strength per output: `-100` greys out, `0` leaves colour
  untouched, `16` is the default (the strength of the hand-written shader
  it replaced), `100` is the maximum. Dull colours move most; saturated ones
  are protected. The profile lives in `~/.local/state/cortetsu/vibrance.json`;
  the shader in `screen-shader.glsl` next to it, which `hypr-user.lua` names
  so a Hyprland reload reads the same thing (no screen shader until the
  `hyprland.start` hook writes it the first time). A change sets a content-hashed copy through
  `hyprctl eval`, because only a new path makes Hyprland recompile, and is
  verified with `getoption`. Hyprland startup, `monitor.added` and
  `monitor.removed` run `apply`, since monitor ids change on hotplug. No
  extra render pass: the screen shader already ran on every output.
- **Why not a colour matrix**: `hyprland-ctm-control-v1` rejects negative
  coefficients, so a CTM can lower saturation but never raise it, and only
  one client may hold it (hyprsunset does). Hyprland's `sdrsaturation` only
  applies in HDR mode.
- **NVIDIA outputs, in addition**: nVibrant writes Digital Vibrance through
  the NVIDIA driver. `cortetsu-nvibrant status` reads sysfs only (never runs
  nvibrant, never wakes the dGPU) and reports `value` (what the profile wants)
  apart from `applied` (what nvibrant echoed in this boot). nvibrant has no
  read-back, so "confirmado" means "echoed in this boot". It cannot reach
  AMD outputs. `nvibrant-bin` comes from the AUR (`yay -S nvibrant-bin`,
  not `pacman`); 1.3.1 bundles the exact `615.78.08` build.

## Safety model

`cortetsu-display-probe` is read-only.

`cortetsu-display-plan` is dry-run only and always reports `"applied": false`.

The preview transaction follows this sequence:

1. validate the whole candidate again;
2. snapshot the currently live layout;
3. write a runtime transaction state under `$XDG_RUNTIME_DIR`;
4. apply only the generated `hyprctl keyword monitor ...` commands;
5. verify output presence, scale and position;
6. start a detached watchdog;
7. automatically restore the snapshot after 15 seconds unless `Keep` is pressed;
8. restore immediately when `Revert` is pressed or when application/verification fails.

The watchdog runs in its own process group, independent of QML, so closing Settings or restarting the shell during a preview does not defeat the timeout rollback.

`Conservar` keeps the arrangement for the current Hyprland session. `Guardar` is offered only for the exact proposal that was previewed and kept; `cortetsu-display-persist` then writes it to Cortetsu's managed monitor block with a backup and verification, and never touches the user's own Lua outside that block.

No normal Display Manager action edits EDID data, creates arbitrary modelines, overclocks a GPU, writes color calibration blindly or leaves an unconfirmed monitor layout permanent.

## Files

- `cortetsu/bin/cortetsu-display-probe`, `-plan`, `-transaction`, `-persist`, `-presets` (native owner: `hardware-runtime-rs/src/display.rs`)
- `cortetsu/modules/DisplayController.qml` (shortcut, IPC)
- `cortetsu/modules/display/Wrapper.qml` (redirect to Settings)
- `cortetsu/modules/settings/display/` (the page) and `cortetsu/services/DisplayModel.qml`, `DisplayTransaction.qml`, `DisplayPresetStore.qml`, `DisplayLayout.js`

## Open and verify

It ships with the shell (`scripts/cortetsu install`). Open it with
`Super+Shift+O`, `qs ipc call display open` or Settings → Sistema → Pantalla.

```fish
node scripts/features/test-settings-display-layout.mjs   # arrangement helpers
python3 scripts/features/test-cortetsu-settings-runtime.py  # includes the "display" scenario
~/.local/bin/cortetsu-display-probe | jq
~/.local/bin/cortetsu-display-transaction status | jq
```

The runtime harness drives the page against display tool doubles with a real
preview deadline: dry run, preview with countdown, Conservar, Guardar and
Revertir.

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
reports them as unknown. Saturation is offered only on the output nVibrant
drives (an NVIDIA output); other outputs say why it is not available.

Previsualizar first runs the dry-run planner and previews only an accepted
proposal. Changing the proposal after Conservar requires a new preview before
Guardar is offered.

## Saturation per GPU

- **NVIDIA outputs** (HDMI-A-1 on the HP Victus): nVibrant writes Digital
  Vibrance through the NVIDIA driver. `cortetsu-nvibrant status` reads sysfs
  only (never runs nvibrant, never wakes the dGPU) and reports `value` (what
  the profile wants) apart from `applied` (what nvibrant echoed in this boot).
  nvibrant has no read-back, so "confirmado" means "echoed in this boot", not
  a hardware readout. Installed `nvibrant-bin` 1.3.0 bundles builds up to
  driver 615.71.09 and falls back to it on 615.78.08; 1.3.1 (2026-11-08) adds
  the exact `615.78.08` build.
- **AMD outputs** (the eDP-1 panel): not offered. Hyprland documents
  `sdrsaturation` only for SDR content while the output is in HDR mode
  (`cm = "hdr"`); there is no documented per-output saturation for an SDR
  output (wiki.hypr.land/configuring/core/monitors/colors, read 2026-11-09).
  A colour transform matrix could do it, but it is the mechanism the colour
  filter (hyprsunset) already owns, so a second owner would fight it. The
  page says the output is not compatible and why.

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

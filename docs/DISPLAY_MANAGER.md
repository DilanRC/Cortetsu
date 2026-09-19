# Cortetsu Display Manager

Branch: `feature/display-manager`

Reserved bind: `Super+Shift+O`.

Display Manager reuses the same native `ContentWindow` integration model as Hardware Center. The controller is always light; the display editor/probes are loaded only while the panel is open.

## Current implementation

Implemented:

- native `DisplayController.qml` + `display/Wrapper.qml` integration;
- `Super+Shift+O` and IPC target `display`;
- monitor inventory from `hyprctl -j monitors all`;
- workspace inventory from `hyprctl -j workspaces`;
- DRM connector → card → GPU vendor mapping from `/sys/class/drm`;
- current geometry, refresh, scale, transform, DPMS, VRR/current-format fields when Hyprland reports them;
- topology canvas based on candidate logical coordinates;
- per-output candidate mode, scale and X/Y editing;
- current workspace, DPMS and GPU/card visibility;
- `cortetsu-display-plan`: validates a complete candidate and renders the exact Hyprland monitor commands without executing them;
- `cortetsu-display-transaction`: timed live preview with automatic rollback;
- explicit `Preview 15s`, `Keep` and `Revert` controls;
- shared `CortetsuButton` interaction states for header and safe-apply actions,
  including keyboard focus and shared tooltips;
- full installer, development updater and validator.

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

The watchdog is independent of the QML panel, so closing Display Manager does not defeat the timeout rollback.

`Keep` currently means **keep for the current Hyprland session**. Persistence across login/reboot is deliberately not enabled until the managed `hypr-user.lua` write path is implemented with its own snapshot/rollback QA.

No normal Display Manager action edits EDID data, creates arbitrary modelines, overclocks a GPU, writes color calibration blindly or leaves an unconfirmed monitor layout permanent.

## Files

- `cortetsu/bin/cortetsu-display-probe`
- `cortetsu/bin/cortetsu-display-plan`
- `cortetsu/bin/cortetsu-display-transaction`
- `cortetsu/modules/DisplayController.qml`
- `cortetsu/modules/display/Wrapper.qml`
- `cortetsu/modules/display/Content.qml`
- `cortetsu/modules/display/Editor.qml`
- `cortetsu/modules/display/PreviewControls.qml`
- `scripts/features/install-display-manager.sh`
- `scripts/features/update-display-manager.sh`
- `scripts/features/validate-display-manager.py`

## Install

```fish
cd ~/Cortetsu
git switch feature/display-manager
git pull --ff-only
bash scripts/features/install-display-manager.sh
```

Restart Caelestia and open:

```text
Super+Shift+O
```

or:

```fish
qs -c caelestia ipc call display open
```

## Validation

```fish
python3 scripts/features/validate-display-manager.py
~/.local/bin/cortetsu-display-probe | jq
~/.local/bin/cortetsu-display-transaction status | jq
```

Before testing a modified layout, first use **Dry run candidate**. Then `Preview 15s` may apply it temporarily. If no confirmation occurs, the watchdog restores the original live layout.

## Next implementation block

The next block is persistence and presets:

- convert a confirmed candidate to managed `hl.monitor({...})` entries;
- snapshot `~/.config/caelestia/hypr-user.lua` before every persistence attempt;
- replace only a Cortetsu-owned monitor block rather than arbitrary user Lua;
- reload and verify;
- restore the previous file and live layout if verification fails;
- named layouts such as Laptop only, Desk dual-monitor and external-display presets;
- workspace-range reassignment only after monitor persistence is proven.

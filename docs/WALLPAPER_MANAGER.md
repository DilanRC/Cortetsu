# Wallpaper Manager

`SUPER + SHIFT + W` opens the native Cortetsu Wallpaper Manager on the focused screen. The Bottom Hub thumbnail opens it on that Hub's screen.

The manager uses the first-party `CortetsuWallpapers` service for preview, apply, random and category metadata. It never invokes a second wallpaper command or assumes a wallpaper directory. Previewed dynamic colours remain owned by `CortetsuWallpapers` and `CortetsuColours`.

Apply is a shared transaction across Wallpaper Manager and Launcher. The service marks the request as pending, invokes `cortetsu-wallpaper-select`, and completes only when the XDG state file reports the requested path. A bounded timeout emits failure, clears the pending state and releases the preview colour lock. Wallpaper Manager emits its short Cosmic pulse only from the success signal; Launcher remains open while applying, disables duplicate wallpaper requests and closes only after the matching success acknowledgement.

V2 opens neutrally: it reselects `Wallpapers.actualCurrent`, aligns the orbit and focus, and does not preview. Path resolution uses an exact match first, then a basename only when it identifies one list entry, so canonical symlink paths remain safe and duplicate names never select arbitrarily. Explicit navigation coalesces wheel and touchpad deltas at 120 angle units or 40 pixel units. Each event emits at most one move and leaves a residual below its threshold; the preview timer uses `ui.toml`'s `wall_utility.orbit_motion` token and previews only the final stable candidate. Navigation replacement, category/model changes, close, Apply and Random cancel it. Cancel and every other-overlay exit call `stopPreview`.

Wall Utility BCDE ownership is declared in `cortetsu/contracts/wall-utility.json`. `CortetsuWallpapers.qml` owns the apply transaction and the ACK from `cortetsu/wallpaper/path.txt`; `CortetsuShellState.forScreen(screen)` owns the monitor-local surface; `WallpaperController.open(screen)` is the BottomHub entry point and `openActive()` is the active-monitor entry point. The Cosmic brand pulse is emitted only after a confirmed successful apply.

Overlay exclusion is global across screens. A native shortcut, drawer toggle, gesture, controller or Bottom Hub action that opens any competing retained overlay closes Wallpaper Manager on every screen. Opening Wallpaper Manager clears competing overlays on every screen.

V2.1 uses a floating orbit instead of the former full opaque panel. A light `m3scrim` preserves contrast while the real desktop remains visible; only categories and metadata/actions use translucent `m3surfaceContainerHigh` surfaces. The orbital view has one central crossfading crop and at most eleven octagonal satellite images. The selected image is never duplicated in the orbit. Scale, opacity, z-order and outlines derive from orbit depth and hover state.

Images load asynchronously at bounded source sizes through the shared Qt image cache. A prefetch window capped at 18 thumbnails warms only six entries beyond the visible budget, even for a 300-item model. Entry motion is latched until the current hero and seven essential thumbnails are `Ready` or `Error`, so incomplete geometry is never presented; subsequent navigation keeps the manager visible while textures swap. Metadata distinguishes `Current` from `Preview`, truncates long filenames, and keeps Apply primary and Random secondary.

## Installation and rollback

Do not run deployment during development. Default staging never writes a live target:

```bash
python3 scripts/features/install-wallpaper-manager.py --stage /tmp/cortetsu-wallpaper-stage
```

`update-wallpaper-manager.py` has the same stage-only contract and refuses to overwrite an existing stage.

At an approved deployment use explicit `--apply`; it validates all exact targets, wires a temporary copy with `display,wallpaper`, and prepares `Wallpapers.qml` fail-closed. A pristine v2.3.0 service receives the patch. A service that already has every V1 generation, cancellation, queue, request-token, and stale-result guard is retained unchanged for a V1→V2 upgrade. Any partial or conflicting service aborts before backup or replacement. Before changing a live target, the installer writes the complete backup manifest; replacements use same-filesystem temporary files plus `os.replace`. Any post-mutation exception automatically restores the manifest before failing. The installer then preflights launcher JSON and writes a timestamped manifest-backed backup before replacing any target:

```bash
python3 scripts/features/install-wallpaper-manager.py --apply --production \
  --live /etc/xdg/quickshell/caelestia \
  --usercfg /home/dilan/.config/caelestia/shell.json \
  --hypr-usercfg /home/dilan/.config/caelestia/hypr-user.lua \
  --backup-root /home/dilan/.local/share/cortetsu/upstream/snapshots
```

Run the privileged file install as Dilan, not through a root environment with an implicit `$HOME`; use `pkexec env HOME=/home/dilan ...` or an equivalent sudo command with all three explicit user paths above.

Rollback restores that timestamped backup, including `services/Wallpapers.qml`, the owned modules, `hypr-user.lua`, and `shell.json`:

```bash
python3 scripts/features/install-wallpaper-manager.py --rollback /path/to/wallpaper-manager-timestamp
```

The deployed V2.1 rollback point is `/home/dilan/.local/state/cortetsu/backups/wallpaper-manager-20260831-180047-459217`.

The configurator itself is idempotent, preserves file mode, and creates no backup when no change is required.

## Gates

```bash
for script in scripts/features/test-*.py scripts/features/validate-*.py scripts/features/eval-*.py; do
  PYTHONDONTWRITEBYTECODE=1 python3 "$script"
done
QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -input cortetsu/modules/wallpaper/tests/TestOrbit.qml
```

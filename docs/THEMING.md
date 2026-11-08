# Cortetsu theming architecture

## State and precedence

The compiled defaults come from `dotfiles/home/.config/cortetsu/ui.toml`.
`platform-rs/templates/theme-profiles.json` supplies Ink, Washi and Kurogane.
The theme compiler emits `CortetsuDesignDefaults.js`, `CortetsuDesign.qml`,
`ThemeProfiles.js` and `ThemePalettes.json`; generated files are committed.
`cortetsu theme check` checks all of them against their sources.

The effective colour order is **validated user scheme → product profile → Ink
compiled defaults**. `EFFECTIVE_ROLES` in `theme-metadata.json` explicitly maps
each canonical role to its profile token and ui.toml fallback. `SCHEME_ROLES`
maps QML aliases to those roles. Native code consumes the compiled palette data;
it does not parse QML/JavaScript or independently invent toolkit palettes.
Readable foreground roles are resolved against the effective surfaces before
projection, with a rounding margin above 4.5:1. QML retains its contrast guard for
legacy files and temporary previews.

There are two existing configuration owners:

- `~/.local/state/cortetsu/scheme.json`: scheme selection, variant, mode, seed,
  `themeId`, `origin`, per-theme colour snapshots and derived `effectiveColours`.
- `~/.config/cortetsu/preferences.json`: `themePreferences`, material/geometry/font
  overrides, transparency, reduced motion, borders and `themeIntegrations`.

For style tokens the validated user override wins over the theme profile and
compiled default. The compiler also exports the allowed token ranges and font
roles. The UI, preference sanitizer and profile importer share that contract.
No second user configuration file is introduced.

`cortetsu-scheme effective` reports the resolved palette without writing it.
`cortetsu-scheme theme ink|washi|kurogane` saves the current colour snapshot and
restores the selected theme's previous selection. A theme's first selection uses
its own defaults, rather than inheriting another theme's colours. The QML theme
owner waits for the durable native acknowledgement; a projection error cannot
undo that selection. On startup the native theme ID recovers an interruption
between native commit and the preference write. The same watcher observes a
subsequent CLI theme change.

`set -n NAME FLAVOUR` records a fresh seed and detects the selected palette's
mode. `set -v VARIANT` and `set --mode light|dark` generate Material roles from
that seed. `source auto|manual` changes ownership explicitly. Automatic wallpaper
updates require `smartScheme` and an automatic/theme-owned palette; a manual
selection wins over an automatic write under `scheme.lock`. Invalid persistent
JSON fails closed. Wallpaper application uses `sync-projections` afterwards.

## Destination matrix

| Destination | Effective input and mutable output | Application | Restoration |
| --- | --- | --- | --- |
| Quickshell | `effectiveColours` plus profile/user style tokens | Reactive bindings, no reload | Cancel preview or restore saved theme |
| Hyprland | `~/.config/hypr/scheme/current.lua` | `hyprctl reload config-only`; no compositor restart or monitor operation | Baseline file plus config-only reload |
| Kitty | `$XDG_STATE_HOME/cortetsu/kitty-colors.conf` | New windows; existing windows need Kitty config reload (`Ctrl+Shift+F5`) | Baseline overlay, never `kitty.conf` |
| GTK 3 | `$XDG_STATE_HOME/cortetsu/gtk-colors.css` via the installed token CSS | Applications consuming symbolic GTK roles, often after reopening | Baseline overlay |
| GTK 4/libadwaita | Symbolic CSS where supported; desktop `color-scheme` and nearest supported named accent via GSettings | Application/portal dependent | Previous desktop appearance values and overlay |
| Qt/KDE | `$XDG_DATA_HOME/color-schemes/CortetsuLive.colors`; editable KDE palette selection; active qtengine colour-scheme path | Reopen compatible applications | Restore only the selected scheme/path; preserve unrelated keys |
| qt6ct | Existing configuration is preserved | Not advertised as dynamically integrated unless its consumer is implemented | No mutation |

GTK applications may override symbolic roles. Libadwaita can force a mode and
uses its own supported accent palette; arbitrary RGB uniformity is not promised.
The desktop preferences are the documented [libadwaita appearance mechanism](https://gnome.pages.gitlab.gnome.org/libadwaita/doc/1-latest/styles-and-appearance.html).
The installed session uses `QT_QPA_PLATFORMTHEME=qtengine`; its documented
[`theme.colorScheme` setting](https://github.com/kossLAN/qtengine) consumes the
KDE-format file. Cortetsu does not change the session's platform-theme variable,
install a Qt style, or overwrite the old Caelestia palette.

The sealed Kitty configuration includes the compiled fallback and then the
mutable overlay. Dotfiles staging resolves its XDG state path before computing
the digest. GTK staging similarly appends a percent-encoded file URI to the
compiled token CSS. Imports and paths are part of the sealed generation; runtime
only writes the referenced mutable files. Personal `gtk.css`, Thunar CSS and
sealed `kitty.conf` are never rewritten by a theme change.

## Ownership, failures and recovery

`cortetsu theme adopt` backs up and disables Caelestia terminal/Hyprland/GTK/Qt
mutations. It detaches `kdeglobals` only from a verified Cortetsu generation and
keeps it editable. During normal synchronization only `[General] ColorScheme`
is changed, and only when Cortetsu owns the current selection. qtengine keeps
its style, icon theme, fonts and miscellaneous settings; only `theme.colorScheme`
is changed, with a prior backup. External symlinks at editable destinations are
rejected. The legacy Kitty overlay symlink is atomically replaced without
reading or modifying its target.

`theme-projections.lock` serializes destination work. Each pass reads a fresh
scheme snapshot under `scheme.lock`, then releases the selection lock before
external reloads. A later selection can commit while an earlier reload is slow;
its queued pass reads the latest state. There is no global filesystem transaction
across external applications. Each destination reports its own result.

Writes use a temporary file, fsync and rename, preserve existing file permissions
and skip unchanged contents. A failed projection leaves the prior valid file
when the write did not complete. A failed reload is retried even if its file
already matches. Disabling a destination restores its baseline; restoration
refuses to overwrite a projection edited outside Cortetsu. Restoring Hyprland
also reloads config-only. Toolkit suboperations can apply partially, and an error
remains visible instead of claiming a global rollback.

`$XDG_STATE_HOME/cortetsu/theme-sync.json` is diagnostic state, not another
configuration source. It records per-destination status, applied projection
version and palette hash. States are `applied`, `reopen`, `disabled`,
`unavailable` and `error`; Settings also shows pending/busy states. Malformed integration
preferences do not authorize writes. Backup state lives
under `$XDG_STATE_HOME/cortetsu/theme-backups/`.

## Profiles and previews

Settings previews use `preview-theme ID` and reactive preview tokens. They never
write scheme/preferences or external destinations. Cancel or leaving Appearance
clears the preview. Geometry editors are disabled during preview, so they cannot
accidentally modify the saved theme.

`cortetsu-scheme profile export /absolute/profile.json` creates a new mode-0600
file and refuses to overwrite it. Import accepts regular JSON files of at most
1 MiB, validates theme snapshots, modes, colours, integration booleans and token
ranges before writing. It merges only visual preferences; application commands,
network and power settings remain unchanged. Prior scheme/preferences are
backed up. A preference-write failure compensates the preceding scheme write;
this is not described as a cross-file atomic commit. After import Settings
reloads its preference owner and requests projections.

`reset-theme` backs up the current scheme and restores the selected theme's
palette. Settings also resets its material, geometry, font, transparency, motion
and border overrides. Other themes' snapshots remain available.

Installation seals and verifies the new shell/dotfiles/helpers first, then runs
mutable synchronization separately. A toolkit error does not invalidate the
shell generation. System rollback and mutable destination restoration are
separate operations; disable an integration to restore its pre-integration
baseline, or reapply the desired palette after a generation rollback.

## Verification

- `qmltestrunner -input cortetsu/tests/qml/themes`: precedence, tokens, contrast,
  reduced motion and Bottom Hub material/radii.
- `cargo test --manifest-path cortetsu/desktop-runtime-rs/Cargo.toml --test theme_sync`:
  fresh sessions, theme cycles, mode, preview, import/export, invalid preferences,
  independent failures, unchanged writes, Qt key preservation and reload retries.
- `scripts/features/test-cortetsu-settings-runtime.py`: real Settings controls,
  keyboard, confirmed persistence, profile roundtrip and a new process/XDG runtime.
- `scripts/verification/build-regressions.sh STAGED_RUNTIME`: use a sealed staged
  runtime, never the source tree.

# Cortetsu theming architecture

Cortetsu owns its desktop identity from one declarative source:

`~/.config/cortetsu/ui.toml`

The repository copy under `dotfiles/home/.config/cortetsu/ui.toml` is compiled by `cortetsu/platform-rs/src/theme.rs`. Generated outputs are committed and verified so an installation never rewrites the Git worktree implicitly.

## 1. One source, multiple surfaces

`cortetsu theme compile` derives the following from `ui.toml`:

- `cortetsu/theme/CortetsuDesignDefaults.js`, the token values from `ui.toml`.
- `cortetsu/theme/CortetsuDesign.qml`, the singleton QML reads tokens from. Its colour tokens bind to the active scheme and fall back to the defaults.
- `dotfiles/generated/theme/home/.config/kitty/cortetsu-theme.conf` for Kitty.
- GTK 3 and GTK 4 `cortetsu-colors.css` token files.
- `dotfiles/generated/theme/home/.local/share/color-schemes/Cortetsu.colors` for the KDE palette.

`cortetsu theme check` is a deterministic build check. CI and `cortetsu install` both fail if generated files do not match `ui.toml`.

The palette is intentionally small: sumi, tetsu, washi, indigo, vermillion and muted. Secondary terminal and toolkit colours are derived from those roles instead of becoming additional independent theme sources.

## 2. Ownership boundary with Caelestia

Caelestia remains the exact upstream shell base during the current adapter phase, but it no longer owns the desktop theme surfaces that Cortetsu manages.

On first native-theme installation, `cortetsu theme adopt` backs up `~/.config/caelestia/cli.json` beneath:

`~/.local/share/cortetsu/migrations/<timestamp>/theme-ownership/cli.json`

and disables Caelestia mutations for:

- terminal
- Hyprland
- GTK
- Qt

Other optional Caelestia integrations and the existing postHook are preserved until Cortetsu explicitly replaces them. The migration is idempotent.

Before `cortetsu install` or `cortetsu dotfiles apply` promotes a dotfiles generation, it runs `cortetsu theme adopt`. That detaches a `~/.config/kdeglobals` symlink only when it points into a Cortetsu generation. It preserves the file and backs it up at `~/.local/share/cortetsu/migrations/<timestamp>/theme-ownership/kdeglobals`. External or broken symlinks stop the operation without being modified. A regular `kdeglobals` remains user-editable, and only its `[General] ColorScheme` value is set to `Cortetsu`.

This boundary prevents KDE from writing application settings through a Cortetsu-managed symlink into an immutable dotfiles generation.

## 3. Kitty

The sealed `kitty.conf` has exactly two includes, in this order:

1. `include cortetsu-theme.conf`: the immutable palette generated from `ui.toml`, part of the dotfiles generation.
2. `include ~/.local/state/cortetsu/kitty-colors.conf`: the live scheme overlay. It is mutable state, never part of a generation.

`cortetsu-scheme set -n NAME FLAVOUR` and `cortetsu-apply-wallpaper-colors` rewrite the overlay from `~/.local/state/cortetsu/scheme.json`, and `cortetsu-scheme sync-kitty` rebuilds it on demand. The write is atomic (temporary file plus rename, mode `0644`). Unchanged colours are not rewritten. A scheme with a missing or invalid role fails the sync and keeps the previous file. If the overlay is missing, Kitty logs `Could not find included config file` and uses the `ui.toml` palette. New Kitty windows pick up changes; running windows keep their colours until Kitty reloads its config (`ctrl+shift+f5`).

The runtime scheme file is also the wallpaper watcher's ownership record. New writes use schema `2` and `origin: "manual"` for explicit selections or `origin: "wallpaper"` for generated palettes; manual selections also record `lastSelection` for recovery. `~/.config/cortetsu/preferences.json` owns the `smartScheme` preference. The watcher applies new wallpaper colours only when that preference is not `false` and the current palette is wallpaper-owned or is a legacy unnamed/dynamic palette. A named legacy palette is treated as a manual choice and preserved. Unknown schema-2 origins, unreadable JSON and malformed state fail closed; a bad preference cannot authorize an overwrite. An explicit manual selection can recover a malformed scheme file. Turning off `smartScheme` stops updates without deleting the current palette. This avoids storing a second synchronization flag in `scheme.json` and keeps the preference and palette ownership in their existing files. The watcher's source fingerprint tracks the effective eligibility state, so changing policy takes effect on its next interval without causing a second apply when the wallpaper-owned palette is first written. Manual scheme changes, automatic palette commits and sync-status writes share `scheme.lock`; the native wallpaper writer rechecks ownership under that lock at the write boundary. Therefore a manual choice made during palette generation wins regardless of which operation reached the lock first. `hypr-scheme.lock` serializes the Hyprland projection and reload; it re-reads the latest committed scheme before applying it, so overlapping manual selections cannot leave Hyprland behind the saved state. Kitty sync likewise re-reads the current scheme under `scheme.lock`. A denied stale automatic write exits with status `3` and is treated as a policy skip. The watcher records `wallpaperSync.status` and the wallpaper source fingerprint after an attempted application. It leaves the source pending after a helper failure, reports the failure to the service log, and retries on the next interval.

Nothing in the theme flow writes to `kitty.conf`. It is a symlink into the sealed generation, so an append such as `>> ~/.config/kitty/kitty.conf` writes inside the generation and breaks the dotfiles digest (`dotfiles digest mismatch` in `cortetsu verify`). Scripts that need Kitty colours call `cortetsu-scheme sync-kitty`. `normalize` in `cortetsu/platform-rs/src/imports.rs` owns the header, so `cortetsu-import-desktop` produces it exactly once.

The old runtime includes under `~/.local/state/caelestia/theme/` are not part of the active Kitty path. The imported `caelestia-theme.conf` target is kept for one transition generation only as an inert compatibility artifact; it is not included by Kitty and can be purged after the native theme is verified on the real machine.

## 4. GTK and Thunar

GTK 3 and GTK 4 load `cortetsu-colors.css` before the imported behavioural CSS. The generated token file defines the common GTK/libadwaita colour roles.

Thunar styling consumes those symbolic roles (`@window_bg_color`, `@card_bg_color`, `@accent_color`, `@window_fg_color`) instead of hard-coded Caelestia-era RGB values. This keeps layout/animation customisation independent from palette generation.

## 5. KDE / Qt

The immutable palette file `~/.local/share/color-schemes/Cortetsu.colors` is generated from `ui.toml`. Editable `~/.config/kdeglobals` selects it with:

`ColorScheme=Cortetsu`

KDE continues to own its application preferences in `kdeglobals`; Cortetsu changes only the selected palette. The existing `qt6ct` behavioural configuration is still preserved. A later phase can replace the remaining toolkit adapter behaviour with a dedicated Cortetsu Qt style/plugin without changing the palette source.

## 6. Shell visual contract

Cortetsu-owned QML imports the `theme` directory and reads `CortetsuDesign.<token>` for colour, shape, spacing and motion. `CortetsuColours` watches `~/.local/state/cortetsu/scheme.json` and feeds the scheme (or a preview palette) to the singleton, so `cortetsu-scheme set` and wallpaper palettes repaint live surfaces without a shell reload and without writing into the promoted generation. `SCHEME_ROLES` in `core/theme.py` lists which tokens follow the scheme; vermillion, warning and scrim keep their `ui.toml` value. The generated contract currently exposes:

- sumi / tetsu / washi / indigo / vermillion / muted colours
- small / medium / large radii
- spacing rhythm
- hover scale
- instant / fast / standard / deliberate motion durations
- the ink material (`[material]`): ground opacity, wash strength, grain and hairline, for full surfaces and for popouts
- the type families (`[typography]`): `ui_family` for data and controls, `ink_family` for the serif of the big moments, `kanji_family` for seals and margin marks, read as `CortetsuDesign.fontUi` / `fontInk` / `fontKanji` (sizes stay in `CortetsuTypography.js`; icons stay Material Symbols)

### The ink material

Every surface sits on one material, drawn in one place: `CortetsuInkPanel`. The dashboard, the session, Settings, Hardware, Keyboards, Displays, Clipboard, Wallpaper, Calendar and the notification sidebar use it directly; Quick Settings, the launcher, every bar popout and the polkit, secret and screen-share dialogs reach it through `CortetsuPopupSurface`. Its strengths are the `material.*` tokens and its colours are the scheme roles (sumi ground, primary wash, washi hairline), so:

- a new scheme or wallpaper palette repaints every surface live;
- editing `[material]` in `ui.toml` and running `cortetsu theme compile` changes every surface in the next generation;
- changing how the material looks (a different texture, no wash, a flat ground) is an edit to `CortetsuInkPanel` alone.

`scripts/features/test-cortetsu-ink-material.py` (part of the install gate) fails if a surface paints its own wash, hard-codes a grain strength or a font family, or stops using the shared pieces.

Upstream `Colours` and `Tokens` may still appear in unported Caelestia components. New Cortetsu components should prefer the Cortetsu contract, and existing owned components should migrate progressively until the upstream visual adapter reaches zero.

## 7. Safe editing workflow

Change design intent only in `ui.toml`, then run:

```bash
cortetsu theme compile
cortetsu theme check
./scripts/cortetsu test
```

Commit `ui.toml` and generated outputs together. `cortetsu install` checks the generated contract before building/promoting a system generation, so rollback continues to cover the shell and all managed desktop theme files atomically.

## Product themes in the live shell

`cortetsu/platform-rs/templates/theme-profiles.json` defines Ink, Washi and
Kurogane. The Rust compiler validates token names and emits
`cortetsu/theme/ThemeProfiles.js` together with the design singleton.
`theme check` includes that generated file. Edit the JSON source and compile;
do not edit the generated JavaScript or QML.

Ink supplies no overrides, preserving the compiled design and active scheme.
Washi supplies warm light surfaces, Noto Sans/Noto Serif typography, softer
materials and more space. Kurogane uses steel surfaces, compact density,
smaller radii and shorter motion. Product overrides take precedence over scheme
roles; reduced motion takes precedence over product motion durations.

Settings changes `CortetsuConfig.themeId` through `CortetsuThemes` and the
native `cortetsu-scheme theme` command. The native command saves the selected
theme and its scheme snapshot atomically in `scheme.json`, then acknowledges
the durable state. Hyprland and Kitty projections run as a separate process so
a slow compositor cannot leave the Settings process with an old theme ID.
At startup, Settings reconciles a committed native theme with
`preferences.json`, covering interruption between the native and preference
writes.
`CortetsuColours` binds its compiled token profile to `CortetsuDesign.themeTokens`;
existing objects update in place. Theme ID and per-theme transparency/reduced
motion and wallpaper-sync preferences are saved in `preferences.json`. Invalid
IDs loaded from disk retain Ink. Each theme's scheme, variant and
manual/wallpaper ownership are snapshotted under `themeProfiles` in the native
scheme state and restored when that theme is selected again. Wallpaper updates
preserve these snapshots under the same scheme lock. A malformed snapshot is
rejected before the active state is changed.

The Settings palette-variant selector uses the existing launcher variant
catalog and `cortetsu-scheme set -v`. The native owner regenerates Material
roles from the saved colour seed and light/dark mode, records the selected
variant as a manual choice, then updates the Hyprland and Kitty projections.
`scheme.json` keeps the seed so changing variants does not derive a new seed
from an already-toned role. Legacy files without a seed use their saved
`primary_paletteKeyColor`, then `primary`, as compatibility fallbacks. Settings
disables this selector until a palette exists and confirms the native commit
and projection result. Its scheme-file watcher updates `CortetsuColours` and
the design tokens in place; no shell reload is required.

The launcher uses the same seed-availability rule: it hides variant results
when no usable palette exists and rejects a stale direct activation. The pinned
end-4 `Auto` value is intentionally not represented. Its implementation runs a
separate OpenCV/NumPy classifier over wallpaper pixels before generating a
scheme; Cortetsu currently has no matching image-analysis owner, so exposing
that value would imply behavior Cortetsu cannot provide.

On a fresh install with no colour scheme selected, `scheme.json` can have no
colour roles yet. Switching product themes still applies Cortetsu's compiled
tokens; `sync-projections` leaves Kitty's overlay untouched until a scheme is
selected. On a fresh install no overlay exists, so Kitty uses its static
`ui.toml` palette. A non-empty but incomplete palette remains an error, so
malformed projections are reported rather than silently accepted.

This live selection currently affects Cortetsu's design tokens. Generated
Kitty/GTK/KDE defaults continue to use ui.toml. It does not rewrite promoted
runtime generations or reload the running session.

Palette variants update the live Cortetsu palette and the Hyprland/Kitty
projections. GTK and KDE files remain the generated ui.toml defaults; selecting
a variant does not mutate those immutable toolkit files.

Verification: `qmltestrunner -input cortetsu/tests/qml/themes` checks live token
changes, contrast and reduced motion; `test-cortetsu-settings-runtime.py` drives
the controls, exercises a simulated native commit failure and startup recovery,
then checks saved preferences in a fresh HOME/XDG environment. Its
`paletteVariant` scenarios verify seed-based role changes, manual ownership,
live token updates and restoration in a fresh process. Rust palette tests cover
variant role generation and keep the legacy Tonal Spot fixtures unchanged; Rust
contract tests cover scheme restoration, wallpaper snapshot preservation,
corrupt snapshot rejection, stale requests and acknowledgement while a
Hyprland projection lock is held. Visual certification against end-4 remains a
separate check from the runtime and persistence tests.

# Cortetsu theming architecture

Cortetsu owns its desktop identity from one declarative source:

`~/.config/cortetsu/ui.toml`

The repository copy under `dotfiles/home/.config/cortetsu/ui.toml` is compiled by `core/theme.py`. Generated outputs are committed and verified so an installation never rewrites the Git worktree implicitly.

## 1. One source, multiple surfaces

`cortetsu theme compile` derives the following from `ui.toml`:

- `cortetsu/modules/CortetsuDesign.js` for Cortetsu-owned QML tokens.
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

`kitty.conf` includes only:

`include cortetsu-theme.conf`

The old runtime includes under `~/.local/state/caelestia/theme/` are not part of the active Kitty path. The imported `caelestia-theme.conf` target is kept for one transition generation only as an inert compatibility artifact; it is not included by Kitty and can be purged after the native theme is verified on the real machine.

## 4. GTK and Thunar

GTK 3 and GTK 4 load `cortetsu-colors.css` before the imported behavioural CSS. The generated token file defines the common GTK/libadwaita colour roles.

Thunar styling consumes those symbolic roles (`@window_bg_color`, `@card_bg_color`, `@accent_color`, `@window_fg_color`) instead of hard-coded Caelestia-era RGB values. This keeps layout/animation customisation independent from palette generation.

## 5. KDE / Qt

The immutable palette file `~/.local/share/color-schemes/Cortetsu.colors` is generated from `ui.toml`. Editable `~/.config/kdeglobals` selects it with:

`ColorScheme=Cortetsu`

KDE continues to own its application preferences in `kdeglobals`; Cortetsu changes only the selected palette. The existing `qt6ct` behavioural configuration is still preserved. A later phase can replace the remaining toolkit adapter behaviour with a dedicated Cortetsu Qt style/plugin without changing the palette source.

## 6. Shell visual contract

Cortetsu-owned QML imports `CortetsuDesign.js` for colour, shape, spacing and motion tokens. The generated contract currently exposes:

- sumi / tetsu / washi / indigo / vermillion / muted colours
- small / medium / large radii
- spacing rhythm
- hover scale
- instant / fast / standard / deliberate motion durations

Upstream `Colours` and `Tokens` may still appear in unported Caelestia components. New Cortetsu components should prefer the Cortetsu contract, and existing owned components should migrate progressively until the upstream visual adapter reaches zero.

## 7. Safe editing workflow

Change design intent only in `ui.toml`, then run:

```bash
cortetsu theme compile
cortetsu theme check
./scripts/cortetsu test
```

Commit `ui.toml` and generated outputs together. `cortetsu install` checks the generated contract before building/promoting a system generation, so rollback continues to cover the shell and all managed desktop theme files atomically.

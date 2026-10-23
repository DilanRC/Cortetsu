# Launcher: Zero-Caelestia migration

The launcher used to be built from 9 Caelestia patches stacked on top of
upstream `modules/launcher/*.qml`:

- 5 "base" patches rewrote the widget itself (grid layout, favourites,
  scoped app launching, dock offset, wallpaper-on-top layout):
  `AppList.qml.patch`, `Content.qml.patch`, `ContentList.qml.patch`,
  `Wrapper.qml.patch`, `services__Apps.qml.patch`.
- 4 more patches were stacked **on top of** those (applied later in
  `MANIFEST.tsv` order) purely to swap every remaining
  `GlobalConfig.launcher.*` / `GlobalConfig.general.apps.terminal`
  reference for `CortetsuConfig.*`: `CortetsuConfig.qml.patch` (touched
  `AppList.qml` + `services/Apps.qml`), `CortetsuConfigMore.qml.patch`
  (touched `ContentList.qml` + the now-dead `items/CalcItem.qml`),
  `SearchPreferences.qml.patch` (touched `services/Actions.qml`,
  `services/Schemes.qml`, `services/M3Variants.qml`), and
  `RemainingConfig.qml.patch` (touched `Content.qml` + the now-dead
  `items/AppItem.qml`).

All 9 are gone. The launcher now lives entirely as first-party QML under
`cortetsu/modules/launcher/`, which `cortetsu/bin/build-runtime.sh` copies
straight over whatever the upstream archive + remaining patches produce
(`cp -a cortetsu/modules/. STAGING/modules/` runs *after* patches are
applied). Editing the launcher is now a normal QML edit, not a diff
against a moving upstream target.

## Why `items/AppItem.qml` and `items/CalcItem.qml` were left behind

The original `AppList.qml.patch` replaced the whole `ListView` with a
`GridView` and inlined every delegate (`appDelegate`, `actionDelegate`,
`calcDelegate`, `schemeDelegate`, `variantDelegate`) directly in
`AppList.qml`, dropping `import qs.modules.launcher.items` entirely.
Verified against the exact pinned upstream commit
(`caelestia-shell@24aa15ee`, tag `v2.4.0`): nothing else in the upstream
tree references `AppItem`, `ActionItem`, `CalcItem`, `SchemeItem`, or
`VariantItem` by type name (`WallpaperList.qml` does `import "items"` but
only uses `WallpaperItem`, which is untouched by any of our patches).
Those five files are dead code post-migration. We do not carry them
forward into `cortetsu/modules/launcher/items/`; they stay as
unreferenced, harmless leftovers in the ephemeral upstream build
staging directory.

## Fuzzy search preferences

Upstream `GlobalConfig.launcher.useFuzzy` was a four-key object. Cortetsu keeps
`useFuzzyApps` for applications and variants, `useFuzzyWallpapers` for the
wallpaper picker, and the existing `useFuzzyActions` and `useFuzzySchemes`
preferences now control their matching live launcher searchers. Their
defaults are `true`, matching the prior fuzzy behavior.

`launcher.maxShown` and `launcher.maxWallpapers` are retired: the app grid
scrolls through every result and the wallpaper strip keeps its layout ceiling
of 12. The keys are still read and saved so older preference files round-trip,
but nothing applies them.

## Terminal command: two sources of truth, on purpose (for now)

`GlobalConfig.general.apps.terminal` fed two different consumers:

1. **Hyprland itself** — `dotfiles/home/.config/hypr/variables.lua` sets
   `vars.terminal = "/home/dilan/.local/bin/kitty-tab"`, consumed by
   Hyprland's own keybinds (e.g. `Super+Return`) to spawn an interactive
   terminal session. This is Lua, loaded by Hyprland directly, and is
   **not owned by this task**.
2. **The QML launcher** — `CortetsuConfig.qml`'s `terminalCommand`
   (`list<string>`, default `["kitty"]`) is used by
   `cortetsu/modules/launcher/AppList.qml` (calc "open in terminal") and
   `cortetsu/modules/launcher/services/Apps.qml` (`entry.runInTerminal`
   app launches via `wrap_term_launch.sh`). This needs an argv list, not
   a single string, because it's spliced into `Quickshell.execDetached`
   command arrays alongside extra arguments.

**Decision:** these stay two independently configured values. They are
not accidentally duplicated — they were already two different upstream
fields feeding two different runtimes, `CortetsuConfig.terminalCommand`
already existed before this task, and this migration only removed the
`GlobalConfig` middleman for the QML side. Unifying them (e.g. Hyprland's
Lua reading `terminalCommand[0]` out of `~/.config/cortetsu/preferences.json`
at reload) is a real option, but it means teaching the Hyprland config
loader to parse JSON at startup, which is Hyprland/dotfiles-platform
territory (see `feat(hyprland): zero-caelestia hypr-user.lua/hypr-vars.lua`
and related commits), not launcher territory, and is out of this task's
scope per the coordinator's instructions. **If a future task unifies
Hyprland config loading around `preferences.json`, `vars.terminal` should
be re-pointed at `terminalCommand[0]` then** — flagging here so it isn't
lost.

## Verification

`git archive` at the pinned upstream commit
(`caelestia-shell@24aa15eefdb146350d2548c0a015b04eddbd1008`, tag
`v2.4.0`, matching `caelestia/compatibility.json`) was fetched from the
already-cached local checkout
(`~/.local/share/caelestia-custom-system/upstream-git`), and all 9
retired patches were applied to it in `MANIFEST.tsv` order with real
`patch -p1` (not by hand-reconstructing diffs) to produce the exact
pre-migration output. That output was diffed against
`cortetsu/modules/launcher/*` to confirm behavioural parity, and grepped
to confirm zero `GlobalConfig` references either way (the old patch
stack already fully eliminated `GlobalConfig` from the *built* output —
this migration's value is retiring the 9-patch dependency chain itself,
not reducing a runtime `GlobalConfig` count that was already zero).

Regression coverage: `scripts/features/test-cortetsu-launcher.py` (new),
`scripts/features/test-cortetsu-config.py` (updated to assert against the
first-party files instead of the retired patches), and
`scripts/features/test-launcher-process-scope.py` (updated the same way).
All three are wired into `scripts/cortetsu test`.

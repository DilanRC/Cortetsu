# Cortetsu Settings

The eight-page shell follows the organization of end-4 Settings at
`end-4/dots-hyprland` commit `2f2a376fdb2ad738bf55f693dd0b474b64bb0ab8`.
That repository is GPL-3.0; this adaptation uses Cortetsu's existing QML
primitives and service sections and does not copy its QML implementation.
The pinned reference, license identifier, and per-control mapping are recorded
in [settings-end4-parity.json](settings-end4-parity.json). It covers all 177
controls found in the eight end-4 pages: 28 are adapted to tested Cortetsu
owners and 149 are explicitly discarded because Cortetsu has no equivalent
service or product control. Each discarded entry explains why an end-4-only
option would have no real consumer.

Opened with `Super+I`. A normal desktop window (`FloatingWindow`), one per
screen, so it can be moved, tiled and resized like any other.

## What it answers

1. Where am I, and what is the state of each domain? The Nexus.
2. What does this page control, and what is its value now? The page header and
   each row.
3. Did my change take effect? The switch itself, the row status, the save
   indicator.
4. What needs my attention? A vermillion dot in the Nexus and the reason in
   the page header.

## Flow

```text
SUPER+I
  keybinds.lua: global cortetsu:settings
  Shortcuts.qml: screenState.settings = true (exclusive with other drawers)
  SettingsHost.qml: FloatingWindow.visible; Loader builds Content
  settings/Content.qml
    SettingsContext    live state of every domain, summary and alert per page
    Nexus              end-4 navigation with eight destinations, search, collapse
    Loader             the one page that is selected
      pages/*.qml
        sections/*.qml, NetworkPage.qml (composed by product area)
        controls/*     SettingsGroup, SettingToggleRow, SettingSliderRow,
                       SettingActionRow, SettingValueRow
  services             CortetsuConfig, Schemes, CortetsuColours, Connectivity,
                       CortetsuAudio, CortetsuPower, Brightness,
                       DisplayCalibration, CortetsuNotifications
  persistence          ~/.config/cortetsu/preferences.json
                       ~/.local/state/cortetsu/scheme.json
```

## Pages and retained Cortetsu settings

| Reference page | Composed Cortetsu sections | Backend and saved state |
| --- | --- | --- |
| Quick Settings | Appearance | `Schemes`, `CortetsuColours`, `CortetsuThemes`, `CortetsuConfig`; palette variants regenerate Material roles from the saved seed and mode |
| General | Audio, power, input | PipeWire/audio services, power service, Hyprland keyboard state and `preferences.json` |
| Bar | Bottom Hub | `CortetsuConfig.bottomHub` and bar preferences |
| Background | Wallpaper | Wallpaper service, scheme ownership, `preferences.json` and `scheme.json` |
| Interface | Dashboard, launcher, notifications | Dashboard/launcher services, notification service and `preferences.json` |
| Services | Network, Bluetooth, automation | Connectivity and policy bridge; service state remains owned outside Settings |
| Advanced | Display, shortcuts | Brightness/display calibration and `cortetsu-keybinds`; persisted through the existing owners |
| About | About | Read-only build metadata from the active generation |

The rail and filter route to the eight pages. Existing domain IDs remain valid
as deep links through `SettingsController.pageForSection()`, so older internal
callers still open the correct composed page.

## Resource model

- A closed Settings holds nothing: `SettingsHost` builds `Content` only while
  the window is visible.
- Only the selected page exists. Selecting another destroys it and builds the
  next one. Each of the eight pages composes Cortetsu's existing feature
  sections; the sections keep their original service and persistence owners.
  Domain deep links such as `network` select their containing page (`services`).
  The page that is open is kept in `SettingsController`, so reopening returns
  to it.
- Nothing in Settings polls. The single process a page starts is the read-only
  `cortetsu-keybinds list` of the Shortcuts page, when that page is opened.
- The display colour filter is applied by `services/DisplayCalibration.qml`,
  which lives with the shell and restores a saved filter at start. It no longer
  depends on a Settings page having been built.

## Reactivity contract

A change touches the properties that depend on it and nothing else.

| Change | What updates | What must not happen |
| --- | --- | --- |
| Colour token or scheme | `CortetsuDesign` tokens notify; colours repaint | No page, row, card or Nexus entry is recreated; Settings stays open |
| Scheme applied | `scheme.json` changes; `Schemes.currentScheme` follows it; the selected card moves | No catalogue reload, no second query for the current scheme |
| Catalogue gains or loses a scheme | One `Scheme` object and one card are added or removed | The other cards are not rebuilt |
| Filter text | Cards and rows are hidden | No model is replaced |
| Preference | One property; one write 300 ms after the last change | No write per slider step, no second write |
| Value changed outside Settings | The bound row follows | A dragged slider does not stop following |

`Schemes.currentScheme` is derived from `scheme.json` through `CortetsuColours`,
so a scheme set from the launcher, a terminal or the wallpaper is reflected with
no extra query. `cortetsu-scheme set` asks Hyprland for `reload config-only`:
the Lua config is read again for the border palette and the monitors are left
alone.

## States

A switch is bound to the real value and never flips on its own. Asking for a
change only calls the backend; the switch moves when the backend does.

| State | What is shown |
| --- | --- |
| In flight | The row says "Aplicando…" and ignores further presses |
| Applied | The switch moves; preferences show "Guardado" for two seconds |
| Failed | The switch stays on the real value; the row gives the reason in vermillion; the Nexus flags the page |
| Not available | The control is replaced by "No disponible" or a message saying what is missing; the rest of the page works |
| Save failed | "No se pudo guardar" stays in the header until a later write succeeds |

Destructive actions (clear the notification history, forget a network) need a
second press within four seconds.

## Volume and brightness feedback

Volume and brightness changes show the compact `MiniSlider` for 1.3 seconds.
It reads the confirmed PipeWire or monitor value, so repeated key presses update
the same item. Volume feedback appears only on the active screen; brightness
feedback appears on the screen whose monitor changed. The indicator has no
keyboard or pointer handlers, and its region is removed from the drawer input
mask so clicks pass through. Fullscreen suppresses the compact overlay.

Opening the full Quick Settings OSD remains an explicit action. It requests
OnDemand keyboard focus while open, and Escape closes it without giving focus
to transient volume or brightness feedback.

## Keyboard

| Key | Effect |
| --- | --- |
| `Tab`, `Shift+Tab` | Nexus (search, collapse, current destination), Close, then the page top to bottom. Disabled and read-only rows are skipped |
| `Up`, `Down` in the Nexus | Open the previous or next destination; the focus moves with it |
| `Right` in the Nexus, `Left` in the page | Enter the page, return to the Nexus |
| `Enter`, `Space` | Activate the focused control |
| `Left`, `Right`, `Home`, `End` on a slider | Change the value |
| `Ctrl+F` | Focus the search |
| `Enter`, `Down` in the search | Open the first result |
| `Escape` | Clear the search if it has text; otherwise close Settings |

The focused control is scrolled into view. Below 940 px of content width the
Nexus shows icons only, with the destination and its state in a tooltip.

## What is not shown

A preference appears in Settings only if something in the running shell reads
it. H-45's ten live preferences now affect the launcher, notifications or
toasts, but Settings still does not draw controls for them. Six preferences
that belonged only to the retired top bar were removed from `CortetsuConfig`;
old files load safely and those keys are ignored. `test-cortetsu-settings.py`
fails if a control is wired to a preference with no reader.

## Checks

| Check | What it proves |
| --- | --- |
| `scripts/features/test-cortetsu-settings-runtime.py` | The real surface in Quickshell with service doubles and real key events: object identity through token, scheme, catalogue and preference changes; one page at a time; pending, failed and unavailable states; outside changes; keyboard; no leftover objects after 20 open and browse cycles; UI → owner → persistence → fresh-process restoration for migrated desktop-clock, Bottom Hub app-segment, Fahrenheit and fuzzy-search settings |
| `scripts/features/test-cortetsu-settings.py` | Every destination has a page; every preference written has a reader; one owner for `SUPER+I` |
| `paletteVariant`, `paletteVariantRestore`, `paletteVariantUnavailable` in `scripts/features/test-cortetsu-settings-runtime.py` | The variant control rejects unknown values, regenerates live Material colours from the saved seed, writes manual origin, restores after restart, explains the no-palette state and guards a direct launcher action |
| `migratedControls`, `migratedControlsRestore` in `scripts/features/test-cortetsu-settings-runtime.py` | Four migrated controls update their actual consumers, persist, and restore in a fresh HOME/XDG process |
| `cortetsu/tests/qml/settings/tst_SettingsNavigation.qml` | Search and movement as pure functions |
| `cortetsu/tests/qml/components/tst_StateMessage.qml`, `tst_Slider.qml` | The layout loop and the lost slider binding do not come back |
| `scripts/features/test-cortetsu-scheme.py` | `set` writes the state file and asks for a config-only reload; a failed `set` reloads nothing |

`CORTETSU_RENDER_DIR=<dir>` makes the runtime test save a PNG of every page at
1368 x 900, at 880 x 620 and on the `aura` scheme at 1280 x 800, plus each
failure and unavailable state.

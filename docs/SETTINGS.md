# Cortetsu Settings

Settings is organised like **Windows 11 Settings** (category › subpage ›
controls), draws its controls with the density and vocabulary of **end-4
Settings** (sections with an icon, segmented choices, compact switches,
sliders with their value), and wears **Cortetsu's identity**: the same pages
look like ink, paper or steel depending on the theme.

end-4 (`end-4/dots-hyprland`, GPL-3.0) is a visual reference only. No QML is
copied; every control is Cortetsu's own and uses the existing services. The
earlier per-control mapping is kept in
[settings-end4-parity.json](settings-end4-parity.json).

Opened with `Super+I`. A normal desktop window (`FloatingWindow`), one per
screen, so it can be moved, tiled and resized like any other.

## What it answers

1. Where am I? The sidebar marks the category; the header writes the path,
   "Personalización › Temas", and the category in it leads back.
2. Where is a setting? The search at the top of the sidebar lists each
   matching setting with its place; opening one goes to the page, scrolls to
   the control, focuses it and marks it for a moment.
3. What does this page control, and what is its value now? Each row.
4. Did my change take effect? The control itself, the row status, the save
   indicator.
5. What needs attention? A vermillion dot on the category, and the reason in
   the page header and on the category page.

## Flow

```text
SUPER+I
  Shortcuts.qml: screenState.settings = true (exclusive with other drawers)
  SettingsHost.qml: FloatingWindow; Loader builds Content
  settings/Content.qml
    SettingsContext    live state of every domain; summary and alert per page
    Nexus              sidebar: search, categories, results, compact mode
    SettingsHeader     back, breadcrumb path, summary, save indicator
    PageRegistry       destination id -> page component
    Loader             the one page that is open
      pages/*.qml          Home, category pages, About
      controls/SettingsPage.qml   the shared page container (width contract)
        sections/*.qml     each reads and writes its own service
        controls/*         SettingsGroup, SettingsColumns, SettingChoiceChips,
                           SettingToggleRow, SettingSliderRow, SettingNavRow,
                           SettingActionRow, SettingValueRow, ThemePreview
  SettingsController   category, subpage, history, search, legacy deep links
  persistence          ~/.config/cortetsu/preferences.json
                       ~/.local/state/cortetsu/scheme.json
```

## Categories and subpages

| Category | Subpages |
| --- | --- |
| Inicio | Desktop overview, status tiles, frequent switches, usual pages |
| Sistema | Pantalla, Sonido, Energía y batería, Atajos de teclado, Capturas y grabación |
| Bluetooth y dispositivos | Bluetooth, Teclado y entrada |
| Red e Internet | Wi-Fi (opens directly) |
| Personalización | Temas, Colores, Fondo, Bottom Hub, Paneles laterales |
| Interfaz | Lanzador, Notificaciones, Indicadores y formatos |
| Aplicaciones y servicios | Automatización, Clima |
| Accesibilidad | Movimiento y contraste (opens directly) |
| Avanzado | Sincronización de aplicaciones, Perfiles y recuperación, Diagnóstico |
| Acerca de Cortetsu | Identity, components and their state, credits, documentation |

A category with one subpage opens straight on it; otherwise it shows its own
page: one row per subpage with what it holds and how it stands. Every setting
of the previous eight pages is still present (`test-cortetsu-settings.py`
checks that every preference written has a reader and every section is shown
by some page). Old ids (`quick`, `general`, `bar`, `services`, `audio`,
`appearance`, `wallpaper`, ...) remain valid deep links through
`SettingsController.legacy`.

## Page width contract

Every page sits in `controls/SettingsPage.qml`. A `form` page keeps a readable
column of at most 780 px; a `wide` page (galleries, grids, two columns) at most
1120 px. The column is centred in the main panel, so the free space is equal
on both sides, and `SettingsColumns` puts groups side by side only from 900 px.
The header uses the same column. The runtime test checks, for every
destination and at 1368×900, 880×620 and 1100×720 at scale 1.25: the page fits,
the margins differ by at most 2 px, no visible control leaves the column, and
no category name in the expanded sidebar is cut.

## Theme identity and colour precedence

A theme is more than a palette. `theme-profiles.json` sets, per theme:

| | Ink | Washi | Kurogane |
| --- | --- | --- | --- |
| Material (`materialStyle`) | sumi wash, grain, hairline | paper lit from above, fibres, soft shadow, no edge | matte steel gradient, brushed streaks, crisp outline, bevel, corner marks |
| Headings | Rubik | Noto Serif, weight 500 | Adwaita Sans, small labels in capitals with tracking |
| Geometry | radius 8–28 | soft, 10–24 | angular, 2–8; buttons and chips square |
| Density | row 52 | airy, row 58, sections 40 | compact, row 44, control 30 |
| Motion | 200 ms | 240 ms | 120 ms |

`CortetsuInkPanel` draws the three materials and is under every large
surface and popout, so the identity reaches Settings, Bottom Hub, Dashboard,
launcher, Hardware Center, OSD, popouts and dialogs together.

Colour precedence, resolved once in `cortetsu-scheme effective` and shared by
QML and the native projections:

1. The theme's palette is the base.
2. A selected scheme (manual or from the wallpaper) overrides it. In Ink it
   overrides every role. Washi and Kurogane **own their ground** (background,
   surfaces, text, outlines and terminal colours): the scheme only sets their
   accents, toned until they keep 3:1 on that ground, with containers rebuilt
   from them. Washi stays paper and Kurogane steel with any scheme, and their
   mode is fixed (light and dark respectively).
3. The user's per-theme tokens (Personalización › Temas › Material,
   tipografía y geometría) win over both.

## Resource model

- A closed Settings holds nothing: `SettingsHost` builds `Content` only while
  the window is visible.
- Only the selected page exists. Selecting another destroys it and builds the
  next one. Each subpage composes Cortetsu's existing feature sections; the
  sections keep their original service and persistence owners. Domain deep
  links such as `network` select their subpage (`wifi`).
  The page that is open is kept in `SettingsController`, so reopening returns
  to it.
- Settings adds no resident polling. Explicit palette, projection and profile
  actions run native helpers; Shortcuts requests its keybinding list when opened.
  Saving an integration change schedules synchronization after the preference
  write and drains the request when an existing operation becomes idle.
- The display colour filter is applied by `services/DisplayCalibration.qml`,
  which lives with the shell and restores a saved filter at start. It no longer
  depends on a Settings page having been built.

## Reactivity contract

A change touches the properties that depend on it and nothing else.

| Change | What updates | What must not happen |
| --- | --- | --- |
| Colour token or scheme | `CortetsuDesign` tokens notify; colours repaint | No page, row, card or sidebar entry is recreated; Settings stays open |
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
| Failed | The switch stays on the real value; the row gives the reason in vermillion; the sidebar flags the category |
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
| `Tab`, `Shift+Tab` | Sidebar (collapse, search, current category), the header (back, path, close), then the page top to bottom. Disabled and read-only rows are skipped |
| `Up`, `Down` in the sidebar | Open the previous or next category; the focus moves with it |
| `Right` in the sidebar, `Left` in the page | Enter the page, return to the sidebar |
| `Enter`, `Space` | Activate the focused control |
| `Left`, `Right` on choices and the clock grid | Move between options (`Up`, `Down` too on the grid) |
| `Left`, `Right`, `Home`, `End` on a slider | Change the value |
| `Ctrl+F` | Focus the search |
| `Down` in the search, then `Up`/`Down` | Move through the results |
| `Enter` in the search or on a result | Open the setting |
| `Alt+Left`, `Back` | Go back to the previous page, at the scroll position it was left |
| `Ctrl+PgDown`, `Ctrl+PgUp` | Next or previous category |
| `Escape` | Clear the search if it has text; otherwise close Settings |

The focused control is scrolled into view. Below 1000 px of window content
the sidebar shows icons only, with the category and its state in a tooltip;
its button forces either mode.

## Existing preferences and control coverage

The Interface page exposes independent controls for fuzzy matching of actions
and schemes. The Notifications page exposes expanded popup bodies and the
Caps Lock, Num Lock, keyboard-layout, Do Not Disturb and now-playing toasts.
These eight settings already had shell consumers; the Settings controls now
have an isolated runtime scenario that toggles each value, checks the live
search policy for actions and schemes, confirms one debounced write for each
page's changes, and starts a fresh process to check restoration.
`test-cortetsu-toasts.py` and the keyboard-state runtime test cover the toast
owners separately.

Six old preferences belonged only to the retired top bar and were removed from
`CortetsuConfig`; old files load safely and those keys are ignored.
`test-cortetsu-settings.py` also fails if a control writes a preference with no
reader in the running shell.

## Checks

| Check | What it proves |
| --- | --- |
| `scripts/features/test-cortetsu-settings-runtime.py` | The real surface in Quickshell with service doubles and real key events: object identity through token, scheme, catalogue and preference changes; one page at a time; pending, failed and unavailable states; outside changes; keyboard; no leftover objects after 20 open and browse cycles; UI → owner → persistence → fresh-process restoration for migrated desktop-clock, Bottom Hub app-segment, Fahrenheit and fuzzy-search settings |
| `scripts/features/test-cortetsu-settings.py` | Every destination has a page; every preference written has a reader; one owner for `SUPER+I` |
| `paletteVariant`, `paletteVariantRestore`, `paletteVariantUnavailable` in `scripts/features/test-cortetsu-settings-runtime.py` | The variant control rejects unknown values, regenerates live Material colours from the saved seed, writes manual origin, restores after restart, explains the no-palette state and guards a direct launcher action |
| `migratedControls`, `migratedControlsRestore` in `scripts/features/test-cortetsu-settings-runtime.py` | Four migrated controls update their actual consumers, persist, and restore in a fresh HOME/XDG process |
| `existingPreferenceControls`, `existingPreferenceControlsRestore` in `scripts/features/test-cortetsu-settings-runtime.py` | Eight existing search, notification-expansion and toast settings update their owners, each page batches its changes into one write, and a fresh HOME/XDG process restores them |
| `cortetsu/tests/qml/settings/tst_SettingsNavigation.qml` | Search and movement as pure functions |
| `cortetsu/tests/qml/components/tst_StateMessage.qml`, `tst_Slider.qml` | The layout loop and the lost slider binding do not come back |
| `scripts/features/test-cortetsu-scheme.py` | `set` writes the state file and asks for a config-only reload; a failed `set` reloads nothing |

`CORTETSU_RENDER_DIR=<dir>` makes the runtime test save a PNG of every page at
1368 x 900, at 880 x 620 and on the `aura` scheme at 1280 x 800, plus each
failure and unavailable state.

The isolated visual comparison with end-4's pinned `settings.qml` was captured
on 2026-11-07. [The evidence page](SETTINGS_VISUAL_QA_2026-11-07.md) links each
of the eight page pairs and Washi/Kurogane captures. It records the isolated
compositors and viewport sizes; Cortetsu keeps its own theme and groups controls
by its existing service owners.


## Global personalization

Quick Settings retains the existing Appearance page and adds reversible theme
previews, light/dark Material generation, explicit manual/automatic ownership,
independent compositor/Kitty/GTK/Qt integration controls and confirmed status.
Profile-specific UI/title/kanji families, radii, row height, section spacing,
material opacity/grain/hairline and reset controls use existing design tokens.
The Bottom Hub consumes the same geometry, material and border preferences while
preserving separate islands. Profiles export/import only visual state and keep
unrelated command, network and power preferences.

General includes optional bounded volume increases through CortetsuAudio. This
limits each request made by Cortetsu; it does not claim to control other mixers.
Interface includes a persisted OSD timeout used by both real timers; repeated
volume/brightness input restarts the compact timer. No emergency power or
suspension thresholds are changed.

See [the theming contract](THEMING.md) for precedence, compatibility, ownership,
partial failures and restoration. `globalPersonalisation` and
`globalPersonalisationRestore` in the runtime test exercise the new control flow
and recover it in a fresh process.

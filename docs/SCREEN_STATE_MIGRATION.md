# Cortetsu screen state migration

## Boundary

`components/ScreenState.qml` remains the persistent compatibility store. It
instantiates `modules/CortetsuScreenState.qml`, which exposes the retained
overlay contract to first-party controllers without moving geometry, popouts,
tray ownership, or wallpaper side effects into state.

The adapter is intentionally transitional: `legacyState` is the only storage
source until every consumer has moved to the contract. Writes to retained
flags go through `setRetained(flag, value)`, other surface flags through
`setFlag(flag, value)`, and unknown flag names are rejected by both.

## Surface registry (F1a)

`modules/SurfaceRegistry.js` is the one inventory of per-screen surface flags.
Each entry has a name, a kind and three policy attributes:

| Kind | Flags | Meaning |
|---|---|---|
| `retained` | overview, calendar, wallpaperManager, clipboard, hardware, displayManager, keyboards | hosted by `RetainedSurfacesHost`: full input mask, keyboard focus, scrim, closed together by Escape, focus-grab clear and fullscreen |
| `transient` | launcher, session, dashboard, utilities, settings, sidebar, osd | upstream drawers owned by `ContentWindow` and their hosts |
| `chrome` | bar | bar reveal; reset with the session, outside the overlay policy, not writable through `setFlag` |

| Attribute | Flags | Used by |
|---|---|---|
| `exclusive` | every retained and transient flag except `osd` | `OverlayPolicy.closeOtherPanels`, `CortetsuOverlayPolicy.closeAll` |
| exclusive minus `wallpaperManager` | (derived: `competingWithWallpaper`) | `OverlayPolicy.closeForWallpaper`, `hasCompetingPanel` |
| `ownsKeyboard` | the retained flags, launcher, session | `CortetsuScreenState.requiresOverlayLayer` / `requiresWindowKeyboardFocus` |
| `ipcExclusive` | launcher, session, dashboard, utilities, settings | `drawers toggle`: closes the exclusive group first and is ignored under fullscreen |

Derived groups are frozen arrays exported by the registry (`names`,
`retained`, `transient`, `exclusive`, `competingWithWallpaper`,
`keyboardOwners`, `ipcExclusive`) with `isKnown`, `isRetained`, `isSettable`,
`isIpcExclusive` and `anyOpen(state, flags)`. The registry imports nothing,
so it has no initialisation order.

QML cannot generate properties, so `ScreenState` declares one `bool` per
registry entry and `CortetsuScreenState` one read-only `bool` per retained
entry. `scripts/features/test-cortetsu-surface-registry.py` fails if either
drifts from the registry or if any first-party module keeps its own list of
surface names; `cortetsu/tests/qml/surfaces` checks the behaviour in the QML
engine.

To add a surface: add its entry to the registry, its property to
`ScreenState` (and to `CortetsuScreenState` if it is retained), and both gates
tell you what else is missing.

## Migrated consumers

These controllers read and write through `cortetsuState`:

- `CalendarController`
- `ClipboardController`
- `HardwareController`
- `DisplayController`
- `WallpaperController`
- `OverviewController`
- `KeyboardsController` (through `RetainedSurfaceController`)

They may pass either `cortetsuState` or the legacy `ScreenState` to
`OverlayPolicy`: the policy writes through `cortetsuState.setFlag` in both
cases, because launcher, session, dashboard, utilities, settings and sidebar
still live in the upstream state object. Upstream drawers still write their
own transient flags directly on `ScreenState` (see
`docs/migration/F1a/README.md`, §3).

## Policy rules

`OverlayPolicy.js` and `CortetsuOverlayPolicy.js` own only state transitions.
They can close retained flags, close every exclusive flag, and open one
retained flag exclusively. Geometry, popouts, tray ownership, preview windows,
and wallpaper start/stop effects remain in their callers.

The static gates are `scripts/features/test-cortetsu-screen-state.py` and
`scripts/features/test-cortetsu-surface-registry.py`. The runtime build runs
them together with the Qt Quick tests in `cortetsu/tests/qml/surfaces` and the
existing retained-overlay and Wallpaper Manager tests.

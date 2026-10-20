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
| `exclusive` | every retained and transient flag except `osd` | `OverlayPolicy.closeOtherPanels`, `CortetsuOverlayPolicy.closeExclusiveEverywhere` / `open` |
| exclusive minus `wallpaperManager` | (derived: `competingWithWallpaper`) | `OverlayPolicy.closeForWallpaper`, `hasCompetingPanel` |
| `ownsKeyboard` | the retained flags, launcher, session | `CortetsuScreenState.requiresOverlayLayer` / `requiresWindowKeyboardFocus` |
| `fullscreenGuard` | every transient flag (launcher, session, dashboard, utilities, settings, sidebar, osd) | shortcuts and `drawers toggle` do not open it over a fullscreen window; closing still works (`CortetsuOverlayPolicy.toggleGuarded`) |

Derived groups are frozen arrays exported by the registry (`names`,
`retained`, `transient`, `exclusive`, `competingWithWallpaper`,
`keyboardOwners`, `fullscreenGuarded`) with `isKnown`, `isRetained`, `isSettable`,
`isFullscreenGuarded` and `anyOpen(state, flags)`. The registry imports nothing,
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

## Transitions (stabilization)

`CortetsuOverlayPolicy.js` is the one place that opens, closes and toggles a
surface. Every caller passes every screen's state
(`CortetsuShellState.allStates()`) and the target screen's state:

| Function | Rule | Callers |
|---|---|---|
| `open(states, target, flag)` | an exclusive flag first closes every exclusive flag on **every** screen (itself included, so a retained surface moves instead of doubling); OSD opens in place | retained controllers, Settings links, Dashboard «Hoy», OSD and Utilities links, Bottom Hub |
| `close(states, flag)` | closes the flag on every screen | controllers (`close`, IPC `close`) |
| `toggle(states, target, flag)` | a retained flag open anywhere closes everywhere; otherwise `toggleOn` | `drawers toggle`, every global shortcut |
| `toggleOn(states, target, flag)` | open on `target` (moving it) unless open there | Bottom Hub buttons |
| `toggleGuarded(states, target, flag, fullscreen)` | `toggle`, except that a fullscreen window blocks *opening* a guarded flag | `Shortcuts.toggleSurface` (shortcuts and `drawers toggle`) |

Exclusive surfaces are exclusive across screens because a retained surface
takes the whole seat's keyboard and a transient panel arms a focus grab that a
surface on another screen clears. Before, `CalendarController` and every
`Shortcuts` toggle closed other panels only on their own screen (O-1), and
`drawers toggle sidebar|osd|<retained>` wrote the flag with no policy at all
(O-2). The exceptions that remain are deliberate and gated
(`test-cortetsu-surface-registry.py` §4): the «showall» shortcut opens three
panels together after closing every exclusive surface, and the legacy drawer's
pointer peeks (`drawers/Interactions.qml`, F1a O-4) still write their own
flags, since a retained surface on the same screen takes the full input mask
and a hover on another screen must not close it.

## Migrated consumers

`CalendarController`, `ClipboardController`, `HardwareController`,
`DisplayController`, `KeyboardsController` and the `WallpaperController`
singleton are each one `RetainedSurfaceController` (surface key, IPC target,
shortcut); `HardwareController` adds the OMEN key. `OverviewController` keeps
its own file: it follows the focused screen on toggle and closes Bottom Hub
popouts before opening.

The policy accepts either `cortetsuState` or the legacy `ScreenState`: it
writes through `cortetsuState.setFlag` in both cases, because launcher, session, dashboard, utilities, settings and sidebar
still live in the upstream state object. Upstream drawers still write their
own transient flags directly on `ScreenState` (see
`docs/migration/F1a/README.md`, §3).

## Policy rules

`OverlayPolicy.js` and `CortetsuOverlayPolicy.js` own only state transitions.
Geometry, popouts, tray ownership, preview windows,
and wallpaper start/stop effects remain in their callers.

The static gates are `scripts/features/test-cortetsu-screen-state.py` and
`scripts/features/test-cortetsu-surface-registry.py`. The runtime build runs
them together with the Qt Quick tests in `cortetsu/tests/qml/surfaces` and the
existing retained-overlay and Wallpaper Manager tests.

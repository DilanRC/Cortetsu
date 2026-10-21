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

### The Bottom Hub bell through the retained scrim

The retained-surfaces window sits on the Overlay layer with a full input mask
while a surface is open, so it covers Bottom Hub (Top layer). A click on the
bell used to land on the surface's outside-click area: it dismissed the
surface, and a second click opened the sidebar. The scrim now forwards that
one click: a full-window `MouseArea` above the surfaces accepts a press only
when

- the point is on the bell (`CortetsuScreenState.bottomHub` is this screen's
  hub window; `notificationsButtonContains` maps the bell to screen
  coordinates),
- only full-window layers cover it (`ScrimHit.backdropOnly`: any panel over
  the bell keeps its click, e.g. Wallpaper's at 720p),
- Overview is not open (it has no scrim), and
- Keyboards is not recording or writing (`dismissBlocked`, the same guard as
  its own outside click).

The click then runs the bell's action (`activateNotifications`, a `toggleOn`
of the sidebar), so the result is the one SUPER+N and `bottomHub
notifications` give. Every other press is rejected and reaches the surface as
before. Masks, layers and keyboard modes do not change, and the OSD keeps
coexisting. `bottomHub notificationsButton` (IPC, read-only) gives the bell's
rectangle in layout coordinates for pointer tests
(`docs/migration/stabilization/tools/stab_contracts.py`, scenario `bell`).

### A second bell click closes the sidebar

With the sidebar open its drawer window holds a focus grab. A press over a
regular window that is not the focused one makes Hyprland refocus before it
delivers the press (`processMouseDownNormal`): the refocus ends the grab, whose
`onCleared` closes the sidebar, and the press goes to the bell, whose click then
opened the sidebar again. On the real session there is almost always a window
under Bottom Hub, so a second click with the pointer left on the bell did
nothing visible. The bell records when its pointer press began
(`pressedAt`, 0 for the keyboard) and the grab records when it closed an open
sidebar (`ScreenState.sidebarGrabClearedAt`). `toggleSidebarFor` ignores a
bell click whose press is within 250 ms of that clear: that press is the one
that closed the sidebar. SUPER+N, IPC and the scrim path pass no press time
and are unchanged.

### Escape in the drawer window

The drawer window's Escape closes its panels while the focus grab is active.
It never fired: `Dash.qml`, instantiated in that window by `Dashboard.Wrapper`,
had its own Escape shortcut, always enabled, so Qt found two enabled shortcuts
for the key and ran neither (`activatedAmbiguously`). `DashboardHost` had the
same pair. `Dash` no longer declares one; each host keeps its own. Keyboard
modes and the grab do not change: the drawer window already held the keyboard
while the sidebar was open. A dashboard opened by IPC still takes the keyboard
only on demand, so Escape reaches it only after a click on it.

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

# Cortetsu Product Rebuild

This document records decisions made during the first-party product redesign.
It is intentionally short and grows with the implementation.

## Product direction

Cortetsu is a desktop shell with its own visual language and surface ownership.
Caelestia remains an implementation dependency only where an existing backend is
still required. It must not determine the final presentation.

## Visual foundation

- Palette: Sumi for the base, Tetsu for elevated surfaces, Washi for legibility,
  Indigo for interaction and selection, Vermillion only for meaningful danger or
  warning. Green is reserved for healthy, connected, or successful states.
- Spacing: `4 / 8 / 12 / 16 / 24 / 32` px. The `spacingSection` token is the
  32 px step used to separate groups.
- Radii: small `8`, medium `12`, large `20`, surface `28`, pill only for controls
  whose geometry is explicitly capsule-shaped.
- Hit targets: standard controls are 36 px; primary controls are 40 px. BottomHub
  actions must not fall below the standard target.
- Motion: fast `120 ms`, standard `180 ms`, emphasis `240 ms`, with OutCubic as
  the default easing. No ornamental bounce or indefinite animation.
- Interaction: hover and press transforms apply to the painted content, not to
  the layout or pointer bounds. Dense controls keep a stable hitbox while their
  surface gives visual feedback.

This interaction contract is shared by `CortetsuButton`, `CortetsuListRow`, the
BottomHub App Rail, utility actions and battery profile controls. Their root
items remain fixed while hover and press feedback is painted by the owned
surface, so keyboard focus, pointer handoff and dense layouts use the same
geometry rule.

## Brand mark

`cortetsu/assets/branding/cortetsu-mark-ascended.svg` is the approved canonical
static mark. The live identity is the five-asset Evolving Mark: Human,
Awakening, Monster, Ascended, and Cosmic. Each phase has its own silhouette and
is selected by a real product condition, not by a timer or random choice.

`CortetsuEvolvingMark.qml` renders the phase inside fixed geometry. BottomHub
uses Human at rest, Awakening on intent/focus, and Monster while the launcher is
active or pressed. Wallpaper Manager uses Awakening for a selected candidate,
while the candidate is moving, applying, or has failed; it uses Ascended once a
selection is settled or already applied, and a short Cosmic pulse only after the
state file confirms a successful apply. Static product surfaces use Ascended.

The mark is used selectively and is not repeated in every popup. Its optional
brand accent is private to the mark; Indigo interaction, Vermillion danger, and
green success remain the shared semantic UI roles.

Attached and detached bar popups use the same single `CortetsuPopupSurface`.
The detached wrapper owns only positioning and click containment, while the
drawer `ContentWindow` owns detached focus and outside-click closure. It does
not add a second background, border or radius around the loaded popup, so
detaching a control changes placement without changing its product surface.

## Brightness contract

Brightness is a capability, not a display-name assumption. Cortetsu discovers
the real `brightnessctl` device with the `backlight` class, reads its maximum
range from `/sys/class/backlight/<device>/max_brightness`, normalizes the raw
value against that range, writes a clamped raw value, and reads it back. A
monitor without a discovered backlight reports unsupported instead of showing
`0%`. The current machine exposes `amdgpu_bl2` with a `0..65535` range.

## Quick Settings Drawer

QSD is a dedicated first-party layer named `cortetsu-qsd`, separate from the
BottomHub and transient OSD. The host layer remains allocated so the first open
does not race layer allocation; only the drawer content is transient. Its visual contract is a 400 px right-side drawer
with a Cortetsu header, live audio and notification controls, real brightness
and volume sliders, and network/Bluetooth status. The state belongs to the
canonical per-screen state, while `SUPER + /` owns the shortcut. The drawer
uses the shared 120/180/240 ms motion scale and is excluded from the legacy
panel host's focus-grab cleanup so opening its own layer cannot immediately
close it.
Its state is screen-owned: edge hover uses a 6 px hotspot and 180 ms dwell, the
drawer keeps itself alive while hovered, and shortcut/keyboard focus keeps it
pinned until Escape or an explicit close. Auto-close uses a 260 ms grace only
for edge-opened drawers. The header mark is contextual inside its fixed 24 px
slot: Human at rest, Awakening while a real action tile has hover or keyboard
focus, and Monster while a tile is pressed. QSD never uses Cosmic; its system
health states remain separate from the identity phase.

Global Hyprland shortcuts are single-owned: `hyprland/keybinds.lua` owns the
canonical QSD, Settings, and Print bindings, while `hypr-user.lua` only owns
user-specific additions. QSD uses the symbol form `SUPER + SLASH` plus the
physical `SUPER + SHIFT + 7` equivalent required by the active `latam` layout.
The workspace-7 move action uses `SUPER + SHIFT + F7` to keep those two product
actions deterministic without a duplicate effective bind.

## Settings Center

`SUPER + I` now opens a dedicated `cortetsu-settings` full surface. The left
navigation is searchable and groups settings by product area; the content area
uses sections instead of a wall of equal cards. Appearance includes a live
gallery backed by `cortetsu-scheme list`, with five swatches per installed
family/flavour and direct selection. Exposed toggles call `CortetsuConfig` and
persist through its XDG preferences contract. Categories without a connected
read/write backend show an explicit staged boundary instead of a fake switch.
The Settings host closes on Escape and uses exclusive keyboard focus only while
open. Its navigation search uses the same Cortetsu search primitive as Launcher,
with a compact density variant so focus, selection, clear, hover, and surface
feedback remain one product interaction.

Wall Utility keeps two explicit configuration authorities: `ui.toml` is the
versioned design and motion source, while `CortetsuConfig.path` points to the
XDG runtime preferences file `cortetsu/preferences.json`. Settings writes only
the latter; changing design tokens uses the theme compiler and does not silently
rewrite user preferences.

Power is also one first-party capability boundary. `CortetsuPower` owns the
UPower readback, rejects unready or non-finite percentages, clamps valid values
to `0..1`, and exposes `-1` when no honest percentage exists. BottomHub, QSD,
Dashboard, Settings, Lock, the battery popup, status icons, and low-battery
notifications consume that same contract, so unavailable hardware cannot turn
into a fake `0%` or inconsistent charging state on one surface.

## Dashboard

Dashboard now has its own `cortetsu-dashboard` layer and no longer relies on the
legacy drawer panel as its visual consumer. The dominant surface is a wide
context view: Cortetsu identity and time in the header, live weather as the
hero, compact Now Playing beside it, and a restrained system rail for CPU,
memory, battery, and network. Values come from existing Cortetsu services;
missing weather or media is presented as an honest empty state. The old panel
wrapper remains available as migration scaffolding but is hidden from the
rendered product.

## Lock screen

The lock surface now lives in the first-party `cortetsu/modules/lock` module.
`WlSessionLock` and the existing PAM provider remain the authentication and
session boundary; the new UI only consumes that backend. It uses the current
screen capture with controlled dimming, Cortetsu mark, clock/date, password
echo, failure feedback, battery/network status, and a restrained keyboard hint.
The mark is Human while the surface waits, Awakening while password, fingerprint,
or face authentication is active, and Ascended only after PAM reports a real
success. PAM emits that success separately from the generic session unlock; the
mark gets one standard motion interval before the lock releases. Failed, error,
maximum-tries, shortcut, and IPC paths never select Ascended. The real lock
shortcut and IPC are unchanged. The lock action was not triggered during
development to avoid interrupting the active session.

## Launcher and system feedback

Launcher now has a dedicated overlay host with exclusive keyboard focus. Its
search-first behavior remains intact, but the header makes the active mode
explicit: Apps, Command, Theme, or Wallpaper. Prefixes continue to be owned
by the existing action services, so the label is a reflection of real routing.

OSD keeps live volume and brightness readback while adding a small Cortetsu
feedback signature with the canonical Ascended mark and `SYSTEM FEEDBACK` label.
The visual stays compact and uses the existing fast motion timing.
When a monitor has no supported backlight, the brightness row says `Unavailable`
and does not render a false zero value. Volume and brightness share one hover
island, so moving between indicators cannot race the auto-hide timer.

Progress feedback is owned by `CortetsuProgressBar`, shared by OSD indicators,
Dashboard Focus, Hardware metric cards, the Calendar Pomodoro and the Battery
popup. It keeps the track, bounded fill, unavailable-state behavior and width
motion in one contract while allowing each surface to choose its density and
semantic fill color, including the Vermillion critical-battery state.

Notifications use the same interaction rule: the card body and its actions are
one hover island, and toast stacks keep fixed hitboxes while pausing expiration
for hover or keyboard focus. The live notification model receives that state as
well, keeping backend expiry and visible action lifetime in sync.

## BottomHub system cluster

The right-side system controls now sit inside one grouped surface with shared
40 px hit targets. Network state distinguishes Ethernet, connecting, offline,
and Wi-Fi signal strength; its tooltip reports the SSID and signal when the
backend provides them. Existing audio, Bluetooth, battery, notification, and
session controls keep their live providers and hover popout ownership.

BottomHub composition is configurable through four first-party segment switches:
Mode and workspaces, App rail, Tray, and Status cluster. Hidden segments release
their layout space instead of leaving an invisible reservation, while the
hardware controls inside Status cluster remain independently configurable.

## Retained surface ownership

Overview, Hardware, Display, Wallpaper, Calendar, and Clipboard now render through `RetainedSurfacesHost.qml`, a dedicated overlay window with per-screen state and explicit keyboard ownership. The legacy `Panels` entries remain as compatibility handles while consumers migrate. This keeps full surfaces from competing with BottomHub and transient popouts in the shared drawer window.

First-party Dashboard, QSD, Launcher, Settings, and retained surfaces now read the same `CortetsuShellState` registry. This makes the exclusivity policy observable: opening a full surface cannot leave a first-party surface hidden behind it because each controller closes the same state owner.

Controllers use the typed `CortetsuScreenState` boundary for overlay policy and
retained writes. The compatibility `ScreenState` object remains the persistence
bridge for older panel handles, but controllers no longer reach through
`.legacyState`; this keeps the migration explicit without creating a second
monitor registry or changing input ownership.

Settings and QSD now import Cortetsu components, modules, services and utilities
through explicit relative boundaries. Their visible composition no longer relies
on the `qs.*` compatibility aliases; native Quickshell providers remain imported
directly where they own the hardware or Wayland contract.

The same boundary now covers the six primary overlay hosts: QSD, Settings,
Launcher, Dashboard, Session and Retained Surfaces. Each host resolves its
monitor-local state, surface primitives and child views from the Cortetsu tree,
so overlay ownership is explicit at the composition root as well as inside the
content pages.

## Wallpaper orbital selector

The Wallpaper Manager uses a stable orbital model during selection. `windowIndex`
is the last settled center, while `currentIndex` may update immediately so the
central preview and its applied/selected state respond without waiting for the
wallpaper backend. The satellite model remains anchored to `windowIndex` until
the configured Wall Utility OutCubic phase animation completes, so the clicked wallpaper stays
visible while the orbit rotates. `orbitPhase` accumulates between selections;
it is reset only by a catalog/category resync, not after every move.

Satellite depth is derived from the animated angle and controls position, scale,
opacity, and z-order. The center preview now exposes `Selected`, `Previewing`,
or `Applied`, with an Indigo focus outline and a distinct healthy secondary
state for an applied wallpaper. Left/Right and Up/Down remain keyboard-first;
Enter/Space apply and Escape closes the surface.

Wallpaper application is one shared transaction owned by
`CortetsuWallpapers`. Its ephemeral `applyStatus` is `idle`, `applying`,
`applied`, or `failed`, and `applyStatusPath` identifies the pending or last
confirmed target without adding another persistence file. Launcher, Wallpaper
Manager, and Settings consume that same status, so applying and failure do not
drift between surfaces. `actualCurrent` remains the confirmed wallpaper path;
Cosmic is emitted only after the backend acknowledgement and never represents
the idle state.

## Wallpaper-aware colour bridge

The wallpaper colour daemon writes a validated M3 scheme to the Cortetsu XDG
state directory. `CortetsuColours` watches that file and exposes the current
palette reactively to compatibility surfaces, while the Wallpaper Manager can
temporarily bind a preview palette during selection. Invalid or missing values
fall back to the generated Sumi/Tetsu/Washi contract. Preview state is cleared
when the manager closes or applies a wallpaper, and the `Smart scheme` setting
controls whether preview colours are adopted.

## Hover surface ownership

BottomHub attached controls now pass through one `CortetsuHoverSurfaceController`.
The controller owns the 120 ms open delay and 240 ms close grace, so moving
between the trigger and its popout does not depend on duplicated timers. The
popout host remains a single surface and can switch its content when the pointer
moves from Network to Bluetooth or Battery.
The four system buttons are one `HoverHandler` island: button entry selects the
content mode, while only leaving the island releases the trigger. This prevents
an exit/enter race at the boundaries between Volume, Network, Bluetooth, and
Battery. Leaving the island also cancels any incomplete dwell, even if the
pointer is crossing an already-open popup, so a stale mode cannot reopen after
the trigger has been left.

`CortetsuTooltip` owns the shared tooltip surface, typography, padding and
delayed visibility. Consumers provide only their target item and hover/focus
state, so pointer behavior and tooltip styling remain aligned across the dock.

## Input ownership

Every first-party full-surface host remains allocated for stable layer timing,
but exposes an empty Wayland input region while closed. Its input region becomes
active only while the surface owns the interaction. This keeps transparent QSD,
Settings, Dashboard, Launcher, Session, and retained-surface layers from stealing
clicks from application windows underneath.

## Session and power

The session surface keeps the real system actions, but destructive actions now require a second explicit activation within a four-second confirmation window. The first activation arms the action and changes its label to `Confirm ...`; no shutdown, reboot, hibernate, or logout command is run during the armed state.
The surface now has its own centered overlay host with a compact power identity and exclusive keyboard focus. The older right-side wrapper remains only as a hidden compatibility handle.

## Delivery order

The redesign is delivered in product slices: design foundation, real state
providers, BottomHub system cluster, QSD, schemes, Settings, Dashboard, Lock,
then the remaining surfaces and legacy visual cleanup. QA artifacts from the
previous phase remain historical snapshots until the redesign is complete.

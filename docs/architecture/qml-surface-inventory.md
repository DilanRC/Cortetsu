# Cortetsu QML surface inventory

Baseline: `9219189` (`Hide inactive popup backgrounds cleanly`).

The active first-party composition enters through `cortetsu/shell.qml`. The
`cortetsu/modules` tree owns visible Cortetsu surfaces. `cortetsu/base` is an
upstream compatibility tree and is counted here only where an owned module
composes it directly. `cortetsu/modules/nexus` is the detached settings and
control surface used by the owned popup wrapper.

Maturity is intentionally conservative. A surface is `VERIFIED` only after
static checks, real runtime interaction, keyboard checks, visual inspection,
and clean journal evidence. Technical gates alone do not promote a surface.

| Surface | Entrypoint | Direct visual dependencies | Maturity | Main product gap | Priority |
| --- | --- | --- | --- | --- | --- |
| BottomHub | `modules/BottomHub.qml`, `modules/CortetsuBottomHubView.qml` | `CortetsuAppRail`, `CortetsuModeSegment`, `CortetsuStatusSegment`, `CortetsuTraySegment` | VERIFIED | multi-monitor bar, segment hierarchy, on-demand focus, workspace navigation and popup anchoring verified | P0 |
| Launcher | `modules/launcher/Wrapper.qml`, `Content.qml`, `AppList.qml`, `ContentList.qml` | launcher services, `CortetsuSearchBar`, item delegates | VERIFIED | runtime search/selection/Enter launch, Escape close, wallpaper query empty state, two-monitor visual inspection and clean journal verified | P1 |
| Quick Settings / Utilities | `modules/utilities/Wrapper.qml`, `Content.qml` | utility cards, `CortetsuSurface`, toggle controls | VERIFIED | two-monitor composition, Keep-awake feedback and restoration, Notification controls activation, keyboard contract and Escape close verified | P1 |
| Notifications | `modules/sidebar/Content.qml`, `modules/notifications/Wrapper.qml`, `Notification.qml` | notification model, action list, scroll container | VERIFIED | real notify-send card, two-monitor toast, always-visible Dismiss, empty state, Escape close, and clean journal verified | P1 |
| Wi-Fi / Network | `modules/bar/popouts/CortetsuNetworkPopup.qml` | network service, list rows, password popup | VERIFIED | connected networks, density, first-party rows, IPC open and Escape close verified | P1 |
| Audio / Volume | `modules/bar/popouts/CortetsuAudioPopup.qml` | audio service, sliders and device rows | VERIFIED | selected output, volume slider, device hierarchy, IPC open and Escape close verified | P1 |
| Bluetooth | `modules/bar/popouts/CortetsuBluetoothPopup.qml`, `base/modules/bar/popouts/Bluetooth.qml` | Bluetooth service, device rows | VERIFIED | adapter-ready state, paired devices, action surface, IPC open and Escape close verified | P1 |
| Battery | `modules/bar/popouts/CortetsuBatteryPopup.qml` | UPower state, battery details | VERIFIED | real 100% power state, charge timing, selected profile, profile focus/activation contract and Escape close verified | P1 |
| Keyboard Layout | `modules/bar/popouts/CortetsuKeyboardPopup.qml` | layout model, selection rows | VERIFIED | active Spanish (LA) layout, empty additional-layout state, selection/focus contract and Escape close verified | P2 |
| Lock Status | `modules/bar/popouts/CortetsuLockStatusPopup.qml` | lock state, action rows | VERIFIED | live Caps/Num indicator state, first-party service ownership and Escape close verified | P2 |
| Active Window | `modules/bar/popouts/CortetsuActiveWindowPopup.qml`, `base/modules/bar/popouts/ActiveWindow.qml` | Hyprland active toplevel | VERIFIED | live title/class, preview, Details action, attached host, keyboard close and clean journal verified | P2 |
| Window Info | `modules/bar/popouts/CortetsuWindowInfoPopup.qml` | preview, details and buttons | VERIFIED | active-window details, workspace controls, keyboard focus, mouse Done, Escape, and two-monitor detached host verified | P2 |
| Tray | `modules/CortetsuTraySegment.qml`, `modules/bar/popouts/CortetsuTrayMenu.qml` | tray items and nested menu | VERIFIED | SNI item activation, row rhythm, focus-visible menu rows and clean close verified | P1 |
| Tray submenus | `modules/bar/popouts/CortetsuTrayMenu.qml` | menu rows, separators, submenu state | VERIFIED | `Right` opens nested state, `Left` returns to parent, `Escape` closes and clean journal verified | P1 |
| OSD | `modules/osd/Wrapper.qml`, `Content.qml` | OSD host and indicators | VERIFIED | two-monitor volume trigger, shared indicator surface, bounded levels, restored volume, and clean journal verified; brightness wheel remains a separate device-dependent check | P2 |
| Toasts | `modules/utilities/toasts/Toasts.qml`, `ToastItem.qml` | toaster service, action rows | VERIFIED | two-monitor runtime, stacking, five-second expiration, mouse and Escape dismissal verified; full notification-center promotion remains separate | P1 |
| Overview | `modules/overview/Wrapper.qml`, `Content.qml`, `WindowCard.qml` | Hyprland windows/workspaces | VERIFIED | multi-window adaptive grid, empty-workspace navigation, keyboard selection, card close, drag, floating action, scrim, focused-monitor routing, Escape and clean journal verified | P0 |
| Display | `modules/display/Wrapper.qml`, `Content.qml` | display controller and editor | VERIFIED | two-monitor topology, layout controls, dry-run/save surface, IPC open and Escape close verified | P2 |
| Hardware | `modules/hardware/Wrapper.qml`, `Content.qml` | hardware controller, metric cards | VERIFIED | live CPU/memory/storage/GPU/battery metrics, sensor cards, loading pipeline, IPC open and Escape close verified | P2 |
| Wallpaper | `modules/wallpaper/Wrapper.qml`, `Content.qml` | `CortetsuWallpapers`, orbit controls | VERIFIED | live orbit previews, categories, current selection, Cancel/Random/Apply actions, IPC open and Escape close verified | P2 |

## Wave 0 foundation status

Existing shared contracts are `CortetsuDesign.js`, `CortetsuTokens.qml`,
`CortetsuColours.qml`, `CortetsuSurface.qml`, `CortetsuButton.qml`,
`CortetsuListRow.qml`, `CortetsuSectionHeader.qml`, `CortetsuSlider.qml`,
`CortetsuToggle.qml`, `CortetsuText.qml`, and `CortetsuStateLayer.qml`.

This checkpoint adds keyboard focus and activation to the two most common
interactive primitives. It does not change popup anchoring, screen selection,
service ownership, or detached popup behavior.

## Launcher verification evidence

The promoted runtime was opened on both monitors. On the right monitor,
searching `kitty` produced a selected application result and Enter launched a
new Kitty instance. Escape closed the launcher. On the left monitor, a
wallpaper query rendered the first-party empty state. The shell remained
active with zero restarts and no new warning/error/critical journal entries.

## Quick Settings verification evidence

Quick Settings was opened on both monitors. The Keep-awake control changed to
its active visual state and was restored to `Allow idle`; Notification controls
opened the notification center, and Escape closed the overlay. Static utility
gates passed, including first-party ownership and keyboard-capable controls.
The shell remained active with zero restarts and no new warning/error/critical
journal entries.

## Display, Hardware and Wallpaper verification evidence

The promoted runtime opened Display Manager, Hardware Center and Wallpaper
Manager through their first-party IPC targets. Display Manager rendered the
two-monitor topology and layout controls; Hardware Center rendered live CPU,
memory, storage, GPU, battery and sensor cards; Wallpaper Manager rendered the
preview orbit, category controls, current selection and Cancel/Random/Apply
actions. Escape closed the active overlay sequence. The shell stayed active
with zero restarts and no new warning/error/critical journal entries.

## Keyboard Layout and Lock Status verification evidence

The promoted runtime opened both popups through `bottomHub control` on the
right monitor. Keyboard Layout showed the active `Spanish (LA)` layout and the
empty additional-layout state. Lock Status showed the live Caps Lock and Num
Lock indicators. Escape closed the active popup sequence; the shell stayed
active with zero restarts and no new warning/error/critical journal entries.

## Battery verification evidence

The promoted runtime opened Battery through `bottomHub control battery`. The
popup rendered the real 100% power state, charge timing text and the selected
Performance profile. Profile controls expose focus and Enter/Return/Space
activation; Escape closed the popup and `powerprofilesctl get` remained
`performance`. The shell stayed active with zero restarts and no new
warning/error/critical journal entries.

## Network, Audio and Bluetooth verification evidence

The promoted runtime opened each popup through the `bottomHub control` IPC on
the right monitor. Network rendered two available networks with the connected
state; Audio rendered the current output, volume slider and output devices;
Bluetooth rendered a ready adapter and paired devices. Escape closed the
active popup after the sequence. Static native-popup gates passed and the
shell stayed active with zero restarts and no new warning/error/critical
journal entries.

## Window Info verification evidence

The detached Window Info surface was opened through `bottomHub control winfo`
after focusing a live Kitty window on the right monitor. The full-screen
drawer host rendered the first-party card with the active title, class,
address, workspace, monitor and size, plus Float, Pin, Close and workspace
controls. Tab moved focus through the controls; Escape closed the surface, and
the `Done` button also closed it by mouse. The shell stayed active with zero
restarts and no new warning/error/critical journal entries.

## Active Window verification evidence

The `bottomHub control activewindow` IPC opened the first-party attached
popup on the right monitor with a live Kitty title/class and screencopy
preview. The Details action remains connected to the detached Window Info
surface; Escape closed the attached popup, and the shell stayed active with
zero restarts and no new warning/error/critical journal entries.

## Tray and submenu verification evidence

The promoted runtime exposed the live ChatGPT StatusNotifier item in the
Tray segment on the left monitor. Clicking it opened the first-party menu
with Running, Recent, More, New Chat, Open ChatGPT and Quit states. `Tab`
cycled through menu rows with a visible focus outline. `Right` opened the
More submenu with its action rows; `Left` returned to the parent menu and
`Escape` closed the retained menu. The shell stayed active with zero
restarts and no new warning/error/critical journal entries.

## BottomHub verification evidence

The promoted runtime rendered the continuous BottomHub on both 1080p
monitors with the mode, app, Tray and status segments aligned in their
respective islands. The bar remained non-stealing at startup and switched to
on-demand keyboard focus after interaction. On `eDP-1`, clicking the network
control opened the attached popup on the same monitor; `Tab` produced a
visible row focus and `Escape` closed it. Clicking a workspace dot moved the
monitor from workspace 1 to 3; `Left` then navigated 3 to 2 and 2 to 1 while
the dot focus was restored to the destination. App-rail focus feedback was
visible through its tooltip. The shell stayed active with zero restarts and
no new warning/error/critical journal entries.

## Overview verification evidence

The promoted runtime rendered the adaptive overview grid with live windows on
the right monitor, workspace/monitor badges and the empty workspace chips.
Keyboard selection and `F` floating action were exercised and the floating
state was restored. A temporary Kitty card was closed through the card mouse
action, and a second temporary card was dragged from workspace 1 to workspace
2 through the visible workspace rail. Clicking the empty workspace 3 chip
closed Overview and Hyprland confirmed `eDP-1` on workspace 3. Escape closed
the overview sequence; the shell stayed active with zero restarts and no new
warning/error/critical journal entries.

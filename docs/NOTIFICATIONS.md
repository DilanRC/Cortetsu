# Notifications (Zero-Caelestia Task 9)

## What this covers

`caelestia/patches/services__NotificationConfig.qml.patch` touches four upstream
files: `services/Notifs.qml`, `services/NotifData.qml`, `services/GameMode.qml`,
`modules/notifications/Notification.qml`. It already replaces every
`GlobalConfig.*` read with a `CortetsuConfig.*` equivalent (see
`cortetsu/modules/CortetsuConfig.qml`: `notificationExpire`,
`suppressNotificationsInFullscreen`, `notificationDefaultExpireTimeout`,
`notificationFullscreenExpireTimeout`, `notificationActionOnClick`,
`toastDndChanged`, `toastGameModeChanged`) and persists DND to
`$XDG_STATE_HOME/cortetsu/notification-status.json` via a `FileView` instead of
upstream's `PersistentProperties`/`reloadableId`. That migration predates this
task (commit `a491e64`); `grep -n 'GlobalConfig\|Caelestia\.Config'` against the
patch only matches diff `-` lines (text being removed), never a surviving `+`
line — i.e. the merged result has zero live GlobalConfig/Caelestia.Config
reads.

This task adds the first-party facade Cortetsu code (bottom hub, future
notification-center UI, CLI) should use instead of reaching into the patched
upstream singleton directly:

- `cortetsu/modules/CortetsuNotifications.qml` — reactive singleton exposing
  `count`, `history` (full persisted notification array), `dnd`, and the
  actions `dismiss(id)`, `clear()`, `toggleDnd()`. It watches
  `cortetsu/notifs.json` and `cortetsu/notification-status.json` via
  `FileView` and never edits JSON inline — every mutation shells out to:
- `cortetsu/bin/cortetsu-notifications` — deterministic Python CLI
  (`count | history | dismiss ID | clear | dnd status|on|off|toggle`) that
  owns those two files. Unit-tested in `cortetsu/tests/test-notifications.py`
  with no QML runtime required.
- `IpcHandler { target: "cortetsu-notifications" }` in the singleton exposes
  `clear`, `dismiss`, `toggleDnd`, `isDndEnabled`, `count` for
  `qs ipc call cortetsu-notifications <fn>` from outside the QML tree
  (shortcuts, scripts), mirroring the `WallpaperController`/`CortetsuRecorder`
  pattern already used for wallpaper and screen recording.

## Toast surface contract

Visible toasts are rendered by `cortetsu/modules/BottomHub.qml` inside each
monitor's top-layer `PanelWindow`, immediately above the BottomHub bar. The
window grows to fit the toast stack and uses a click mask so the toast region
and bar remain interactive without intercepting the rest of the screen.

Mouse click, Escape, and the per-item action keys dismiss the newest visible
toast. Toasts take exclusive keyboard focus only while the stack is visible,
then release it when the stack becomes empty. The current implementation caps
the visible stack at five items and expires each item after five seconds. The
notification card keeps one hover island across its body and actions, while
toast hitboxes remain fixed and their timeout pauses during hover or keyboard
focus. The live notification model receives the same interaction state, so its
backend expiry timer pauses too and cannot remove the popup under an active
action row.

## What is explicitly out of scope, and why

Fully eliminating the patch (deleting
`services__NotificationConfig.qml.patch` and its `MANIFEST.tsv` line) would
require reimplementing `services/Notifs.qml`'s `NotificationServer` — the
actual freedesktop `org.freedesktop.Notifications` DBus server, urgency/action
dispatch, hint parsing, and per-notification image caching in
`services/NotifData.qml` — as first-party Cortetsu code with zero patch. That
is a full notification-daemon rewrite (comparable in scope to `mako` or
`dunst`), not a config-coupling removal, and every other still-patched service
in `MANIFEST.tsv` (`services/Hypr.qml`, `services/Time.qml`,
`services/Audio.qml`, `services/Players.qml`, etc.) is in the same
intermediate state: GlobalConfig removed from the patch, upstream service
itself not yet replaced. Notifications follow the same increment as those.
The patch is **not** deleted this round — only a part of what it enables
(GlobalConfig removal) is done, plus a new first-party layer on top of its
output.

`cortetsu/modules` may never `import qs.services` (enforced by
`scripts/features/test-zero-caelestia-gate.py` and
`scripts/features/test-cortetsu-notifications.py`), so
`CortetsuNotifications.qml` cannot call into the live `Notifs` singleton's
in-memory list directly (e.g. to close one specific still-open toast). Its
`dismiss`/`clear` therefore operate on the **persisted snapshot**
(`cortetsu/notifs.json`) only. If the live shell's own `Notifs.qml` still
considers a notification open, its own save timer can re-write that entry
back into the snapshot on its next list mutation — this is expected, not a
bug, and mirrors the same file-boundary tradeoff already accepted for DND.
Actually clearing all *currently visible* toasts (not just history) is
already possible with zero GlobalConfig coupling via upstream's own
untouched `IpcHandler { target: "notifs" }` (`qs ipc call notifs clear`,
`qs ipc call notifs toggleDnd`) — that code path was never part of the patch
diff and needed no migration.

## DBus notification ownership (runtime verification)

After promoting the Cortetsu runtime, the active owner was rechecked on the
real session. The first check found a competing `mako` process even though its
user unit was disabled, so the test stopped that already-running unit before
reloading Cortetsu:

```
$ systemctl --user stop mako.service
$ cortetsu shell reload
$ busctl --user status org.freedesktop.Notifications
PID=<current Cortetsu qs PID>
Comm=qs
CommandLine=/usr/bin/qs -p /home/dilan/.config/quickshell/cortetsu/current -n
```

Quickshell's `NotificationServer` is therefore the live backend in the
promoted session while `mako` remains inactive. A real `notify-send`
notification was rendered in the Cortetsu notification center and expired from
the popup collection after its configured timeout. The service remained at
`NRestarts=0`, `ExecMainStatus=0`, with no new QML warnings or errors.

The ownership check is part of the runtime contract: if another daemon claims
`org.freedesktop.Notifications`, Cortetsu cannot receive the live event. Keep
`mako.service` inactive while Cortetsu's native `NotificationServer` is in use.

```sh
# Confirm current owner if the runtime is rebuilt:
busctl --user list | grep -i notif
busctl --user status org.freedesktop.Notifications
```

`CortetsuNotifications.qml` and `cortetsu-notifications` continue to use the
Cortetsu XDG-state boundary for history, DND and external actions.

## Shared toast channel with Pomodoro

`cortetsu/bin/cortetsu-pomodoro` does not call DBus/`notify-send` directly. It
writes `$XDG_STATE_HOME/cortetsu/pomodoro-notification.json`
(`write_event`/`event_path`), which `cortetsu/modules/BottomHub.qml` watches
and renders via `Toaster.toast(event.title, event.message, "timer")` — the
same `Toaster` singleton the patched `Notifs.qml`/`GameMode.qml` use for DND
and game-mode toasts (`toastDndChanged`, `toastGameModeChanged`). One toast
channel, confirmed by reading both call sites; no duplicate toast pipeline
was introduced.

## Status

- GlobalConfig/Caelestia.Config in the patch: 0 (already migrated before this
  task; verified by inspection, not just the audit bucket).
- First-party facade added this task: `CortetsuNotifications.qml` (history,
  dismiss, clear, DND toggle, IPC handler) + `cortetsu-notifications` CLI +
  tests.
- Patch **not** deleted: the DBus notification server itself
  (`NotificationServer`, image caching, action/urgency dispatch in
  `NotifData.qml`) is still upstream-owned, same as every other still-patched
  service in `MANIFEST.tsv`. Deleting the patch would require a full
  first-party notification-daemon rewrite, out of scope for this increment.

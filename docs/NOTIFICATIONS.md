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

The backend popup timeout follows the freedesktop `expire_timeout`: a positive
value is used as sent, `0` keeps the popup until it is dismissed, and `-1` (what
`notify-send` and most clients send) uses `notificationDefaultExpireTimeout`
(5000 ms by default). `CortetsuNotificationModel.popupTimeout` holds the rule;
before it, `-1` popups never expired. An expired popup stays in the history.

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
in-memory list directly. `cortetsu/notifs.json` is the bridge instead:

- `services/Notifs.qml` writes every open notification to it (300 ms
  debounce) and restores them on start, without invocable actions.
- When the file changes, Notifs closes each notification that its last save
  listed and the edit removed. A notification that arrived after that save is
  never closed by a stale snapshot. An empty file is a clear and closes
  everything. An unreadable file is ignored, and the CLI writes atomically
  and refuses to edit one. Before each save it rereads the file, so a
  pending save cannot bring back what the CLI just dismissed.
- Snapshot ids are `<arrival ms>-<server id>`, because the server restarts its
  ids at 1 and would collide with restored entries.

`scripts/features/test-notification-history-runtime.py` checks this end to
end in a nested Hyprland with a private session bus.

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
`org.freedesktop.Notifications`, Cortetsu cannot receive the live event.

Disabling `mako.service` was not enough. mako ships
`/usr/share/dbus-1/services/fr.emersion.mako.service` with
`SystemdService=mako.service`, so the first notification sent before the shell
registers the name activates mako and it keeps the bus (EVIDENCIA F06).

`install-cortetsu.sh` calls `mask_rival_notification_daemon`
(`scripts/lib/notification-owner.sh`), which masks that one user unit with
`--now`, so a running mako stops too. mako stays installed; no generic unit or
D-Bus file is touched. A notification sent in the startup window now fails
instead of starting a rival server.

If mako held the bus during the install, the running shell never got the name
and does not retry. The installer prints a hint to run
`systemctl --user restart cortetsu-shell` rather than restarting the shell
itself. Masking blocks only systemd activation: a mako started by hand or from
`exec-once` would still win (the repo starts none, and the live check below
fails in that case). Revert with `systemctl --user unmask mako.service`.

`scripts/features/test-notification-owner.py` runs that function against a fake
systemctl and, on a live session, checks that the bus owner is
`cortetsu-shell.service`.

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

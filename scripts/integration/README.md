# SNI and DBusMenu manual integration fixture

`status-notifier-fixture.py` runs only when invoked manually; it is not part of
the regular test suite. It registers items with the active
`org.kde.StatusNotifierWatcher`, so it changes the live tray. Do not connect it
to the main Cortetsu shell while the crash investigation is open.

Start with one minimal item:

```sh
python3 scripts/integration/status-notifier-fixture.py --minimal
```

The item is Active, has a unique application Id and a simple title. Optional
icon names, pixmaps, attention/overlay icons, tooltip content, menu and special
ItemIsMenu behavior are empty or disabled. `GetAll` still returns the complete
set of protocol properties with their specified DBus types.

After M1 is understood, test menu support with one item:

```sh
python3 scripts/integration/status-notifier-fixture.py --instances 1
```

Two items with different application Id values:

```sh
python3 scripts/integration/status-notifier-fixture.py --instances 2 \
  --id cortetsu-first --id2 cortetsu-second
```

Two items with the same application Id require an explicit choice:

```sh
python3 scripts/integration/status-notifier-fixture.py --instances 2 --id cortetsu-fixture
```

Do not run duplicate-Id or menu scenarios before the single-item minimal-shell
test passes. For an isolated live test, record the current user service state,
stop the main shell only if it owns the watcher, launch the temporary Quickshell
host on the same session bus and Wayland session, then use a cleanup trap to
stop the fixture/host and restore the service. Never install the fixture as a
service or run it as part of `./scripts/cortetsu test`.

For example, when the service was active before the test, keep both process IDs
and install the trap before stopping it:

```sh
qs_pid=''
fixture_pid=''
cleanup() {
  [[ -z "$fixture_pid" ]] || kill "$fixture_pid" 2>/dev/null || true
  [[ -z "$qs_pid" ]] || kill "$qs_pid" 2>/dev/null || true
  [[ -z "$fixture_pid" ]] || wait "$fixture_pid" 2>/dev/null || true
  [[ -z "$qs_pid" ]] || wait "$qs_pid" 2>/dev/null || true
  systemctl --user start cortetsu-shell.service
}
trap cleanup EXIT
systemctl --user stop cortetsu-shell.service
# Start the temporary Quickshell config, then the fixture; assign each PID above.
```

If the service was inactive beforehand, do not start it in cleanup. Wait for
both processes to exit and verify `systemctl --user is-active cortetsu-shell.service`
and the service journal after cleanup.

The control service is named `org.cortetsu.SniFixture<PID>`:

```sh
gdbus call --session --dest org.cortetsu.SniFixture<PID> \
  --object-path /Fixture --method org.cortetsu.SniFixture.Set 1 status NeedsAttention
gdbus call --session --dest org.cortetsu.SniFixture<PID> \
  --object-path /Fixture --method org.cortetsu.SniFixture.Set 1 menu off
gdbus call --session --dest org.cortetsu.SniFixture<PID> \
  --object-path /Fixture --method org.cortetsu.SniFixture.Unregister 1
gdbus call --session --dest org.cortetsu.SniFixture<PID> \
  --object-path /Fixture --method org.cortetsu.SniFixture.Register 1
gdbus call --session --dest org.cortetsu.SniFixture<PID> \
  --object-path /Fixture --method org.cortetsu.SniFixture.Stop
```

`--minimal` disables menu control. Full mode provides a DBusMenu tree with an
action, a disabled row, nested submenus and a separator. `Event` reports action
activation to stdout. `GetLayout` respects the requested recursion depth and
property list. Stopping or unregistering removes the item's bus name.
Re-registering creates a new service name while retaining the application Id.
The fixture does not drive the shell UI by itself.

# Launcher dismissal (nested Hyprland)

```sh
python3 scripts/integration/test-launcher-dismiss.py --cycles 3
```

Runs the composed shell from this checkout in a nested Hyprland with the
repository's Lua keybinds, three outputs (the nested window plus two headless
ones) and a `kitty` terminal. `launcher_harness.py` compiles `vinput.c`, a virtual
keyboard and pointer (`zwp_virtual_keyboard_v1`, `zwlr_virtual_pointer_v1`)
that connects only to the nested `WAYLAND_DISPLAY`. Super therefore goes
through Hyprland's real `SUPER_L` release bind and global-shortcut path, and
the desktop session never receives an event.

Isolation: temporary `HOME` and `XDG_*` directories, a private
`dbus-daemon` with no service directories (nothing is bus-activated),
`PATH` limited to a stub directory and `/usr/bin` (no `~/.local/bin`
helpers), fixture `.desktop` entries, and a `cortetsu-launch-persistent` stub
that only records argv. Startup programs from the Lua config are not run.

Scenarios run on two headless outputs. The nested window's own output
(`WAYLAND-1`) only gets frames when the desktop compositor paints that window,
so a client commit on it can wait seconds; on it the launcher changed state
without its surface catching up, which looked like the bug but was the test
bed. The real Super key, the parent keyboard and pointer are disabled in the
nested compositor (`hl.device`), and its `exec` binds are replaced by `true`
so a stray chord never starts a real program.

Every close is followed by a key typed into the terminal: the test fails if
the launcher, or an invisible surface, still holds the keyboard. Needs a
Wayland session, `Hyprland`, `qs`, `kitty`, `cc`, `wayland-scanner`,
`pkg-config` with `wayland-client` and `xkbcommon`, and `dbus-daemon`; it
prints SKIP otherwise. `cortetsu test` runs it with the default two cycles.

The real Super key cannot be replaced fully: a physical check on the laptop
keyboard is listed in the PR.

## HP Victus keys

```sh
python3 scripts/integration/test-hp-keys.py
```

Checks that `cortetsu-keybinds list` shows the OMEN (`XF86Launch2`) and
Copilot (`SUPER + SHIFT + F23`) binds of `config/hypr-user.lua` as editable,
deletable and conflict-free, then sends their evdev codes with `vinput` in a
nested Hyprland using the latam layout (`VINPUT_LAYOUT=latam`; `vinput.c`
defaults to `us`). Copilot must not fire the launcher's Super-release bind;
plain `F23` and `Shift+F23` must fire nothing.

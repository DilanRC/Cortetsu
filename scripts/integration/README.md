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

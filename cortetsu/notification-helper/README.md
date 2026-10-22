# Cortetsu Notifications — Rust port, opt-in, not installed

F5 parity candidate for `cortetsu/bin/cortetsu-notifications` (Python).
Builds `cortetsu-notifications-rs` to avoid replacing the currently installed
helper before the transition and reverse transition have been tested.

Commands: `count`, `history`, `dismiss ID`, `clear`, `dnd status/on/off/toggle`.
Reads the existing XDG state schema without upgrades or QML changes. Mutations
preserve unrelated fields and use a sibling tempfile plus `fsync`+rename.
The Rust helper's private advisory lock coordinates its own instances only;
**Quickshell does not acquire that lock**. The old owner remains active until
cross-process contention and real QML integration tests establish safety.

`history` on malformed JSON fails with exit 65 without overwriting the file;
`clear` deliberately replaces malformed history, matching Python. Usage errors
exit 64. DND status and history/count are strictly read-only.

For trial in a private HOME only:

```sh
cargo build --release --manifest-path cortetsu/notification-helper/Cargo.toml
XDG_STATE_HOME=/tmp/cortetsu-notif-test cortetsu/notification-helper/target/release/cortetsu-notifications-rs count
```

Do not install into `~/.local/bin` until parity and rollback are signed off.

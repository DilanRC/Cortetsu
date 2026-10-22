# Cortetsu native platform

`cortetsu-platform` owns platform operations previously implemented by the
repository's Python core and build transforms. It is a Rust implementation;
installed commands do not spawn a Python interpreter or load the archived Python
sources. `scripts/cortetsu` resolves this binary beside its own canonical path,
so a running command remains associated with its immutable helper generation.

## Commands and compatibility

The first argument identifies the former script; the `.py` suffix is accepted
for compatibility. Subsequent arguments retain the original command structure.

| Command | Responsibility |
| --- | --- |
| `dotfiles` | Profile plan, immutable generation, apply, verification, status, rollback and recovery |
| `system` | Schema 1/2 verification, helper-aware promotion, complete rollback and promotion recovery |
| `generation_gc` / `gc` | Reviewed garbage-collection plan, retention, metadata archive and coordinated removal |
| `doctor` | Repository and installed runtime diagnostics |
| `theme` | Theme checking, compilation and ownership adoption |
| `import_desktop`, `import_fish`, `import_hyprland` | Scoped imports with sensitive-file filtering and Git safeguards |
| `migrate_config` | Existing preference and state migration |
| `shell_lifecycle` | Audit and backed-up migration of shell lifecycle configuration |
| `migrate_legacy_processes` | Legacy ownership audit and configuration migration |
| `normalize-shell-24`, `normalize-contentwindow-overview-24` | Idempotent source normalization with required-anchor checks |
| `compose-panels`, `migrate-bottom-hub-from-main`, `check-bottom-hub-target` | Native build composition and compatibility checks |
| `wire_sad_shell`, `retire_legacy_theme` | Controlled shell wiring and obsolete-theme cleanup |
| `build-metadata`, `metadata`, `show-generation`, `verify-shell-metadata` | Build and status metadata without inline interpreter scripts |
| `seal-runtime`, `validate-runtime` | File inventory, digest sealing and runtime contract verification |
| `install-transaction` | Durable whole-install begin, activate, commit, recovery and status |

`metadata PATH FIELD...` accepts dotted object paths, for example
`metadata report.json bundle.directory`. Scalar values are printed one per line;
an absent field prints `unknown`.

Explicit environment roots are `HOME`, `XDG_CONFIG_HOME`, `XDG_DATA_HOME`,
`XDG_STATE_HOME`, `CORTETSU_DATA_ROOT`, and `CORTETSU_RUNTIME_ROOT`. Filesystem roots
must be absolute. CLI repository arguments use `--repo PATH` where applicable.

## Generation integrity

The installer builds and validates an immutable shell first, then stages a flat
helper bundle. The bundle includes a hashed `cortetsu-resource-root` executable
that identifies the exact shell generation containing its data files. Helpers
therefore retain their associated resources across promotion and rollback.

New system generations use schema 2. `SYSTEM.json` records the shell, dotfiles
and helper directories, digests of their manifests, and the owned launcher
names. Native shell manifests seal `FILES.json`, which records every runtime
file digest. Verification rejects changed contents, missing or extra files,
manifest drift, generation paths outside the managed build roots, unsafe
symlinks and launcher targets that bypass `helpers/current`.

The independently usable `cortetsu-rescue` verifier implements the same manifest
and launcher checks. The platform additionally checks the shell's composition,
wallpaper and required-file contracts. SHA-256 detects accidental or unreviewed
changes; it is not a signature against another process with unrestricted access
to the same user's files.

An existing schema 1 installation is upgraded without rewriting its original
`SYSTEM.json`. The installer records its installed helpers in a legacy bundle
and creates a new schema 2 checkpoint referring to the original shell and
dotfiles. This checkpoint retains an explicit `legacySourceSystem` proof. The
new native management commands are retained in that helper bundle when available
so recovery does not depend on the removed Python management source. Legacy
application helpers in that rollback checkpoint may still require the original
interpreter. Garbage collection retains the original schema 1 proof while any
retained checkpoint refers to it.

## Installation and crash recovery

`scripts/install-cortetsu.sh` owns `install.lock` across mutation. Helper staging
finishes before this outer lock is acquired. `install-transaction` requires the
caller to hold that lock; it does not silently disable locking or inherit an
unvalidated file-descriptor option.

1. `begin --repo R --helpers H --shell S` verifies staged artifacts, captures
   current and previous pointers, launchers, owned user files and subordinate
   journals, and syncs backups before writing a `PREPARED` journal. It prints
   the transaction ID.
2. The caller exports this ID as `CORTETSU_INSTALL_TRANSACTION`. `activate`
   durably marks the journal `ACTIVE` before selecting helpers and shell or
   changing launchers. Other platform mutations refuse a pending transaction
   unless they carry its token.
3. Theme ownership, dotfiles and lifecycle updates run inside the transaction.
   System promotion and complete verification precede `commit`.
4. `commit` checks that the selected shell and helpers equal the prepared
   generations, verifies the system and dotfiles, and records `COMMITTED`.
   Service reloads and owned daemon restarts occur afterward.

Every backed-up file has a digest and a recorded parent-directory identity.
Recovery verifies *all* backup records before restoring any target, refuses
redirected ancestors and unexpected directories, and can be resumed after a
second interruption. A failed installer invokes recovery from its EXIT trap;
if recovery itself cannot complete, it retains the native recovery executable
and prints its path. SIGKILL is handled on the next explicit recovery or install.

`cortetsu recover` holds the installation lock and processes the whole-install,
standalone dotfiles and standalone system-promotion journals in that order.
Standalone dotfiles apply restores its before-state. Standalone system promotion
completes the prepared target only if its shell, dotfiles, helpers and launchers
still match; it refuses unrelated changes instead of guessing which generation
the user intended. Normal complete-system rollback uses the rescue module's
durable rollback journal.

Backups and terminal-state journals remain available for diagnosis. `recover`
does not discard corrupt evidence or overwrite a user directory to force a
successful result.

## Building and verification

```sh
cargo test --locked --manifest-path cortetsu/platform-rs/Cargo.toml
cargo clippy --locked --manifest-path cortetsu/platform-rs/Cargo.toml --all-targets -- -D warnings
python3 cortetsu/platform-rs/tests/parity.py cortetsu/platform-rs/target/debug/cortetsu-platform
scripts/build-native.sh
python3 scripts/features/test-cortetsu-build.py --native-bundle "$PWD/dist/native"
```

The Python commands above are development test drivers only. Differential tests
load immutable reference implementations from `tests/reference/python-runtime`
and compare native output in temporary directories. They cover normalization,
bottom-hub transforms, shell wiring and preference migration. Native Rust tests
exercise manifest drift, ownership safeguards, imports, resource sealing,
helper-aware rollback, retained generations and interruption recovery, including
corrupted backups and redirected parents.

The integration driver runs the real installer twice with isolated HOME/XDG
roots and a PATH without Python, reusing the compiled bundle. It checks both
schema 2 generations, corruption rejection, complete rollback, preserved user
scheme state and automatic recovery after a real post-activation failure.
`systemctl` is mocked to prevent interaction with the test host; Qt Quick Test
is required and runs against the real QML suites. The real Arch CI gate supplies
Qt and Quickshell. A local run with a substitute Qt runner can only establish
filesystem plumbing, not QML correctness.

`cortetsu test` runs native, Node and QML suites. Historical Python structural
tests remain development oracles and are not installation dependencies.

# Native hardware and display runtime

`cortetsu-hardware-runtime COMMAND [ARGS...]` implements the existing command
interfaces for these eleven helpers:

- `cortetsu-display-probe`, `cortetsu-display-plan`, `cortetsu-display-persist`,
  `cortetsu-display-transaction`, `cortetsu-display-workspaces`;
- `cortetsu-hardware-probe`, `cortetsu-hardware-power`;
- `cortetsu-gamemode`, `cortetsu-nvibrant`, `cortetsu-power-auto`,
  `cortetsu-power-auto-control`.

Installed launchers select this binary within their own helper generation. The
binary contains no Python interpreter and launches no Python runtime. It uses
the desktop's existing `hyprctl`, `powerprofilesctl`, `nvibrant`, `systemctl`,
`edid-decode`, and passive GPU telemetry commands where appropriate.

## Typed ownership

The additional fixed command `exec` reads one bounded `cortetsu.exec/1` JSON
request from stdin. It accepts only these operations:

| Operation | Arguments | Authoritative body, besides common fields |
| --- | --- | --- |
| `power.status` | `{}` | `profile` |
| `power.profile.set` | `profile`: `balanced`, `power-saver`, or `performance` | `profile` |
| `gamemode.status` | `{}` | `enabled`, `state`, `options` |
| `gamemode.set` | `enabled`: boolean | `enabled`, `state`, `options` |
| `display.status` | `{}` | `outputs`, `preview` |
| `display.profile.preview` | `monitor`, `profile`: bounded strings | `outputs`, `preview` |

Every success includes a JavaScript-safe integer `revision` and
`manual_override_until_unix_ms`. Writes require `expected_revision` and a UUID
`idempotency_key`. A saved display profile must target exactly the requested
monitor. A typed display preview also requires established compositor color
readback; absent capability is rejected before preparing a mutation. Legacy
manual display commands retain their compatibility behavior.

Private owner journals live under
`$XDG_STATE_HOME/cortetsu/hardware-owners` (or the standard HOME fallback).
Power ownership is per user; display and game mode are scoped to the Hyprland
instance. Manual CLI writes and typed writes take the same domain lock. State
changes found by fresh readback advance the revision. Manual writes and detected
external changes establish a one-hour override; automation then receives
`USER_CONFIRMATION_REQUIRED`. `CORTETSU_MANUAL_OVERRIDE_SECONDS` can set a
duration between zero and 86,400 seconds.

A durable `PREPARED` record precedes external effects. Only verified readback
can produce `COMMITTED`, `verified: true`, and `outcome: applied`. An uncertain
operation blocks new mutations across that domain until a successful manual
operation has fresh readback. That recovery retains the original key as a
`RECONCILED_MANUAL` tombstone. The original request is never executed again.
Committed replays require the same payload, current revision and state hash.
Their response expires after seven days; expiration retains a terminal record
and produces `STATE_STALE`. The ledger is bounded at 4,096 entries and refuses
additional writes instead of evicting keys that could otherwise be replayed.

Display preview records the original state before applying commands and starts
its rollback watcher first. Confirmation and rollback use locks and token
checks. Rollback failures preserve the original journal for recovery. A changed
configuration file, external monitor geometry or established external color,
bit-depth or VRR changes prevent rollback from overwriting the newer choice.
Subprocesses have deadlines and bounded output; cancellation kills and reaps
their process groups, including descendants holding inherited pipes.

## Isolated verification

```sh
cargo test --locked
cargo clippy --all-targets --locked -- -D warnings
python3 tests/legacy_contracts.py
```

The Python command is a test-only compatibility harness; it runs existing
historical test assertions against the compiled native binary. Installed
runtime operation does not depend on it. Forty-four frozen planner cases are
also exercised directly by native tests without a Python reference at runtime.
Black-box fixtures cover duplicate requests, stale revisions, manual override,
expired tombstones, uncertain writes, cancellation, retained rollback journals,
ignored display changes, external edits, passive NVIDIA telemetry, and the
legacy automatic power loop.

Tests supply temporary HOME/XDG directories and fake executables. Sysfs/procfs
fixtures use `CORTETSU_SYSFS_ROOT`, `CORTETSU_DRM_ROOT`, and
`CORTETSU_PROCFS_ROOT`. They do not operate a real compositor, GPU, power
profile service, or user installation. Hardware-dependent capability readback
therefore remains subject to the installed compositor and driver interfaces.

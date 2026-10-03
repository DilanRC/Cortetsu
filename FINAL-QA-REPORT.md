# CORTETSU FINAL RELEASE QA

Verdict: **DO_NOT_MERGE**

SHA inicial: `4851e64df526378df81d55a6e5cdf52f94ac04ad`
SHA final: `925d6e09ab83e23ee9466e0634c0e95c44569066`
Rama: `ascension/product-elevation`
Generado: `2026-09-07T16:59:48.026378+00:00`

## Gate

`PENDING=0` en los artefactos de esta ronda. `BLOCKED_EXTERNAL` permanece en la matriz exhaustiva porque sólo hay un monitor y no existen fixtures para todos los backends/estados. Por eso el veredicto es `DO_NOT_MERGE`: los bloqueos no se ocultan como PASS.

| Área | PASS | FAIL | PENDING | BLOCKED_EXTERNAL | SKIPPED_SAFETY | NOT_APPLICABLE |
|---|---:|---:|---:|---:|---:|---:|
| Functional contracts | 19 | 0 | 0 | 2 | 0 | 0 |
| Keybinds | 11 | 0 | 0 | 169 | 2 | 0 |
| Design surfaces | 3 | 0 | 0 | 1 | 0 | 0 |

## Confirmed fixes

- Display Manager footer overlap fixed by reserving footer space in `cortetsu/modules/display/Editor.qml`.
- Display preview fixed for this non-legacy Hyprland parser by translating planned monitor commands to `hyprctl eval hl.monitor(...)`; real 60 Hz preview/revert passed and 144 Hz was restored.
- Screenshot freeze and region routes opened the real first-party picker and closed with Escape.
- Spotify tooltip disappeared after pointer leave; no stale tooltip remained through the tested transition.

## Technical validation

- `./scripts/cortetsu test`: PASS
- `./scripts/cortetsu install`: PASS
- `./scripts/cortetsu verify`: PASS
- `./scripts/cortetsu doctor --json`: PASS
- Service: `ActiveState=active`, `SubState=running`, `NRestarts=0`, `ExecMainStatus=0`
- Journal after final promotion: no QML errors, type/reference errors, binding loops, or segfaults.
- Zero-Caelestia audit: PASS.

## Performance

| Window | CPU average | RSS average | Threads |
|---|---:|---:|---:|
| 144 Hz / 60 s | 6.96% | 501516 KiB | 67 |
| 144 Hz / 15 min | 5.84% | 503758 KiB | 67 |
| 60 Hz / 60 s | 5.60% | 503870 KiB | 67 |

The 144 Hz mode was restored to 144.003 Hz. The 15-minute RSS sample did not show a sustained upward trend.

## Recording

- Path: `/home/dilan/Videos/Recordings/recording_20260907_10-43-02.mp4`
- Duration: 261.784726 s
- Resolution: 1920×1080
- ffprobe reported frame rate: 288/1
- Validated: PASS

## Safety skips

Destructive session/power actions are `SKIPPED_SAFETY`, not FAIL or PENDING. Their wiring was inspected structurally. No logout, shutdown, reboot, suspend, hibernate, lock, VT switch, compositor kill, display disable, or irreversible delete was executed.

## Cleanup

Cleanup audit found no safe repository deletion candidate. `.git`, stash, active `.claude/worktrees`, and historical provenance were preserved.

Source of truth: `~/cortetsu-qa/qa-state.json`, `functional-contracts.json`, `effective-keybinds.json`, `design-results.json`, `cleanup-results.json`. Verification command: `python3 ~/cortetsu-qa/verify-qa-artifacts.py`.

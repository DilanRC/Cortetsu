# Cortetsu coordinator and typed protocols

The Go module owns per-session observation, policy evaluation, consent and
coordination. Rust owns resource mutations and generation recovery; QML displays
confirmed snapshots and changes consent through a fixed local CLI.

| Package | Contract |
| --- | --- |
| `ipcv1` | Private AF_UNIX framing, UID/session/epoch negotiation, bounded read-only QML RPC |
| `execv1`, `execclient` | Strict typed Rust requests/responses, CAS, UUIDs, deadlines and process cancellation |
| `daemon` | One coordinator per session, metadata publication, reconnect and snapshot invalidation |
| `observehypr`, `observedbus` | Hyprland, logind, UPower and NetworkManager owner reads and event invalidation |
| `policy`, `coordinator` | Pure simulation plus consent-gated execution, hysteresis, TTL, cooldown and verified readback |
| `activation` | Private durable per-domain/session consent, explicit revocation and override |
| `policyaudit` | Bounded, redacted durable intent/result audit |
| `shadow` | Deterministic offline trace simulation |

```sh
go test -race ./...
go vet ./...
go run ./cmd/cortetsu-shadow -rules fixtures/rules.json < fixtures/trace.ndjson
go run ./cmd/cortetsu-python-inventory --repo ../.. --require-native
```

The shell starts `cortetsu-coordinator --observe` once. `cortetsu-bridge` is a
compatibility name for the same daemon. Neither grants consent at startup.
`cortetsu-policy status|rules` is read-only; `enable`, `disable`, `override` and
`revoke` change only configuration. Device writes remain enumerated requests to
the trusted sibling Rust owner. Default domains are disabled.

The full operating and verification contract is
[`docs/migration/NATIVE-RUNTIME.md`](../../docs/migration/NATIVE-RUNTIME.md).

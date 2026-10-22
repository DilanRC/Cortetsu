# F6 — Traza opcional del simulador Go

El motor de políticas sigue en simulación; `active` continúa respondiendo
`NO_VERIFIED_RUST_OWNER`. Para un análisis explícito sin ejecutar acciones:

```sh
mkdir -m 700 "$HOME/.local/state/cortetsu-policy-audit" # una vez
cd cortetsu/protocol
go run ./cmd/cortetsu-shadow -rules fixtures/rules.json \
  -audit-dir "$HOME/.local/state/cortetsu-policy-audit" < fixtures/trace.ndjson
```

La traza se limita a 4 MiB. Cada entrada incluye solo sesión, cursor de evento,
identificadores de regla/recurso, operación declarada y los códigos cerrados
de resultado/motivo. No contiene campos del evento, títulos, direcciones,
ventanas ni secretos. La bitácora es de usuario, modo 0600 en directorio 0700.
Error de escritura/permiso/capacidad aborta la evaluación, sin fail-open.

No existe unidad systemd ni escritura de hardware. Este gate todavía necesita
costo de CPU/PSS/batería medido sobre la máquina real y pruebas de integridad.

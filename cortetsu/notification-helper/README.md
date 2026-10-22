# Cortetsu Notifications — owner Rust

El bundle nativo instala este ejecutable detrás de `cortetsu-notifications`.
Mantiene count/history/dismiss/clear y dnd status/on/off/toggle. QML utiliza
merge con IDs base y revisión de clear; Go utiliza estado/DND tipados con CAS,
idempotencia durable y readback. Todos comparten el mismo lock.

DND preserva campos desconocidos y aplica cambios atómicos con fsync/journal.
La recuperación repara una intención incompleta o un anchor pendiente tras
commit; nunca reejecuta una clave incierta. Los cambios manuales tienen prioridad
sobre automatización. Los receipts automáticos son acotados; una elección manual
sigue disponible cuando el ledger está lleno.

El historial conserva su array JSON. Un clear tiene token durable propio para
no resucitar lotes anteriores, incluso si el array ya estaba vacío. QML aplica
el resultado sobre IDs congelados y conserva notificaciones posteriores.

Historial inválido falla con salida65; clear explícito puede vaciar un archivo
regular corrupto. Un symlink no se sigue ni reemplaza. DND corrupto se conserva
y devuelve error. Las lecturas de estado pueden reconciliar una edición externa
con una revisión y pausa manual; no se describen como estrictamente read-only.

```sh
cargo test --locked --all-targets
cargo build --locked --release
python3 tests/parity.py
```

La paridad usa referencias históricas archivadas; las pruebas adicionales cubren
las garantías transaccionales nuevas. La fixture Quickshell del historial usa
el owner real en un D-Bus privado. Ver el
[contrato completo](../../docs/migration/NATIVE-RUNTIME.md).

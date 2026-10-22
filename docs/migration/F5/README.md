# F5 — Migración Rust de helpers Python (primer candidato: notificaciones)

Estado: **PILOT / NO_CUTOVER**. La versión de Cortetsu desplegada continúa
usando `cortetsu/bin/cortetsu-notifications` (Python). Este piloto se compila
como `cortetsu-notifications-rs` y **no reemplaza la instalación ni su esquema**.

## Dominio y fuente de verdad

| Recurso | Propietario actual | Candidato Rust | Evaluación |
|---|---|---|---|
| `~/.local/state/cortetsu/notifs.json` | Quickshell `Notifs.qml` escribe snapshot; CLI elimina entradas | Misma ruta y JSON, por comandos explícitos | F5-Candidate |
| `~/.local/state/cortetsu/notification-status.json` | Servicio de notificaciones y CLI | Mismo objeto con `dnd`, claves ajenas preservadas | F5-Candidate |
| CLI `count`, `history`, `dismiss`, `clear`, `dnd` | Python, códigos 0/64/65 | Rust mantiene comandos y códigos | Paridad automatizada en HOME/XDG privado |

No se introducen sockets ni daemon ni se tocan preferencias de hardware.

## Verificaciones

- Rust `cargo fmt --check`, `cargo clippy --locked --all-targets -- -D warnings`, `cargo test --locked`. Artefactos de CI con `Cargo.lock` en el repositorio.
- `tests/parity.py` ejecuta Python y Rust con estados iniciales equivalentes
  pero **distintos** `XDG_STATE_HOME` temporales; compara códigos de salida,
  salida normalizada y JSON resultante tras operaciones secuenciales.
- Entradas de prueba con Unicode, fallback `notificationId`/`id`, DND con
  propiedades desconocidas, historia corrupta y uso inválido.
- El helper Rust escribe archivos con `fsync`+rename y permisos privados;
  `dnd status`, `history` y `count` no escriben.

## Pendientes que bloquean retirar Python

1. La antigua implementación no usa el lock del candidato Rust. No promover
   sin definir propietario único para `Notifs.qml`, coordinar simultaneidad y
   evitar pérdidas entre un dismiss concurrente y un snapshot de QML.
2. Realizar pruebas de interacción en Quickshell/Wayland, incluyendo `FileView`,
   notificaciones vivas, DND, restart y rollback de ambas versiones.
3. Integrar helper y hashes dentro de generaciones para que `rollback`
   restaure el binario correcto; no copiar encima de `~/.local/bin` sin respaldo.
4. Conservar Python original hasta que pasen paridad, CI, compatibilidad y
   gates físicos pertinentes. Este paquete NO constituye F5 completada.

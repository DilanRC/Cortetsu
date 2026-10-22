# Cortetsu 2.0 — F1b, inicio de F2/F4/F6/F7 (trabajo en nube)

> Registro de diseño/prototipo anterior a la integración nativa. Para el
> comportamiento actual, consultar [NATIVE-RUNTIME.md](../NATIVE-RUNTIME.md).

**Estado: `IN_PROGRESS / NO_CUTOVER` — no es una release candidate.**
Base revisada en GitHub: `b586c90db06d08bf0aba22a55e809f69e8b2a9ee` (instalación estable después de #51).
Fecha del trabajo aislado: 2026-10-22. No activar nada en la sesión real ni sustituir Python.

El objetivo del usuario es continuar F1b–F11 en orden y probar en su CachyOS al final. Esta entrega conserva el escritorio actual intacto: los archivos son **aditivos**, no se instalan automáticamente. Nada de aquí justifica declarar F1b–F11 completas o apagar un owner anterior.

## Implementado y verificable

| Dominio | Entregado | Verificación disponible | Falta para cerrar la fase |
|---|---|---|---|
| F1b, `cortetsu.exec/1` | JSON Schema (request/response), fixtures, analizador estricto Go, validación de argumentos enumerados, límites y JCS/SHA-256 | Go tests + fuzz seeds, RFC 8785 sample, rechazos por duplicate keys/UTF-16/negative-zero/oversize/major | Cliente Rust equivalente, journal idempotente, dos sesiones Wayland reales, integración con helpers, owner/revision/readback |
| F1b, `cortetsu.ipc/1` | Hello/negociación, requests solo lectura, separación de sesión/epoch, bounded framing y denegación de operaciones mutantes | `ipcv1` tests Go + socket AF_UNIX aislado (SO_PEERCRED, UID actual, root 0700/socket 0600) | ADR de socket definitiva, bind/peer modelo de sesión Wayland real, mensajes de evento completos y snapshots de owners |
| F2 (prototipo) | `cortetsu-rescue`: `verify/status/plan-rollback`, `exec system.verify`, `recover` y rollback **explícito solo de punteros** con journal fsync | Rust CI Clippy/test/build y SIGKILL en HOME privado | Restauración de helpers dentro de generación, fallos ENOSPC y readback físico antes de la adopción |
| F4 (prototipo) | Normalizador Go y adaptador de **observación Hyprland AF_UNIX** voluntaria con payload redactado, reconexión y resync | `go test -race`, fake socket desconectado, simulación multisession | logind, snapshots reales completos, decisión de socket, benchmark PSS/CPU/dGPU; no daemon activado |
| F6 (prototipo) | Motor de reglas declarativo con prioridades, overrides manuales, cooldown, TTL, campos de evento permitidos, modos `observe/simulate/active` | Tests deterministas y escenarios de seguridad | Reglas de dominio, hysteresis, persistencia de trace, presupuestos y activación opt-in; `active` deliberadamente devuelve `NO_VERIFIED_RUST_OWNER` |
| F7 (prototipo) | `cortetsu.ipc/1` en librería y servidor de pruebas de solo lectura; utilidad `cortetsu-shadow` para trazas offline | Socket test con dos rutas y handshake separado; fixture de salida determinista | Bridge QML, reconnect físico, event streams reales, permiso de usuario, control de sockets múltiples |
| F3/F8/F9/F10/F11 | Sin cutover funcional | No procede | Requieren contratos y propietario verificados, paridad Python/Rust, QA física y release |
| F5 (piloto) | `cortetsu-notifications-rs` con los mismos comandos y estado JSON | `cargo test`, `clippy` y comparador Python/Rust sobre XDG temporal en CI | Concurrencia con Quickshell, ownership, rollback de binario, pruebas físicas |

## Diseño y seguridad

- El protocolo **nunca** admite `shell.exec`, `argv` arbitrario, scripts, secretos, ni rutas para ejecutar comandos; las operaciones enumeradas son el único vocabulario válido.
- Éxito de `cortetsu.exec/1` requiere `verified=true` en la respuesta. Un código 0 de proceso no equivale a readback. Ninguna operación nueva tiene todavía owner Rust y **no se ejecutan mutaciones**.
- JSON con claves duplicadas, UTF-8 inválido, surrogates aislados, cero negativo, números binary64 no finitos y frames grandes se rechazan; se exigen versión y códigos estables.
- RFC 8785/JCS genera fingerprint de idempotencia **solo** como dato: no existe todavía journal durable, tombstone, reconciliación ni ACL de escrituras, así que no puede autorizar reintentos con efectos.
- La instancia AF_UNIX se levanta **solo desde tests** en un directorio temporal 0700. Compara UID del peer mediante SO_PEERCRED, protocolo/sesión/epoch y no admite operaciones mutantes. No se configura unidad `systemd`, no hay socket ni puerto en el escritorio instalado. La coincidencia de UID no protege frente a otro proceso comprometido del mismo UID.
- El simulador `cortetsu-shadow` lee trazas JSONL por stdin y, opcionalmente, reglas JSON desde un archivo explícito, sin invocar procesos, API de hardware, sockets reales de Hyprland ni modificar disco.
- `cortetsu-rescue` comprueba `SYSTEM.json`, `BUILD.json` y `MANIFEST.json` sin el checkout. Su `rollback` explícito puede cambiar seis punteros y journaliza/recupera interrupciones, **pero no restaura helpers**, lo que impide instalarlo como reemplazo automático del rollback actual; `verify`, `status`, `plan-rollback` y `exec` son de lectura.

## Pruebas locales en el entorno de nube

```sh
cd cortetsu/protocol
go test ./...
go test -race ./...
go vet ./...
test -z "$(gofmt -l .)"
go run ./cmd/cortetsu-shadow -rules fixtures/rules.json < fixtures/trace.ndjson
```

Go pasa en Linux x86_64 con fake sockets AF_UNIX, pero no son dos sesiones Wayland reales. Los workflows están incorporados a `main` y ejecutan las compilaciones en GitHub Actions. Los artefactos siguen opt-in y fuera de la instalación real.

GitHub Actions ejecuta estas comprobaciones con Rust estable y `Cargo.lock` fijado:

```sh
cd cortetsu/rescue
cargo fmt --all -- --check
cargo clippy --locked --all-targets -- -D warnings
cargo test --locked --all-targets
cargo build --locked --release
```

Cada commit debe superar el workflow Rust. No añadir binario Rust a `~/.local/bin` ni usar su rollback en producción hasta validar helpers, compatibilidad y estados de recuperación en CachyOS real.

## ADR provisional: socket por sesión

**Propuesta, no aceptada para producción:** un socket AF_UNIX por sesión Wayland, con nombre asociado a un identificador opaco de sesión y epoch aleatorio/reiniciado; no TCP. Directorio XDG runtime 0700, socket 0600 y UID obtenido de SO_PEERCRED; heartbeat limitado, frame 64 KiB y conexión acotada. El contrato impide que una petición de sesión B se confunda con la de sesión A. El test usa dos sockets aislados, pero **faltan dos sesiones Wayland simultáneas reales y la comprobación de exposición del pathname**. No encender una unidad `systemd` antes del ADR.

## Siguientes gates, no alcanzados

1. **F1b:** contratos de lectura y mutación equivalentes Go/Rust/QML, tablas de propietarios, fixtures compartidas y socket ADR físico. Sin fail-open al cambiar de versión.
2. **F2:** CLI Rust offline con `recover/rollback` transaccional, journal y backups de helpers, prueba SIGKILL entre enlaces; comparación contra Python; estado `RECOVERY_REQUIRED` cuando corresponda. Un `plan-rollback` **no** es rollback.
3. **F3/F5:** cada helper Python pasa a Rust solo con readback, tests de paridad y rollback por dominio. No eliminar funciones actuales mientras falten gates.
4. **F4/F6:** observer Go real, costes medidos y políticas inertes por defecto. Simulación sin escrituras y con trazas deterministas.
5. **F7/F8:** puente QML real y activación por dominio sin doble escritor. Conserva teclado, focus, pantallas y OSD del shell #51.
6. **F9:** CI/instalador/tooling sin Python propio y sin reducción de cobertura. No tocar el Python de Arch.
7. **F10/F11:** pruebas en HP Victus de HDMI, suspensión, OMEN/Copilot, GameMode, energía, juegos y rollback físico. Release solo después del gate humano.

**Resultado de esta entrega: `PARTIAL_CODE_READY`, integración en `main` = `PUBLISHED`; QA física y cutovers = `NOT_TESTED`.** El estado de CI es el de los checks del HEAD actual, no el de una ejecución histórica; verificarlo en GitHub Actions. La presencia del código no satisface los gates de F3–F11.


## Incremento de implementación (2026-10-22): Rust rollback explícito y Go observer

El CLI Rust ahora incluye un motor de intercambio de **punteros únicamente**,
con `flock` sobre `system.lock`, journal durable `rescue-transaction-v1.json`,
readback y compensación ante fallo. `recover` puede deshacer un intercambio
incompleto después de un crash. Las pruebas de Rust contienen una simulación
de interrupción tras el tercer enlace, preflight de generación anterior, un
rollback reversible y rechazo del journal con schema desconocido. La ruta de
escritura se **rechaza por defecto**: exige `--acknowledge-unmanaged-helpers`
porque el sistema instalado de schema 1 no incluye `~/.local/bin` en las
generaciones. No llamar a este mecanismo desde el instalador, la sesión ni la
CLI histórica hasta que se complete el gate de helpers y la QA local.

Go añade `cortetsu-coordinator` como **observador explícito** que lee
`HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock` por AF_UNIX, emite solo tipos de
evento permitidos (nunca títulos, direcciones ni payload arbitrario), y
publica `resync_required` con un epoch nuevo tras reconexión. No interpreta
comandos del usuario ni solicita acciones Rust. Las pruebas usan un socket
Hyprland falso, eventos secretos, desconexión/reconexión y sesiones aisladas.
**No se instala una unidad ni se consume CPU en reposo de la sesión real.**

Estas mejoras corresponden a partes de F2 y F4. **No completan F3, F5, F7,
F8, F9, F10 o F11**. No se autoriza eliminar Python propio ni declarar un
release hasta la paridad y la QA física. La compilación de Rust debe ser
corroborada por GitHub Actions en el SHA que contenga este incremento.


## Adaptador Rust/Go compartido y prueba de proceso interrumpido

`system.verify` es la primera operación de **lectura** admitida por ambos
validadores `cortetsu.exec/1`. Los binarios no habilitan `set` ni un ejecutor de
comandos. La fixture `cortetsu/contracts/exec/v1/fixtures/system-verify.json`
se consume desde tests de Go y tests Rust de la CLI. El CLI Rust devuelve
`verified=true` solo tras leer y comprobar la generación real o de pruebas.

El test Rust de recuperación lanza el CLI como proceso independiente con
`CORTETSU_RESCUE_TEST_PAUSE_AFTER=3` (instrumentación **solo debug**), lo mata
mediante SIGKILL y ejecuta `recover` desde otro proceso. Se exige retornar al
snapshot de seis punteros sin un checkout de Cortetsu. Aún faltan tests de
rotura de disco/ENOSPC y la restauración de los helpers.


## F5 (paralelo, sin cambio de propietario): notifications

Existe un primer candidato Rust para `cortetsu-notifications` con CLI y
esquema históricos, ficheros XDG privados y comparación semántica contra
Python. Consulte `docs/migration/F5/README.md`. No se activa en Quickshell:
se conserva la única ruta instalada hasta verificar la concurrencia de
Notifs.qml, el helper de generación y el rollback.

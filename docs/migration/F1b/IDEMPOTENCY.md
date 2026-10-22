# F1b — Tombstones idempotentes en Rust (sin owner de mutación)

`cortetsu/rescue/src/idempotency.rs` contiene una bitácora durable **inerte**,
preparada para una operación enumerada y autenticada. Exige directorio privado
0700 ya existente, llave UUID, huella SHA-256 canónica, recurso y revisión
esperada. `begin` persiste `PREPARED` con fsync **antes** de una posible acción;
repetir una llave preparada regresa `RECOVERY_REQUIRED`, nunca reejecuta.
La misma llave con otros argumentos/revisión devuelve `IDEMPOTENCY_CONFLICT`.

`finish_with_readback` requiere una lectura del owner que devuelva revisión
estrictamente mayor que la esperada; un exit 0 no basta. Tras `VERIFIED`,
los reintentos devuelven `READBACK_REQUIRED` hasta consultar el estado real,
no un éxito de caché. Si ocurre un crash, el archivo PREPARED persiste y la
reconciliación debe decidirse por operación; no se borra automáticamente.

Esta librería no incluye CLI para aplicar, no ejecuta comandos y no está
conectada al coordinador Go. **No cierra F1b ni habilita F8** sin ACL de
propietario, contratos de mutación Rust↔Go↔QML, reconciliación durable,
baseline de rendimiento, tests multisesión y QA del equipo.

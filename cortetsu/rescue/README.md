# cortetsu-rescue — recuperación Rust independiente

Se incluye en las generaciones nativas. `verify`, `status` y `plan-rollback`
funcionan sin QML, Go, Python ni checkout. Schema 2 comprueba shell, dotfiles,
helpers, manifiestos sellados y launchers. `rollback` restaura los punteros
coordinadamente con journal, preflight y readback; `recover` repara su journal.
Para journals pendientes del instalador, dotfiles o promoción se utiliza
`cortetsu recover`, antes de iniciar otro rollback.

Schema 1 se conserva para inspección histórica. Su rollback aislado requiere
`--acknowledge-unmanaged-helpers` porque ese formato no registra ejecutables.
El instalador nuevo crea un checkpoint schema 2 con los helpers heredados al
actualizar, sin reescribir el SYSTEM original.

`helpers-stage SOURCE` prepara un bundle inmutable con SHA-256; no lo activa.
`exec` recibe `cortetsu.exec/1` por stdin: verificación de sistema, estado/DND de
notificaciones y dispatch tipado al owner hardware de la misma generación.
Rechaza argv arbitrario, revisiones stale, duplicados JSON, respuestas inválidas
u owners no confiables. Los procesos y pipes tienen límites y cancelación.

Ver [contrato operativo](../../docs/migration/NATIVE-RUNTIME.md) y
[plataforma](../platform-rs/README.md). Los tests de nube no sustituyen QA física.

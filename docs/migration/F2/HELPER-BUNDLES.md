# F2 — Generaciones de helpers (staging sin cutover)

El primer defecto real de instalación detectado después de la PR #51 fue que `cortetsu rollback` revertía shell y dotfiles pero dejaba los ejecutables copiados a `~/.local/bin` en la versión nueva. El esquema `SYSTEM.json` 1 no menciona esos helpers.

`cortetsu-rescue helpers-stage --experimental /ruta/absoluta/cortetsu/bin` crea una copia inmutable de los archivos regulares `cortetsu-*` en `$CORTETSU_DATA_ROOT/helpers/builds/helpers-...`. Genera `HELPERS.json` con SHA-256 por archivo, sincroniza los datos antes de publicar y verifica que el archivo no se modificó durante la copia. `cortetsu-rescue helpers-verify BUILD_ID` comprueba entradas, tamaño, hash y rechaza symlinks y archivos adicionales. Respeta el mismo `install.lock` del instalador.

**No cambia `~/.local/bin`, no crea symlinks activos, no altera `SYSTEM.json` y no recupera helpers todavía.** No incluye automáticamente `cortetsu-keybinds` (Rust), porque se construye desde otro directorio; un stage futuro debe reunir todos los helpers reales, más unidades y manifiestos. Con un schema-2 faltan definir el owner, comprobación de hashes de los 32 ejecutables, retención y la transacción que permita promoverlos/retrocederlos como una sola unidad observable. No activar rollback Rust de punteros mientras quede una versión auxiliar sin respaldo.

Pruebas Rust: stage, verify, modificación posterior, symlink malicioso, nombres peligrosos, bloqueo concurrente. Faltan ENOSPC real, fuente simultáneamente modificada con mismo tamaño y QA de instalación/rollback en el Victus. El stage no es un cutover de F2 ni cierra F3.

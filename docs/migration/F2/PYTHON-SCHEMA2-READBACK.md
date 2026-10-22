# F2 — verificación defensiva de bundles de helpers (schema 2)

**Estado: verificación solamente, sin cutover.** El instalador y
`core/system.py promote` siguen escribiendo `SYSTEM.json` schema 1. Los
helpers instalados en `~/.local/bin` permanecen bajo el propietario existente.

`core/system.py` acepta schema 2 en `validate_system`, `verify` y `status`,
siempre que `helpersGeneration` esté en el directorio administrado
`<data>/helpers/builds/helpers-*` y `HELPERS.json` sea íntegro. Los hashes,
modos ejecutables, número de archivos, entradas no esperadas, límites de
bytes, ruta y enlace `helpers/current` forman parte del readback. No acepta
una generación schema 1 que declare helpers ni una schema 2 sin ellos.

La ruta Python de `rollback` **rechaza** schema 2 y cruces entre schema 1/2;
no realiza el rollback histórico de seis enlaces si el sistema debe gestionar
ocho. El propietario transaccional experimental para schema 2 es
`cortetsu-rescue`, protegido por journal; aún no sustituye las operaciones
del instalador ni restaura el entorno de `~/.local/bin`.

El gate offline `scripts/features/test-system-helper-schema2.py` crea
shell, dotfiles y dos bundles de prueba bajo un directorio temporal, sin
modificar la sesión del usuario. Verifica detección de modificaciones, drift,
manifest e incapacidad de rollback mixto. Ejecutarlo junto a
`test-system-generations.py` y `test-system-recovery.py`.

**No activar schema 2 en producción** hasta que los ejecutables instalados
apunten de forma verificable al bundle activo y las transiciones completas
(schema 1 → 2 y 2 → 1) preserven un rollback funcional, sin cambios de
propiedad por parte de otros procesos.

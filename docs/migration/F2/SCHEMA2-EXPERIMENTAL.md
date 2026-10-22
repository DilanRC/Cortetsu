# SYSTEM.json esquema 2 (propuesta experimental no instalable)

> Registro de diseño/prototipo anterior a la integración nativa. Para el
> comportamiento actual, consultar [NATIVE-RUNTIME.md](../NATIVE-RUNTIME.md).

Formato adicional respecto al esquema 1:

```json
{
  "schema": 2,
  "shellGeneration": "/absolute/cortetsu/builds/shell-id",
  "dotfilesGeneration": "/absolute/cortetsu/dotfiles/builds/dots-id",
  "helpersGeneration": "/absolute/cortetsu/helpers/builds/helpers-id"
}
```

El verificador Rust exige que `helpersGeneration` sea un directorio inmediato
bajo `helpers/builds`, que tenga `HELPERS.json` válido y que cada SHA-256 coincida.
`system/current` requiere el puntero `helpers/current` a ese mismo bundle. El
rollback de **punteros** ahora contempla `helpers/current/previous` además
de los otros seis enlaces, con journal y fsync; no instala ni comprueba todavía
los enlaces efectivos bajo `~/.local/bin`.

**No usar schema2 en producción:** el instalador y `core/system.py` continúan
siendo schema1 y los helpers instalados son copias independientes; un rollback
de punteros en schema2 no garantiza, por sí mismo, que el shell ejecute los
helpers correspondientes. Falta una migración transaccional de instalación
con respaldo de los 32 ejecutables, actualización de ownership y rollback
exacto. En particular no cambiar los enlaces de usuario sin preservar los
archivos originales y sin pruebas físicas de todos los dominios.

Compatibilidad: Rust sigue leyendo schema1 sin exigir bundles. Los estados
mezclados schema1/schema2 bloquean rollback, evitando un downgrade implícito.

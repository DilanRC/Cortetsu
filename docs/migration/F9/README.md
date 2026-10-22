# F9 — Inventario verificable antes de retirar Python propio

**Gate de retirada: `NOT_READY`**. La versión instalada todavía depende de
Python en `scripts/cortetsu`, `core/*.py`, helpers de `cortetsu/bin/` y pruebas
de integración. Sustituir tres comandos y borrar los `.py` daría un falso
`Python-free` y perdería recuperación, seguridad o funcionalidades.

`cortetsu/protocol/cmd/cortetsu-python-inventory` es una herramienta **Go**
de solo lectura que inspecciona archivos Git rastreados, su extensión y su
shebang. Agrupa rutas Python en runtime, test y tooling, y compara runtime
contra la lista congelada `python-baseline.json`. Una nueva dependencia
Python del runtime falla la CI; eliminar una ruta migrada reduce la lista
sin editar el baseline. Esta clasificación **no** cuenta scripts de Bash que
llaman a Python, imports transitivos ni librerías del sistema; esos caminos
se auditan en el gate F9 final.

La cifra del inventario es una fotografía del árbol actual, no un indicador
de que se haya migrado algo. El gate F9 completo requiere un Rust/Go
`install/verify/rollback/doctor/test` funcional sin Python de primera parte,
la equivalencia de todos los helpers y la ejecución de CI sin intérprete
Python en PATH dentro del entorno de prueba. No se elimina el Python de Arch.

Ejecutar:

```sh
cd cortetsu/protocol
go run ./cmd/cortetsu-python-inventory --repo ../.. --baseline ../../docs/migration/F9/python-baseline.json
```

## Dato corregido (2026-10-22)

La primera clasificación omitía `cortetsu/services/ConnectivitySecret.py` como
runtime: `ConnectivityNmAdapter.qml` lo invoca explícitamente con `python3`.
El inventario ahora contabiliza **41 rutas Python runtime** y un apartado
`runtime_python_invocations` con los launchers QML/Bash que todavía dependen
del intérprete. Esto sigue siendo una aproximación conservadora: el gate final
requiere un rastreo completo de imports y de todas las rutas dinámicas.

NO eliminar `ConnectivitySecret.py` ni la ejecución Python que lo llama sin
conservar el aislamiento y protección de secretos de NetworkManager.

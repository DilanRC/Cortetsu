# F9 — runtime nativo sin Python propio

El runtime nuevo tiene **cero archivos Python y cero sitios de invocación de
Python**. El baseline original de 41 rutas se conserva en
[`python-baseline.json`](python-baseline.json); no se edita para ocultar rutas.
Dos transformaciones adicionales del instalador también se migraron a Rust.

Los 43 originales Python y seis scripts de integración quedan en
[`tests/reference/python-runtime`](../../../tests/reference/python-runtime),
con el SHA de origen y hashes por archivo. Son oráculos de desarrollo; no se
copian al bundle ni se importan desde Rust. Las pruebas históricas estructurales
pueden ejecutarse en una copia congelada mediante `cortetsu test --developer`.
`cortetsu test` utiliza Rust, Go, Node y Qt.

```sh
cd cortetsu/protocol
go run ./cmd/cortetsu-python-inventory --repo ../.. --require-native
```

El inventario inspecciona archivos rastreados y nuevos, shebangs, extensiones y
sitios de llamada QML/Bash/systemd. CI añade comprobaciones de los paquetes y
launchers y ejecuta el instalador real con un PATH que no contiene intérprete
Python. Ese gate cubre instalación, verificación, scheme, dos generaciones,
rollback y recuperación de un fallo, usando un bundle nativo ya compilado.
Las herramientas de compilación/pruebas pueden usar Python en CI.

[`NATIVE-RUNTIME.md`](../NATIVE-RUNTIME.md) documenta los owners y el cierre de
cada dominio. `cortetsu-connectivity-secret` usa D-Bus nativo para NetworkManager
y Secret Service; recibe el secreto por stdin, no por argv ni por logs.

El rollback a un checkpoint anterior a esta migración conserva sus helpers
históricos y puede necesitar Python, igual que aquella versión. No se elimina
el paquete Python de Arch ni las dependencias de aplicaciones ajenas.

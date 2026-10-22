# Cuarentena de aplicaciones — helper Rust

`cortetsu-prune-applications` utiliza este ejecutable en el bundle nativo.
Acepta --dry-run o ninguna opción, considera los `.desktop` del directorio
XDG_DATA_HOME/applications y mueve entradas rotas a la cuarentena de Cortetsu.
No elimina paquetes ni entradas del sistema, y no ejecuta el campo Exec.

La paridad compara dos HOME separados, incluyendo delimitadores `=`/`:`,
DEFAULT, claves/sections repetidas, comentarios, continuaciones, indentación,
archivos malformados fuera de Desktop Entry y quoting compatible con shlex.
Los errores de acceso o movimiento se comunican; una operación de cuarentena
no es una transacción global de múltiples archivos. Las entradas movidas se
conservan para recuperación explícita.

Ver [runtime nativo](../../docs/migration/NATIVE-RUNTIME.md).

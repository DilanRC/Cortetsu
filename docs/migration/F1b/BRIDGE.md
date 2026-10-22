# Cortetsu 2.0 — Puente IPC local de lectura (experimental)

**Estado:** se compila y prueba en entorno aislado. No está habilitado en la instalación actual y no sustituye `Notifs`, `Hypr`, `Calendar` ni otro propietario.

## Topología y activación manual

`cortetsu-bridge` es un ejecutable Go aislado. No hay unidad de systemd ni socket activation predeterminados. La opción `--observe` conecta el stream de eventos a Hyprland. Siempre usa un socket AF_UNIX por sesión con UID comprobado; no TCP, root ni shell. El componente `CortetsuPolicyBridge.qml` se instancia una sola vez a través de `Loader` únicamente si se define `CORTETSU_V2_IPC_EXPERIMENTAL=1` **antes** de iniciar Quickshell. No altera ventanas, foco, teclado ni atajos.

Para probarlo en una sesión desechable, con `XDG_RUNTIME_DIR` y `HYPRLAND_INSTANCE_SIGNATURE` válidos:

```sh
cd cortetsu/protocol
go build -o ./dist/cortetsu-bridge ./cmd/cortetsu-bridge
./dist/cortetsu-bridge --session "$HYPRLAND_INSTANCE_SIGNATURE" --observe
```

El servicio crea `$XDG_RUNTIME_DIR/cortetsu/cortetsu-$HYPRLAND_INSTANCE_SIGNATURE.sock` (0600) y un descriptor `bridge-$HYPRLAND_INSTANCE_SIGNATURE.json` (0600), ambos dentro de directorio 0700 y sin sobrescribir un socket existente. La sesión tiene epoch aleatorio; el cliente QML lee el descriptor y negocia `hello`/`hello_ack` antes de pedir `snapshot.get`. La ruta y el descriptor son locales y no se consideran secretos frente a otros procesos del mismo UID.

**No activar esta opción en la sesión personal como parte de las pruebas CI.** La comprobación final requiere probarla con dos sesiones Wayland reales, distintas firmas de compositor y un cambio/reinicio de Hyprland.

## Contrato de seguridad

- El servidor recibe **solo** `snapshot.get`, `policy.list`, `policy.simulate` y `explain.get`; `gamemode.set`, display, comandos arbitrarios y mutaciones siguen rechazados.
- Los snapshots contienen únicamente contadores y booleanos; nunca títulos, datos de notificación, información sensible de red o direcciones de ventanas.
- Con `--observe`, cada solicitud de snapshot consulta directamente `j/monitors` y `j/workspaces` sobre el socket de control Hyprland, con deadline de 450 ms por petición y conexión cerrada inmediatamente. Los eventos de `socket2` son normalizados y redactados.
- La UI no inventa estado válido después de un error: muestra `UNAVAILABLE`, `STALE` o `OWNER_UNAVAILABLE`. La falta de snapshot autoritativo no se disfraza de éxito.
- Se limita el número de clientes, frames (64 KiB), timeouts, requests por conexión, permisos y capacidad. No hay comandos de escritura ni renovación automática de políticas.

## Gates aún abiertos

1. Dos sesiones Wayland reales, eventos de hotplug y reconexión sin perder foco ni teclado.
2. Pruebas de coste CPU/PSS, wakeups y dGPU dormida, comparadas con el baseline F0.
3. Seguridad de socket frente a UID ajeno y rutas de runtime inusuales en CachyOS real.
4. Integración QML con Quickshell 0.3.2 en compositor anidado y QA física.
5. Separar caches read-only del coordinador de un posible futuro estado `active`; no se activa ninguna acción Go→Rust.

Rollback: no lanzar `cortetsu-bridge`, no establecer la variable experimental, o detener manualmente el proceso. El desktop actual no depende del puente.

## Políticas read-only y trazabilidad en memoria

`cortetsu-bridge --rules /ruta/reglas.json` añade un catálogo declarativo local
validado (máximo 64 KiB y 128 reglas, sin campos secretos). `policy.list` lo
publica a clientes que negociaron la capacidad. `policy.simulate` devuelve
solamente decisiones, sin mutar recursos. `explain.get` conserva hasta 16
trazas **por conexión**, sólo en memoria y con un máximo de 64 decisiones
por traza; tras desconexión desaparecen. Go bloquea `active` sin ejecutor Rust
verificado. La CLI no se instala ni lanza automáticamente.

## Prueba mínima de integración

El test Go establece dos sockets de sesión independientes y confirma una
secuencia real AF_UNIX de hello, `snapshot.get`, `policy.list`, simulación,
explicación y rechazo de `display.profile.preview`. Una segunda suite de Qt
parsea el componente QML en Arch, además de comprobar estáticamente que está
desactivado por defecto. Esto **no** reemplaza una prueba con Hyprland y
Quickshell 0.3.2 corriendo sobre un compositor anidado real.

## Interoperabilidad Go→Rust de lectura

El bridge solo admite `system.verify` **si** se inicia con
`--rescue-binary /ruta/absoluta/cortetsu-rescue`. El cliente Go `execclient`
rechaza ejecutables relativos, symlinks y archivos editables por grupo/otros;
lanza ese binario exclusivamente con el argumento fijo `exec`, stdin JSON
limitado a 64 KiB y timeout. No acepta argv ni rutas desde una petición IPC.

La salida se valida contra `cortetsu.exec/1`, exige id de solicitud idéntico,
`outcome=read` y `verified=true`; no confía en exit code 0. Solo hereda
variables HOME/XDG/CORTETSU_* de la configuración fiable del proceso, y
no muestra stderr ni contenidos de peticiones en logs. Sin `--rescue-binary`,
la lectura devuelve `OWNER_UNAVAILABLE` y ningún ejecutor se inicia.

`cortetsu-v2-cross-language-ci.yml` construye Rust y Go, levanta un socket
por sesión en HOME/XDG privado, comprueba `system.verify` contra una
generación ficticia de schema1 y rechaza `display.profile.preview`. No
reemplaza la prueba física de dos sesiones Wayland ni el contrato de mutación
con journal idempotente todavía pendiente.

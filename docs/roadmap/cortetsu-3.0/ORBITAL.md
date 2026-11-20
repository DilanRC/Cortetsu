# Orbital: fondos animados de Steam

Estado: **IMPLEMENTADO_SIN_VERIFICAR**. La cadena completa está escrita:
Orbital QML → catálogo Steam → supervisor Rust → renderizador Wayland de
Almamu → ownership por monitor → reproducción o fondo estático → `orbital.json`.
No se compiló, no se ejecutaron pruebas ni el motor, y la generación instalada
no cambió. Nada de este documento afirma que un fondo se reproduzca: eso lo
decide la QA de [QA_POSTERIOR.md](QA_POSTERIOR.md#orbital-reproducción-escenarios-sin-ejecutar).

## Arquitectura

| Pieza | Archivo | Responsabilidad |
| --- | --- | --- |
| Catálogo | `desktop-runtime-rs/src/orbital.rs` | Descubre bibliotecas Steam y lee `project.json` sin ejecutar nada |
| Supervisor | `desktop-runtime-rs/src/orbital_session.rs` | `cortetsu-orbital session`: procesos, ownership, estados, preferencias |
| Backend | `trait Backend` + `Almamu` en el mismo archivo | Inspección de compatibilidad y argv del motor |
| Cliente QML | `services/Orbital.qml` | Arranque bajo demanda, canal JSON, espejo de snapshots |
| Cubierta estática | `modules/background/Background.qml` | Acusa por fotograma la cubierta y la revelación |
| Interfaz | `modules/wallpaper/SteamLibrary.qml`, `SteamPlayback.qml` | Galería, controles y estados |

No hay un daemon nuevo. El supervisor es un modo del ejecutable
`cortetsu-desktop-runtime` ya registrado como `cortetsu-orbital`, hijo del
proceso Quickshell: lee peticiones por stdin y emite snapshots por stdout. Si
Quickshell se cierra o recarga, stdin se cierra y el supervisor mata sus
renderizadores. Un lock en `$XDG_RUNTIME_DIR/cortetsu/orbital.lock` impide dos
supervisores por sesión. El protocolo está en [el contrato](ORBITAL_CONTRATO.md#supervisor-de-reproducción).

## Ruta de presentación

`linux-wallpaperengine` (Almamu) ya presenta en Wayland de forma nativa:
`WaylandOpenGLDriver.cpp` usa `zwlr_layer_shell_v1` por salida con el namespace
`linux-wallpaperengine`, y `WaylandFullScreenDetector.cpp` usa
`zwlr_foreign_toplevel_management_v1` para pausar con pantalla completa.
Hyprland implementa ambos protocolos. No se convierte una ventana X11: el
supervisor lanza el motor con `XDG_SESSION_TYPE=wayland` y sin `DISPLAY`, de
modo que `WallpaperApplication.cpp:667` elige el driver Wayland.

Capas en un monitor con fondo animado, de abajo arriba:

1. `background`: el renderizador, con `--layer background`.
2. `bottom`: `cortetsu-background`, que siempre vive aquí. Es la cubierta
   estática opaca durante las transiciones y transparente con el fondo activo;
   los widgets del escritorio y el visualizador siguen encima.

Antes `cortetsu-background` usaba `background` cuando el fondo estaba activo.
Ningún otro cliente de Cortetsu usa `bottom` y no hay reglas de capa para ese
namespace.

## Ownership transaccional por monitor

Cada conector (`eDP-1`, `HDMI-A-1`) tiene su `Output` con fase, generación,
proceso propio, selección y error. Un cambio en un monitor no toca el otro: las
peticiones llevan el conector y el supervisor solo actúa sobre esa entrada.

1. **Solicitar**: `apply` valida la selección y construye el argv (`prepare`).
   Rechaza `busy` si ese monitor ya está en transición.
2. **Comprobar propietarios**: `hyprctl layers -j` del monitor. Cualquier
   superficie en la capa `background`, o con el namespace del motor, que no sea
   del PID propio bloquea con `foreign-owner`. No se adoptan ni se matan procesos
   ajenos y no existe `pkill`.
3. **Cubrir**: fase `preparing` con una generación nueva. `Background.qml`
   pinta la cubierta y, tras dos `frameSwapped`, envía `covered`.
4. **Transferir**: con la cubierta confirmada se libera el renderizador anterior
   de ese monitor y se lanza el nuevo. Nunca coexisten dos renderizadores propios
   en un conector.
5. **Confirmar**: fase `applying` solo cuando Hyprland lista una superficie del
   PID nuevo, con el namespace del motor y tamaño no nulo. QML levanta la cubierta
   y envía `revealed`; entonces la fase pasa a `active` y se guarda la selección.
6. **Rollback**: la selección confirmada anterior pasa a `previous` y la
   restaura «Restaurar anterior». Cualquier fallo vuelve a cubrir con el fondo
   estático y deja el error visible.

Crear el proceso no cuenta como éxito. La interfaz muestra «Activo» solo con la
fase `active` del snapshot.

## Supervisor

- **Procesos**: el motor se lanza mediante el shim `renderer-child`, el mismo
  binario, que fija `PR_SET_PDEATHSIG` y hace `exec` del ejecutable registrado.
  Va en su propio grupo de procesos; liberarlo mata el grupo y lo recoge. El
  shim solo ejecuta `/opt/linux-wallpaperengine/linux-wallpaperengine`.
- **Argumentos**: cada valor es un elemento de argv validado (`renderer_args`):
  conector, FPS 1–144, volumen 0–100, escalado, política de GPU y propiedades
  del autor. Nada de `project.json` llega a un shell.
- **Estados**: `stopped`, `preparing`, `applying`, `active`, `paused`, `error`.
  La incompatibilidad se informa como veredicto de inspección y como error
  `incompatible` al aplicar.
- **Errores**: `{code, message}` con códigos estables (`foreign-owner`,
  `transition-timeout`, `renderer-exited`, `surface-lost`, `spawn`,
  `persist`, …). Se conservan los últimos 4 KiB de stderr del motor.
- **Cierre inesperado**: si un fondo `active` muere, se reintenta dos veces en
  120 s; después queda el fondo estático con el error.
- **Transición**: 15 s sin superficie terminan en `transition-timeout`.
- **Monitor desconectado o desactivado**: su `Output` desaparece y el motor
  muere. Al reconectar se restaura si la selección guardada lo pide.
- **Suspensión**: un salto de reloj de pared mayor de 25 s pausa y reinicia
  los motores, lo que evita contextos GL rotos tras reanudar.
- **Monitor apagado (DPMS)** y **batería**: pausa con cubierta estática.
- **Cubierta sin acuse**: a los 3 s el motor se libera igualmente y el
  monitor no queda bloqueado.
- **Concurrencia**: un solo hilo procesa peticiones y ticks; el lock evita
  supervisores duplicados.
- **Sondeo**: 500 ms en transición, 3 s con motor activo, 10 s en reposo.

## Capacidades por tipo

Lo decide `Almamu::inspect`; la interfaz muestra ese veredicto.

| Tipo | Estado | Límites |
| --- | --- | --- |
| Scene (`scene.json` o `scene.pkg`) | Reproducible | Reimplementación OpenGL: shaders, efectos, SceneScript y audio reactivo pueden diferir de Windows. Sin interacción de ratón |
| Video | Reproducible | libmpv; con GPU integrada la decodificación es por software |
| Web | **Bloqueado** | `WebBrowserContext.cpp:87` fija `no_sandbox = true`; Orbital no abre páginas no confiables sin aislamiento auditado |
| Image | Biblioteca estática | Conserva el pipeline oficial de colores |
| Desconocido o proyecto roto | Rechazado | Error con el motivo |

Propiedades del autor editables: `bool`, `slider` (dentro de min/max) y
`combo` (solo valores declarados). `color`, `text` y archivos se ignoran. El
motor no tiene IPC para cambios en vivo: aplicar cambios reinicia solo ese
monitor.

## Energía y GPU

glvnd prueba `10_nvidia.json` antes que `50_mesa.json`. Con la política
**GPU integrada** (predeterminada) el supervisor fija
`__EGL_VENDOR_LIBRARY_FILENAMES` a Mesa y `--hwdec no`, y elimina `DRI_PRIME`
y las variables de PRIME offload: la RTX 3050 no debería despertarse. **GPU del
sistema** deja ambas decisiones al controlador (`--hwdec auto`). Otras opciones:
30 FPS por defecto, pausa con batería, pausa en pantalla completa (detector del
motor) y pausa con monitor apagado. No se afirma ningún ahorro sin medirlo.

## Persistencia

`$XDG_STATE_HOME/cortetsu/orbital.json`, `version: 1`, escritura atómica
(`common::json_save`, modo 0600). Campos: `monitors` (selección confirmada por
conector, con motor, FPS, volumen, silencio, escalado, GPU, propiedades,
energía y restauración), `previous`, `libraryRoots`, `favorites`,
`collections`, `playlists` y `profiles` por monitor. `deny_unknown_fields` y
una versión desconocida detienen el supervisor sin tocar el archivo. Las
preferencias estáticas de Cortetsu no se migran ni se modifican. No se escribe
en Steam Workshop ni se copian assets.

## Integración

- **Orbital**: botón Steam → galería → panel de reproducción.
- **Launcher**: acción «Fondos animados de Steam».
- **Ajustes → Fondo**: botón «Fondos animados de Steam».
- **Ajustes rápidos**: mosaico Orbital con el estado del monitor.
- **Fondo estático**: aplicar uno desde Orbital detiene el animado de ese monitor.
- **Bloqueo de pantalla**: sigue usando la imagen estática aplicada.
- **Colores**: Ink, Washi y Kurogane no cambian al aplicar un fondo animado; la
  paleta sigue el pipeline oficial del fondo estático.
- **Biblioteca**: favoritos, colecciones, carpetas adicionales, rotación por
  monitor con intervalo y aleatorio, perfiles por monitor.

El supervisor arranca al abrir la biblioteca Steam o al iniciar sesión si
`orbital.json` pide restaurar. Sin uso no hay proceso ni sondeo.

## Bloqueos y riesgos

- **Web**: bloqueado por el sandbox CEF desactivado en el motor instalado.
  Sustituirlo exige un backend aislado (bubblewrap o similar) y su auditoría.
- **Cambios en vivo**: Almamu no tiene IPC. FPS, volumen y propiedades
  reinician el motor del monitor.
- **Contextos**: los contextos Gaming y Batería (y los propios que lo
  pidan) envían `hold` en el `heartbeat`; el supervisor pausa con el motivo
  `context` y reanuda al quitarlo. Ver [CONTEXTS](../../CONTEXTS.md).
- **Color desde el fondo animado**: no se extrae paleta del preview; requiere
  elección explícita.
- **`cortetsu-background` en `bottom`**: cambia la capa del fondo estático para
  todos. Verificar en QA que nada queda tapado.
- **Licencia**: el motor GPL se ejecuta como proceso aparte. No se enlaza ni se
  copia código.

## Instalación y rollback (posterior, no ejecutado)

Tras la QA autorizada: construir un bundle nuevo con
`scripts/build-native.sh`, instalar como generación nueva según
[NATIVE-RUNTIME](../../migration/NATIVE-RUNTIME.md) y adoptar el QML con una
recarga explícita. Rollback: `cortetsu rollback` a la generación anterior y
`cortetsu verify`. `orbital.json` es nuevo y la generación anterior lo ignora.
Para limpiar también el estado, borrar ese archivo; no hay otras migraciones.

## Revisión de entrega

Ver la sección de revisión en [QA_POSTERIOR.md](QA_POSTERIOR.md#orbital-reproducción-escenarios-sin-ejecutar).
Inventario QML: se añaden `services/Orbital.qml`,
`modules/wallpaper/SteamPlayback.qml` y `modules/wallpaper/OrbitalField.qml`.
Regenerar el inventario durante la QA.

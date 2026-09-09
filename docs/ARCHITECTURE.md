# Arquitectura de Cortetsu

## Principio principal

Cortetsu no debe reemplazar archivos completos de una versión nueva de Caelestia con copias viejas. Las modificaciones se dividen en dos categorías:

1. **Módulos propios**: archivos completos que pertenecen a Cortetsu, por ejemplo `BottomHub.qml`, `HubButton.qml`, `OverviewController.qml` y `modules/overview/*`.
2. **Integraciones sobre upstream**: cambios mínimos sobre archivos nativos de Caelestia, almacenados como patches.

## Base upstream actual

- paquete instalado: `caelestia-shell 2.3.0-3`
- tag: `v2.3.0`
- commit: `94d5eb9e6fe9c6b1f69e663d9ed410a441e2d67f`

## Runtime

El shell real continúa instalado bajo:

`/etc/xdg/quickshell/caelestia`

Cortetsu es la fuente versionada. El runtime se valida/aplica mediante los scripts guardados en `cortetsu/bin` después de sincronizar el estado real.

## Superficies e input

El Bottom Hub usa un `PanelWindow` propio únicamente para la barra inferior: botones, iconos de aplicaciones, rueda, clics y acciones simples.

Los overlays interactivos que necesitan scroll complejo, foco, teclado o una máscara de input coordinada permanecen en `modules/drawers/ContentWindow.qml`. Bottom Hub reutiliza su contenido, pero sustituye la geometría lateral: notificaciones, Quick Settings y popouts tienen anclajes inferiores fijos. `BarWrapper` permanece únicamente como adaptador de contrato de ancho cero y nunca carga una barra visual.

La migración de `Panels.qml` localiza cada componente por tipo e `id` y modifica solo ese bloque. El checker aplica la misma regla; una cadena de anclajes presente en otro componente no puede satisfacer la validación.

`ContentWindow.qml` es una superficie de integración compartida, no un archivo exclusivo del patch de Overview. Clipboard, Hardware Center y Display Manager extienden las mismas cadenas de layer, keyboard focus, input mask, focus grab y cierre. El preflight de Bottom Hub debe preservar esos miembros y validar el estado semántico compuesto; no debe exigir que el archivo vuelva a ser byte por byte el resultado del patch base.

El launcher es una superficie nativa de Cortetsu y se desplaza 72 px para aparecer visualmente unido al Bottom Hub.

## Wallpaper Manager

Wallpaper Manager sigue el límite `ScreenState -> WallpaperController -> ContentWindow -> Panels -> wallpaper/Wrapper -> Content`. `wallpaperManager` es un estado por pantalla y participa en layer overlay, foco OnDemand, máscara nula, focus grab, scrim y cierre en fullscreen. `OverlayPolicy.js` es la única lista de exclusión para launcher, sidebar/notificaciones, overview, clipboard, hardware, display, session, utilities y dashboard. Cada controlador la aplica en todas las pantallas. Además, cada `wallpaper/Wrapper` observa esos estados en todas las pantallas, por lo que un shortcut, drawer o gesto nativo que no pasa por un controlador también cierra Wallpaper Manager y ejecuta `stopPreview`.

`OrbitModel.js` es la fuente determinística para filtros de categoría, resolución exacta/alias único de `actualCurrent`, wrap, intención de wheel, satélites y prefetch. La órbita excluye el índice seleccionado y queda limitada a 11 thumbnails cuando el presupuesto visible es 12; una ventana separada de hasta 18 imágenes a 128 px precarga sólo vecinos. `Content.qml` posee el gate de presentación y el único timer de preview de 220 ms. `CortetsuWallpapers.qml` es el backend first-party y conserva el ACK del state-file como fuente de verdad: `apply()` y `applyRandom()` comparten una transacción con generación, timeout y señales de éxito/error. Wallpaper Manager muestra Cosmic sólo tras el ACK real; Launcher mantiene su superficie hasta el éxito y bloquea solicitudes duplicadas.

## Actualizaciones

Después de actualizar Caelestia:

```bash
cortetsu verify
```

- `APPLIED`: el patch literal está presente.
- `TARGET`: el archivo contiene el estado funcional objetivo, pero fue extendido por otras integraciones Cortetsu y ya no coincide byte por byte con el patch base.
- `MISSING`: patch compatible pero no aplicado.
- `CONFLICT`: upstream o una integración cambió de forma que no satisface ni el patch ni las invariantes semánticas; adaptar antes de tocar el runtime.

`install-patches.sh` hace preflight y aborta antes de modificar nada si hay un conflicto. Para Bottom Hub, el instalador ejecuta además `test-bottom-hub-target.py` antes de iniciar la instalación, de modo que el propio checker semántico se valide antes de usarse sobre `/etc/xdg`.

## Git

`main` representa el estado estable probado. Cada módulo nuevo debe desarrollarse en una rama `feature/*` y fusionarse solo cuando funcione en el shell real.

El desarrollo de la interfaz inferior vive en `feature/bottom-hub` hasta completar las pruebas descritas en `docs/BOTTOM-HUB.md`.

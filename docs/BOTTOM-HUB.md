# Cortetsu Bottom Hub

## Estado canónico

El Bottom Hub es la barra inferior first-party de Cortetsu. Caelestia 2.4.0 sigue proporcionando temporalmente varios servicios de backend, pero ya no define la presentación del Hub.

La separación es deliberada:

- `BottomHub.qml` es el controlador/orquestador. Lee servicios, mantiene IPC, agrupa ventanas, ejecuta acciones de Hyprland y traduce estados de Caelestia a datos simples.
- `CortetsuBottomHubView.qml` es la raíz de presentación y no importa servicios de Caelestia/Hyprland.
- Los segmentos visuales reciben propiedades simples y emiten señales; nunca ejecutan acciones del compositor o de los servicios por su cuenta.
- `native-bottom-hub.py` fue retirado. El runtime copia directamente los módulos first-party versionados en el repositorio.

No existe un camino soportado que escriba directamente en `/etc/xdg/quickshell/caelestia`.

## Componentes first-party

- `BottomHub.qml`: controlador, IPC y adapters de backend.
- `CortetsuBottomHubView.qml`: composición y geometría general.
- `CortetsuModeSegment.qml`: launcher, wallpaper, Clipboard y workspaces.
- `CortetsuWorkspaceDots.qml`: indicador/selector de workspaces.
- `CortetsuAppRail.qml`: favoritas y aplicaciones abiertas.
- `CortetsuTraySegment.qml`: bandeja SNI proyectada como datos simples.
- `CortetsuStatusSegment.qml`: volumen, red, Bluetooth, batería, notificaciones, reloj y sesión.
- `HubButton.qml`: botón visual Cortetsu reutilizable.
- `StatusPill.qml`: estados REC/DND/Awake.
- `CortetsuSurface.qml`: superficie visual base.
- `CortetsuIcon.qml`: iconografía first-party.
- `CortetsuText.qml`: texto first-party.
- `theme/CortetsuDesign.qml`: color, espaciado, radio y motion.
- `CortetsuTypography.js`: tipografía e icon font.

Las vistas no pueden depender de `Hypr`, `SystemTray`, `Audio`, `Nmcli`, `Bluetooth`, `UPower`, `Notifs`, `Recorder`, `DesktopEntries`, `GlobalConfig`, `Apps`, `Wallpapers`, `qs.services`, `Caelestia.Config`, `Colours`, `Tokens`, `StyledRect`, `StyledText`, `MaterialIcon` o `ColouredIcon`. El gate `scripts/features/test-native-bottom-hub.py` hace cumplir esta frontera.

## Posición

Desde Cortetsu 3.0 la denominación visible es **Hub**. Los nombres internos
(`BottomHub.qml`, el destino IPC `bottomHub`, la clave `bottomHub` de las
preferencias y el namespace `cortetsu-bottom-hub`) se conservan.

El Hub se apoya en uno de ocho anclajes, el mismo para todas las pantallas o
uno propio por salida. `modules/HubAnchor.js` es el modelo: geometría pura,
sin compositor, probada en `tests/qml/bottomhub/tst_HubAnchor.qml`.

| Anclaje | Borde | Islas |
| --- | --- | --- |
| `bottom-center` (por defecto), `top-center` | inferior, superior | repartidas: modo a un extremo, aplicaciones al centro, bandeja y estado al otro |
| `bottom-left`, `bottom-right`, `top-left`, `top-right` | inferior, superior | juntas en esa esquina |
| `middle-left`, `middle-right` | izquierdo, derecho | apiladas: las mismas islas en columna, sin rotar nada |

Reglas:

- Un valor desconocido se lee como `bottom-center`. Una preferencia dañada no
  puede dejar el Hub fuera de pantalla.
- La ventana reserva en su borde el grosor del Hub y nada más (`exclusiveZone`).
- La máscara de entrada es la unión de las islas, la franja de revelado y los
  toasts. El aire entre dos islas no captura el puntero.
- Un popout anclado se abre hacia el interior, centrado en el control que lo
  abrió y siempre dentro de la pantalla (`HubAnchor.popoutPosition`).
- OSD, avisos, sesión, panel lateral y Dashboard se apartan del borde que ocupa
  el Hub (`HubAnchor.reserved`, leído en `drawers/Panels.qml`).
- Los tooltips salen hacia el interior: debajo con el Hub arriba, al lado con
  el Hub lateral.
- En un Hub lateral el reloj muestra solo la hora y las píldoras REC/DND/Activo
  solo su icono; el tooltip sigue nombrándolas.

Cómo cambiarlo:

- Ajustes → Personalización → Hub → Posición: un selector con los ocho puntos,
  un solo paso de `Tab`, flechas para recorrerlos y `Enter` para elegir. Con
  más de una pantalla se elige a cuál aplica.
- IPC, que también sirve para recuperar un Hub mal colocado:

```sh
qs ipc call bottomHub -- anchor "" bottom-center      # todas las pantallas
qs ipc call bottomHub -- anchor HDMI-A-1 top-right    # solo esa salida
qs ipc call bottomHub clearAnchor HDMI-A-1            # vuelve a la común
qs ipc call bottomHub anchors                         # anclaje efectivo por salida
```

Preferencias (`~/.config/cortetsu/preferences.json`): `bottomHub.anchor`
(cadena) y `bottomHub.anchors` (mapa salida → anclaje). Un archivo anterior a
3.0 no las tiene y se comporta como `bottom-center`.

Prueba con compositor real: `scripts/integration/test-hub-anchors.py`, bajo
`ws2_run.py`. Recorre los ocho anclajes en un Hyprland anidado y comprueba la
capa, la zona reservada, la posición del popout, el anclaje por monitor, el
rechazo de un valor desconocido y que el log de QML quede limpio.

Con «Ocultar automáticamente» (`bar.showOnHover`) el Hub vuelve desde el último
píxel de su borde. Su ventana queda dentro de las zonas exclusivas de las demás
superficies (el borde de pantalla reserva 1 px), así que `HubRevealEdge` pone en
el propio borde una tira de 3 px que ignora esas zonas; su hover cuenta como el
del Hub, también con el puntero quieto en el borde. Solo existe con el auto-hide
activo, porque cada ventana de capa cuesta un contexto GL. Un cambio de anclaje
con el auto-hide activo desmapea el Hub un ciclo: oculto no pinta, y sin eso el
compositor no recibía el borde nuevo. Prueba: `scripts/integration/test-hub-autohide-edge.py`.

Pendiente: mover el Hub arrastrándolo en un modo de edición. Hoy se elige en
Ajustes o por IPC.

## Geometría

La ventana ocupa el largo útil de su borde menos 8 px por extremo.
`CortetsuBottomHubView` coloca cuatro islas a lo largo de él:

1. modo: lanzador y espacios de trabajo;
2. aplicaciones, centradas respecto al monitor cuando el Hub va repartido y
   limitadas por el espacio simétrico disponible;
3. bandeja adaptativa;
4. estado y sistema.

Las islas usan tamaño explícito derivado de su tamaño implícito; el riel de
aplicaciones usa `Flickable` únicamente cuando el contenido excede el espacio.

## Contrato de comportamiento

El controlador conserva las capacidades del Hub anterior:

- logo CachyOS → launcher;
- thumbnail → Wallpaper Manager;
- icono Clipboard → historial de portapapeles;
- click en workspace → cambio de workspace;
- app sin ventanas → lanzar;
- app abierta → enfocar; clicks sucesivos o rueda → recorrer ventanas;
- click central en app → cerrar ventana activa del grupo;
- click derecho → fijar/quitar de favoritas;
- tray → activación primaria/secundaria y menú nativo por hover;
- volumen → mute y rueda de nivel;
- red/Bluetooth → popout/centro correspondiente;
- batería → estado real y severidad crítica;
- notificaciones → centro inferior;
- `REC`, `DND`, `Awake` → acciones sobre los singletons reales;
- reloj → Calendar;
- power → Session;
- filtrado de ventanas por monitor.

`BottomHub.qml` conserva los IPC targets `bottomHub` y `customDock`. `customDock` es únicamente una compatibilidad de entrada para bindings existentes; no implica que exista un CustomDock visual.

## Tray

La vista consume el icono SNI resuelto por el controlador y lo muestra como `Image`. Ya no usa el `ColouredIcon` ni el recolor de Caelestia. Esto elimina una dependencia visual heredada, pero la legibilidad de iconos monocromos debe validarse en la sesión real; si algún icono necesita recolor, debe resolverse con una primitiva Cortetsu first-party y no reintroduciendo `Config.bar.tray.recolour`.

## Pomodoro

El Hub observa el evento canónico:

```text
$XDG_STATE_HOME/cortetsu/pomodoro-notification.json
```

No usa el namespace histórico `caelestia` para ese estado.

## Build e instalación

El camino soportado es siempre el runtime inmutable:

```bash
./scripts/cortetsu test
cortetsu install
cortetsu verify
cortetsu doctor
cortetsu status
```

`cortetsu/bin/build-runtime.sh` parte de la base exacta declarada en `compatibility.json`, aplica patches en staging, copia los módulos first-party y ejecuta las regresiones antes de promover una generación.

No usar `sudo install` sobre `/etc/xdg/quickshell/caelestia`, no reiniciar mediante `caelestia shell -d` y no editar el paquete del sistema.

## Validación automática

Los gates relevantes comprueban:

- frontera controller/view;
- ausencia de Material/Caelestia visual dentro de los componentes del Hub;
- comportamiento App Rail v3;
- arquitectura Bottom Hub v4;
- runtime generado idéntico al source first-party;
- base exacta de Caelestia 2.4.0;
- dos generaciones aisladas y rollback.

La CI no sustituye una instanciación real de QML en Hyprland. Después de fusionar un cambio del Hub debe validarse visualmente en la máquina.

## Validación real

Comprobar, como mínimo:

1. Hub visible y correctamente dimensionado en cada monitor.
2. launcher y Wallpaper Manager.
3. cambio de workspaces por click.
4. launch/focus/cycle/close/pin del App Rail.
5. tray: iconos legibles, activación, secundario y menús por hover.
6. volumen, red, Bluetooth y batería con sus popouts.
7. contador de notificaciones y centro inferior.
8. acciones REC/DND/Awake.
9. reloj → Calendar.
10. power → Session.
11. multimonitor y filtrado de ventanas.
12. un único proceso `qs` supervisado por `cortetsu-shell.service`.

## Rollback

El rollback soportado es el de generaciones Cortetsu:

```bash
cortetsu rollback
cortetsu verify
cortetsu shell reload
```

La recarga suave reutiliza el proceso y las ventanas de Quickshell. El reinicio
duro sólo es explícito y ahora es seguro para las aplicaciones persistentes de
Cortetsu: cada lanzamiento vive en un scope de usuario independiente y no
pertenece al cgroup del shell. ChatGPT Desktop puede permanecer abierto durante
esa operación.

Para diagnosticar una carga QML fallida:

```bash
journalctl --user -u cortetsu-shell.service -n 120 --no-pager
```

El rollback es coordinado con las generaciones de sistema; no se restaura el Hub copiando archivos manualmente desde `/etc`.

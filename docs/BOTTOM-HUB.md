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
- `CortetsuModeSegment.qml`: launcher, wallpaper y workspaces.
- `CortetsuWorkspaceDots.qml`: indicador/selector de workspaces.
- `CortetsuAppRail.qml`: favoritas y aplicaciones abiertas.
- `CortetsuTraySegment.qml`: bandeja SNI proyectada como datos simples.
- `CortetsuStatusSegment.qml`: volumen, red, Bluetooth, batería, notificaciones, reloj y sesión.
- `HubButton.qml`: botón visual Cortetsu reutilizable.
- `StatusPill.qml`: estados REC/DND/Awake.
- `CortetsuSurface.qml`: superficie visual base.
- `CortetsuIcon.qml`: iconografía first-party.
- `CortetsuText.qml`: texto first-party.
- `CortetsuDesign.js`: color, espaciado, radio y motion.
- `CortetsuTypography.js`: tipografía e icon font.

Las vistas no pueden depender de `Hypr`, `SystemTray`, `Audio`, `Nmcli`, `Bluetooth`, `UPower`, `Notifs`, `Recorder`, `DesktopEntries`, `GlobalConfig`, `Apps`, `Wallpapers`, `qs.services`, `Caelestia.Config`, `Colours`, `Tokens`, `StyledRect`, `StyledText`, `MaterialIcon` o `ColouredIcon`. El gate `scripts/features/test-native-bottom-hub.py` hace cumplir esta frontera.

## Geometría

El `PanelWindow` ocupa el ancho útil del monitor menos 8 px por lado. `CortetsuBottomHubView` compone cuatro zonas:

1. izquierda: modo/launcher/wallpaper/workspaces;
2. centro: App Rail, centrado respecto al monitor y limitado por el espacio simétrico disponible;
3. derecha intermedia: tray adaptativo;
4. derecha: estado/sistema.

Los segmentos visuales usan tamaño explícito derivado de su `implicitWidth`/`implicitHeight`; el App Rail usa `Flickable` únicamente cuando el contenido excede el ancho disponible.

## Contrato de comportamiento

El controlador conserva las capacidades del Hub anterior:

- logo CachyOS → launcher;
- thumbnail → Wallpaper Manager;
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

La recarga suave reutiliza el proceso y las ventanas de Quickshell. No uses el
reinicio duro mientras ChatGPT Desktop u otra aplicación de bandeja esté
abierta: el host `StatusNotifier` puede desaparecer durante ese ciclo.

Para diagnosticar una carga QML fallida:

```bash
journalctl --user -u cortetsu-shell.service -n 120 --no-pager
```

El rollback es coordinado con las generaciones de sistema; no se restaura el Hub copiando archivos manualmente desde `/etc`.

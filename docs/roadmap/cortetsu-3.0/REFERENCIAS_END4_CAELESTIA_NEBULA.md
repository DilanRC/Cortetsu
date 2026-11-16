# Referencias: end-4, Caelestia y Nebula

Segunda ola de construcción 3.0, 2026-11-16. Este documento resume lo que
se leyó en el **código** de los tres proyectos, no en sus capturas ni en
sus README. Lo que no se comprobó en un archivo no aparece como hecho.

## 1. Copias de referencia

Clonadas en `~/Documentos/GitHub/cortetsu-references/` (carpeta hermana
del repositorio, fuera de él y de su runtime) con `git clone
--no-recurse-submodules` y `core.hooksPath=/dev/null`. No se ejecutó
ningún instalador, script, servicio ni gestor de paquetes de ellas.

| Proyecto | Carpeta | URL | Rama | Commit | Fecha del commit | Licencia |
| --- | --- | --- | --- | --- | --- | --- |
| end-4 (illogical-impulse) | `end4/` | <https://github.com/end-4/dots-hyprland> | `main` | `21733c3ca7f4edc20faafedea844dc96002c6f7f` | 2026-11-15 11:44 +08:00 | GPL-3.0 (`LICENSE`); `licenses/` guarda LGPL-3.0 y MIT de código incluido |
| Caelestia Shell | `caelestia/` | <https://github.com/caelestia-dots/shell> | `main` | `e72df8eb687246aa6c6ec6daa631073b374e5215` | 2026-11-15 04:39 UTC | GPL-3.0 |
| Nebula | `nebula/` | <https://github.com/LilaccFlowerr/Nebula> | `main` | `9749c30402b4e6712d0222c48b645fa357d0217e` | 2026-11-14 21:13 +01:00 | AGPL-3.0 |
| PipeWire (solo para verificar el ecualizador) | `pipewire/` | <https://gitlab.freedesktop.org/pipewire/pipewire> | etiqueta `1.6.11` | la versión instalada en el equipo | — | MIT |

Las rutas de este documento son relativas a esa carpeta y a esos commits.

### Tecnología y organización

| | end-4 | Caelestia | Nebula |
| --- | --- | --- | --- |
| QML | 586 archivos en `dots/.config/quickshell/ii/` | 282, raíz del repo | 171 en `quickshell/nebula/` |
| Organización | Dos «familias» de paneles: `modules/ii` (Material) y `modules/waffle` (estilo Windows), elegidas por `panelFamilies/PanelLoader.qml`; `modules/common` con ~120 widgets y `Config.qml`/`Appearance.qml` | `modules/` por superficie, `services/`, `components/`, `daemons/`; un plugin C++ propio (`plugin/src/Caelestia/`: Models, Blobs, Services, Shaders, I18n…) | `services/` (singletons), `components/`, `widgets/` por superficie, `shaders/*.frag` |
| Quickshell | `sdata/dist-arch/illogical-impulse-quickshell-git/PKGBUILD` fija el commit `4f508be5…`, **la misma revisión instalada en este equipo** (Quickshell 0.3.2) | README: `quickshell-git`, «tiene que ser la versión git» | `install.sh`: paquete `quickshell` de Arch |
| Dependencias que importan | Python en un venv propio (`$ILLOGICAL_IMPULSE_VIRTUAL_ENV`) para scripts; `hyprsunset`; `cliphist`; matugen | Plugin C++ compilado; `caelestia` CLI | `m3shapes` compilado al instalar (Material 3 Shapes), `cava`, `gpu-screen-recorder`, `zenity`, `matugen`, `mate-polkit` |
| Persistencia | `Config.qml` sobre JSON con escritura diferida | `Caelestia.Config` (plugin) | `services/Settings.qml` sobre `~/.config/nebula/settings.json` |

Cortetsu no adopta ninguna de esas dependencias: no hay plugin C++, venv,
`m3shapes` ni CLI ajena nuevos en esta ola.

## 2. end-4: hallazgos

| Característica | Archivos | Cómo funciona | Qué toma Cortetsu |
| --- | --- | --- | --- |
| Ajustes | `ii/settings.qml`, `ii/modules/settings/*Config.qml` | Ventana propia con 8 páginas en un `NavigationRail`; Ctrl+RePág/AvPág y Ctrl+Tab cambian de página; filas `ConfigSwitch`, `ConfigSlider`, `ConfigSelectionArray` en `ContentSection` (título con icono y filas apiladas). **No tiene búsqueda.** | Cortetsu ya tenía búsqueda con revelado y los mismos atajos de página (`settings/Content.qml`). Se confirmó; no se copió nada |
| Widgets de fondo | `common/widgets/widgetCanvas/{AbstractWidget,WidgetCanvas}.qml`, `ii/background/widgets/AbstractBackgroundWidget.qml` | `MouseArea` con `drag.target`; posición absoluta en píxeles en la configuración; estrategia de colocación opcional que llama a un script Python para la región «menos ocupada» del fondo | La idea de arrastrar sobre el fondo. Se descartan los píxeles absolutos (no sobreviven a otra resolución) y el script Python |
| Luz nocturna | `services/Hyprsunset.qml`, `ii/sidebarRight/nightLight/NightLightDialog.qml`, `quickToggles/androidStyle/AndroidNightLightToggle.qml` | Horario `from`/`to` evaluado cada minuto; un cambio manual se mantiene hasta el siguiente límite; mata y relanza `hyprsunset` con `bash -c` | La regla de «manual hasta el siguiente cambio de horario». Cortetsu no lanza procesos con `bash -c` ni mata `hyprsunset`: usa su dueño existente (`DisplayCalibration`, unidad systemd) |
| Hoja de atajos | `ii/cheatsheet/CheatsheetKeybinds.qml`, `services/HyprlandKeybinds.qml` | `hyprctl binds -j`, grupos por prefijo de la descripción, `Flow` en columnas de arriba abajo | El concepto. Cortetsu reutiliza su propio `cortetsu-keybinds list` (grupos, etiquetas, conflictos) y añade búsqueda |
| Ajustes rápidos | `ii/sidebarRight/quickToggles/` (19 `Android*Toggle.qml`), `volumeMixer/` | Mosaicos por servicio; diálogos por dominio | Ya adoptado en la ola anterior (mosaicos compactos, dispositivos a demanda). Ahora: mezclador por aplicación a demanda |
| Notificaciones | `common/widgets/NotificationGroup.qml`, `NotificationListView.qml` | Agrupación por app con expansión | Adoptado en la ola anterior; ahora con silencio por aplicación |
| Overlay | `ii/overlay/{notes,recorder,volumeMixer,crosshair,fpsLimiter}` | Capa de widgets fijables sobre las ventanas | Descartado como superficie: duplicaría el centro de control y los widgets de escritorio |
| IA, anime, traductor | `ii/sidebarLeft/{aiChat,anime,translator}` | APIs externas | Descartado: AGENTS.md prohíbe APIs externas de LLM sin instrucción expresa; el resto es ajeno al escritorio |

## 3. Caelestia: hallazgos

Cortetsu nació de Caelestia (`cortetsu/base/` conserva siete archivos
de compatibilidad), así que muchas piezas coinciden en nombre.

| Característica | Archivos | Cómo funciona | Qué toma Cortetsu |
| --- | --- | --- | --- |
| Ajustes («nexus») | `modules/nexus/{PageRegistry,Nexus,NavPane}.qml`, `pages/` | Registro de páginas por categoría con descripción; subpáginas (`StackPage`) para detalle de app, red o dispositivo | Cortetsu ya tiene el mismo patrón (`PageRegistry.qml`, `SettingsController.qml`) con búsqueda que abre grupos plegados |
| Grabaciones | `modules/utilities/cards/RecordingList.qml` | `FileSystemModel` del plugin C++ sobre `recording_*.mp4`; reproducir, abrir carpeta, borrar | Lista de grabaciones recientes en Ajustes → Capturas con `FolderListModel` de Qt (sin plugin), sin borrar desde la lista |
| Dashboard de rendimiento | `modules/dashboard/performance/{HeroCard,BatteryTank,MemoryCard,NetworkCard,StorageCard}.qml` | Tarjetas por recurso | Cortetsu ya tiene su dashboard y el Centro de hardware; los widgets de escritorio reutilizan los servicios (`Cpu`, `Memory`, `Gpu`, `Storage`, `NetworkUsage`) con su contador de consumidores |
| Bloqueo | `modules/lock/{Lock,LockSurface,Pam,NotifDock}.qml` | `WlSessionLock` + `PamContext`; dock de avisos en el bloqueo | Sin cambios: la ruta PAM de Cortetsu no se toca sin prueba manual inmediata |
| Fondo | `modules/background/{DesktopClock,Visualiser}.qml` | Un reloj fijo y barras de cava | Cortetsu tenía las mismas dos piezas. El reloj pasa a ser un widget; el visualizador deja de recrear las barras por muestra y escribe su propia configuración de cava |
| Lanzador | `modules/launcher/services/{Apps,Actions,Schemes,M3Variants}.qml`, `items/CalcItem.qml` | Modos por prefijo | Mismo modelo; Cortetsu añade el modo archivos sobre `plocate` |

## 4. Nebula: hallazgos

| Característica | Archivos | Cómo funciona | Qué toma Cortetsu |
| --- | --- | --- | --- |
| Widgets de escritorio | `services/Widgets.qml` (625 líneas), `services/WidgetSnap.qml`, `widgets/desktop/{WidgetsWindow,EditToolbar,SnapGuides,SnapGrid,SelectionChrome}.qml` | Lista JSON en ajustes; modo edición con deshacer/rehacer (50 pasos), empuje con flechas, ajuste a márgenes, centro y bordes de otros widgets, rejilla opcional; un widget de un monitor ausente se muestra en el primero y su posición se reescala desde el tamaño guardado de ese monitor | El modelo de edición (deshacer, guías, monitor ausente). Cortetsu guarda el **centro en fracciones** del monitor en lugar de píxeles más tamaño de origen, y reserva el borde del Hub |
| Formas expresivas | `components/{MorphButton,WavyProgress,FloatingShapes}.qml`, `m3shapes` | Formas M3 animadas, también en reposo | Descartado: movimiento decorativo en reposo, contrario a ENERGY 1 / MOTION 1 y a ADR-008 |
| Ecualizador | `services/Equalizer.qml`, `assets/nebula-eq.conf` | `filter-chain` de 10 bandas sin preamplificador; si el nodo falta, cada 3 s lanza `pipewire -c` con `sh -c` | Cortetsu ya tenía su ecualizador opcional. Revisado contra PipeWire 1.6.11 (sección 6) |
| Cava | `services/Cava.qml` | Escribe una configuración propia en `XDG_RUNTIME_DIR` y lanza `cava -p` | Adoptado el principio: `CortetsuSpectrum` deja de depender del `~/.config/cava/config` del usuario |
| Bloqueo | `services/Lock.qml` (`PamContext { config: "login" }`), `widgets/lock/` (agujero negro, planetas) | Escena animada de varios segundos | Descartado: el desbloqueo depende de PAM, no de una escena |
| Barra de tres islas | `widgets/bar/{left,center,right}` | Islas flotantes | Cortetsu ya tiene sus islas (fase 4 VERIFIED); no se reabre |
| Selector de imagen | `services/Widgets.qml` `fileDialog` | `zenity --file-selection` | Descartado por ahora: `zenity` no es dependencia de Cortetsu (el widget de imagen no se implementó) |

## 5. Matriz por familia

Estados de la columna Cortetsu: lo que hay **después** de esta ola, sin
verificar en ejecución.

| Familia | end-4 | Caelestia | Nebula | Cortetsu actual | Mejora original |
| --- | --- | --- | --- | --- | --- |
| Settings | Rail de 8 páginas, sin búsqueda (`ii/settings.qml`) | Nexus con subpáginas (`modules/nexus/`) | Páginas por pestañas (`widgets/settings/`) | Categorías y subpáginas, búsqueda que revela la fila, atajos de página, migas | Página de widgets, biblioteca de componentes, horario de luz nocturna, apps silenciadas, grabaciones recientes |
| Ajustes rápidos | 19 mosaicos Android (`quickToggles/androidStyle/`) | `utilities/cards/Toggles.qml` | `popups/quicksettings/QuickSettings.qml` | Niveles, conexión, 6 mosaicos compactos, energía y perfil | Mezclador por app y lo que suena a demanda; luz nocturna y captura |
| OSD | `onScreenDisplay/OsdValueIndicator.qml` | `modules/osd/` | `popups/osd/LevelOsd.qml` | Volumen, brillo, micrófono, perfil; sin foco | Conservado (ola anterior) |
| Hub | Barra (`ii/bar`, `verticalBar`) | Barra lateral (`modules/bar`) | Tres islas | Ocho anclajes, islas, edición, bandeja (fase 4 VERIFIED) | Conservado. Los widgets evitan su borde |
| Launcher | `overview/SearchWidget.qml` | Modos por prefijo | Anillo (`launcher/LauncherRing.qml`) | Explorar, favoritas, recientes, categorías, acciones, emoji, esquemas | Búsqueda de archivos con `plocate` |
| Notificaciones | Grupos (`NotificationGroup.qml`) | Grupos y dock (`sidebar/NotifDock.qml`) | Pila (`popups/notifications/NotificationStack.qml`) | Grupos, búsqueda, historial, DND | Silenciar por aplicación, críticas siempre visibles |
| Audio | Mezclador, EasyEffects | Popout de audio | Ecualizador sin preamp | Ecualizador opcional con preamp | Margen calculado sobre la curva real, `mixer` lineal, curva dibujada |
| Wallpaper | `wallpaperSelector/` | `services/Wallpapers.qml` | `wallpaper/WallpaperWindow.qml` | Orbital (fase previa) | Fichas con rol y nombre accesibles |
| Overview | `ii/overview/` con búsqueda de apps | `windowinfo/` | — | Rejilla de ventanas por espacio | Filtro de ventanas con `/` o Ctrl+F |
| Lockscreen | `ii/lock/` | `modules/lock/` + PAM | Escena animada + PAM | Emblema que sigue a PAM (fase 7) | Conservado sin tocar PAM |
| Widgets | `background/widgets/{clock,weather}` | Reloj de escritorio | 9 tipos con edición | 9 tipos con datos reales, editor, galería | Centro en fracciones, borde del Hub reservado, muestreo solo con el escritorio a la vista |
| Dashboard | — | `modules/dashboard/` | — | Hoy, medios, letras, rendimiento, clima | Medidor de nivel con `PwNodePeakMonitor` (sin cava) |
| Calendario | `sidebarRight/calendar/` | `dashboard/dash/Calendar.qml` | `popups/calendar/Calendar.qml` | Superficie con agenda y Pomodoro | Conservado; widget de mes en el escritorio |
| Portapapeles | `services/Cliphist.qml` | — | `cliphist` | Superficie sobre Clipse | Filtro y limpieza como controles; limpiar pide confirmación |
| Captura | `regionSelector/`, `AndroidScreenSnipToggle.qml` | `modules/areapicker/` | `screenshot/FreezeWindow.qml` | Selector de área, congelado, portapapeles | Mosaico de captura en el centro de control |
| Grabación | `overlay/recorder` | `utilities/cards/Record.qml`, `RecordingList.qml` | `recorder/RecorderCorner.qml` | `cortetsu-record` nativo | Grabaciones recientes en Ajustes; avisos en español |
| Multimonitor | Por pantalla | Por pantalla | Por pantalla; widgets reescalados | Por pantalla; Hub por monitor | Widgets por monitor con «llevar a» y regreso al reconectar |
| Personalización | `ConfigSelectionArray`, matugen | Esquemas, M3 | Formas M3, matugen | Ink, Washi, Kurogane; esquemas | Biblioteca viva para juzgar los tres temas |
| Atajos | Hoja con `hyprctl binds` | — | — | Editor «Atajos y teclados» | Hoja con búsqueda en SUPER+F1 |
| Luz nocturna | `Hyprsunset.qml` | — | — | Filtro de color manual | Horario sobre el mismo dueño |

## 6. Ecualizador: lo que dice PipeWire 1.6.11

- `spa/plugins/audioconvert/biquad.c`, `biquad_highshelf()`: con
  `frequency <= 0` fija el filtro a la ganancia constante A² =
  10^(dB/20). El preamp de la primera versión de Cortetsu (`bq_highshelf`
  a 0 Hz) **sí atenuaba bien**, pero por un caso especial del código.
- `spa/plugins/filter-graph/plugin_builtin.c`: el nodo `mixer` tiene
  ocho entradas y un control `"Gain N"` lineal (−10…10). Es la pieza
  pensada para escalar una señal; con ocho entradas, el grafo debe
  declarar `inputs`/`outputs`.
- Los filtros `bq_peaking` de bandas vecinas a una octava se solapan: el
  preamp «menos la banda más alta» se quedaba corto.

Cambio en `cortetsu/data/pipewire/cortetsu-eq.conf`,
`services/CortetsuEqualizer.qml` y `services/EqResponse.js`; detalle en
`docs/AUDIO_EQ.md`.

## 7. Lo que Cortetsu ofrece y ninguno de los tres resuelve

1. **Un dueño por dato, en todas partes.** La luz nocturna del centro de
   control, de Ajustes y del horario es el mismo `DisplayCalibration`; el
   mezclador del centro de control llama a lo mismo que Ajustes → Sonido;
   la hoja de atajos lee el mismo ayudante que el editor de atajos.
2. **Widgets que no ensucian el rendimiento.** Solo muestrean mientras el
   escritorio de ese monitor está a la vista, con el contador de
   consumidores que ya usaban el dashboard y el Hardware.
3. **Geometría consciente del Hub.** Los widgets y el panel del editor
   evitan el borde que ocupa el Hub en cada monitor, con el modelo de
   anclajes de la fase 3.
4. **Continuidad Ajustes → superficie.** Ajustes → Widgets abre el editor
   con el widget elegido seleccionado; el centro de control abre Ajustes en
   Sonido; los popouts de teclado llevan a su página.
5. **Honestidad de datos.** Ningún widget dibuja `0 %` antes de la primera
   muestra; la batería no se ofrece sin batería; la galería dice por qué un
   tipo no está disponible.
6. **Sin dependencias nuevas.** Archivos con `plocate` (instalado), nivel
   con `PwNodePeakMonitor` (Quickshell), recientes con `FolderListModel`
   (Qt), luz nocturna con la unidad `hyprsunset` existente.

## 8. Descartado, con motivo

| Idea | Origen | Motivo |
| --- | --- | --- |
| Formas y ondas animadas en reposo | Nebula `MorphButton`, `WavyProgress`, `FloatingShapes` | MOTION 1; animación sin estado que la justifique |
| Escena de bloqueo de varios segundos | Nebula `widgets/lock/` | El desbloqueo depende de PAM; la escena retrasa o confunde el resultado |
| Chat de IA, anime, traductor | end-4 `sidebarLeft` | APIs externas prohibidas sin instrucción; ajeno al escritorio |
| Colocación automática por imagen | end-4 `AbstractBackgroundWidget` | Script Python en venv; el usuario coloca y el ajuste a guías basta |
| Relanzar PipeWire desde el shell | Nebula `Equalizer.qml` | Cortetsu no mata ni lanza el servidor de audio |
| Widget de imagen, terminal «fetch», letras en el escritorio | Nebula | Imagen: requiere un selector (`zenity`) que no es dependencia; fetch: decorativo; letras: ya están en el dashboard |
| Overlay de widgets sobre ventanas | end-4 `ii/overlay` | Duplica el centro de control y los widgets de escritorio |

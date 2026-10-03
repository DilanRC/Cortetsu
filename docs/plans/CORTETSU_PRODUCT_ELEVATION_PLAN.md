# Cortetsu: auditoría de producto y plan de elevación

Fecha: 2026-10-03. Base auditada: `main` en `51f9a2e` (merge del PR #21, árbol idéntico a `52b21bb`).
Estado: plan. Ninguna fase está implementada.

Este documento sustituye a una auditoría nueva antes de cada fase. Cada hallazgo
cita archivo y línea, y dice si se verificó en ejecución o se dedujo del código.

## 1. Entorno real contra el que se diseña

| Componente | Versión instalada |
| --- | --- |
| Quickshell | 0.3.1 (`quickshell-git 0.3.1.r6.g0f9939c`) |
| Qt | 6.11.2 (`qt6-base`, `qt6-declarative`) |
| Hyprland | 0.56.2, configuración Lua (`hl.dsp.*`) |
| PipeWire / NetworkManager / BlueZ | 1.6.9 / 1.58.1 / 5.87 |
| Monitores | `eDP-1` 144 Hz y `HDMI-A-1` 60 Hz, ambos 1080p |

Consecuencia directa de Hyprland 0.56 con Lua: `hyprctl dispatch <nombre> <args>`
ya no existe. Comprobado: `hyprctl dispatch global cortetsu:x` y
`hyprctl dispatch movecursor` devuelven error de sintaxis Lua. Solo funciona la
forma `hyprctl dispatch 'hl.dsp.focus({ monitor = "eDP-1" })'`.

Atajos reales (de `hyprctl binds` y `~/.config/hypr/hypr-user.lua`):
`SUPER+H` Hardware Center, `SUPER+SHIFT+D` Dashboard, `SUPER+I` Ajustes,
`SUPER+SHIFT+W` Wallpaper Orbital, `SUPER+V` portapapeles, `SUPER+TAB` Overview,
`SUPER+N` notificaciones, `SUPER+/` ajustes rápidos (OSD completo).

## 2. Inventario

QML propio (fuera de `cortetsu/base/`): 232 archivos, 33 376 líneas.
QML heredado en `cortetsu/base/`: 211 archivos, de los que 143 leen la paleta
reactiva `Colours.palette`.

Profundidad de auditoría: **A** leído completo, **B** leído por partes más
búsquedas dirigidas, **C** solo estructura, textos y métricas.

| Superficie | Entrada | Líneas | Acceso | Prof. |
| --- | --- | --- | --- | --- |
| Wallpaper Orbital | `modules/wallpaper/Content.qml`, `OrbitModel.js`, `CortetsuWallpapers.qml` | 715 + 133 + 276 | `SUPER+SHIFT+W` | A |
| Hardware Center | `modules/hardware/Content.qml` y 10 páginas | 4 823 | `SUPER+H` | A (Content, Overview, Keys), B (resto) |
| Ajustes | `modules/settings/Content.qml`, `SystemPage.qml`, 12 secciones, `network/` | 3 700 aprox. | `SUPER+I` | A (Content, SystemPage, 5 secciones), C (red) |
| Dashboard | `modules/dashboard/Dash.qml`, `Today.qml`, `Focus.qml` | 889 | `SUPER+SHIFT+D` | A (Dash), B |
| Pantalla de bloqueo | `modules/lock/LockSurface.qml`, `Lock.qml`, `base/modules/lock/Pam.qml` | 321 + 39 + 305 | `SUPER+L`, reposo | A |
| Sesión | `modules/session/Content.qml`, `SessionHost.qml` | 185 + 93 | menú de energía | A |
| BottomHub | `modules/BottomHub.qml`, `CortetsuBottomHubView.qml`, segmentos | 869 + 217 + 900 aprox. | siempre visible | B |
| Popouts de barra | `modules/bar/popouts/*` (audio, red, Bluetooth, batería, teclado, bloqueos, ventana, tray) | 1 800 aprox. | hover, clic, IPC | B |
| Ajustes rápidos | `modules/osd/FullContent.qml` y `modules/utilities/Content.qml` | 335 + 262 | `SUPER+/` | C |
| OSD | `modules/osd/Wrapper.qml`, `Content.qml` | 129 | volumen, brillo | C |
| Notificaciones y toasts | `modules/sidebar/Content.qml`, `notifications/`, `utilities/toasts/` | 760 aprox. | `SUPER+N` | C |
| Launcher | `modules/launcher/*` | 1 600 aprox. | `SUPER` | C |
| Overview | `modules/overview/Content.qml`, `WindowCard.qml` | 1 101 + 572 | `SUPER+TAB` | C |
| Portapapeles | `modules/clipboard/Content.qml`, `ClipboardItem.qml` | 871 + 416 | `SUPER+V` | C |
| Gestor de pantallas | `modules/display/*` | 1 480 aprox. | desde Ajustes | C |
| Calendario y Pomodoro | `modules/calendar/Content.qml` | 357 | BottomHub | C |
| Selector de área, fondo, reloj, visualizador | `modules/areapicker/`, `modules/background/` | 540 aprox. | varios | C |

Las superficies en **C** tienen hallazgos concretos de estado, idioma y
estructura, pero no una revisión de interacción. La fase 8 empieza con una
pasada de uso real sobre ellas; eso está contado en su alcance.

QML de más de 700 líneas: `overview/Content.qml` (1 101), `base/services/VPN.qml`
(959), `clipboard/Content.qml` (871), `BottomHub.qml` (869),
`settings/Content.qml` (804), `launcher/AppList.qml` (723),
`hardware/PowerAutomationPage.qml` (722), `wallpaper/Content.qml` (715),
`display/Editor.qml` (713), `CortetsuConfig.qml` (704).

## 3. Estado posterior a la fusión

| Comprobación | Resultado |
| --- | --- |
| PR #21 | Fusionado con merge commit `51f9a2e`. Antes: HEAD `52b21bb`, CI 10/10, `MERGEABLE`, árbol limpio. Estaba en borrador, se marcó listo para poder fusionar |
| Stashes y worktrees | 2 stashes y 11 worktrees, sin tocar |
| Entorno instalado | `cortetsu install` desde `main`; generación `current_revision=51f9a2e`; recarga suave en el mismo proceso, `NRestarts=0` |
| `cortetsu doctor` | PASS |
| `cortetsu test` | PASS (exit 0) |
| `cortetsu audit` | PASS (exit 0), sistema promovido verificado |
| `test-cortetsu-lock-runtime.py` | PASS (Hyprland anidado, PAM real) |
| `test-connectivity-ui-wayland.py` | PASS 11 |
| `test-connectivity-wifi-runtime.py` | PASS |
| `test-connectivity-bluetooth-runtime.py` | 1 fallo en la primera corrida, 3/3 PASS al repetir en solitario. Prueba sensible a carga (ventanas de 80 ms entre temporizadores). No está en `cortetsu test` ni en CI |
| `eval-ascension-runtime.py` | No ejecutable en esta máquina: `ydotool.service` está caído (`start-limit-hit`) y además el script usa `hyprctl dispatch movecursor`, que Hyprland 0.56 rechaza |

## 4. Mediciones

Shell en reposo, sin superficies abiertas, muestreo de 20 s sobre los hijos del
proceso `qs`:

- 7 ejecuciones de `nvidia-smi` (una cada 3 s, `services/Gpu.qml:37-42`).
- RSS 546 MB, 183 hilos.
- La GPU NVIDIA lleva 0 ms en suspensión en 15,5 h de sesión. No es atribuible
  solo a Cortetsu porque HDMI está conectado, pero el sondeo impide la suspensión
  cuando sí sería posible.

Estas cifras son la línea base para las fases 2 y 3.

## 5. Hallazgos

Tipos: **C** comportamiento incorrecto, **A** deuda arquitectónica, **U** UX
incompleta, **D** diseño mejorable, **O** cosmético opcional.
Evidencia: **V** verificado en ejecución, **K** deducido del código.

### P0

| ID | Tipo | Hallazgo | Evidencia |
| --- | --- | --- | --- |
| H-01 | C | En el menú de sesión, **Bloquear** y **Cerrar sesión** ejecutan `hyprctl dispatch global cortetsu:lock` y `hyprctl dispatch exit`. Hyprland 0.56 rechaza esa sintaxis. El menú se cierra y no pasa nada, sin aviso | `session/Content.qml:26,46,107`. V para `global` y `movecursor`; `exit` no se ejecutó a propósito |
| H-02 | C/A | Aplicar un esquema reescribe `CortetsuDesign.js` dentro de la generación promovida y luego recarga el shell entero y Hyprland. La recarga recrea todo el QML, y `ScreenState` pone a `false` todas las superficies, así que Ajustes se cierra a mitad de la acción y el aviso "Esquema aplicado" no llega a verse | `bin/cortetsu-scheme:63-131,150,219-221`; `components/ScreenState.qml:36-45`. K |
| H-03 | C/A | Hay dos mundos de color. El esquema dinámico del fondo solo escribe `scheme.json`, que leen 2 archivos propios y 143 heredados. Los otros 115 archivos propios (1 259 referencias a `CortetsuDesign.color*`) usan constantes JS estáticas y no cambian. Hoy el estado es `dynamic` y el archivo instalado sigue con los colores por defecto | `services/CortetsuColours.qml`, `modules/CortetsuDesign.js`, `bin/cortetsu-apply-wallpaper-colors`. V (diff de tokens instalados y `scheme.json`) |
| H-04 | C | Wallpaper Orbital pierde la selección cada 30 s. Un temporizador siempre activo relanza `find`, reasigna `list` con una lista nueva y `Content.qml` responde con `resync()`: vuelve al fondo aplicado, cancela la vista previa y pone la fase a cero | `CortetsuWallpapers.qml:236,275`; `wallpaper/Content.qml:108-120,312`. K |
| H-05 | U/C | Grabación de atajos sin estado inequívoco: lo único que cambia es el texto de un chip ("Press keys…") y una línea de estado pequeña. Sin modal, sin eco de modificadores, sin tiempo límite. Las combinaciones con `SUPER` que ya tienen acción las consume Hyprland y disparan esa acción en vez de grabarse. Las teclas fuera de la tabla (`F1`-`F12`, `Print`, símbolos con `SHIFT`) se descartan en silencio. Una tecla sola sin modificador se guarda tal cual | `hardware/KeybindsPage.qml:85-171,408,556`. K |
| H-06 | C | El popout de bloqueos siempre dice "Desactivado" y Ajustes > Entrada siempre muestra aviso con "Distribución Unknown": `capsLock`, `numLock`, `kbLayout` y `kbLayoutFull` están fijos en el adaptador | `services/Hypr.qml:21-25`; `CortetsuLockStatusPopup.qml:11-12`; `InputSection.qml:28-29`. K |

### P1

| ID | Tipo | Hallazgo | Evidencia |
| --- | --- | --- | --- |
| H-07 | A | Telemetría que no para: `Cpu`, `Gpu`, `Memory`, `Storage` y `NetworkUsage` tienen temporizadores con `running: true`. `Dash` está instanciado siempre en los dos monitores, así que sondean con el Dashboard cerrado. `Cpu.qml` y `Gpu.qml` usan `sh -c`, que `docs/PERFORMANCE.md` prohíbe | `services/Cpu.qml:50,60-67`, `Gpu.qml:19,37-42`; `DashboardHost.qml:43-48`. V |
| H-08 | A | Dos fuentes de telemetría para lo mismo: los servicios anteriores para el Dashboard y `cortetsu-hardware-probe` cada 1,5 s para Hardware. Cada muestra copia 11 arreglos de historial más uno por núcleo y entrega una lista de procesos nueva, que reconstruye la tabla entera | `hardware/Content.qml:61-87,135-160` |
| H-09 | A | Primitivas duplicadas y distintas: `CortetsuSurface`, `CortetsuText`, `CortetsuIcon` y `CortetsuStateLayer` existen en `modules/` y en `components/`. Solo la de `components/` aplica "Superficies transparentes"; la de `modules/` tiene otros colores de contorno. Cuál se usa depende del orden de imports | `modules/CortetsuSurface.qml` frente a `components/CortetsuSurface.qml` (diff) |
| H-10 | A | `CortetsuConfig.qml`: 704 líneas escritas a mano. Cada preferencia vive en tres sitios (propiedad con `onXChanged: save()`, `load()` de 235 líneas y una línea de serialización de 4 000 caracteres). Cada guardado escribe el archivo dos veces (`patchBottomHubAfterSave`). Los deslizadores guardan en cada paso, sin retardo. Ajustes además llama a `save()` a mano | `CortetsuConfig.qml:573-591,660-704`; `settings/Content.qml:602-712` |
| H-11 | A | Seis controladores casi iguales (`Clipboard`, `Hardware`, `Display`, `Overview`, `Calendar`, `Wallpaper`) con las mismas cinco funciones y el mismo `IpcHandler`. Dos políticas de exclusividad con listas de banderas repetidas: `OverlayPolicy.js` y `CortetsuOverlayPolicy.js`. Tres registros de estado: `ScreenState`, `CortetsuShellState`, `ShellState` | archivos citados |
| H-12 | C | Los popouts quedan fuera de la exclusividad. Abrir el portapapeles no cierra un popout abierto. `bottomHub control <modo>` abre pero no alterna ni tiene cierre por IPC, y puede dejar el mismo popout abierto en los dos monitores | V durante la sesión (hubo que cerrarlos con `detachedControl`) |
| H-13 | A | `CortetsuHypr` responde a casi cualquier evento crudo con `refreshToplevels`, `refreshWorkspaces` y `refreshMonitors` completos. Cada cambio de foco refresca todas las ventanas | `CortetsuHypr.qml:53-68` |
| H-14 | A | Ajustes instancia las 12 secciones, Apariencia, Red y Acerca de a la vez y alterna `visible`. Además existe una ventana por monitor. No hay `Loader` por página | `settings/SystemPage.qml:92-165`, `Content.qml:324-789`, `SettingsHost.qml:14-46` |
| H-15 | U | El atajo `showall` abre a la vez launcher, Dashboard, OSD y Ajustes, contra la política de exclusividad del propio archivo | `Shortcuts.qml:25-37` |
| H-16 | U | Hardware Center mezcla dominios y nombres: 10 pestañas con mínimo de 92 px, entre ellas "Energía" (`PowerPage`), "Energy" (`EnergyPage`) y "Automático", más "Keys" e "Inicio", que no son hardware. "Inicio" es el inventario de arranque, pero se lee como página principal | `hardware/Content.qml:309-320` |
| H-17 | U | La página principal de Hardware es una rejilla de seis tarjetas iguales y una fila de cuatro datos. No da veredicto de salud, no marca qué necesita atención y no lleva a la pestaña de detalle | `hardware/OverviewPage.qml` |
| H-18 | U | En Hardware, el error se pinta en rojo solo si el texto contiene "already" o "could not". Los mensajes en español y el resto de errores salen en gris | `KeybindsPage.qml:446-448` |
| H-19 | U/D | Wallpaper Orbital: el octágono central mide hasta 330 x 340 px y recorta a casi cuadrado una imagen 16:9; los satélites son 12 como máximo, de 78 px con miniaturas de 128 px. No hay búsqueda, ni rejilla, ni conteo por categoría, ni indicador de monitor destino. `Arriba`/`Abajo` no hacen nada aunque `docs/design/CORTETSU-PRODUCT-REBUILD.md` lo afirma. Un clic fuera cancela sin confirmar | `wallpaper/Content.qml:42,322,491-492,589-590` |
| H-20 | U/D | Ajustes: dos encabezados seguidos sin contenido entre ellos; "N familias" cuenta variantes; cada sección repite el dato en un `DomainHero` y en la `StatusCard` de debajo; "Atajos" es una lista fija de 6 filas con el texto "6 accesos" mientras el editor real vive en Hardware; "Acerca de" no muestra revisión ni generación; el buscador solo filtra categorías | `settings/Content.qml:384,587-595,782`; `ShortcutsSection.qml:24-35`; `PowerSection.qml:24-51` |
| H-21 | U/D | Pantalla de bloqueo: nueve elementos centrados apilados y dos instrucciones que dicen lo mismo. No hay estado "verificando", ni feedback de huella o rostro aunque `Pam` los expone, ni aviso de intentos agotados, ni sacudida al fallar. Lanza `hyprctl -j devices` cada 2 s por monitor mientras está bloqueado. Debajo deja ver, muy atenuada y sin desenfoque, la captura del escritorio | `lock/LockSurface.qml:81-90,107-121,185,299` |
| H-22 | U/D | Dashboard: la fila de sistema usa `CortetsuListRow`, que responde a hover y foco, pero no hace nada. Hay texto de relleno donde falta el dato ("Your desktop", "A focused space for the next thing", "The shell is ready", "Ambient conditions"). Multimedia no tiene carátula, progreso ni cambio de reproductor. Tamaño fijo de 1 180 x 620 | `dashboard/Dash.qml:17-18,197,281,373-431` |
| H-23 | U | Idioma mezclado en casi todas las superficies: "Wallpaper Forge", "Applied", "Live", "Probe unavailable", "Overview", "Sensors", "Keys", "Create app shortcut", "Clipboard history is empty", "Desktop context", junto a texto en español | búsqueda de `qsTr` |
| H-24 | A | 157 de los 194 scripts `eval-*.py` y `test-*.py` no lanzan ningún proceso: comprueban cadenas literales del código, por ejemplo `"Wallpaper Forge" in content`. Pasan con H-01 y H-06 presentes y fallarán con cualquier rediseño aunque el comportamiento sea correcto | `scripts/features/eval-wallpaper-orbital.py` |
| H-25 | U | Accesibilidad casi ausente: 2 usos de `Accessible.*` en 232 archivos, ningún `KeyNavigation`, `activeFocusOnTab` en 22 archivos | métricas |

### P2

| ID | Tipo | Hallazgo | Evidencia |
| --- | --- | --- | --- |
| H-26 | A | `BottomHub.qml` es dueño del demonio de Pomodoro, de la sincronización de calendario y de un archivo de notificaciones, dentro de un archivo de presentación de 869 líneas | `BottomHub.qml:104-130` |
| H-27 | U | Dos superficies llamadas "Ajustes rápidos" (`osd/FullContent.qml` y `utilities/Content.qml`); los atajos `qsd`, `utilities` y `osd` abren la misma | `Shortcuts.qml:79-104` |
| H-28 | D | Doble velo: el host retenido pinta un scrim de 0,34 y Hardware añade otro de 0,38; Wallpaper añade 0,18. Cada superficie queda con una oscuridad distinta | `RetainedSurfacesHost.qml:47`; `hardware/Wrapper.qml:28`; `wallpaper/Wrapper.qml:40` |
| H-29 | A | `Escape` se gestiona dos veces en casi todas las superficies (host y contenido) | `RetainedSurfacesHost.qml:83`, `DashboardHost.qml:49` más `Dash.qml:433` |
| H-30 | D | Valores sueltos: 40 radios numéricos en 25 archivos, tamaños de fuente fijos en bloqueo y Ajustes, 8 `TextInput` crudos fuera de `CortetsuSearchBar`, 37 usos de `CortetsuStateLayer`, la mayoría sobre rectángulos hechos a mano en vez de `CortetsuButton` | métricas |
| H-31 | D | El emblema aparece tres veces en una misma pantalla de Ajustes, contra la regla de uso selectivo | `settings/Content.qml:111,266,348` |
| H-32 | U | En Procesos, `sendSignal` ejecuta `kill` de inmediato. Falta confirmar si la interfaz pide confirmación para `KILL` | `hardware/ProcessesPage.qml:79-85` |
| H-33 | A | El octágono del Orbital está escrito cuatro veces como `ShapePath` | `wallpaper/Content.qml:475,540,614,647` |
| H-34 | A | `cortetsu-scheme-posthook` busca `surface` en la raíz de `scheme.json`, pero los colores están bajo `colours`. El puente con Brave nunca encuentra color | `bin/cortetsu-scheme-posthook:52-58` |
| H-35 | A | `test-connectivity-bluetooth-runtime.py` es inestable bajo carga y `eval-ascension-runtime.py` usa sintaxis de dispatch retirada | sección 3 |

## 6. Coherencia entre superficies

El mismo problema resuelto de formas distintas:

| Aspecto | Variantes encontradas |
| --- | --- |
| Marco de panel | `Rectangle` a mano con radio 24 (Hardware), `CortetsuSurface` con `radiusSurface` 28 (Ajustes, Dashboard), sin panel (Wallpaper) |
| Cabecera | Icono, título y botones redondos a mano (Hardware); emblema, título y botón con texto "Cerrar" (Ajustes); emblema, título y botón solo icono (Dashboard, Wallpaper) |
| Velo | 0,34, 0,34 + 0,38, 0,34 + 0,18, 0,34 con otro color base |
| Búsqueda | `CortetsuSearchBar` (Ajustes, Launcher) y `TextInput` crudo sin foco visible ni texto de ayuda (Hardware, Portapapeles, Pantallas) |
| Estados vacío, carga y error | `CortetsuStateMessage` en 14 archivos; texto de estado suelto en Hardware, Wallpaper, Portapapeles y Calendario |
| Confirmación destructiva | Dos clics en 4 s (Sesión, Keys), "Confirmar detener" (Inicio), ninguna (Procesos, cerrar Wallpaper con vista previa) |
| Color | Tokens estáticos (propio) frente a paleta reactiva (heredado), ver H-03 |
| Idioma | Español, inglés o ambos en la misma superficie |

Cortetsu se percibe como módulos de épocas distintas por estas ocho diferencias
más que por el estilo de cada pantalla. La fase 4 las cierra antes de rediseñar.

## 7. Fases

Ocho fases. Las tres primeras son estructurales y deben ir antes de añadir
funciones.

### Fase 1. Correcciones de comportamiento y pruebas que miden comportamiento

**Situación y evidencia.** H-01, H-04, H-06, H-12, H-15, H-18, H-24, H-34, H-35.

**Problemas.** Acciones que fallan en silencio, datos falsos en pantalla y una
batería de pruebas que no los detecta.

**Archivos.** `session/Content.qml`, `services/Hypr.qml`, `CortetsuHypr.qml`,
`CortetsuWallpapers.qml`, `wallpaper/Content.qml`, `Shortcuts.qml`,
`BottomHub.qml`, `bar/popouts/Wrapper.qml`, `hardware/KeybindsPage.qml`,
`bin/cortetsu-scheme-posthook`, `scripts/features/eval-ascension-runtime.py`,
`scripts/features/test-connectivity-bluetooth-runtime.py`.

**Comportamiento objetivo.**
- Bloquear bloquea y Cerrar sesión cierra la sesión. Si la orden falla, el menú
  sigue abierto y muestra el error.
- El popout de bloqueos y Ajustes > Entrada muestran el estado real del teclado.
- El Orbital no cambia de selección si la carpeta no cambió.
- Abrir cualquier superficie cierra los popouts; `bottomHub control` alterna y
  existe `bottomHub closeControl`.
- `showall` no abre Ajustes.

**Propuesta técnica.**
- Sesión: Bloquear llama a `lockController.requestLock()` (ya se pasa al
  componente). Cerrar sesión usa `CortetsuHypr.dispatch` con la forma Lua cuando
  `usingLua` es cierto, igual que `BottomHub.qml:712-715`. Sustituir
  `execDetached` por un `Process` con `onExited` para poder informar del fallo.
  Antes de escribir el dispatcher de salida, confirmar su nombre en la
  documentación de Hyprland 0.56.
- Teclado: una sola fuente en `CortetsuHypr` que lea `hyprctl -j devices` al
  arrancar y en los eventos `activelayout`; el bloqueo y el popout la consumen.
  Si Caps y Num no llegan por evento, sondear solo mientras un consumidor esté
  visible. Sin dato, la interfaz dice "No disponible", no "Desactivado".
- Wallpaper: en `scan`, comparar la lista de rutas con la anterior y asignar
  `list` solo si cambia. Quitar el temporizador de 30 s y releer al abrir el
  gestor y cuando cambie `path.txt` (ya hay `FileView`).
- Popouts: mover "popout abierto" a `CortetsuScreenState` para que
  `closeOtherPanels` lo cierre.
- Estado de error en Keys: campo `ok` del JSON del helper, no el texto.
- Pruebas: un arnés que carga la superficie real con `quickshell -p` y dobles de
  servicio, como ya hacen `test-cortetsu-lock-runtime.py` y
  `test-connectivity-ui-wayland.py`. Se sustituye un test de cadenas solo cuando
  la fase toca esa superficie.

**Propuesta UX.** Las filas de Sesión muestran "No se pudo bloquear" o "No se
pudo cerrar la sesión" con el motivo. Sin más cambio visual.

**Dependencias.** Ninguna.

**Riesgos.** Probar Cerrar sesión cierra la sesión real: se prueba en Hyprland
anidado. El origen de Caps y Num puede exigir sondeo.

**Pruebas automáticas.** Sesión en Hyprland anidado (bloqueo efectivo, salida
del compositor, fila de error con orden falsa). `qmltestrunner` para el Orbital:
dos escaneos con la misma lista no emiten `listChanged`. Estado de teclado con
JSON de `devices` simulado. IPC: abrir popout, abrir portapapeles, `inspect`
devuelve `open: false`. Corregir H-35.

**Validación manual.** Bloquear y cerrar sesión desde el menú en la sesión real.
Dejar el Orbital abierto 90 s sobre un fondo no aplicado. Pulsar Bloq Mayús con
el popout abierto.

**Criterios de finalización.** Los seis comportamientos anteriores pasan en
automático y a mano; `cortetsu test` y `cortetsu audit` en verde; existe el
arnés y lo usan al menos Sesión y Wallpaper.

### Fase 2. Tema reactivo y una sola familia de primitivas

**Situación y evidencia.** H-02, H-03, H-09, H-34. Es el caso que pediste: un
cambio de esquema hoy recrea todo el shell cuando debería cambiar colores.

**Problemas.** Los tokens son una biblioteca JS (`.pragma library`): sus valores
no notifican cambios, así que la única forma de cambiarlos es reescribir el
archivo y recargar. Además el archivo vive en una generación que debería ser
inmutable.

**Archivos.** `modules/CortetsuDesign.js`, `core/theme.py`,
`services/CortetsuColours.qml`, `bin/cortetsu-scheme`, `bin/build-runtime.sh:296-322`,
`launcher/services/Schemes.qml`, `CortetsuWallpapers.qml`, las 115 líneas de
import de `CortetsuDesign.js`, y los cuatro pares duplicados en `modules/` y
`components/`.

**Comportamiento objetivo.** Elegir un esquema cambia los colores en la misma
sesión, sin recarga, sin cerrar ninguna superficie y sin tocar la generación.
El fondo con "Esquema inteligente" tiñe todas las superficies, propias y
heredadas. La transparencia afecta a todas por igual.

**Propuesta técnica.**
1. `core/theme.py` genera `CortetsuDesignDefaults.js` (los mismos valores de
   hoy) y un singleton QML `modules/CortetsuDesign.qml` con las mismas
   propiedades. Los tokens de color son enlaces
   `CortetsuColours.schemeColour("<rol M3>", Defaults.colorX)` con el mapa de
   roles que hoy está en `cortetsu-scheme:70-90`. Los tokens que no son color
   son `readonly property` constantes.
2. En los 115 archivos se elimina la línea
   `import ".../CortetsuDesign.js" as CortetsuDesign`. El nombre
   `CortetsuDesign.colorX` sigue resolviendo, ahora contra el singleton, a
   través del import del directorio `modules` (añadirlo donde falte). Las 1 259 expresiones no
   cambian. Ningún `.js` importa los tokens (comprobado), así que no hay
   bibliotecas que adaptar.
3. `cortetsu-scheme set` solo escribe `scheme.json` y `hypr/scheme/current.lua`.
   Se borran `write_runtime_design`, `reload_runtime` y el bloque de
   `build-runtime.sh` que reaplica el esquema tras promover.
4. Hyprland: comprobar si 0.56 permite cambiar los colores de borde sin
   recarga completa; si no, mantener `hyprctl reload` solo para eso.
5. Fusionar los pares duplicados en `components/` y borrar las copias de
   `modules/`. `CortetsuSurface` aplica la transparencia en un único sitio.
6. `Schemes.apply` deja de depender de una recarga: el estado `applied` se
   deriva de que `CortetsuColours.scheme` coincida con el pedido.
7. Corregir la clave que lee el posthook (H-34).

**Propuesta UX.** Transición de color de 180 ms en las superficies
(`ColorAnimation` en `CortetsuSurface` y `CortetsuText`, no por consumidor).
Vista previa al pasar el cursor o el foco por una tarjeta de esquema, usando el
canal `previewColours` que ya existe, con retardo de 150 ms; confirmar con clic
o `Enter`, descartar al salir.

**Dependencias.** Fase 1 por el arnés.

**Riesgos.** Coste de 1 259 enlaces reactivos frente a constantes: medir el
arranque y el RSS antes y después. Contraste con esquemas claros o con paletas
dinámicas de poco contraste: validar pares texto/superficie con
`scripts/features/audit-theme-colours.py`. Los tests de cadenas que buscan el
import antiguo fallarán y hay que reescribirlos.

**Pruebas automáticas.** `cortetsu-scheme set` no modifica ningún archivo bajo
`quickshell/cortetsu/current` (hash antes y después). Arnés: cambiar
`scheme.json` con una superficie abierta cambia `color` de un `CortetsuSurface`
y el contador de `Component.onCompleted` no sube. `theme check` cubre los dos
archivos generados.

**Validación manual.** Con Ajustes abierto, aplicar tres esquemas seguidos:
Ajustes no se cierra, barra y popouts cambian a la vez, `NRestarts` no sube y el
journal no muestra "Reloading configuration". Repetir con un fondo y esquema
inteligente activo. Comprobar los dos monitores.

**Criterios de finalización.** Cero recargas al cambiar esquema; cero
escrituras en la generación; una definición por primitiva; arranque no más de
un 5 % más lento que la línea base.

### Fase 3. Estado, persistencia y telemetría

**Situación y evidencia.** H-07, H-08, H-10, H-11, H-13, H-14, H-26, H-29.

**Problemas.** Trabajo en segundo plano que no depende de que alguien mire,
modelos que se reemplazan enteros, preferencias con tres copias del esquema y
lógica de exclusividad repetida.

**Archivos.** `services/Cpu.qml`, `Gpu.qml`, `Memory.qml`, `Storage.qml`,
`NetworkUsage.qml`, `hardware/Content.qml`, `hardware/ProcessesPage.qml`,
`CortetsuConfig.qml`, los seis `*Controller.qml`, `OverlayPolicy.js`,
`CortetsuOverlayPolicy.js`, `CortetsuShellState.qml`, `services/ShellState.qml`,
`CortetsuHypr.qml`, `settings/SystemPage.qml`, `settings/Content.qml`,
`DashboardHost.qml`, `BottomHub.qml`.

**Comportamiento objetivo.** Con todo cerrado, el shell no lanza procesos
periódicos de telemetría. Una preferencia nueva se declara en un solo sitio.
Una muestra nueva actualiza las filas que cambian, no la tabla.

**Propuesta técnica.**
- Telemetría: un servicio `CortetsuTelemetry` con contador de consumidores
  (`retain()`/`release()` desde `Component.onCompleted` y `onDestruction` de la
  vista, o una propiedad `active` enlazada a su visibilidad). Sondea solo si el
  contador es mayor que cero. Fuente única: `cortetsu-hardware-probe`; Dashboard
  y Hardware leen el mismo objeto. Se eliminan los `sh -c`. La consulta a NVIDIA
  solo ocurre con consumidor visible.
- Historial: búfer circular de tamaño fijo por métrica, sin `Array.from` por
  muestra.
- Modelos: `ScriptModel` con `objectProp` (ya se usa en el launcher y en las
  pruebas de BottomHub) para procesos, atajos, esquemas e inventario de inicio.
- Preferencias: `FileView` con `JsonAdapter` de Quickshell 0.3.1, una propiedad
  por preferencia, escritura con retardo de 300 ms y un solo `writeAdapter()`.
  Migración de `preferences.json` con el esquema actual y prueba de ida y vuelta.
  Se retira `patchBottomHubAfterSave`.
- Controladores: un componente `RetainedSurfaceController { flag; ipcTarget;
  shortcutName }` y una sola política de exclusividad.
- Hyprland: confiar en el seguimiento propio de `Quickshell.Hyprland` y
  refrescar solo lo que cada evento invalida.
- Ajustes: un `Loader` por página con `active` ligado a la categoría, y una sola
  instancia de contenido, no una por monitor.
- Dashboard: `Loader` activo solo mientras está abierto o cerrándose.
- Pomodoro y calendario salen de `BottomHub.qml` a un servicio propio.

**Propuesta UX.** Sin cambio visible, salvo que los deslizadores de Ajustes
dejan de escribir a disco en cada paso.

**Dependencias.** Fase 1. Conviene después de la fase 2 para no migrar dos
veces los mismos archivos.

**Riesgos.** Migrar preferencias puede perder ajustes: copia de seguridad del
archivo y prueba con el `preferences.json` real. Cargar páginas bajo demanda
puede añadir latencia al abrir: medir contra el objetivo de 120 ms de
`docs/PERFORMANCE.md`.

**Pruebas automáticas.** Muestreo de procesos hijos durante 20 s en reposo: cero
`nvidia-smi` y cero `sh`. Ida y vuelta de preferencias con el archivo actual.
Prueba de modelo: una muestra nueva no destruye delegados (patrón de
`tst_BottomHubDelegateChurn.qml`). Una prueba por controlador retenido contra el
componente común.

**Validación manual.** `runtime_status` de la GPU con HDMI desconectado y el
shell en reposo. Arrastrar un deslizador en Ajustes y observar las escrituras
con `inotifywait`.

**Criterios de finalización.** Cero procesos periódicos de telemetría en
reposo; `CortetsuConfig.qml` por debajo de 300 líneas; un controlador retenido,
una política y un registro de estado; apertura de Ajustes dentro del presupuesto.

### Fase 4. Sistema de componentes, idioma y accesibilidad

**Situación y evidencia.** Sección 6, H-23, H-25, H-28, H-29, H-30, H-31.

**Problemas.** Cada superficie construye su marco, su cabecera, su búsqueda, su
velo y sus estados.

**Archivos.** `components/*`, `modules/CortetsuSearchBar.qml`,
`RetainedSurfacesHost.qml`, los hosts, y cada superficie al adoptar los
componentes.

**Comportamiento objetivo.** Dos superficies cualesquiera comparten marco,
cabecera, velo, foco, estados y tono.

**Propuesta técnica.** Componentes que faltan, todos en `components/`:

| Componente | Sustituye |
| --- | --- |
| `CortetsuPanel` (marco, radio, contorno, relleno) | `Rectangle` de Hardware, superficies de Ajustes y Dashboard |
| `CortetsuPanelHeader` (icono o emblema, título, detalle, acciones, cerrar) | cuatro cabeceras a mano |
| `CortetsuScrim` (una opacidad, en el host) | velos de host y de superficie |
| `CortetsuIconButton` | `Item` + `CortetsuSurface` + `CortetsuStateLayer` + `CortetsuIcon` repetidos |
| `CortetsuTextField` | 8 `TextInput` crudos |
| `CortetsuKeyChip` | chips de atajo de Keys y de Ajustes |
| `CortetsuConfirm` (acción armada, cuenta atrás visible) | tres variantes de confirmación |
| `CortetsuTabBar` | pestañas de Hardware, categorías del Orbital |

`CortetsuStateMessage` pasa a ser obligatorio para vacío, carga y error.
`Escape` lo gestiona solo el host. Cada control interactivo declara
`Accessible.role` y `Accessible.name`, y el anillo de foco es uno. Una
comprobación estática prohíbe radios, duraciones y tamaños de fuente numéricos
fuera de los tokens.

**Propuesta UX y visual.**
- Idioma: español en toda la interfaz. Los nombres de producto no se traducen.
- Emblema: una vez por superficie, en la cabecera.
- Velo: una sola opacidad para superficies completas; el Orbital puede pedir
  una menor porque el fondo es su contenido.
- Radios: 28 marco, 20 tarjeta, 12 control, 8 chip.
- Movimiento: 120, 180 y 240 ms con `OutCubic`, ya definidos.

**Dependencias.** Fase 2 (una sola familia de primitivas).

**Riesgos.** Cambio amplio de apariencia: adoptar por superficie con capturas
antes y después en los dos monitores. Los tests de cadenas de cada superficie
tocada se sustituyen por pruebas de comportamiento.

**Pruebas automáticas.** `qmltestrunner` por componente: hover, pulsado, foco,
deshabilitado, activación con `Enter` y `Space`, `Tab` salta deshabilitados
(patrón de `tests/qml/focus`). Comprobación estática de tokens y de texto en
inglés dentro de `qsTr`.

**Validación manual.** Recorrido solo con teclado por cada superficie: `Tab`,
`Shift+Tab`, `Enter`, `Escape`. Revisión a escala 1 y 1,25.

**Criterios de finalización.** Cero `TextInput` crudos fuera de los
componentes; cero radios o duraciones numéricas; cero textos en inglés; todas
las superficies completas usan `CortetsuPanel`, `CortetsuPanelHeader` y el velo
del host.

### Fase 5. Ajustes y atajos

**Situación y evidencia.** H-05, H-14, H-16, H-18, H-20, H-31.

**Problemas.** El editor de atajos está en Hardware y no comunica cuándo
escucha. Ajustes repite datos y tiene secciones de relleno.

**Archivos.** `settings/*`, `hardware/KeybindsPage.qml`,
`hardware/StartupPage.qml`, `bin/cortetsu-keybinds`, `hardware/Content.qml`.

**Comportamiento objetivo.** Los atajos se consultan y se editan en Ajustes >
Atajos. Mientras se graba no hay duda de que se está grabando, qué se ha pulsado
y cómo salir.

**Propuesta técnica.**
- Mover `KeybindsPage` a Ajustes > Atajos y `StartupPage` a Ajustes > Inicio
  automático. Hardware queda con hardware.
- Captura como máquina de estados: `reposo`, `escuchando`, `capturado`,
  `conflicto`, `guardando`, `error`.
- Para que `SUPER` y las combinaciones ya asignadas lleguen a la interfaz,
  entrar en un submapa vacío de Hyprland al empezar y salir al terminar,
  cancelar, cerrar o perder el foco. Hay que validar en 0.56.2 que un submapa
  sin atajos entrega las teclas a la capa con foco exclusivo y cuál es la orden
  Lua. Si no funciona, declarar el límite en la interfaz ("las combinaciones ya
  asignadas se cambian liberándolas antes").
- Exigir al menos un modificador, salvo teclas de función y multimedia. Ampliar
  la tabla de teclas. Validar también en el helper.
- Salida automática de la escucha a los 10 s.
- Conflictos: el helper ya los detecta; mostrar con qué acción choca y ofrecer
  reasignar.
- Búsqueda de Ajustes sobre ajustes individuales con salto al control.
- "Acerca de" lee revisión, generación y versiones de `cortetsu status`.

**Propuesta UX y visual.**
- Grabación: velo sobre la página, tarjeta centrada con el nombre de la acción,
  el atajo actual, y una fila de `CortetsuKeyChip` que se llena en vivo con cada
  modificador mantenido. Borde índigo con pulso mientras escucha. Texto fijo:
  "Escuchando. Pulsa la combinación · Esc cancela". Barra de cuenta atrás.
  Al capturar: la combinación en grande durante 600 ms y luego "Guardado", o
  bermellón con "Ya asignado a <acción>" y los botones Reasignar y Cancelar.
- Lista de atajos agrupada por dominio (Shell, Ventanas, Espacios, Apps,
  Multimedia), con filtro y con marca en los modificados por el usuario.
- Cada sección de Ajustes: un resumen de una línea en la cabecera y debajo los
  controles. Se retira el `DomainHero` cuando repite la tarjeta siguiente.
- Apariencia: esquema activo, galería con vista previa (fase 2) y preferencias
  agrupadas en Superficie, Reloj y unidades, Visualizador.

**Dependencias.** Fases 2, 3 y 4.

**Riesgos.** Un submapa sin salida deja el teclado sin atajos: salida garantizada
en `Component.onDestruction`, al cerrar la superficie y por el tiempo límite.
Mover páginas cambia hábitos: dejar en Hardware un enlace "Atajos está ahora en
Ajustes" durante una versión.

**Pruebas automáticas.** Máquina de estados de captura con eventos sintéticos:
solo modificador, tecla sin modificador, combinación válida, `Esc`, tiempo
límite, conflicto. Helper: rechazo sin modificador. Ajustes: una sola página
instanciada a la vez. Hyprland anidado: entrar y salir del submapa.

**Validación manual.** Grabar `SUPER+SHIFT+K`, una combinación en uso, `F9`,
cancelar con `Esc`, dejar agotar el tiempo. Tras cada caso, comprobar que
`SUPER+I` sigue funcionando.

**Criterios de finalización.** Los seis estados son visibles y están probados;
ningún camino deja el submapa activo; Hardware no contiene Keys ni Inicio;
Ajustes no tiene encabezados vacíos ni tarjetas duplicadas.

### Fase 6. Hardware Center, Dashboard y ajustes rápidos

**Situación y evidencia.** H-08, H-16, H-17, H-22, H-27, H-32.

**Problemas.** La página principal de Hardware no responde a "¿está bien el
equipo?". El Dashboard muestra relleno y tiene filas que parecen botones.
Existen dos "Ajustes rápidos".

**Archivos.** `hardware/*`, `dashboard/*`, `DashboardHost.qml`,
`osd/FullContent.qml`, `utilities/Content.qml`, `Shortcuts.qml`.

**Comportamiento objetivo.**
- Hardware abre en un resumen que dice el estado, qué necesita atención y lleva
  al detalle con un clic o una tecla.
- Cada elemento del Dashboard con aspecto de control hace algo.
- Hay una sola superficie de ajustes rápidos.

**Propuesta técnica.** Hardware con cinco pestañas: Resumen, Rendimiento,
Procesos, Sensores y E/S, Energía. Energía une `PowerPage`, `EnergyPage` y
`PowerAutomationPage` como secciones. Un módulo JS puro calcula la salud a
partir de umbrales (temperatura, memoria, disco, batería, carga) para poder
probarlo con datos fijos. El Dashboard usa la telemetría de la fase 3. Se retira
la superficie de ajustes rápidos que quede sin uso y sus atajos de
compatibilidad apuntan a la otra.

**Propuesta UX y visual.**
- Resumen de Hardware, de arriba abajo:
  1. Franja de estado: "Todo en orden", o la lista de lo que requiere atención
     ("GPU a 86 °C", "Disco al 93 %"). Cada entrada lleva a su pestaña.
  2. Cuatro medidores principales (CPU, memoria, GPU, disco) con valor grande,
     minigráfica de 60 muestras y un dato secundario. Clic: abre Rendimiento con
     esa métrica.
  3. Columna derecha: los tres procesos con más consumo, con enlace a Procesos.
  4. Pie: energía (perfil, batería, autonomía), red (interfaz, bajada y subida)
     y tiempo encendido.
  Las tarjetas dejan de ser iguales: los medidores mandan y el resto acompaña.
- Estados de Hardware: primera lectura con esqueleto, sonda caída con
  `CortetsuStateMessage` y botón Reintentar, y "en vivo" con la hora de la
  última muestra en lugar de la palabra "Live".
- Procesos: `KILL` pide confirmación con `CortetsuConfirm`; `TERM` no.
- Dashboard: la fila de sistema pasa a `CortetsuActionTile` y abre Hardware en
  la pestaña correspondiente. Sin clima: "Sin datos de clima" y Configurar
  ubicación. Sin multimedia: "Nada en reproducción" sin frase de relleno.
  Multimedia con carátula, progreso y selector de reproductor (el modelo ya
  existe en `services/Players.qml`). Ancho `min(1180, pantalla - 96)`.

**Dependencias.** Fases 3, 4 y 5 (Keys e Inicio ya fuera de Hardware).

**Riesgos.** Los umbrales de salud pueden alarmar sin motivo: empezar
conservadores. Las minigráficas se actualizan una vez por muestra, no por
fotograma.

**Pruebas automáticas.** Módulo de salud con instantáneas fijas. Navegación:
clic en un medidor abre la pestaña correcta. Dashboard: cada fila emite su
acción. Confirmación de `KILL`.

**Validación manual.** Hardware bajo carga real (`stress-ng` unos minutos), con
la sonda renombrada para ver el estado de error, y en los dos monitores.

**Criterios de finalización.** Cinco pestañas, ninguna con nombre duplicado; el
Resumen muestra veredicto y enlaces; ningún control inerte en el Dashboard; una
superficie de ajustes rápidos.

### Fase 7. Wallpaper Orbital y pantalla de bloqueo

**Situación y evidencia.** H-19, H-21, H-33.

**Problemas.** El Orbital dedica el centro a un recorte que no representa el
fondo y solo enseña doce candidatos pequeños. El bloqueo funciona, pero es una
columna de texto sin carácter.

**Archivos.** `wallpaper/Content.qml`, `OrbitModel.js`, `wallpaper/Wrapper.qml`,
`CortetsuWallpapers.qml`, `CortetsuWallpaperSearch.js`, `lock/LockSurface.qml`,
`lock/Lock.qml`.

**Comportamiento objetivo.**
- Orbital: explorar una colección grande, filtrar, ver el candidato como
  quedará, comparar con el actual y aplicar, con el teclado o con el ratón.
- Bloqueo: desbloquear igual de rápido y fiable que hoy, con identidad y con
  estado de autenticación legible.

**Propuesta técnica (Orbital).**
- El modelo orbital se mantiene (`OrbitModel.js` está probado). Cambia la
  geometría: el arco es una franja de navegación, no un anillo alrededor del
  centro.
- Un componente `OctagonFrame` para el octágono achaflanado, usado por
  satélites y marco.
- Búsqueda con `CortetsuWallpaperSearch.js`, que ya usa el launcher.
- Miniaturas en caché en disco con tamaño fijo; decodificación asíncrona
  acotada como ahora.
- La vista previa en el escritorio sigue con retardo y se cancela al salir.

**Propuesta UX y visual (Orbital).**
- Composición en tres bandas dentro del mismo panel de hasta 1 100 x 720:
  1. Cabecera: emblema, nombre, búsqueda, categorías con conteo ("Paisajes 42"),
     monitor destino y cerrar.
  2. Escenario, cerca del 60 % del alto: el candidato en 16:9 real, sin recorte
     octogonal de la imagen. El chaflán pasa al marco. A la derecha, una
     miniatura del fondo actual para comparar, que desaparece si el candidato es
     el actual. Sobre la imagen, abajo a la izquierda: nombre, categoría,
     resolución y estado (Actual, Vista previa, Aplicando, Error).
  3. Órbita: arco inferior de 9 a 15 satélites de unos 120 x 72 px, 16:9, con
     el central más grande y la profundidad actual (escala, opacidad, orden).
     Aquí vive la identidad orbital: la rueda gira bajo el escenario.
- `Tab` alterna entre órbita y rejilla completa por categoría con
  desplazamiento, para colecciones grandes.
- Teclado: `Izquierda`/`Derecha` mueven, `Arriba`/`Abajo` cambian de categoría,
  `/` enfoca la búsqueda, `Inicio`/`Fin`, `Re Pág`/`Av Pág` saltan una ventana,
  `Enter` aplica, `R` aleatorio, `Esc` cierra. Leyenda de teclas en el pie.
- Clic fuera con una vista previa activa: restaura y cierra, con un aviso breve
  "Vista previa descartada". Sin diálogo.
- Estados: cargando biblioteca (esqueleto), carpeta vacía (ruta y Abrir
  carpeta), sin resultados, y error al aplicar con el motivo y Reintentar.

**Propuesta técnica (bloqueo).** No se toca `Pam.qml` ni `WlSessionLock`. El
estado de teclado viene de la fuente única de la fase 1, sin proceso cada 2 s.
Los estados de `pam.state`, `fprint` y `howdy` se traducen a un enumerado
legible en un módulo JS probado.

**Propuesta UX y visual (bloqueo).**
- Fondo: el fondo de pantalla actual con desenfoque y velo sumi, no la captura
  del escritorio. Si el desenfoque cuesta, imagen pre-desenfocada en caché al
  cambiar de fondo.
- Composición asimétrica: reloj grande y fecha arriba a la izquierda, con peso
  tipográfico. Bloque de autenticación abajo al centro: emblema, usuario y
  campo. Estado del sistema (batería, red, teclado, Bloq Mayús) en una línea en
  la esquina inferior derecha, sin tarjetas.
- Una sola instrucción, dentro del campo vacío.
- Campo: puntos con cursor; "Verificando…" con el emblema en Awakening; fallo
  con sacudida horizontal de 160 ms, borde bermellón y "Contraseña incorrecta";
  intentos agotados con texto propio; huella y rostro con icono y estado cuando
  estén activos.
- Motivo de identidad: un trazo fino diagonal (el "corte") entre el bloque de
  reloj y el de autenticación, y el emblema que evoluciona con el estado real,
  como ya hace.
- Bloq Mayús activo se muestra junto al campo, que es donde importa.

**Dependencias.** Fases 1 (H-04, estado de teclado), 2 (colores) y 4
(componentes).

**Riesgos.** Bloqueo: cualquier regresión deja al usuario fuera. La parte visual
se cambia sin tocar la ruta de autenticación y `test-cortetsu-lock-runtime.py`
debe pasar en cada commit. El desenfoque no puede retrasar el primer fotograma
del bloqueo: si no está listo, se usa un color sólido. Orbital: decodificar
imágenes grandes para el escenario; mantener `sourceSize` acotado al tamaño del
escenario.

**Pruebas automáticas.** `tst_Orbit.qml` ampliado: geometría del arco, saltos de
ventana, cambio de categoría con teclado, búsqueda. Arnés del Orbital: vacío,
sin resultados, error al aplicar, cierre con vista previa activa. Bloqueo:
módulo de estados con todas las combinaciones de `pam`; prueba en Hyprland
anidado existente; prueba de que la superficie aparece aunque la imagen de
fondo falte.

**Validación manual.** Orbital con la colección real y con una carpeta de 500
imágenes, en ambos monitores, con rueda, clic y teclado. Bloqueo: contraseña
correcta, incorrecta tres veces, Bloq Mayús, suspensión y reanudación, conectar
y desconectar HDMI mientras está bloqueado.

**Criterios de finalización.** El escenario muestra la imagen en su proporción;
búsqueda, rejilla y teclado completos; cuatro estados del Orbital probados; el
bloqueo no lanza procesos periódicos; la prueba de bloqueo en ejecución pasa.

### Fase 8. BottomHub, popouts, notificaciones, launcher, Overview, portapapeles, pantallas y calendario

**Situación y evidencia.** H-12, H-23, H-26, H-30 y las superficies en
profundidad C del inventario.

**Problemas conocidos.** Portapapeles y calendario con textos en inglés, sin
`CortetsuStateMessage` y con búsqueda cruda. Overview de 1 101 líneas con la
lógica de Hyprland dentro de la vista. `launcher/AppList.qml` de 723 líneas con
cinco delegados en un archivo. Popouts con estado fuera del registro común.

**Archivos.** `BottomHub.qml`, `CortetsuStatusSegment.qml`, `CortetsuAppRail.qml`,
`CortetsuTraySegment.qml`, `bar/popouts/*`, `sidebar/*`, `notifications/*`,
`utilities/toasts/*`, `osd/*`, `launcher/*`, `overview/*`, `clipboard/*`,
`display/*`, `calendar/*`.

**Comportamiento objetivo.** Estas superficies usan los mismos componentes,
estados, idioma y reglas de foco que las anteriores, y se comportan igual en
los dos monitores.

**Propuesta técnica.** La fase empieza con una pasada de uso real por
superficie (teclado, ratón, dos monitores, escala) que añade hallazgos a este
documento con el formato de la sección 5. Después: adoptar los componentes de la
fase 4; sacar la lógica de Hyprland de `overview/Content.qml` a un controlador;
partir `AppList.qml` en un archivo por delegado; partir `BottomHub.qml` en
ventana, IPC y lógica de foco de ventanas.

**Propuesta UX y visual.** Popouts con la misma cabecera compacta y el mismo
ancho por tipo. Toasts y OSD con el mismo marco y el mismo margen sobre el
BottomHub. Notificaciones con estados vacío e "En silencio" ya existentes como
referencia para el resto. Ningún rediseño de composición salvo que la pasada
inicial lo justifique con un hallazgo P0 o P1.

**Dependencias.** Fases 2, 3 y 4.

**Riesgos.** BottomHub y Overview son las superficies de uso continuo: cambios
pequeños y verificados con `eval-ascension-runtime.py` una vez corregido.

**Pruebas automáticas.** Las de `tests/qml/bottomhub` se mantienen. IPC
`inspect` en cada superficie retenida. Pruebas de comportamiento para
portapapeles (vacío, error de Clipse, fijar, limpiar) y Overview (selección,
mover ventana, cerrar).

**Validación manual.** Recorrido completo de teclado y ratón en ambos
monitores; 40 ciclos de apertura y cierre en BottomHub, launcher y Overview,
como pide `docs/PERFORMANCE.md`.

**Criterios de finalización.** Ningún archivo propio por encima de 700 líneas;
todas las superficies pasan las comprobaciones estáticas de la fase 4; el
inventario de la sección 2 queda con profundidad A en todas las filas.

## 8. Cambios rápidos de bajo riesgo

Cada uno cabe en un commit pequeño y no depende de otra fase.

1. Sesión: Bloquear por `lockController.requestLock()` y Cerrar sesión con el
   dispatcher Lua (H-01).
2. Wallpaper: asignar `list` solo si cambia y quitar el temporizador de 30 s
   (H-04).
3. `showall`: quitar `state.settings = open` (H-15).
4. Keys: color de error por el campo `ok` del helper (H-18).
5. Ajustes: borrar el encabezado vacío "Apariencia del shell" y corregir
   "familias" (H-20).
6. Posthook de Brave: leer `colours.surface` (H-34).
7. Renombrar pestañas de Hardware: "Resumen", "Rendimiento", "Sensores",
   "Energía", "Automatización", "Consumo", "Atajos", "Inicio automático"
   (H-16, H-23).
8. `Gpu.qml`: sondear solo con el Dashboard abierto, como paso previo a la
   fase 3 (H-07).
9. `eval-ascension-runtime.py`: usar la forma Lua para mover el cursor (H-35).
10. `bottomHub control`: alternar y añadir `closeControl` (H-12).

## 9. Cambios estructurales previos a nuevas funciones

1. Tema reactivo sin recarga (fase 2). Cualquier superficie nueva escrita sobre
   tokens estáticos añade deuda a migrar.
2. Una sola familia de primitivas (fase 2).
3. Preferencias con `JsonAdapter` (fase 3). Hoy cada preferencia nueva se
   escribe tres veces.
4. Telemetría con consumidores (fase 3).
5. Controlador retenido y política de exclusividad únicos, con los popouts
   dentro (fases 1 y 3).
6. Pruebas de comportamiento en lugar de cadenas (fase 1 en adelante). Sin
   ellas, las fases 5 a 8 rompen la batería sin que eso diga nada del producto.

## 10. Orden recomendado

1. **Fase 1.** Contiene los únicos fallos que rompen flujos hoy (bloquear y
   cerrar sesión desde el menú, selección del Orbital, datos falsos de teclado)
   y crea el arnés que necesitan todas las demás.
2. **Fase 2.** Es la causa raíz del problema de recarga y de los dos mundos de
   color, y toca los 115 archivos propios una sola vez. Hacerla después de
   rediseñar superficies obligaría a repasarlas.
3. **Fase 3.** Quita el trabajo en segundo plano y simplifica el estado antes
   de que las fases 5 y 6 añadan vistas sobre él.
4. **Fase 4.** Componentes compartidos, para que los rediseños no vuelvan a
   divergir.
5. **Fases 5, 6 y 7**, en ese orden: la 5 saca Keys e Inicio de Hardware, de lo
   que depende la 6; la 7 es independiente de ambas y puede adelantarse si se
   prefiere ver antes el Orbital y el bloqueo.
6. **Fase 8** al final.

Los cambios rápidos 1 a 6 de la sección 8 pueden entrar antes de empezar la
fase 1 completa.

## 11. Límites de esta auditoría

- H-02, H-04 y H-05 están deducidos del código; no se reprodujeron en vivo para
  no cambiar el esquema ni los atajos de la sesión. La fase que los corrige
  empieza reproduciéndolos.
- No se probó `hyprctl dispatch exit`. El fallo se infiere de `global` y
  `movecursor`, que usan la misma vía.
- Las superficies con profundidad C no tienen revisión de interacción.
- No se hicieron capturas ni revisión visual en ejecución de ninguna
  superficie; los juicios de composición salen de la geometría del código.
- La GPU sin suspender no es atribuible solo al sondeo.

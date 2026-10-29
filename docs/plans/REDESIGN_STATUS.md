# Estado del rediseño (rama `redesign/v2`)

Plan: rediseño QML y superficies nuevas. Worktree `~/Documentos/Cortetsu-redesign`.
Se fusiona en `main` al cerrar cada bloque; no se instala en la sesión real.

| Fase | Estado | Evidencia |
|---|---|---|
| 0.1 Skills Emil e Impeccable en `~/.claude/skills` | Hecho (antes de esta rama) | `ls ~/.claude/skills` |
| 0.2 `PRODUCT.md` y `DESIGN.md` | Hecho | raíz del repo |
| 0.3 `qml-design-lint.py` (informa, no bloquea) | Hecho | `scripts/features/test-qml-design-lint.py` |
| 1 Tokens de movimiento y primitivos | Hecho | `tst_MotionTokens.qml`; features 127 → 127 |
| 2.1 Selector de compartir pantalla | Hecho en código; pendiente físico | `docs/SCREENSHARE.md` |
| 2.2 Agente polkit | Hecho | `docs/POLKIT.md` |
| 2.3 Llavero y GPG | Hecho | `docs/SECRET-PROMPTS.md` |
| 2.4 Wi-Fi y Bluetooth | Hecho | `docs/SECRET-PROMPTS.md` |
| 2.5 Atajos | Hecho | `docs/UTILITY-SHORTCUTS.md` |
| 3.1 BottomHub, barra y popouts | Hecho en código; pendiente revisión en la sesión real | `tst_HubControls.qml`, `test-cortetsu-hub-controls-runtime.py`, lint `--strict` a 0 |
| 3.2 Launcher y Overview | Hecho en código; pendiente revisión en la sesión real | `tst_MotionTokens.qml`, `eval-retained-surfaces-host.py`, lint `--strict` a 0 |
| 3.3 Notificaciones, OSD y toasts | Hecho en código; pendiente revisión en la sesión real | `test-cortetsu-notice-cards-runtime.py`, lint `--strict` a 0 |
| 3.4 Dashboard | Hecho en código; pendiente revisión en la sesión real | `test-cortetsu-dashboard-dismiss-runtime.py`, lint `--strict` a 0 |
| 3.5 Ajustes | Hecho en código; pendiente revisión en la sesión real | `test-cortetsu-settings-runtime.py`, regla `type-field-font`, lint `--strict` a 0 |
| 3.6 Hardware Center | Hecho en código; pendiente revisión en la sesión real | `test-cortetsu-hardware-home-runtime.py`, `tests/qml/hardware`, lint `--strict` a 0 |
| 3.7 Lock | Hecho en código; pendiente prueba manual de desbloqueo en la sesión real | `test-cortetsu-lock-card-runtime.py`, `test-cortetsu-lock-runtime.py`, lint `--strict` a 0 |
| 3.8 Wallpaper, calendario, teclados, pantalla y sesión | Hecho en código; pendiente revisión en la sesión real | `test-cortetsu-calendar-keyboard-runtime.py`, `test-cortetsu-wallpaper-orbital-runtime.py`, `test-cortetsu-keyboards-runtime.py`, `test-cortetsu-session-runtime.py`, lint `--strict` a 0 |

## Línea base del linter (fase 0)

Reglas manuales, no estáticas: «una acción de teclado no anima» y «sin texto gris
sobre fondo de color».

```
qml-design-lint: 317 findings in 478 files
      2  motion-bounce  (bounce/elastic/overshoot easing)
      9  motion-ease-in  (ease-in curve (only valid on exits))
     28  motion-scale-from-zero  (scale starts below 0.95)
     37  motion-duration  (duration above 300 ms (500 ms for drawers))
     58  motion-layout-property  (animates width/height instead of opacity/scale/x/y)
     24  color-untinted-neutral  (pure black/grey/white without a washi/sumi tint)
      2  color-contrast  (token pair below WCAG AA)
     39  layout-nested-surface  (CortetsuSurface nested inside another CortetsuSurface)
      9  layout-small-target  (click target smaller than 36 px)
     24  token-literal-color  (colour literal outside CortetsuDesign)
     31  token-literal-radius  (radius literal outside CortetsuDesign)
     54  token-literal-duration  (duration literal outside CortetsuDesign)
by surface:
     80  base/modules/nexus
     31  base/modules/bar
     19  base/components/controls
     18  base/modules/dashboard
     16  base/components/containers
     16  base/modules/sidebar
     15  modules
     14  base/modules/lock
     12  base/modules/utilities
     11  modules/bar
      9  modules/clipboard
      8  base/components/filedialog
      7  components
      6  modules/overview
      5  modules/calendar
      5  modules/launcher
      5  modules/settings
      5  modules/utilities
      4  base/components/effects
      4  modules/background
      4  modules/hardware
      4  modules/notifications
      3  base/components/widgets
      2  base/modules/launcher
      2  base/modules/notifications
      2  modules/keyboards
      2  modules/osd
      2  services
      2  theme
      1  modules/display
      1  modules/lock
      1  modules/sidebar
      1  modules/wallpaper
```

## 3.1 BottomHub, barra y popouts

Lint de la superficie: 15 hallazgos → 0. Global: 317 → 284.

- Puntos de espacio de trabajo: objetivo de 28 → 36 px de alto y el hueco
  entre puntos también cambia de espacio (antes era zona muerta).
- Píldora de estado: elementos de 36 px; ya no toman el foco al cargar (REC
  aparecía con anillo de foco); la grabación respira en opacidad, no en escala.
- Insignia de avisos: círculo con una cifra, crece con «9+» (antes se salía).
- Indicador del botón activo: el ensanche por foco de teclado es inmediato.
- Popouts: el cuadrado de icono es `CortetsuIconBadge` (40 px, antes 36/42/44
  y superficies anidadas). Iconos, relleno de batería y perfil usan
  `colorIndicator` (H-37: `colorPrimary` quedaba por debajo de 3:1).
- Wi-Fi: el campo marca el foco y usa la fuente del shell (antes monoespaciada).
- Batería: se quita el detalle «Balanced» en inglés, que repetía el botón.
- Popouts anclados: tamaño sin animación (la posición usa el tamaño final);
  la transición de contenido dura `motionStandardMs` desde el arranque (antes
  0 hasta el primer desacople).
- Distribución de teclado: sin rebote ni escala; fundido de 120 ms.

Excepciones justificadas en el código: ancho de la píldora y de los puntos
activos (los vecinos se recolocan), morph de popouts desacoplados, salidas con
ease-in y la escala 0,975..1 del popup.

Capturas: `CORTETSU_RENDER_DIR=<dir> python3 scripts/features/test-cortetsu-hub-controls-runtime.py`.

## 3.2 Launcher y Overview

Lint de la superficie: 11 hallazgos → 0.

- Apertura con tecla: tokens nuevos `motionSummonMs` 140 y
  `motionSummonExitMs` 100 (`ui.toml` → generador del tema). Solo opacidad.
- Launcher real (`LauncherHost`): antes aparecía de golpe; ahora un fundido de
  140 ms al abrir. Al cerrar la ventana se desmapea, sin salida que animar.
- Overview: entrada de 180 → 140 ms y salida con ease-out en 100 ms (antes
  ease-in).
- Lista del launcher: el tamaño sigue a los resultados al instante; antes cada
  tecla animaba ancho y alto.
- Mensaje de vacío: solo opacidad (antes crecía desde 0,5).
- Carrusel de fondos: los vecinos a 0,95 (antes 0,5 y 0,8).
- Píldoras de Overview: radio `height / 2` en vez del literal 999.

## 3.3 Notificaciones, OSD y toasts

Lint de la superficie: 15 hallazgos → 0. Global: 284 → 261. Las superficies
rediseñadas se listan en `scripts/verification/redesigned-surfaces.txt`;
`build-regressions.sh` les pasa el lint con `--strict`.

- Notificación, toast, panel de utilidades y cabecera de avisos de la barra
  lateral usan `CortetsuIconBadge` (antes una `CortetsuSurface` anidada por
  tarjeta) con tono `colorIndicator`; bermellón si es urgente.
- La franja de urgencia es una línea de 2 px sin radio.
- Salidas de notificación, OSD y utilidades con ease-out (antes ease-in).
- Prueba nueva con datos extremos (resumen, app y cuerpo de 300 caracteres,
  toast sin icono): el texto se corta dentro de la tarjeta y una notificación
  cerrada se desvanece.
- Las tarjetas de `base/modules/utilities` y `base/modules/notifications` no
  las usa nada; se borran en el paso de restos de `base/`.

## 3.4 Dashboard

El lint ya estaba a 0 en `modules/dashboard`; el trabajo es de comportamiento y
de contenido (H-22).

- Hover en el borde superior: desde b18b607 la capa del Dashboard solo se
  mapea abierta. Al abrir por hover, el puntero pasaba a esa capa, la ventana
  drawers perdía el puntero y lo cerraba; la capa se desmapeaba y el borde lo
  volvía a abrir (bucle). Ahora `ScreenState.dashboardOpenedBy = "hover"` y la
  capa decide: salir del panel tras entrar lo cierra; el trayecto desde el
  borde no.
- Clic fuera del panel lo cierra (antes la capa a pantalla completa se comía
  el clic). Un clic en una zona vacía del panel no.
- Escape: foco exclusivo mientras está abierto (antes a demanda, Escape solo
  llegaba tras un clic) y atajo a nivel de ventana.
- `DashboardLayer.qml` separa el contenido del host para probarlo sin
  compositor.
- Texto: todo en español, sin relleno («Your desktop», «The shell is ready»,
  «Ambient conditions», «Desktop context», «Live context»).
- Estados: sin lectura del tiempo, «Tiempo no disponible» y no «--»; sin
  reproductor, «Nada en reproducción» y sin controles deshabilitados.
- Fila de sistema: `SystemFact` sin hover ni foco (antes `CortetsuListRow`,
  que parecía pulsable). Unidades con espacio (`57 °C`, `44 %`, `GiB`); CPU
  sin sensor lo dice en vez de `0°C`.
- Tamaño: 1180 × 620 cuando cabe; en una pantalla menor se ajusta.
- Etiquetas de sección en `colorOnSurfaceVariant` (4,5:1) en vez de primario.

## 3.5 Ajustes

Las páginas ya estaban migradas a `modules/settings/sections`;
`base/modules/nexus` no lo importa nada (80 hallazgos de lint muertos) y se
borra con los restos de `base/`.

- Lint de la superficie: 5 → 0. Franjas de selección sin radio, punto de
  aviso con `width / 2`, barras de señal en `colorIndicator` y la tarjeta de
  red seleccionada con `CortetsuIconBadge`.
- Campos de texto: `CortetsuSearchBar` y los campos de red, portapapeles,
  pantallas, polkit y secretos salían en monoespaciada (sin `font.family`).
  Ahora usan Rubik, y la regla nueva `type-field-font` lo exige en todo el
  árbol (0 hallazgos).

## 3.6 Hardware Center

La superficie ya venía del plan de elevación (veredicto, estados, unidades).
Lint 4 → 0:

- Marco con `radiusSurface` (antes 24 literal).
- Filas de procesos de 32 → 36 px (objetivo de clic).
- El giro de 900 ms del indicador de perfil queda permitido con motivo: es el
  periodo de un bucle, no una transición.
- Energía y Consumo tenían el mismo rayo; ahora `battery_charging_full` y
  `electric_meter`. Icono de cabecera en `colorIndicator`.

## 3.7 Lock

`LockSurface.qml` conserva teclas, foco, PAM y liberación sin cambios; lo visual
pasa a `LockCard.qml`, que solo lee el estado de PAM.

- Punto focal: la hora. Se quitan el título «Cortetsu», la segunda pista de
  Enter y el texto CAPS/NUM.
- Campo de contraseña de 52 px con borde índigo; bermellón y una sacudida de
  200 ms en cada rechazo (`flashMsg`), también con demasiados intentos.
- «Bloq Mayús» dentro del campo. Batería, red y teclado en una fila sin
  tarjetas.
- Emblema de 64 → 56 px. «Batería 86 %» con espacio.
- Sin probar: desbloqueo real con WlSessionLock; el emblema no se dibuja en
  offscreen.

## 3.8 Wallpaper, calendario, teclados, pantalla y sesión

Lint 9 → 0. Sesión ya estaba limpia.

- Calendario: el día, el chip y el panel de agenda dejan de ser superficies
  anidadas (rectángulos dentro del marco). Hoy es un anillo; el chip con foco,
  un borde índigo de 2 px. Radios `width / 2` y `height / 2`.
- Agenda vacía: «Día libre» y «No hay eventos»; fuera «Tómate el tiempo para ti».
- Pantalla: marco con `radiusSurface` (antes 30). Wallpaper: insignia de
  aplicado con `height / 2`.
- Teclados: la cuenta atrás de borrado de 4 s queda permitida con motivo.

Fallan también en la línea base y no son de esta fase: siete
`cortetsu/tests/test-*.py` (calendar-credentials, calendar-pomodoro-services,
gpu-passive, hardware-probe, notifications, pomodoro, runtime-contract), que
ejecutan con Python helpers de `bin/` que ahora son shell.


# Cortetsu 3.0, fase 4: islas, vista previa de ventanas, modo de edición y el cierre intermitente

Fecha: 2026-11-13. Rama `main`. HEAD inicial `91570fb3` (sin push, sin instalar).
Todo se probó en Hyprland anidado (`ws2_run.py --workspace 4`: el WS 3 tenía una
ventana del usuario) o en Quickshell offscreen. Nada se instaló ni se recargó en la
sesión real.

## 1. El cierre intermitente de Quickshell

### Qué pasaba

El gate `test-popout-cycles.py` pasó 12 de 13 veces; en la otra Quickshell cayó al
abrir un menú de bandeja. Se dijo que no había volcado. Sí lo había:
`systemd-coredump` guardó dos (`coredumps-20261113.txt`, 19:18:57 y 19:19:39, ambos
con `qs -p /tmp/cz30-cycles-*`, la prueba de ciclos). El informe del gestor de fallos
de Quickshell no apareció porque el arnés pone `XDG_CACHE_HOME` dentro del
directorio temporal de la prueba, que se borra al terminar.

Las dos pilas son idénticas, en el hilo de render por software:

```
QSGSoftwareRenderer::render
QSGSoftwareRenderableNode::renderNode
libQt6QuickShapes.so.6 +0x38269  = QQuickShapeSoftwareRenderNode::render
QQuickWindow::rendererInterface() const   <- SIGSEGV
```

El desensamblado de `QQuickShapeSoftwareRenderNode::render` (qt6-declarative
6.12.0-4.1) llama a `QQuickItem::window()` y luego a `rendererInterface()`: el nodo
de render del `Shape` lee su `QQuickItem` desde el hilo de render. Si el hilo de GUI
destruye o desparenta ese `Shape` mientras el hilo de render pinta el fotograma,
`window()` es nulo o memoria liberada. Es un defecto de Qt en el backend por
software; un nodo de render no debe tocar su item.

### Qué hacía Cortetsu para provocarlo

Cada popout se pinta sobre `CortetsuInkPanel`, que contiene un `Shape`. Al cerrar un
menú de bandeja con `popouts.hasCurrent = false` (Escape, Intro tras una acción,
Izquierda en el primer nivel, clic en una fila), `Wrapper.qml` vuelve a poner
`hasCurrent = true` para animar el cierre. `Content.qml` reaccionaba a ese cambio
reconstruyendo el menú (`menuReady`): destruía el menú que estaba en pantalla y
creaba otro. Es decir, cada cierre por teclado o acción destruía un `Shape` visible.

Esa ruta ya existía en `a352a342` (activar una fila o Escape dentro del menú);
`91570fb3` la hizo alcanzable desde el teclado del Hub y su gate la recorría unas 30
veces por ejecución.

### Experimento

Reproductor: 150 aperturas de menú con clic derecho real, cerrando con Escape y
reabriendo durante el cierre (`crash-matrix.jsonl`; el reproductor y el detector de
caídas conservan el informe con la pila, `crash-reproduced-stack.txt`).

| Configuración | Ejecuciones | Con caída |
| --- | --- | --- |
| `91570fb3`, software con render en hilo (como el gate) | 4 | 2 |
| `91570fb3`, software con `QSG_RENDER_LOOP=basic` | 3 | 0 |
| `91570fb3`, backend RHI (OpenGL sobre Mesa, como la sesión real) | 3 | 0 |
| Corrección, software con render en hilo | 6 | 0 |

La sesión real no fija `QT_QUICK_BACKEND` (usa RHI) y lleva
`QS_DISABLE_CRASH_HANDLER=1`; el nodo que falla no existe en RHI. El riesgo en
producción era bajo; en las pruebas, un fallo intermitente que podía ocultar
otros.

### Corrección

- `Content.qml`: el menú ya no se reconstruye. Un menú solo sobrevive a su popout
  mientras se desvanece; si se reabre entonces (`shouldBeActive` vuelve a ser
  cierto con el menú vivo), `CortetsuTrayMenu.reset()` lo devuelve al primer nivel
  con el foco en la primera fila, en el sitio. `BottomHub.openAttachedControlNow`
  hace lo mismo si se reabre durante la fase de cierre (120 ms).
- Un segundo disparador, previo y ajeno a la bandeja, apareció al conservar los
  informes: `test-bottomhub-hover-close-race` caía 2 de 5 veces, igual en
  `91570fb3` (un popout destruido justo al terminar su fundido). El `Shape` es el
  lavado radial de `CortetsuInkPanel`, la primitiva de todos los popouts; quitarlo
  cambiaría el material entero. Las pruebas anidadas pasan a renderizar como la
  sesión: RHI sobre Mesa (`MESA_ONLY` sigue sin cargar el driver NVIDIA);
  `CORTETSU_TEST_QUICK_BACKEND=software` devuelve el modo anterior. Con RHI: 6 de 6
  limpias en esa prueba y la batería anidada completa en verde. La regresión de
  Cortetsu (no reconstruir el menú en pantalla) se comprueba por su estado, no por
  la caída, así que no depende del backend.
- `launcher_harness.Session.crash_reports()` y `keep_crash_reports()`: el gestor de
  fallos reinicia el shell en el mismo PID, así que una prueba podía pasar a través
  de una caída. Ahora los informes se copian a `~/.local/state/cortetsu/test-crashes/`
  (o `CORTETSU_TEST_CRASH_DIR`) y los gates de la fase fallan si hay alguno.
- Regresión en `test-popout-cycles.py`: tras Escape desde un submenú, durante la fase
  de cierre el menú sigue en el nivel 2 (no se reconstruyó en pantalla); reabierto
  durante el cierre o el fundido, empieza en el nivel 1. Contra `HEAD` falla con
  "el menú se reconstruyó en pantalla al cerrarse"; con la corrección pasa.

### Segundo síntoma: "el menú no abrió"

En la matriz apareció un fallo distinto: un clic derecho que no abría nada. La traza
`qt.quick.pointer.localization` mostró que la pulsación llegó al borde izquierdo de
la isla de estado. La prueba leía la posición del icono de bandeja en cuanto el
proveedor SNI aparecía, antes de que el Hub terminara de colocar la isla (la `Grid`
mide en el siguiente pulido y, ahora, la isla se desliza). Es una carrera de la
prueba, no un clic perdido del producto: `launcher_harness.settled()` espera a que
la posición se mantenga 0,3 s.

### Riesgo residual

- El defecto de Qt sigue ahí: cualquier superficie que destruya un `Shape` visible
  con el backend por software y render en hilo puede caer. Ningún otro camino del
  Hub lo hace tras esta corrección (los popouts se destruyen al terminar su
  fundido, con opacidad 0); no se auditó el resto del shell.
- No se notificó a Qt; queda como siguiente paso.

## 2. Islas Premium sobria

- `CortetsuIsland` tiene estados: reposo; hover (el filo sube y el fondo se
  densifica); foco de teclado dentro (filo washi visible); `engaged`, cuando el
  popout o panel que abrió esa isla se ve (filo y lavado índigo, y el segmento se
  inclina 2 px hacia el popout). El material base es el del tema, sin animar: un
  cambio de tema lo repinta al instante.
- Elevación según el tema: Washi proyecta su sombra (en su tinta, no en negro),
  Ink y Kurogane no tienen; todas llevan una luz tenue en el filo superior.
- Núcleo, Aplicaciones y Sistema quedan a 12 px; bandeja y estado, un mismo
  grupo, a 4 px.
- Las islas que crecen o aparecen se deslizan a su sitio; un cambio de borde se
  coloca de golpe (`layoutAnchor`), también cuando la ventana recibe su tamaño
  nuevo un instante después.
- Los popouts crecen desde el punto que mira a su control
  (`HubAnchor.popoutOrigin`) y vuelven a él.
- Mientras un popout o panel del Hub está abierto, los tooltips del Hub se
  apartan: ninguno cae sobre el popout.
- Todo cambio es un `Behavior` corto sobre los tokens de movimiento: con
  movimiento reducido es instantáneo; en reposo no corre nada (sin
  `FrameAnimation`, temporizadores ni shaders). El único temporizador nuevo es el
  disparo único de 250 ms tras un cambio de borde.
- `HubFlow` cambiaba filas y columnas como dos enlaces; durante un instante ambos
  valían 1 y `Grid` avisaba en cada cambio de orientación. Corregido.

Capturas: `islands-three-themes.png` (Ink, Washi, Kurogane, render offscreen);
`popout-engaged-{ink,washi,kurogane}.png` (isla de estado engaged con Audio).

## 3. Vista previa de ventanas del App Rail

- Detenerse 450 ms sobre una app abierta, o la tecla Menú en su icono, abre una
  tarjeta por ventana: miniatura (un fotograma, `ScreencopyView` con
  `live: false`, el patrón del Overview) o, sin captura, el icono de la app;
  título y espacio de trabajo reales; cerrar; "traer a este espacio" si la
  ventana está en otro; nueva ventana y fijar en la cabecera.
- Clic o Intro van a esa ventana. Desde el teclado toma las teclas escritas en el
  icono (flechas, Tab, Inicio/Fin, Intro, Supr, Escape) y se cierra con un clic
  fuera; por hover nunca toma el teclado. El clic derecho sigue fijando.
- Es un popout adjunto más (`apppreview:<clave>`): hereda los ocho anclajes, el
  recorte a pantalla, el traspaso de hover y el focus grab. Los datos son el grupo
  vivo del carril; las tarjetas van por dirección de ventana: una ventana que se
  cierra se lleva su tarjeta, y la última cierra la vista previa.
- Ajustes → Hub: apertura por hover y miniaturas se pueden desactivar
  (`bottomHub.windowPreviews`, `bottomHub.windowThumbnails`; activadas por
  defecto; sin la clave se usa el defecto, no hay migración).

Limitaciones: la miniatura es un fotograma al abrir, no vídeo; en el arnés
anidado (render por software) las capturas funcionan, pero en la sesión real no
se midió qué GPU reserva los búferes. Una ventana en un espacio especial
(scratchpad) muestra "Especial" en vez de número.

Capturas: `preview-{ink,washi,kurogane}.png`.

## 4. Modo de edición

Ajustes → Hub → Mover el Hub, o `qs ipc call bottomHub editMode ""`. Capa Overlay
solo en el monitor editado, cargada solo mientras se edita. Las ocho posiciones son
marcas donde el Hub se apoyaría; el Hub es una forma que se arrastra; mientras se
mueve se ilumina el sitio al que se ajustaría (`HubAnchor.nearest`, tercios de la
pantalla) y al soltarlo se asienta ahí. Flechas, clic en una marca, Inicio
(predeterminada), Intro (guardar) y Escape (nada cambia). El Hub real solo se mueve
al guardar, con entrada propia para ese monitor. Un monitor que se desconecta
termina la edición. El esquema de preferencias no cambia: la posición por monitor
ya existía (`bottomHub.anchors`, fase 3) y se recupera por nombre de salida al
reconectar.

Capturas: `edit-mode-ink.png`, `edit-target-washi.png`;
`lateral-tray-{ink,washi,kurogane}.png` (Hub lateral tras guardar, con el menú de
bandeja y el aviso); `top-right-kurogane.png`.

## 5. Contrato de geometría y propiedad

- El Hub (`cortetsu-bottom-hub`, capa Top) solo toma el puntero en sus islas
  (máscara). Su ventana guarda en el lado interior el espacio del tooltip más grande
  (fijo, fuera de la máscara): crecer bajo un puntero quieto haría que Hyprland
  descartara el siguiente clic. En lateral eso son unos 365 px de franja
  transparente; se mantiene por esa razón y no captura nada.
- Los popouts viven en la ventana de cajones de su monitor, con `HubAnchor.popoutPosition`
  (recortado a 8 px del borde, en los ocho anclajes) y un único popout adjunto por
  pantalla. Tooltip y popout no se pisan: los tooltips del Hub se apartan mientras
  hay popout.
- El modo edición es otra capa (Overlay, teclado exclusivo) y solo existe mientras
  se edita.

## 6. Rendimiento (antes `91570fb3`, después este bloque)

Hyprland anidado, render por software, dos salidas, tres ventanas, mismo guion,
dos pasadas por árbol (`performance.jsonl`). Las latencias incluyen la llamada IPC
y el sondeo de `inspect`.

| Medida | Antes | Después |
| --- | --- | --- |
| PSS del shell en reposo | 300 / 303 MiB | 296 / 299 MiB |
| Hilos | 34 | 33 |
| Procesos hijo | dbus-monitor, nmcli, sleep, systemd-inhibit | los mismos |
| Instancias de Quickshell | 1 | 1 |
| CPU en reposo, 30 s | 0,08 / 0,10 s | 0,09 / 0,08 s |
| Apertura de popout (mediana) | 190 / 191 ms | 171 / 175 ms |
| CPU en 40 ciclos de popout | 3,22 / 3,15 s | 3,44 / 3,46 s |
| PSS tras 40 ciclos (delta) | 0 / −2 MiB | −1 / −1 MiB |
| Apertura de la vista previa (mediana) | — | 98 / 96 ms |
| 10 ciclos de vista previa con 3 miniaturas | — | +1 / +2 MiB, 1,17 s de CPU |
| NVIDIA `runtime_status` antes/después | suspended / suspended | suspended / suspended |
| Avisos QML de escena / caídas | 0 / 0 | 0 / 0 |

Los ciclos cuestan un 8 % más de CPU (las transiciones de las islas). En reposo no
hay diferencia medible. La NVIDIA no se despierta en el arnés, que fuerza Mesa: no
prueba el camino real con la RTX 3050.

## 7. QA

Ejecutado en `HEAD` final salvo indicación:

| Prueba | Resultado |
| --- | --- |
| `cortetsu test` (Rust, Go, Node, todas las suites QML) | PASS |
| `build-runtime.sh --stage` en raíces temporales + `build-regressions.sh` | PASS (la primera vez detectó que la isla animaba su material al cambiar de tema; corregido) |
| Cada commit del bloque prepara un runtime válido (`--stage`) | PASS, 5/5 |
| `qml-design-lint` en superficies rediseñadas | 0 hallazgos; total del repo igual que en `91570fb3` (27) |
| `test-popout-cycles.py` | 9/9 software, 4/4 RHI |
| `test-hub-previews-edit.py` | 3/3 software, 2/2 RHI |
| Reproductor de reapertura (150 ciclos) | 9/9 sin caída tras la corrección |
| `test-bottomhub-hover-close-race.py` | RHI 6/6; software 3/5 (fallo previo de Qt, igual en `91570fb3`) |
| `test-hub-anchors`, `test-hover-edges`, `test-launcher-dismiss`, `test-bottomhub-wayland-policy`, `test-lock-surface-nested` | PASS (RHI y software) |
| `test-cortetsu-settings-runtime.py` | PASS |
| `test-shell-boot-clean.py` | FAIL en todas las variantes, también en `91570fb3`: bucle `displayManager` en `CortetsuScreenState`; previo, fuera de alcance |
| Revisión externa Codex `gpt-6-luna` (solo lectura) | 1 hallazgo P2, falso al verificarlo (ver abajo) |

Revisión externa: Codex sostuvo que Intro en el icono podría activar la ventana
elegida y además la app. En `QQuickKeysAttached` la señal específica
(`returnPressed`) se emite antes que `pressed`, y `pressed` solo si la primera no
aceptó; `tst_HubIslands.test_open_preview_takes_the_keys_typed_on_the_icon` muestra
cada tecla entregada una sola vez. Además `activateItem` con ventanas abiertas solo
enfoca. Sin cambio.

Thermos, en línea y en secuencia (sin subagentes, por preferencia de Dilan; no son
independientes del autor): corrección sin P0/P1 (dos P3: texto de la fila "Mover el
Hub", corregido; el retardo del hover se conserva al cruzar controles, por diseño);
mantenibilidad: `BottomHub.qml` sigue por encima de mil líneas (deuda previa), un
literal duplicado sustituido por la constante.

NVIDIA durante las pruebas: 353 de 353 muestras `suspended` en seis arranques con
RHI; en la batería larga, 20 s `active` de 440 sin causa atribuible.

Pendiente de hardware real: sesión instalada, `eDP-1` + `HDMI-A-1`, escala no
entera física, aplicaciones reales de bandeja (Steam, Discord, nm-applet),
miniaturas con ventanas en la salida de la NVIDIA, lector de pantalla, coste de
energía real.

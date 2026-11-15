# Cortetsu 3.0, fase 4: certificación física en la sesión real

Fecha: 2026-11-14. Rama `main`. HEAD inicial `edd6633e`; HEAD final en el apartado 11.
Sin push ni release. No se tocaron kernel, controladores, paquetes, SVG del Evolving Mark
ni los temas. `.codebase-memory/` tenía cambios ajenos y sigue intacto.

Equipo: CachyOS (kernel 7.3.1), Hyprland 0.57.1 con configuración Lua, Quickshell 0.3.2,
Qt 6.12.0. `eDP-1` 1920×1080 a 144 Hz en la iGPU AMD (06:00.0); `HDMI-A-1` 1920×1080 a
60 Hz en la RTX 3050 (01:00.0), a la izquierda.

Veredicto: VERIFIED (apartado 14; el apartado 12 recoge el de la mañana).

## 1. Procedimiento y salvaguardas

- La sesión real se manejó con un puntero y un teclado virtuales propios (`vinput`,
  protocolos wlr de Hyprland). Antes de cada evento, el conductor comprobaba que el
  cursor siguiera donde lo dejó y que no hubiera cambiado ningún workspace; si no,
  abortaba.
- Teclas solo con una guarda: el modo edición (teclado exclusivo), o un efecto inocuo
  comprobado antes de enviar Escape. Se descubrió que `keyboardHeld` no basta (apartado 6).
- Capturas solo de workspaces sin ventanas ajenas, o con ventanas propias de prueba
  (`kitty --class cortetsu-qa`). A mitad de la mañana una captura recortada del Hub
  recogió por error una videollamada en curso de un tercero; se borró en el acto, se paró
  y se añadió la guarda. Las capturas de este directorio se revisaron una a una: no
  contienen nombres de redes, dispositivos, datos de cuentas ni ventanas de Dilan.
- Copia de las preferencias antes de empezar; el estado final se restauró (apartado 13).

## 2. Instalación y recarga suave

Gates previos sin tocar la sesión: `cortetsu test` y `build-regressions.sh` pasan; 8 de 8
pruebas anidadas pasan (RHI sobre Mesa). Después: `cortetsu install`, `verify` y
`cortetsu shell reload`. La sesión real sacó tres defectos que las pruebas anidadas no
podían ver, corregidos cada uno en su commit:

1. `7f6b62a9` `install` abortaba ("dotfiles digest mismatch"): `hypr-user.lua` se había
   editado dentro de la generación sellada (HDMI a 60 Hz). Dilan eligió conservar 60 Hz:
   el cambio pasa al repo y el archivo sellado vuelve a su contenido.
2. `4da2b15b` La recarga suave rechazaba la fase 4 (`Lean is not a type`). Quickshell
   conserva los tipos de un archivo entre recargas y un *inline component* nuevo en un
   archivo existente no existe hasta reiniciar. Reproducido 3 de 3 en aislamiento;
   `HubLean.qml`/`HubGlide.qml` pasan a archivos propios.
3. `a470cd61` `cortetsu shell reload` decía "completada" aunque Quickshell hubiera
   rechazado los archivos. Ahora espera "Configuration Loaded" o "Failed to load" en el
   journal de la unidad; prueba con control rojo.

## 3. Matriz física

PASS: comprobado en la sesión real. FAIL→FIX: defecto encontrado aquí, corregido y
probado (apartado 4). NOT_TESTED: no se ejecutó, con su motivo.

| Área | Caso | Resultado |
| --- | --- | --- |
| Temas | Ink, Washi y Kurogane aplicados desde Ajustes (clic real), perfiles por tema y esquema intactos al volver | PASS |
| Islas | reposo, hover, `engaged` con popout, lean y glide, en los tres temas | PASS |
| Islas | foco tras un clic de ratón: anillo, filo de isla y tooltip quedaban fijos | FAIL→FIX |
| Popouts de estado | audio, red, Bluetooth y batería por hover en los tres temas; siguen abiertos con el puntero dentro; cierran al salir y con clic fuera; nunca en el otro monitor | PASS |
| Movimiento reducido | activado desde Ajustes: cierre ~320 ms frente a ~400 ms, sin animación | PASS |
| Bandeja | ZapZap, Claude Desktop, Wallpaper Engine UX, Steam y Legcord: hover, clic derecho fija, clic fuera cierra | PASS |
| Bandeja | teclado en el menú (Izquierda cierra; Steam: fila "Salir de Steam" por clic) | PASS |
| Bandeja | la fila elegida con el teclado no se veía | FAIL→FIX |
| Bandeja | cambio de anclaje con el menú de Steam abierto: el menú se cierra, mismo PID | PASS |
| Bandeja | Legcord termina con su menú abierto: el menú se cierra, la bandeja pasa a 4, sin volcado | PASS |
| Vistas previas | barrido del carril sin abrir nada; permanencia 450 ms; ventana nueva y cerrada actualizan; salir cierra; clic en tarjeta enfoca | PASS |
| Vistas previas | Menú abre con teclado; flechas, Inicio, Intro; Supr pide cerrar (kitty confirma); Escape | PASS |
| Anclajes | los ocho por arrastre real en el modo edición e Intro; persistencia; HDMI intacto; menú de bandeja dentro de pantalla en cada uno | PASS |
| Modo edición | Escape cancela; Inicio vuelve a la posición común | PASS |
| Persistencia | `top-right` y Kurogane tras `cortetsu shell restart` | PASS |
| Auto-hide | el último píxel del borde no revelaba el Hub (solo 3 px más arriba) | FAIL→FIX |
| Auto-hide | cambiar el anclaje con el Hub oculto lo dejaba en el borde anterior | FAIL→FIX (nested) |
| Escala 1.25 | `eDP-1`: popouts y menú dentro de la pantalla lógica; arrastre a lateral y vuelta; revertida | PASS |
| Monitor | `HDMI-A-1` desactivado y reactivado: mismo PID, Hub solo en `eDP-1` y de vuelta en los dos, WS 11 regresa, sin volcados | PASS |
| Rendimiento | apartado 7 | PASS |
| Bloqueo | bloqueo y desbloqueo real | NOT_TESTED (Dilan: "ahora no") |
| Suspensión | suspender y reanudar | NOT_TESTED (requiere aprobación específica; no se pidió) |
| Lector de pantalla | | NOT_TESTED |

## 4. Defectos encontrados en vivo y corregidos

Cada uno con control rojo contra el código anterior y verde con el arreglo.

1. `3b08a1ed` + `73895399` **Auto-hide inalcanzable desde el borde** (regresión de
   `9335caf7`, fase 4). La ventana del Hub queda dentro de la zona exclusiva del borde de
   pantalla (1 px) y de su margen (2 px): un puntero lanzado al borde se para en el último
   píxel, fuera de la franja de revelado. `HubRevealEdges.qml` pone una tira de 3 px en el
   propio borde, que ignora las zonas; su hover cuenta como el del Hub, también con el
   puntero quieto. Solo existe con auto-hide (cada ventana de capa cuesta un contexto GL).
   Dos defectos más del mismo cruce, vistos en el arnés: con auto-hide, un cambio de
   anclaje dejaba el Hub en el borde viejo (una capa mapeada que no pinta no envía los
   anclajes nuevos: se desmapea un ciclo), y una tira sustituida bajo el puntero dejaba el
   hover contado para siempre. Prueba: `test-hub-autohide-edge.py` (anidado, cuatro
   bordes).
2. `61c47e9a` **Fila del menú de bandeja invisible al teclado** (fase 4, `91570fb3`). El
   resaltado seguía `activeFocus`, que la ventana del menú nunca tiene porque el Hub se
   queda el teclado. Ahora se marca por índice mientras el Hub retiene el teclado.
   `test-popout-cycles.py` compara la fila con foco y la que dibuja el contorno
   (`inspect`: `focusedRow`, `markedRow`): rojo con 2 y −1.
3. `2ac0d34d` **Foco residual tras un clic** (fase 3, `9fc1dd5f`). El anillo, el filo de
   la isla y el tooltip de foco (el de red, con SSID y señal) seguían visibles con el
   puntero lejos hasta que otra ventana tomaba el teclado. Semántica *focus-visible*: la
   pulsación sigue dando el foco, pero solo lo marca el teclado.
   `test-hub-button-focus-runtime.py` (13 comprobaciones). `58ec59b2` ajusta el contrato
   textual de `test-native-bottom-hub.py`.

## 5. Bandeja con aplicaciones reales

- Iconos: ZapZap (pixmap propio), Claude Desktop, Wallpaper Engine UX (Electron), Steam y
  Legcord. Menús de 113 a 475 px; ninguno tiene submenús, así que la navegación de varios
  niveles sigue cubierta solo por el proveedor SNI de prueba del gate anidado.
- El incidente de Qt (Shape por software) no reapareció: 0 volcados de Quickshell en el
  día, también al cerrar Legcord con su menú abierto. La sesión usa RHI.
- Legcord deja un SIGTRAP propio al arrancar (`ThreadPoolForeg`, `electron44`), hoy a las
  11:03:34 y ayer a las 22:34:43: es un fallo de la app.

## 6. Hallazgos que quedan abiertos

- **`follow_mouse` y el teclado del Hub.** Con un popout abierto desde el teclado, mover el
  puntero sobre él con una ventana debajo da el teclado a esa ventana (el popout no lo
  pide); el shell sigue creyendo `keyboardHeld`. Las flechas van a la ventana. Es
  interacción con el compositor; arreglarlo pediría que el popout tome el teclado, lo que
  la fase 4 descartó a propósito.
- Con escala 1.25, la primera apertura de cada popout tras el cambio tardó ~605 ms; las
  siguientes, 167–179 ms.
- `areapicker/Picker.qml:102` lanza un TypeError al reconfigurar monitores (ajeno a la fase).
- Al cerrarse un Hyprland anidado, su Xwayland `:1` deja un SIGABRT: artefacto del arnés.
- Qt 6.12: el defecto de `QQuickShapeSoftwareRenderNode` sigue en Qt; solo afecta al
  backend por software.

## 7. Rendimiento

En la sesión real, Kurogane, `eDP-1` (`metrics.jsonl`, bloque `perf`):

| Medida | Valor |
| --- | --- |
| 40 popouts por hover | apertura p50 181 ms, p95 186 ms; cierre p50 401 ms (240 ms de espera más el fundido) |
| 20 vistas previas | apertura p50 534 ms (450 ms de permanencia); cierre p50 402 ms |
| 16 anclajes por IPC | p50 77 ms |
| CPU del shell en reposo (60 s) | 0,59 % |
| PSS | 283–333 MiB en el proceso largo; 508 MiB a los 30 s de un arranque limpio |
| Hilos | 98 → 122 y estables tras 15 ciclos del modo edición y 4 de Ajustes (un conjunto por ventana) |
| Zombis | 0 |

Después de los arreglos (generación `20261114-114246-2201182`, mismo guion, mismas
ventanas de prueba): 40 popouts p50 179 ms y 5,07 s de CPU (antes 181 ms y 5,13 s); 20
vistas previas p50 530 ms; anclajes p50 74 ms; reposo 0,19 % de CPU; 118 hilos; 0 zombis;
el shell sigue solo en `renderD129`. Sin coste medible.

PSS: el proceso de esta mañana (2 h 30 de vida) marcaba 283–333 MiB con 43 MiB en swap;
uno recién arrancado marca ~500 MiB (420 MiB anónimos) a los 30 s. No hay medida en vivo de
un arranque limpio anterior a la fase 4 con la que comparar: queda sin atribuir.

Las cifras anidadas de ayer (software o Mesa, una salida) no son comparables con estas.

## 8. NVIDIA

- La NVIDIA estuvo `active` toda la mañana porque el HDMI está conectado desde las 07:44.
- El shell solo abre `/dev/dri/renderD129` (AMD) durante popouts, vistas previas y
  anclajes (229 muestras de `/proc/<pid>/fd`); nunca un nodo NVIDIA. Las bibliotecas de
  NVIDIA aparecen en su mapa por la enumeración de glvnd, sin contexto en la GPU.
  `nvidia-smi pmon` solo ve a Hyprland (24–32 % SM), que saca la imagen al HDMI.
- Los 20 s de actividad del informe anterior coinciden con el arranque de Legcord y su
  SIGTRAP (22:34:35–22:34:43), no con las vistas previas.

## 9. Volcados

`coredumps-20261114.txt`. Ninguno de Quickshell en la sesión real. Clasificados: Legcord
(fallo de la app, 2), Xwayland `:1` de Hyprland anidados al cerrarse (arnés). Los 11 de
`quickshell` del 13 de noviembre ya estaban clasificados en la evidencia anterior.

## 10. Rollback

- Código: `git revert` de los commits de este bloque en orden inverso.
- Instalación: `cortetsu rollback` vuelve a la generación anterior (reinicia `power-auto`
  si está activo). Tras volver, `cortetsu shell restart`, no recarga suave: una recarga
  hacia atrás choca con los tipos que Quickshell conserva.
- La última generación probada en vivo antes de este bloque sigue en disco
  (`20261112-123052-132232`).
- Auto-hide: si la tira molestara, se quita apagando "Ocultar automáticamente" en Ajustes
  → Hub.

## 11. Gates y commits

Sobre `58ec59b2`, el HEAD instalado: `cortetsu test` (64 s), `build-runtime.sh` en un
directorio temporal y `build-regressions.sh` sobre él; recarga suave de la generación viva a
la nueva en un Hyprland anidado (`loaded`, sin errores); nueve pruebas anidadas:
`test-popout-cycles`, `test-hub-previews-edit`, `test-hub-anchors`, `test-hub-autohide-edge`,
`test-bottomhub-hover-close-race`, `test-hover-edges`, `test-launcher-dismiss`,
`test-bottomhub-wayland-policy`, `test-lock-surface-nested`. Todo pasa.

Instalación final: generación `20261114-114246-2201182`, `cortetsu verify` correcto,
recarga suave confirmada en el mismo proceso. Verificación en vivo de los arreglos
(`postfix-live.png`, `metrics.jsonl`): tras un clic en Red no queda tooltip ni anillo; en el
menú de bandeja Abajo marca la fila (`focusedRow` = `markedRow` = 2); con auto-hide el Hub
se revela desde las filas 1079 a 1076 y se queda con el puntero quieto; la tira
`cortetsu-hub-reveal` ocupa y 1077–1079 y desaparece al apagar el auto-hide.

Commits (locales, sin push): `7f6b62a9`, `4da2b15b`, `a470cd61` (instalación y recarga),
`3b08a1ed`, `61c47e9a`, `2ac0d34d`, `73895399`, `58ec59b2` (defectos de la sesión real).

Revisión: Thermos en línea y en secuencia, sin subagentes; no es independiente del autor.
Corrección: encontró la tira sustituida bajo el puntero (`73895399`) y el contrato textual
roto por `2ac0d34d` (`58ec59b2`). Mantenibilidad: las tiras salen de `BottomHub.qml` a su
archivo; `BottomHub.qml` queda en 1185 líneas (22 más que al empezar). Sin revisión externa.

## 12. Veredicto de la mañana (cerrado en el apartado 14)

**DONE_WITH_CONCERNS.** La matriz física pasa en los tres temas, los ocho anclajes, la
bandeja con cinco aplicaciones reales, las vistas previas, la escala 1.25, la pérdida de
monitor y el reinicio. Los defectos que solo salían en la sesión real (apartados 2 y 4) están corregidos,
con prueba y verificados en vivo. No sube a VERIFIED por tres huecos con evidencia
insuficiente:

1. Ninguna aplicación instalada tiene menús de bandeja de varios niveles; esa ruta solo la
   cubre el proveedor de prueba del gate.
2. PSS de ~500 MiB en un arranque limpio sin línea base comparable.
3. Suspensión y reanudación no ejecutadas (requieren aprobación específica).

## 13. Estado final de la sesión

Generación `20261114-114246-2201182` adoptada en el PID 2093398 (0 reinicios). Kurogane,
Hub oculto (como estaba), anclaje común sin entradas por monitor, auto-hide apagado, `eDP-1`
a escala 1 y 144 Hz, `HDMI-A-1` a 60 Hz, volumen al 70 %, sin ventanas ni unidades de
prueba. `preferences.json` igual a la copia inicial salvo valores por defecto escritos
explícitamente. `scheme.json`: al aplicar Washi (esquema inteligente activo) su perfil pasó
de la paleta propia del tema a una dinámica del fondo; no había copia de hoy, así que no se
editó a mano.

## Capturas

`rest-hub-kurogane.png` (reposo), `popout-battery-three-themes.png` (Kurogane, Ink, Washi;
se ve el anillo de foco residual del audio antes del arreglo), `tray-menus.png` (ZapZap y
Wallpaper Engine UX en Kurogane y Washi), `preview-kurogane.png` (ventanas de prueba),
`anchors-kurogane.png` (seis anclajes con su menú de bandeja), `scale-125.png`,
`restart-top-right.png` (anclaje tras reinicio), `postfix-live.png` (sin foco residual y fila
marcada en el menú, tras instalar los arreglos).

## 14. Cierre de los tres huecos (2026-11-14, tarde y noche)

Veredicto final: **VERIFIED**. Los tres huecos del apartado 12 quedan cerrados con
evidencia y salieron dos defectos más, corregidos con prueba e instalados
(generación `20261114-222216-44629`). Entre medias el equipo se apagó (16:49) y arrancó
(22:09); el shell arrancado en limpio también se probó.

### Hueco 1: menús de bandeja de varios niveles

Ninguna app instalada los tiene e instalar `nm-applet` habría tocado paquetes del
sistema. Se usó un indicador real con `libayatana-appindicator` y `libdbusmenu-gtk`, la
pila de `nm-applet` y `blueman` (`scripts/integration/ayatana-indicator-fixture.py`): tres
niveles, fila deshabilitada, separador, radio, casilla, filas que cambian en vivo. No es
una app de terceros; la biblioteca del lado de la app sí es la misma.

En la sesión real:

| Caso | Resultado |
| --- | --- |
| Abajo salta la fila deshabilitada y el separador (fila 3); Derecha abre el nivel 2 y el 3; Izquierda vuelve; Intro en la hoja del nivel 3 llega a la app | PASS |
| Clic en "Red" abre el nivel 2; clic en "VPN" llega a la app y cierra | PASS |
| Una fila añadida al nivel abierto y otra renombrada, con el menú abierto | PASS |
| Casilla y radio: antes sin estado visible | FAIL→FIX (`e8165147`) |
| Casilla de desactivada a activada y radio de A a B, comprobados en el menú siguiente | PASS |
| La app se cierra con el nivel 3 abierto: el popout quedaba abierto, vacío y con el teclado | FAIL→FIX (`462a59c2`) |
| Tras el arreglo, dos veces con el shell recién arrancado: menú cerrado, teclado e isla libres, mismo PID, sin volcados | PASS |

`462a59c2`: el runtime tiene dos copias de `SystemTrayIdentity.js`; la isla de la bandeja
y los menús importaban cada una la suya, con dos contadores `tray-instance-N`. Como los
menús se crean con el primer popout, una app que entraba y salía antes desalineaba las
claves. `test-tray-relaunch.py` lo reproduce (rojo con dos rutas, verde con una).
`e8165147`: el menú no leía `buttonType`/`checkState`; el proveedor de prueba del gate
termina ahora con una casilla y un radio.

### Hueco 2: memoria de un arranque limpio

A/B en el mismo entorno (Hyprland anidado, dos salidas, arranque limpio, sin
interacción), tres ejecuciones alternas de cada uno. A: `a352a342`, último commit antes
de la fase 4 (sin el IPC `editMode`, comprobado). B: la generación instalada.

| | PSS a 30 s | a 120 s | anónima | hilos |
| --- | --- | --- | --- | --- |
| Antes de la fase 4 | 417–423 MiB | 416–422 MiB | 380–385 MiB | 106–107 |
| Fase 4 | 420–422 MiB | 417–421 MiB | 381–385 MiB | 106–107 |

La fase 4 no cambia la memoria de arranque. Los ~500 MiB del shell real recién arrancado
son del entorno (fondos, bandeja y monitores reales), y bajan con las horas por swap.

### Hueco 3: suspensión, reanudación y bloqueo

Con aprobación de Dilan y el HDMI desconectado: s2idle de 22:24:48 a 22:25:32. El bloqueo
antes de suspender funcionó. Hubo un intento de contraseña rechazado y luego el desbloqueo
correcto con PAM. Tras volver:
- mismo PID (2641) y 0 reinicios;
- 0 volcados y ningún aviso en el journal del shell;
- Hub sin popouts ni teclado retenido;
- bandeja intacta y un popout abierto y cerrado bien.

La NVIDIA quedó `active` un momento tras reanudar y volvió sola a `suspended`. El shell no
tiene ningún nodo NVIDIA abierto; solo Hyprland y Legcord.

Riesgos que siguen: `follow_mouse` (apartado 6); el perfil de Washi en `scheme.json`
(apartado 13); con el HDMI conectado, la reanudación no se probó esta vez (memoria: puede
quedarse congelado y se recupera con un ciclo DPMS).

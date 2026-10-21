# PR #51 · QA física (multimonitor y suspensión con Pomodoro)

Fecha: 2026-10-20, 20:30–22:05 (CST). Rama `fix/stabilization-surfaces-calendar-pomodoro`, HEAD probado `d6769c3`.
Evidencia: `evidence/physical/`. Driver: `tools/physical_qa.py`.

| Prueba | Resultado |
|---|---|
| Multimonitor físico | **`PHYSICAL_MULTIMONITOR_PASS`** |
| Suspensión con Pomodoro | **`PHYSICAL_SUSPEND_POMODORO_FAIL`**: Pomodoro cumplió los 10 puntos; falló «ambas pantallas vuelven a funcionar» (el HDMI quedó congelado tras reanudar, también con el shell instalado; §4.4) |

## 1. Entorno

| | |
|---|---|
| Monitores físicos | `eDP-1` (BOE 0x0CFD, 1920×1080, x=1920, AMD 06:00.0) · `HDMI-A-1` (1920×1080, x=0, NVIDIA 01:00.0) |
| Versiones | Hyprland 0.56.2 · Quickshell 0.3.2 (4f508be) · Qt 6.12.0 · Python 3.14.8 · systemd 262 · kernel 7.2.10-1-cachyos · nvidia-utils 615.78.08 (`evidence/physical/versions.txt`) |
| Suspensión | `s2idle`; sin root, sin despertar por RTC; inhibidores solo de tipo *delay* |
| GPU | ambas `active` antes y después (el HDMI depende de la NVIDIA; no se forzó su suspensión ni se usó `prime-run`) |
| CI del HEAD | verde (13 jobs) |

Instalado antes y después: sistema `20261017-220915-104304`, shell `20261017-160736-98327` (revisión `71e13b4`, anterior a
la PR), helper `cortetsu-pomodoro` sha256 `c2661198…`.

## 2. Candidata y activación temporal

- Construida con `build-runtime.sh` y `CORTETSU_DATA_ROOT`/`CORTETSU_RUNTIME_ROOT` en un directorio temporal: generación
  `20261020-203033-52095`, `repositoryRevision` = `d6769c3`; todos los gates del build en verde; los enlaces reales
  (`current`, `previous`, `legacy-previous`) no se tocaron.
- El QML ejecuta `~/.local/bin/cortetsu-pomodoro` por ruta absoluta (`Pomodoro.qml`), así que el helper se cambió en su
  sitio durante la ventana, con copia previa. Es el único helper que la PR cambia con efecto (el de `cortetsu-startup`
  es metadata).
- Activación: `systemctl --user stop cortetsu-shell` y la candidata como unidad transitoria `cortetsu-qa-shell`
  (`qs -p <candidata> -n`). Nunca hubo dos shells: comprobado con `owners.sh` (un `qs`, un daemon, cgroup de la unidad
  QA, sha256 del helper = rama `8b2d1d73…`, daemon con `timerfd`).
- Restauración probada antes de la QA: vuelta al shell instalado, enlaces idénticos, `system verify` PASS, y
  reactivación.
- Límite de este método: `SUPER+V` y `cortetsu shell reload|ipc` buscan el `MainPID` de `cortetsu-shell.service`, así
  que no alcanzan a la candidata. El Portapapeles se probó por IPC directo (`qs ipc -p`) y la recarga con
  `qs ipc --pid … call cortetsu-shell reload`.

## 3. Prueba A · Multimonitor

Teclas reales por uinput (`ydotoold` propio). El teclado se observa tecleando `a` y mirando si llega a una Kitty
sumidero de ese monitor (WS 10 en eDP-1, WS 20 en HDMI-A-1, ambos vacíos antes); el driver se niega a teclear si la
ventana activa no es un sumidero. Las ventanas de diagnóstico (Kitty `Cortetsu-Physical-QA`, 6 pestañas) estuvieron
en WS 2.

| Escenario | Comprobaciones | Resultado |
|---|---|---|
| A1 Calendario: SUPER+H en un monitor, SUPER+SHIFT+C en el otro, Escape; en ambos sentidos | 16 | 16 PASS |
| A2 Las 7 retenidas × 6 en el otro monitor, en ambos sentidos | 84 | 84 PASS |
| A2 Hardware ↔ los 6 transitorios en el otro monitor | 24 | 24 PASS |
| A2 OSD coexiste con Hardware; Hardware se mueve de monitor y se lleva el teclado | 8 | 8 PASS |
| A3 Hardware → Sidebar por IPC, SUPER+N y `bottomHub notifications` (×3 por ruta y monitor) | 6 | 6 PASS |
| A3 **Wallpaper → Sidebar (O-3), 20 repeticiones por ruta y monitor = 120 transiciones** | 6 | 6 PASS, 0 carreras |
| A3 cierre por la misma ruta y teclado de vuelta | 24 | 24 PASS |
| A4 Pantalla completa (modo 2) en cada monitor: Sidebar no abre por las 3 rutas, OSD guardado, SUPER+H sí abre, cerrar sí funciona, OSD coexiste con Calendario, teclado en el cliente | 28 | 28 PASS |
| Estado final, tras A1 y tras A4: todo cerrado en ambas pantallas | 2 | 2 PASS |
| **Total** | **198** | **198 PASS** |

O-1, O-2 y O-3 no aparecieron en el hardware real.

### Botón visual de Bottom Hub

Con Hardware o Wallpaper abiertos, el primer clic en la campana cae en el scrim de `RetainedSurfacesHost` (capa
Overlay, máscara completa) y cierra la superficie sin abrir el Sidebar (20/20, `bh.json`). Un segundo clic la abre
(2/2). Sin superficie abierta, el primer clic la abre. El shell instalado, sin la PR, hace lo mismo: el host no cambia
en la PR. Es la diferencia de diseño entre el botón (detrás del scrim modal) y las rutas de atajo/IPC (un paso).
No bloquea la PR; si se quiere un solo clic, el scrim tendría que dejar pasar la franja de Bottom Hub.

### Incidencias del driver (no de la PR)

Tres primeras pasadas inválidas, conservadas para trazabilidad (`a1-driver-try1.jsonl`; las filas `a4` de
`a2-a3-results.jsonl`):
1. Enfocar un monitor por dispatch no movía el foco de ventana en esta sesión: el `a` iba al sumidero del otro monitor.
   Ahora el driver enfoca el sumidero.
2. `hl.dsp.window.fullscreen({ mode = "fullscreen" })` desde una ventana maximizada (los sumideros nacen en modo 1)
   no alterna como se esperaba, y el driver aceptaba modo 1 como «pantalla completa». La guarda lee `fullscreen > 1`.
   Ahora el driver exige modo 2.
3. Durante la primera pasada Dilan estaba usando el equipo; se paró y se pidió la máquina libre.

## 4. Prueba B · Suspensión con Pomodoro

Estado de prueba en el archivo real (`pomodoro.json`, 1 min por fase), escrito bajo el lock del helper, con la sesión
personal guardada antes (FOCUS, 36 sesiones). Registro cada 2 s (`pomodoro-state.log`), inotify del directorio de
estado (`pomodoro-inotify.log`) y journal persistente. El registrador no abre el archivo de avisos (usa `stat`), así
que un `OPEN/ACCESS` de `pomodoro-notification.json` tras su `MOVED_TO` es la lectura de Quickshell.

### 4.1 Control con la sesión desbloqueada

Fin de FOCUS a las 21:08:22.266; aviso escrito a las .278, leído por Quickshell a las .285. Capturas: un toast
«Sesión de concentración completada» por pantalla, sin duplicados.

### 4.2 Suspensiones

| | Antes | Suspensión | Resultado |
|---|---|---|---|
| Intento 1 | FOCUS, vence 21:22:01, 7 sesiones | 21:21:04 → 21:21:16 | Despertó solo a los 12 s (IRQ 9, ACPI/EC; «Unexpected lid state reported by firmware»). La fase venció despierto, a su hora: 7→8, `LONG_BREAK`, un aviso. **No cuenta**: no venció durante la suspensión |
| Intento 2 (autorizado por Dilan) | FOCUS, vence 21:23:30, 8 sesiones | 21:22:32 → 21:53:48 (31 min) | ver 4.3 |

### 4.3 Tras reanudar (intento 2)

| Punto | Resultado |
|---|---|
| 1 Sesión recuperada (bloqueo de la candidata, desbloqueo) | PASS |
| 2 Ambas pantallas funcionan | **FAIL**: HDMI-A-1 congelado (§4.4) |
| 3 Hyprland reconoce los monitores | PASS: mismos dos, sin `monitoradded/removed` en ninguna suspensión |
| 4 Cortetsu sigue funcionando | PASS: IPC, superficies y recarga |
| 5 Pomodoro detecta la fase vencida durante la suspensión | PASS: el daemon la cerró a las 21:53:47.523, al reanudar (`timerfd` sobre `CLOCK_REALTIME`), sin esperar a sondeos |
| 6 Transición y contador | PASS: 8→9, `BREAK` (9 no es múltiplo de 4), nuevo fin a +60 s |
| 7 Aviso sin duplicados | escrito: 1 (21:53:47.529) · consumido por Quickshell: 1 (lectura a las .531) · visible: no verificado (el toast dura 5 s y estaba la pantalla de bloqueo) |
| 8 Recarga controlada no repite el aviso | PASS: tras `cortetsu-shell reload`, Quickshell releyó el archivo y no hubo toast (capturas); el aviso anterior se mostró en el control (4.1) |
| 9 Procesos y errores | PASS: un `qs`, un daemon (la recarga sustituye al daemon, no lo duplica). Avisos nuevos: 5 de `services/Time.qml` («Unable to assign [undefined]») durante la recarga suave, archivo que la PR no toca; `textinput` ya conocidos de F0 |
| 10 Estado persistente coherente | PASS: `pomodoro.json` y el aviso coinciden con el registro y el inotify |

Pomodoro sobrevivió a la suspensión real.

### 4.4 HDMI congelado tras reanudar

Tras el intento 2, `grim -o HDMI-A-1` se colgaba (eDP-1 funcionaba), y Dilan confirmó que el HDMI estaba congelado.
Hyprland lo seguía dando activo y con DPMS encendido. Ocurrió igual con el shell instalado, restaurado después, y el
journal solo muestra el aviso habitual de nvidia-modeset sobre el reloj de píxel HDMI. Un ciclo
`hl.dsp.dpms({ action = "off" })` / `"on"` lo recuperó (grim y la imagen, confirmado por Dilan). El QML no gestiona
salidas DRM: es un fallo de la plataforma (Hyprland 0.56.2 / NVIDIA 615.78 tras `s2idle`), no de la PR. No se sabe si
el intento 1 lo produjo también.

## 5. Restauración

- Candidata parada; helper instalado devuelto (sha256 `c2661198…`); `cortetsu-shell.service` activo con un `qs` y un
  daemon; `current`, `previous` y `legacy-previous` idénticos a la copia; generaciones intactas; `system verify` PASS;
  `cortetsu-power-auto` y `cortetsu-wallpaper-color` activos.
- Pomodoro personal: se restauró la copia de las 21:07 (FOCUS, 36 sesiones). Esa fase había vencido, así que el daemon
  instalado la cerró al arrancar (36→37, BREAK). El ciclo personal quedó en pausa de 21:07 a 21:59. El estado final de
  la prueba se guardó en `evidence/physical/test-final-*`.
- Cerradas las ventanas de prueba (Kitty QA y sumideros); paradas las unidades `cortetsu-qa-*`; borrado el socket de
  `ydotoold`. Monitores: eDP-1 → WS 1 (enfocado), HDMI-A-1 → WS 11, como al empezar.
- Cambios de workspace inesperados: ninguno atribuible al shell. Los únicos fuera del driver fueron de Dilan
  (21:20:49 y 21:21:53–21:22:09, incluido mover dos Kitty a WS 1, `hypr-events-filtered.log`); la Kitty QA se devolvió
  a WS 2.

## 6. Limitaciones

- La visibilidad del aviso tras la suspensión no es observable con bloqueo de pantalla y toasts de 5 s; se verificó
  escritura y consumo, y la visibilidad en el control desbloqueado.
- `SUPER+V` y `cortetsu shell reload` no se probaron contra la candidata (§2).
- Sin despertar por RTC; el despertar fue manual.
- Una única suspensión válida.

## 7. ¿Bloquea la fusión?

Nada de la PR. Pendiente de decidir aparte: el congelado del HDMI tras `s2idle` (plataforma) y el clic de Bottom Hub
detrás del scrim (diseño previo).

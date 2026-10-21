# Cortetsu 2.0 · Estabilización de superficies, Calendario y Pomodoro

Fecha: 2026-10-20. Rama `fix/stabilization-surfaces-calendar-pomodoro` sobre `main` = `3c432ea` (F1a, #50). Versiones:
Hyprland 0.56.2 · Quickshell 0.3.2 (4f508be) · Qt 6.12.0 · Python 3.14.8. Generación instalada (sin tocar):
`20261017-160736-98327`. F1b no se ha iniciado.

**Veredicto: `STABILIZATION_WITH_CONCERNS`** (§11, actualizado en §12).

## 1. Causas raíz confirmadas

### O-1 · Calendario multimonitor

`CalendarController.open` cerraba los demás paneles solo en el estado de su pantalla
(`OverlayPolicy.closeOtherPanels(state)`); los otros controladores retenidos recorrían todas las pantallas. Abrir el
Calendario en la pantalla B dejaba abierta la superficie retenida de la pantalla A, con su teclado exclusivo. El mismo
defecto, con otra forma, existía en todas las rutas que no pasaban por los controladores: los atajos de los paneles
transitorios (`Shortcuts.toggleExclusive` cerraba solo en su pantalla), los enlaces de Ajustes (`openSurface` cerraba
las retenidas de su pantalla), la tarjeta «Hoy» del Dashboard (abría el Calendario sin cerrar nada) y los enlaces del
OSD y de Utilidades. Reproducción en `main`: los 5 FAIL «X then calendar, other screen» (§6).

### O-2 · Rutas de transición distintas para la misma operación

Había cuatro implementaciones de «abrir la barra lateral», cada una con su regla:

| Ruta | `main` |
|---|---|
| `drawers toggle sidebar` (IPC) | `setFlag("sidebar", …)` sin política: se apilaba sobre Hardware y no tenía guarda de pantalla completa |
| SUPER+N (`cortetsu:sidebar`) | cerraba los exclusivos solo en su pantalla, con guarda de pantalla completa que también impedía cerrar |
| `bottomHub notifications` y botón de Bottom Hub | cerraba en todas las pantallas, sin guarda |
| enlace de Utilidades | escribía `sidebar = true` sin cerrar nada |

`drawers toggle osd|<retenida>` tampoco pasaba por la política.

### O-3 · Carrera Wallpaper/Sidebar

Reproducida con instrumentación (4 de 15 repeticiones en `main`; `evidence/o3-diagnosis.md`): en las 4, y solo en
ellas, el `HyprlandFocusGrab` de la ventana de cajones se limpió 20–40 ms después de armarse y su `onCleared` cerró la
barra lateral. Mecanismo, leído en el código de Hyprland 0.56.2 y Quickshell 4f508be:

1. Al cerrarse el Wallpaper Manager (por la política o por su reacción a un panel competidor), la ventana de cajones
   pasa de `keyboardFocus: OnDemand` (el Wallpaper Manager es dueño de teclado) a `None`.
2. En la misma transición la barra lateral pide el grab, que se crea al momento; el cambio de interactividad de la
   capa se envía en el siguiente `commit` de la superficie.
3. Si el grab ya enfocó la ventana de cajones cuando llega ese `commit`, Hyprland ejecuta
   `LayerSurface::onCommit → refocusLastWindow`, que reenfoca por el puntero y, como la superficie bajo el puntero no
   pertenece al grab, lo termina (`setGrab(nullptr)` → `cleared`).

El resultado dependía del orden entre dos peticiones Wayland del mismo cliente. SUPER+N sobre Hardware en la misma
pantalla sufría la misma carrera (en `main`: ambas cerradas). Además, `focusable` y `WlrLayershell.keyboardFocus`
eran dos bindings que escriben la misma propiedad de Quickshell (`setFocusable` llama a `setKeyboardFocus`): el modo
final dependía del orden de evaluación.

### Superficies retenidas instanciadas dos veces

`compose-panels.py` inyectaba en la ventana de cajones una copia oculta (`visible: false`) de los seis wrappers que
`RetainedSurfacesHost` ya aloja. Las copias cargaban su contenido y ejecutaban sus efectos: dos `Content` de Calendario
por pantalla, cada uno con sus `FileView` y su sincronización; un Wallpaper Manager oculto que también cerraba paneles
al reaccionar a la exclusión; dos Hardware por pantalla. Nadie leía esos alias.

### Calendario y Pomodoro

| Defecto | Evidencia |
|---|---|
| Los archivos se releían con `text()` tras `fileChanged`, sin `reload()`: la caché de eventos, la selección y el estado de Pomodoro se quedaban con el contenido del arranque | documentación de `FileView` (Quickshell 4f508be); la fixture de servicios y dos mutantes lo detectan |
| Cada apertura lanzaba hasta tres sincronizaciones (dos vistas por pantalla y Bottom Hub) | código; `stab_contracts.py` cuenta llamadas al helper |
| Tres copias de las reglas de fecha (Calendario, Dashboard «Hoy») y tres de la máquina de estados de Pomodoro (Calendario, Dashboard «Focus», helper) con reglas distintas: la UI conservaba las duraciones al reiniciar y el helper las borraba | código; `test-pomodoro.py` falla con el helper de `main` |
| «Hoy» no cambiaba a medianoche con el panel abierto | `isToday` usaba `new Date()` sin dependencia reactiva |
| El botón de Calendario de Bottom Hub no cerraba nunca: leía `state.calendar` después de cerrar todo | código |
| Textos mezclados en inglés y español | código |
| El daemon leía el archivo cada 0,5 s para siempre | 120 despertares y 50 ms de CPU por minuto en reposo (§7) |
| Una orden en el instante del fin de fase avanzaba el estado sin aviso | `settle()` solo existía en el daemon |
| Cada recarga o reinicio del shell repetía el último aviso | el lector toastaba el evento existente en `onLoaded` |
| Un estado activo sin `targetEndTimestamp` no terminaba nunca; con el reloj atrasado quedaba más que una fase | `test-pomodoro.py` |

## 2. Refactorizaciones y por qué

| Cambio | Causa técnica |
|---|---|
| `CortetsuOverlayPolicy.js`: `open`, `close`, `toggle`, `toggleOn`, `toggleGuarded`, `closeExclusiveEverywhere` sobre todas las pantallas | una regla por operación para atajos, IPC, Bottom Hub, Ajustes, Dashboard, OSD y controladores (O-1, O-2) |
| `SurfaceRegistry.js`: `ipcExclusive` → `fullscreenGuard`, presente en todos los transitorios | la guarda era distinta por ruta; ahora bloquea abrir, nunca cerrar |
| Calendario, Portapapeles, Display, Hardware y Wallpaper son `RetainedSurfaceController` | cinco copias del mismo controlador (una con el defecto O-1) |
| `ContentWindow`: un solo binding de modo de teclado, `OnDemand` mientras se quiere el grab | O-3 y el doble escritor |
| Retenidas alojadas una vez; `compose-panels.py` valida en lugar de inyectar | instancias y efectos duplicados |
| `CalendarService` (singleton), `CalendarModel.js`, `Content.qml` + `PomodoroCard.qml` | separar datos, reglas de fecha y presentación; una caché y una sincronización |
| `Pomodoro` (singleton), `PomodoroModel.js`; Dashboard «Hoy» y «Focus» sobre ellos | una fuente de estado; el helper es el único que calcula transiciones |
| `cortetsu-pomodoro`: `settle()`, `reset` que conserva la configuración, daemon con `timerfd` | avisos únicos, datos del usuario, cero despertares en reposo |

El detalle de contratos está en `docs/SCREEN_STATE_MIGRATION.md` (transiciones) y `docs/CALENDAR.md` (Calendario y
Pomodoro).

## 3. Qué se conserva y por qué

- **Python para Pomodoro.** El helper sigue en Python; la mejora viene del diseño (espera por `timerfd`), no del lenguaje.
- **El daemon.** Sigue siendo un proceso: avisa aunque el Calendario no esté abierto y no depende de los timers de Qt,
  que no avanzan durante la suspensión. Ahora no despierta en reposo.
- **Reloj de pared.** Las fases terminan en un instante UTC porque deben sobrevivir a reinicios. Un reloj adelantado
  acorta la fase (no se distingue de una suspensión); uno atrasado queda acotado a la duración de la fase.
- **La fase siguiente empieza al detectar el final.** Tras una suspensión larga no se encadenan fases «perdidas».
- **Formato de `pomodoro.json` y del archivo de avisos.** Sin cambios (schema 2). Un estado escrito por `main` se carga igual.
- **OSD no exclusivo y la barra fuera de la política.** Excepciones del registro, sin cambios.
- **Overview sigue al foco.** Su toggle desde otra pantalla la mueve allí; los demás retenidos se cierran.
- **Wallpaper Manager reactivo.** Sigue cerrándose si se abre un competidor por una ruta que no pasa por la política
  (los vistazos por puntero del cajón heredado, O-4 de F1a). Ahora hay una sola instancia por pantalla.
- **Vistazos por puntero (`drawers/Interactions.qml`).** No pasan por la política: en la misma pantalla no pueden
  apilarse (la retenida tiene la máscara completa) y rozar el borde de otra pantalla no debe cerrar nada.
- **«showall».** Abre lanzador, panel y OSD juntos a propósito; ahora cierra antes cualquier exclusivo.
- **Estética.** Misma geometría, colores, tipografía, transparencia y animaciones. Cambian los textos en inglés y el
  contador de Pomodoro redondea hacia arriba (muestra 25:00 al empezar y 00:00 solo al terminar).
- **Calendario y Pomodoro separados.** Comparten la tarjeta en la vista del Calendario, nada más.

## 4. Matriz de comportamiento

Observada en Hyprland anidado con `tools/stab_contracts.py`, el mismo script contra `main` y contra la rama
(86 comprobaciones; `evidence/stab-before.json`, `evidence/stab-after.json`).

| Contrato | `main` | rama |
|---|---|---|
| Cada retenida abre en una pantalla tras otra retenida en la otra: queda una (42 pares) | 37/42 (los 5 «… then calendar») | 42/42 |
| Hardware abierta, barra lateral por IPC / SUPER+N / Bottom Hub, misma pantalla: solo la barra | 0/3 (IPC apila; SUPER+N y Bottom Hub cierran ambas: carrera O-3) | 3/3 |
| Lo mismo desde la otra pantalla: Hardware se cierra | 1/3 (solo Bottom Hub) | 3/3 |
| El mismo toggle vuelve a cerrar la barra | 1/6 | 6/6 |
| Hardware, luego `drawers toggle <panel>` (6 transitorios): solo el panel; y al revés | 11/12 (sidebar apila) | 12/12 |
| OSD coexiste con Hardware | sí | sí |
| Pantalla completa: la barra lateral no se abre por IPC / SUPER+N / Bottom Hub | 1/3 | 3/3 (la de Bottom Hub, tras añadir su guarda) |
| Wallpaper Manager, luego la barra por las tres rutas: solo la barra | 3/3 en esta pasada (intermitente, 4/15 en la instrumentada) | 3/3; 15/15 en 5 repeticiones (`stab-o2o3-x5.json`); 20/20 en la instrumentada |
| Calendario: una sincronización por apertura | 2 por apertura (10 en 5 aperturas) | 1 (≤5 en 5) |
| Calendario: se mueve de pantalla, el toggle desde la otra lo cierra, Escape lo cierra, el teclado vuelve | sí | sí |
| Hardware → barra → cerrar: el teclado vuelve al cliente | no (Hardware seguía abierta) | sí |
| Estado final: todo cerrado y el teclado en el cliente | sí | sí |

Cambios de comportamiento deliberados, además de los defectos: la guarda de pantalla completa bloquea abrir el OSD y
la barra lateral también por IPC y nunca bloquea cerrar; abrir un panel transitorio cierra las superficies exclusivas
de las demás pantallas; el botón de Calendario de Bottom Hub cierra el Calendario si está abierto en su pantalla.

## 5. Pruebas

| Prueba | Resultado |
|---|---|
| Qt Quick Test `surfaces` (nuevo `tst_OverlayTransitions`: 42 pares × 2 formas de estado, rutas, guarda, 40 ciclos) | 118 PASS |
| Qt Quick Test `calendar` (`tst_CalendarModel`) en UTC, America/Costa_Rica, Europe/Madrid, America/Santiago, Pacific/Kiritimati | 10 PASS en cada zona |
| Qt Quick Test `pomodoro` (`tst_PomodoroModel`) | 8 PASS |
| Resto de suites QML (focus, components, hardware, keyboards, settings, hypr, wallpaper, bottomhub) | mismos recuentos que F1a, 0 FAIL |
| `test-pomodoro.py`: fases, pausa en descanso, `reset`, relojes atrasado/adelantado, zonas horarias, `settle` único, aviso desde una orden, compatibilidad schema 2, daemon real aislado (lock, despertar, aviso a tiempo, cero despertares en reposo) | PASS; falla con el helper de `main` |
| `test-calendar-pomodoro-services.py`: los servicios reales en Quickshell con `HOME` privado, helper real de Pomodoro y stub de calendario: relectura de archivos, sincronización, aviso único, un solo daemon que termina con el shell, sin avisos | PASS |
| 187 gates estáticos de `cortetsu test` y de `build-runtime.sh` | 187 PASS; los 29 que comprobaban cadenas antiguas pasan a comprobar el contrato |
| Mutantes (`tools/mutants.sh`, 20) | 20/20 eliminados (dos sobrevivieron en la primera versión y destaparon dos huecos, ya cubiertos) |
| `cortetsu test` completo en el WS 2 (`run_suite.py`, 188 entradas) | 186 PASS, 1 NOT_RUN (el mismo de F0), 1 FAIL transitorio (`test-cortetsu-idle-runtime.py`: compara los inhibidores de logind del sistema real; repetido después en la rama y en `main`: PASS en ambos) |
| Construcción aislada de dos generaciones y rollback (`test-cortetsu-build.py`, el job de la CI) | PASS |
| Cada commit intermedio de la rama: gates estáticos y QML | PASS en los cuatro |

## 6. Evidencia funcional (Hyprland anidado, WS 2)

Kitty propia `Cortetsu-Stabilization-Debug` en el WS 2; cada sesión anidada con `ws2_run.py` y `F0Session` (HOME, XDG,
D-Bus, PATH y sockets propios; stubs para todo helper del sistema; solo Mesa). Shell compuesto desde el checkout.

| Pasada | Comprobaciones | FAIL | Restos |
|---|---|---|---|
| `main`, todos los escenarios | 86 | 21 | ningún PID, runtime borrado |
| rama, todos los escenarios | 86 | 1 (la guarda de `bottomHub notifications`, corregida después) | ídem |
| rama corregida, O-2 y O-3 × 5 | 157 | 0 | ídem |
| O-3 instrumentado, `main` × 15 / corrección × 20 | 15 / 20 | 4 / 0 | ídem (`evidence/o3-diagnosis.md`) |

Avisos QML (rama frente a `main`, mismo escenario): ningún tipo nuevo. El aviso del portapapeles aparece la mitad de
veces (una instancia en vez de dos) y los de `textinput` bajan de 229 a 165.

Escritorio real: antes de empezar, WS 4 enfocado; tras las pasadas, el escritorio cambió de WS 1 a WS 2 durante el
suite, marcado en `test-startup-inventory.py`. Ese test no llama a Hyprland y, repetido tres veces con `ws_watch.py`,
no movió nada; la causa no se determinó y no se atribuye. Huella del resto (binds, opciones, monitores) sin cambios;
la dGPU NVIDIA siguió `suspended`.

## 7. Rendimiento

Banco de F0 (`nested_bench.py`, 20 arranques, 10 aperturas, 40 ciclos × 7), mismo arnés y máquina, rama y `main`
alternados en dos pares (rama→main, main→rama). `evidence/perf-table.txt`, `evidence/bench-*.json`.

| Pasada | Apertura P50 ms hw/disp/clip/kbd/wall/ovw/cal | Config. cargada P50 | Lista P50 (σ) | IPC P50 | fds | Fallos de estado |
|---|---|---|---|---|---|---|
| 1 rama | 81 / 80 / 82 / 81 / 87 / 118 / 80 | 953 | 1702 (42) | 22.7 | 85 | 0 |
| 1 main | 79 / 82 / 83 / 81 / 94 / 130 / 95 | 1104 | 1883 (129) | 23.3 | 112 | 0 |
| 2 main | 80 / 80 / 85 / 80 / 91 / 115 / 81 | 1003 | 1795 (21) | 23.0 | 112 | 0 |
| 2 rama | 81 / 80 / 84 / 81 / 87 / 115 / 82 | 903 | 1664 (26) | 22.9 | 88→84 | 0 |
| F1a `main` (referencia) | 78–110 | 1003 | 1779 | 22 | 112 | 0 |

- **Arranque:** la rama carga ~100 ms antes y queda lista ~130 ms antes, en los dos pares y en los dos órdenes. Es
  coherente con las 12 instancias de wrappers que ya no se crean, pero la resolución del método (fotograma más
  captura) es del mismo orden: se informa como observado, no como garantía.
- **Apertura y cierre:** sin diferencia atribuible; están en el suelo del método (~80 ms).
- **Recursos en 40 ciclos:** 0 fallos de estado; hilos estables; 27 descriptores menos (85 frente a 112); PSS sin
  tendencia en ninguna versión (el valor absoluto varía entre arranques en ambas).
- **Daemon de Pomodoro en reposo** (`tools/pomodoro_idle.py`, 60 s, `evidence/pomodoro-idle.jsonl`): `main` 120
  despertares y 50 ms de CPU por minuto, en IDLE y en FOCUS; la rama 0 y 0. RSS 13,8 → 14,1 MiB (+0,3 MiB por
  `select`/`signal`). En la sesión real, el daemon de `main` llevaba 118 827 despertares y 58 s de CPU en 16,5 h.
- **Navegación del Calendario:** `eventsByDay` recorre los eventos una vez por mes en vez de filtrarlos dos veces por
  cada una de las 42 celdas. No se midió en ms: con la caché vacía del arnés no hay diferencia observable.

## 8. Riesgos

| Riesgo | Mitigación |
|---|---|
| Abrir un panel en una pantalla cierra ahora lo exclusivo de las otras (antes solo los retenidos lo hacían) | es la regla que ya seguían Bottom Hub y los controladores retenidos; documentada en `SCREEN_STATE_MIGRATION.md` |
| La ventana de cajones queda `OnDemand` con la barra lateral, utilidades, dashboard sin hover o un popout adjunto | el teclado ya iba a esa ventana por el grab; al cerrar vuelve al cliente (comprobado). La prueba de carrera de hover de Bottom Hub pasa en el suite |
| Un daemon de una generación anterior sigue vivo tras instalar | no escribe su PID en el lock, así que la orden nueva no le envía `SIGUSR1` (que lo terminaría); sigue sondeando como antes hasta reiniciar el shell |
| `timerfd` requiere Python ≥ 3.13 | hay un modo de espera acotada (30 s) si falta; la máquina y la CI usan 3.14 |
| Los vistazos por puntero del cajón heredado no pasan por la política | excepción documentada y verificada por el gate; F1a O-4 |
| Un reloj adelantado acorta la fase en curso | inherente al reloj de pared; documentado |

## 9. Compatibilidad y rollback

- Datos: `pomodoro.json` y el archivo de avisos conservan el formato (schema 2); un estado escrito por `main` se carga
  igual y viceversa. `reset` deja de borrar las duraciones. La caché y la selección del calendario no cambian.
- Configuración: ninguna clave nueva. El registro cambia `ipcExclusive` por `fullscreenGuard`; ningún consumidor
  externo lo leía (grep en `cortetsu/`, `scripts/`, `dotfiles/`).
- IPC: los mismos targets y funciones (`calendar`, `hardware`, `clipboard`, `display`, `wallpapermanager`, `overview`,
  `keyboards`, `drawers`, `bottomHub`, `customDock`).
- Sin desplegar: cerrar la PR o revertir su merge. Desplegado: `cortetsu rollback` vuelve a la generación anterior y
  `cortetsu system verify` lo confirma; el helper anterior lee el mismo estado.
- Las herramientas de F1a (`docs/migration/F1a/tools/mutants.sh`) apuntan a cadenas del código de F1a y ya no aplican;
  se conservan como evidencia histórica. Las de esta fase están en `tools/`.

## 10. Pendientes físicos y limitaciones de revisión

**Pruebas físicas (2026-10-20, `PHYSICAL-QA.md`):**

- Dos monitores reales (eDP-1 y HDMI-A-1) con la candidata de `d6769c3`: `PHYSICAL_MULTIMONITOR_PASS`, 198
  comprobaciones, 120 transiciones Wallpaper→Sidebar sin carrera.
- Suspensión real con Pomodoro: `PHYSICAL_SUSPEND_POMODORO_FAIL` por la plataforma, no por la PR. Pomodoro cerró la
  fase vencida al reanudar, con un único aviso y sin repetirlo al recargar. El HDMI (NVIDIA) quedó congelado tras
  `s2idle`, también con el shell instalado, y se recuperó con un ciclo DPMS.

**Pendientes físicos:**

- Cambio real de la hora del sistema (requiere privilegios). Cubierto con reloj simulado.
- Una semana de uso con la nueva generación instalada.

**Limitaciones de revisión:**

- Revisión externa **incompleta**, sin veredicto PASS. `ai-review deep`: OpenCode/Big Pickle revisó el diff de forma
  estática (no pudo ejecutar órdenes) y encontró un P3 verificado y corregido (la tarjeta «Hoy» leía `summary`; los
  eventos traen `title`); AGY/Gemini no se ejecutó: el diff superó el límite de longitud de argumentos del sistema.
- Las dos pasadas Thermos las hizo Claude en línea y en secuencia, sin revisores independientes (preferencia
  registrada de no usar subagentes en paralelo).
- Durante el suite el escritorio pasó del WS 1 al WS 2; causa indeterminada (§6).

## 11. Veredicto

**`STABILIZATION_WITH_CONCERNS`.**

Comprobado: O-1, O-2 y O-3 corregidos con reproducciones que fallan en `main` y pasan en la rama; Calendario y
Pomodoro auditados y sus defectos del alcance corregidos, cada refactorización con su causa (§1–2); gates, suites QML,
fixture de servicios, mutantes, suite completo en el WS 2 y construcción con rollback en verde; sin tipos de aviso QML
nuevos; persistencia compatible; rendimiento contrastado frente a F0/F1a; sesión real sin cambios atribuibles.

Reservas, todas verificables: la revisión externa está incompleta (un revisor no se ejecutó, el otro solo leyó el
código); la prueba física de suspensión dejó el HDMI congelado (plataforma, `PHYSICAL-QA.md` §4.4); el cambio de workspace
del escritorio durante el suite no tiene causa determinada. El estado de la CI está en la PR.

## 12. Cierre (2026-10-21): campana de Bottom Hub, SUPER+X, revisión externa y HDMI

HEAD final en la PR; los commits de esta pasada van de `4aec446` en adelante. No se fusionó, no se desplegó y F1b no
se empezó. No se suspendió el equipo ni se cambiaron drivers, kernel o energía.

### 12.1 Un clic en la campana a través del scrim

Causa: la ventana `retained-surfaces` (capa Overlay, máscara completa mientras hay una superficie) tapa Bottom Hub
(capa Top). El clic sobre la campana caía en el área de «clic fuera» de la superficie y solo la cerraba.

Solución (contrato en `SCREEN_STATE_MIGRATION.md`): un `MouseArea` de ventana completa sobre las superficies acepta la
pulsación solo si cae en la campana de esa pantalla, ningún panel la cubre (`ScrimHit.backdropOnly`), no hay Overview,
Teclados no está grabando ni escribiendo y no hay ventana a pantalla completa. Entonces ejecuta la acción de la
campana (`toggleOn` del Sidebar, la misma regla que SUPER+N). Cualquier otra pulsación sigue a la superficie como
antes. No cambian máscaras, capas, modos de teclado ni la excepción del OSD.

| Verificación | Resultado |
|---|---|
| Qt Quick Test `surfaces` (nuevo `tst_ScrimHit`) | 126 PASS |
| Anidado, escenario `bell` (puntero real del arnés, no IPC) | 29/29 en la rama; en `63bb651` y en `main` falla «un clic deja solo el Sidebar» en las 5 superficies |
| Anidado, `bellfs` (pantalla completa) | la guarda pasa; el arnés deja el cliente sin teclado tras salir de pantalla completa, también en `63bb651` y sin el clic (observación, no contrato) |
| Mutantes (`tools/mutants.sh`, `NESTED=1`) | 26/26 eliminados. El de «sin exclusión de Overview» se retiró: es equivalente en el arnés, porque el contenido de Overview ya cubre la campana |
| Físico (`tools/physical_qa.py b1`, clics uinput, candidata de `22f2266` en eDP-1 y HDMI-A-1) | un clic deja solo el Sidebar: 12/12 (6 superficies × 2 monitores); OSD 2/2; guarda de pantalla completa 2/2; teclado en el cliente al final 2/2 (`evidence/physical/bell/`) |

Defectos anteriores a la PR observados en la QA física (se reproducen igual con el shell instalado, `71e13b4`;
`evidence/physical/bell/probes.txt`):

- En eDP-1, un segundo clic en la campana no cierra el Sidebar; en HDMI-A-1 sí. Defecto de Cortetsu, no de la PR.
- En HDMI-A-1 se pierde cerca del 40 % de los clics del scrim (`63bb651` 10/20, rama 9/20, instalado 4/10); con trazas
  en el QML, en los clics perdidos no llega ningún evento al shell. Causa no determinada; este HDMI es la salida NVIDIA
  del incidente de `s2idle` y la sesión no se reinició desde entonces.
- Escape no cierra el Sidebar abierto por la campana, SUPER+N o IPC, en anidado y en físico, también en `main`: la ventana
  de cajones solo toma el teclado bajo demanda. Ningún contrato lo promete; queda como decisión de diseño.

### 12.2 SUPER+X abre el menú de sesión

`kbSession` = `CTRL + ALT + Delete` y `SUPER + X`, el mismo `cortetsu:session` que el botón de apagado de Bottom Hub.
SUPER+X era el alias de teclado para redimensionar; redimensionar sigue en SUPER + arrastre derecho (bind literal,
para que el editor de atajos no ofrezca una combinación de ratón). `test-keybind-editor-runtime.py` (Hyprland anidado)
comprueba SUPER+X, el arrastre y que editar o borrar una combinación de `kbSession` conserva la otra. En la sesión real
llega al instalar la generación.

### 12.3 Revisión externa por bloques

`ai-review deep` sobre un árbol completo de la PR por bloque, con un commit temporal que contiene los demás bloques, de
modo que el diff revisado es solo el del bloque y ninguno supera el límite de 128 KiB por argumento. Una primera tanda
usó árboles con solo los archivos del bloque y produjo hallazgos falsos (faltaban `PomodoroCard` y `allStates`); se
descartó y se repitió.

| Bloque | OpenCode / Big Pickle | AGY / Gemini 3.8 Flash | Resultado |
|---|---|---|---|
| Superficies / Wayland | sin veredicto (salida degenerada; sin permiso de shell) | P1 `isOpen` siempre falso, P1 bucle de binding en la campana, P2 `OverviewController`, P3 test con estado ficticio: **refutados** (los flags retenidos están en `components/ScreenState.qml`; sin bucle en el log; toggles verificados en anidado y físico). Se renombró el id de la campana para evitar la duda | **INCOMPLETE** |
| Calendario | P3: la sincronización al abrir solo se comprueba por cadena. Refutado: `stab_contracts.py` la cuenta en ejecución («una sincronización por apertura») | PASS estático | **INCOMPLETE** (ninguno ejecutó verificaciones) |
| Pomodoro | cortado por límite de cuota | PASS estático | **INCOMPLETE** |
| Integración (código y gates) | cortado por límite de cuota | PASS estático | **INCOMPLETE** |
| Integración (documentación y herramientas) | cortado por límite de cuota | P2 válido: `stab_contracts.py` salía con 0 con FAIL. Corregido | **NEEDS_CHANGES → corregido**, sin segunda revisión: **INCOMPLETE** |

Ningún bloque llega a PASS: ninguna revisión ejecutó pruebas.

### 12.4 HDMI tras `s2idle`

Incidencia de plataforma separada: `HDMI-S2IDLE.md`. `PHYSICAL-QA.md` conserva `PHYSICAL_SUSPEND_POMODORO_FAIL`.

### 12.5 Verificación del HEAD final

| | Resultado |
|---|---|
| `cortetsu test` en el WS 2 (`run_suite.py`, 188 entradas) | 186 PASS, 1 NOT_RUN (el de siempre), 1 FAIL transitorio (`test-cortetsu-idle-runtime.py`, inhibidores reales de logind; repetido: PASS). Dos gates de Bottom Hub fallaron en una pasada intermedia por este cambio y se corrigieron |
| Construcción aislada y rollback (`test-cortetsu-build.py`) | PASS |
| Candidata construida con `build-runtime.sh` en raíces temporales | todos los gates en verde; enlaces reales intactos; `system verify` PASS al restaurar |
| CI | ver la PR |

Riesgos residuales: la guarda de pantalla completa lee el monitor enfocado (un clic en otra pantalla con pantalla
completa en la enfocada cae en la superficie como antes); una edición previa de `kbResizeWindow` en `keybinds.json`
quedaría sin efecto (en esta máquina no hay ninguna).

**Veredicto: `STABILIZATION_WITH_CONCERNS`.** Defectos de Cortetsu de la PR: ninguno abierto. Defectos de Cortetsu
anteriores a la PR: segundo clic en eDP-1 y Escape en el Sidebar. Plataforma: HDMI tras `s2idle` y clics perdidos en
HDMI. Proceso: revisión externa INCOMPLETE en todos los bloques.

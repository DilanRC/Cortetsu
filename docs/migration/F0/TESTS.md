# F0 · Evidencias y resultados de pruebas

Fuentes en `evidence/run-20261020/`: `suite.json` (cada entrada de `cortetsu test` ejecutada por separado, con la huella de la
sesión real antes y después), `tests-static.json` (clasificación estática), `nested/nested-bench.json` (sesión anidada) y
`ws-audit.txt` (workspace de cada ventana anidada, muestreado cada segundo). Resultados posibles: PASS, FAIL, SKIP, NOT_RUN.
Un SKIP no cuenta como PASS.

## 1. `cortetsu test` en esta rama

Ejecución: 2026-10-20, `0a803e7` más los cambios de esta rama (solo arnés, herramientas y documentación), en la sesión Wayland
real, con todos los compositores anidados en el WS 2 vía `ws2_run.py` (`suite.json`, `suite-log.txt`).

| Resultado | N | Detalle |
|---|---:|---|
| PASS | 182 | 362 s en total; ninguna entrada cambió la huella de la sesión real (`real_session_changed = []`) |
| FAIL | 0 | |
| SKIP | 0 | con Wayland disponible, ninguna entrada imprimió SKIP |
| NOT_RUN | 1 | `eval-cortetsu-process-launcher.py`: crea un scope transitorio en el systemd real de usuario |

Ayer (`71e13b4` sin las correcciones), el resultado fue 181 PASS, 1 FAIL y 1 NOT_RUN. El FAIL era el falso negativo que corrigió
el PR #46.

La huella de `tools/real_snapshot.sh` se tomó antes y después de toda la pasada (`real-before.txt`, `real-after.txt`) y
`real-diff.txt` = `unchanged`. Incluye opciones de Hyprland, monitores, número y hash de binds, hash de atajos globales y
transacción de GameMode real. Ninguna prueba dejó binds temporales ni atajos registrados.

## 2. Corrección del arnés: socket de Hyprland truncado

- **Síntoma:** en el Hyprland anidado, `hardware`, `clipboard`, `overview` y `calendar` no abrían por IPC (`isOpen` = false), y
  el log QML mostraba `Unable to connect to hyprland event socket: QLocalSocket::ServerNotFoundError` antes de
  `Configuration Loaded`.
- **Causa raíz (confirmada):** la ruta `$XDG_RUNTIME_DIR/hypr/<firma de 62 caracteres>/.socket2.sock` supera los 107 bytes de
  `sun_path` cuando `XDG_RUNTIME_DIR` está en `<base>/run` con una base larga. Hyprland la trunca, y `.socket.sock` y
  `.socket2.sock` acaban en un mismo `.socket.so` (`connect(): AF_UNIX path too long`). `hyprctl` trunca igual y funciona;
  Quickshell no conecta, así que `Hyprland.focusedMonitor` queda nulo y `CortetsuShellState.forActive()` devuelve null.
  `display`, `keyboards` y `wallpapermanager` abrían solo porque `monitorFor(screen) === focusedMonitor` daba `null === null`.
- **Alcance:** `test-launcher-dismiss.py` (base `/tmp/czl…`) cabía por poco. `test-bottomhub-hover-close-race.py` (base
  `/tmp/cz-hover-race-…`, 113 bytes) **pasaba con el QML ciego**: 5 errores `ServerNotFound` con el arnés de `0a803e7`.
- **Corrección:** `Session` crea su propio `XDG_RUNTIME_DIR` corto (`mkdtemp(prefix="czr", dir="/tmp")`), lo borra en `stop()`
  y comprueba al arrancar que existan `.socket.sock` y `.socket2.sock`.
- **Verificación:**
  - Arnés antiguo: PASS con 5 `ServerNotFound`.
  - Arnés nuevo: PASS con 0.
  - Mutante (runtime de nuevo en `<base>/run`): `AssertionError: sockets de Hyprland truncados: ['.socket', 'hyprland.lock', 'hyprland.log']`.
  - Con la corrección, las 7 superficies abren (`isOpen` = true) y se renderizan (`evidence/run-20261020/nested/surface-*.png`).
  - No queda ningún `/tmp/czr*` tras las ejecuciones.

## 3. Ventanas de prueba en el WS 2

- **Hallazgo:** el escritorio coloca la ventana de cada Hyprland anidado según sus reglas. Esta máquina tiene una regla personal,
  `cortetsu-nested-tests` (`~/.config/hypr/custom/rules.lua`: clase `aquamarine` → `11 silent`, sin foco inicial). Sin ella, la
  ventana caería en el workspace activo.
- **Primer intento descartado:** lanzar la orden completa con `exec_cmd(…, { workspace = "2 silent" })`. La regla de exec alcanza
  al proceso lanzado y a un hijo directo (comprobado con un Kitty), pero no a los descendientes más profundos que crean las
  pruebas: un Kitty de prueba cayó en el WS 3 y el banco completo en el WS 11. Además, el trabajo compartía grupo de procesos con
  el escritorio (`pgid` 1793), así que un `killpg` por tiempo agotado habría alcanzado al escritorio. Una guarda `pid == pgid` lo
  evitó.
- **Solución:** `ws2_run.py` ejecuta la orden como hijo normal, con un shim `Hyprland` primero en el PATH. El shim hace que el
  escritorio lance `/usr/bin/Hyprland` directamente con la regla de exec (profundidad 0, el caso comprobado), reenvía
  TERM/INT/HUP y termina cuando el compositor termina. La regla de exec gana a la regla personal. No se añade ninguna regla.
- **Verificación:** `test-bottomhub-hover-close-race.py` bajo `ws2_run.py`: PASS, ventana anidada en el WS 2 en las 13 muestras,
  workspace activo en 3 y sin restos en `/tmp`.
- **Ejecuciones anteriores:** las de depuración previas a esta solución usaron el lanzador con `setsid`. Fueron la prueba de
  hover antes, después y con mutante, el sondeo de superficies, la pasada corta y el primer banco completo, y terminaron entre las
  08:39 y las 08:49 del 2026-10-20. Se observó la ventana del banco completo en el WS 11 (silenciosa, sin foco); las demás usaron el
  mismo mecanismo, así que no tenían garantía de WS 2. Sus números no se usan en el baseline.

**Auditoría de la pasada definitiva** (`ws-audit.txt`, escrito por `tools/ws-audit.sh`, una muestra por segundo): 489 muestras de ventanas `aquamarine` (la suite
más el banco anidado), **todas en el WS 2**. El workspace activo estuvo en 3, 2 y 1 por acción del usuario: ninguna herramienta
de F0 despacha foco en el escritorio real.

**Prueba del shim** (`scripts/integration/test-ws2-run-shim.py`, sin escritorio). Un `hyprctl` falso ejecuta el job y un
`Hyprland` falso registra lo que recibe. Comprueba que argv, entorno y cwd sobreviven al entrecomillado (comillas, espacios, saltos
de línea, `$`, barras invertidas y argumentos vacíos), que la salida llega al stdout del llamador, que TERM se reenvía, que el
directorio del job se borra y que un exec rechazado da 125. PASS. Mutantes: argumentos sin entrecomillar → FAIL (el compositor no
arranca); trap sin reenvío → FAIL (`TERM reenviado al compositor`). Se ejecuta a mano; no está en `cortetsu test` porque F0 no
modifica la CLI (D-03).

Tras los últimos cambios de `ws2_run.py`, se repitieron contra el escritorio real `test-bottomhub-hover-close-race.py` (PASS, 13/13
muestras en el WS 2) y `test-launcher-dismiss.py` (PASS, 25 comprobaciones, 86/86 muestras en el WS 2).

## 4. Comprobaciones funcionales pedidas para F0

| # | Comprobación | Resultado | Evidencia |
|---|---|---|---|
| 1 | GameMode nunca resuelve el helper real | **PASS** | `test-gamemode-runtime.py` PASS (aserción: solo el falso es resoluble). En el banco, sin helper en el PATH: 0 llamadas a `cortetsu-gamemode` registradas, PATH = `<stubs>:/usr/bin` |
| 2 | Estado UNKNOWN cuando el helper no arranca | **PASS** | `qs ipc call gameMode status` → `UNKNOWN` (`nested-bench.json → gamemode`); `test-gamemode-runtime.py` PASS |
| 3 | La detección de receptores QML reconoce propiedades reenviadas | **PASS** | `test-global-shortcut-receivers.py` PASS (PR #46, con mutantes) |
| 4 | La UI funciona en la sesión anidada | **PASS** | 7 superficies con `isOpen` = true, 280 aperturas y cierres sin fallos de estado, capturas `nested/surface-*.png` |
| 5 | Los procesos auxiliares terminan | **PASS** | `cleanup.leftover_pids_after_stop = []` y `runtime_dir_removed = true`; sin `/tmp/czr*`, `/tmp/czf*` ni `/tmp/cz-ws2-*` tras la pasada; el barrido por `XDG_RUNTIME_DIR` de prueba no encuentra procesos |
| 6 | No quedan binds temporales | **PASS** | hash de `hyprctl binds -j` (187 binds) y de `globalshortcuts` idéntico antes y después |
| 7 | Errores QML distinguidos de los avisos históricos | **PASS** | 643 avisos nuevos durante el remojo: 442 del arnés (helpers ausentes del HOME temporal, sin historial de portapapeles), 201 históricos (`QWaylandTextInputv3::disableSurface`, también 83 veces en el journal del shell real) y **0 de otra clase**. El journal real añade F-01 y F-02 (RISKS.md) |
| 8 | Cada prueba da PASS, FAIL, SKIP o NOT_RUN de forma explícita | **PASS** | `suite.json`: 182 PASS y 1 NOT_RUN con motivo |
| — | dGPU dormida | **PASS** | `suspended` antes y después (`preflight.txt`, `latency.json`) |
| — | Huella de la sesión real | **PASS** | `real-diff.txt` = `unchanged` |
| — | HDMI, suspensión, teclas físicas, energía, dos sesiones | **NOT_TESTED** | RISKS.md §4 |

## 5. Pruebas que salen con SKIP (exit 0) sin Wayland [obs, 2026-10-19]

Estas 9 entradas del gate terminan con **exit 0 y SKIP** sin Wayland, así que una ejecución en CI o en TTY sale verde sin
ejecutarlas: `test-cortetsu-idle-runtime.py`, `test-gamemode-runtime.py`, `test-notification-history-runtime.py`,
`test-bottomhub-hover-close-race.py`, `test-hp-keys.py`, `test-keyboards-capture.py`, `test-keyboards-probe.py`,
`test-keyboards-scope.py` y `test-launcher-dismiss.py`. CI solo puede verificar la parte estática y offscreen (decisión D-02 de
RISKS.md).

## 6. Pruebas fuera de cualquier gate (20)

No están en `cortetsu test`, `build-runtime.sh`, el instalador ni CI: `test-regional.node.js`, `test-status-pill.sh`,
`eval-ascension-runtime.py`, `eval-cortetsu-session-actions.py`, `test-configure-launcher-wallpaper-actions.py`,
`test-connectivity-{original-nexus,password-copy,ui-wayland}.py`, `test-cortetsu-hover-lifetime.py`, `test-cortetsu-lock-runtime.py`,
`test-diagnose-sad-wiring.py`, `test-dotfiles-recovery.py`, `test-keep-awake.py`, `test-keybind-editor-runtime.py`,
`test-nvibrant.py`, `test-performance-baseline.py`, `test-power-auto-control.py`, `test-system-recovery.py`,
`test-wire-sad-shell.py` y `test-clipboard-sensitive-history.py`. Dos cubren recuperación. Decisión D-03.

## 7. Correcciones previas ya fusionadas

- **PR #45** (`a4b4a47`): `test-gamemode-runtime.py` resolvía el `cortetsu-gamemode` instalado por el PATH heredado. Ahora quita
  del PATH anidado todo directorio con ese ejecutable. Incluye regresión y mutante.
- **PR #46** (`62efcb8`): `test-global-shortcut-receivers.py` cuenta los receptores cuyo nombre reenvía un componente
  (`name: root.shortcutName`). Se comprobó con mutantes que sigue detectando faltantes y duplicados.

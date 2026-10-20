# Cortetsu 2.0 · F0: baseline del sistema actual

**Veredicto: `F0_COMPLETE`.** El inventario, los contratos y el baseline funcional y de rendimiento están medidos sobre `0a803e7`,
se regeneran con una sola orden (`tools/reproduce.sh`; su rc=0 indica que terminó, no que todo pasó: cada paso guarda
su resultado y el veredicto sale de `suite.json`, `real-diff.txt` y `baseline.json`) y el aislamiento está verificado. La sesión anidada visible
en el WS 2 funciona con la interfaz de Cortetsu renderizada, y el escritorio real no cambió. Las pruebas físicas siguen en
`NOT_TESTED`, clasificadas en RISKS.md §4: el encargo pide expresamente dejarlas pendientes cuando no se pueden reproducir de
forma segura. F1 no se ha iniciado.

Fecha: 2026-10-20. Rama: `docs/f0-baseline-2026-10-20` (sin fusionar ni desplegar). Referencias:
`CORTETSU_MIGRACION_TOTAL_GO_RUST_2026-10-17.md` (fuera del repo; §2, §10.2, §11.1–11.2, §12) y la primera pasada de F0
(`~/Documentos/Auditorias/Cortetsu-F0-2026-10-19/`, `F0_PARTIAL`), cuyos pendientes quedan cerrados o reclasificados aquí.

## Entregables

| # | Entregable | Archivo |
|---|---|---|
| 1 | Informe técnico | este archivo |
| 2 | Inventario arquitectónico y de procesos | [INVENTORY.md](INVENTORY.md) |
| 3 | Contratos funcionales observados | [CONTRACTS.md](CONTRACTS.md) |
| 4 | Baseline de rendimiento y metodología | [BASELINE.md](BASELINE.md) |
| 5 | Matriz de paridad futura Python/Rust/Go | [PARITY-MATRIX.md](PARITY-MATRIX.md) |
| 6 | Evidencias y resultados de pruebas | [TESTS.md](TESTS.md), `evidence/run-20261020/`, `evidence/idle-20261020-0733/` |
| 7 | Riesgos e incertidumbres | [RISKS.md](RISKS.md) |
| 8 | Requisitos de entrada a F1 | §5 de este archivo |
| 9 | Reproducir la sesión de depuración | [DEBUG-SESSION.md](DEBUG-SESSION.md), `tools/` |

## 1. Preparación verificada

| Comprobación | Resultado |
|---|---|
| Repo | `DilanRC/Cortetsu`, `main` = `origin/main` = `0a803e7`, árbol limpio al empezar |
| PR #45 / #46 | aislamiento del PATH en `test-gamemode-runtime.py` y receptores con nombre reenviado; entre `71e13b4` y `0a803e7` solo cambian esos dos archivos de prueba |
| Generación desplegada | shell `20261017-160736-98327` (Cortetsu@71e13b4); `previous` → `20261017-154533-53190`. Rollback: `cortetsu rollback` (alias `~/.local/bin/cortetsu-rollback`), que valida la generación anterior antes de mover los symlinks. `cortetsu system verify` → PASS |
| Versiones | Hyprland 0.56.2 · Quickshell 0.3.2 (4f508be) · Qt 6.12.0 · kitty 0.49.2 · Python 3.14.8 · grim 1.5.0 · cc, wayland-scanner, pkg-config, dbus-daemon presentes |
| Ejecutables | `Hyprland` y `qs` en `/usr/bin`; `hyprctl` resuelve a un wrapper personal (`~/.local/bin/hyprctl`) que delega en `/usr/bin/hyprctl`; no existe ningún `hyprland-start` |
| Servicios | `cortetsu-shell`, `cortetsu-power-auto`, `cortetsu-wallpaper-color`: activos |

## 2. Sesión visual de depuración

- Kitty propia `Cortetsu-F0-Debug` (clase `cortetsu-f0-debug`), nacida en el WS 2 con `exec_cmd(…, { workspace = "2 silent" })`,
  con pestañas para logs del shell y del compositor anidados, procesos y recursos del arnés, y salida de la suite y del banco.
- Hyprland anidado con el shell **compuesto desde el checkout** y 3 salidas. Se renderizan Hardware, Pantallas, Portapapeles,
  Atajos, Wallpaper Orbital, Overview y Calendario (`evidence/run-20261020/nested/surface-*.png`).
- La pasada definitiva tuvo **489/489** muestras de ventanas anidadas en el WS 2. El foco y el workspace activo nunca se tocaron.
- Órdenes reales en DEBUG-SESSION.md.

## 3. Resultados

**Pruebas:** `cortetsu test` → **182 PASS, 0 FAIL, 0 SKIP, 1 NOT_RUN**, el que crea un scope en el systemd real. La huella de la
sesión real no cambió en ninguna prueba. Las 8 comprobaciones funcionales pedidas dan PASS (TESTS.md §4).

**Rendimiento** (BASELINE.md):

| Medida | Resultado |
|---|---|
| Helpers en la sesión real, P50 | 27 ms (`gamemode status`) a 196 ms (`cortetsu status`); Rust `keybinds list` 2,0 ms; suelo de Python 11 ms |
| Residentes | shell 0,36 % de un núcleo y 139 MiB de PSS; power-auto 0,06 % y 3,8 MiB; wallpaper-color 0,28 % y 6,6 MiB |
| Procesos | 8 persistentes; 0 transitorios en reposo |
| Arranque | real P50 1.118 ms (journal, n=6); en el arnés P50 1.054 ms (n=20, σ 29 ms) hasta `Configuration Loaded` |
| Superficies en el arnés | apertura P50 80–113 ms (n=10 por superficie, cota superior con ~60 ms de suelo de medida) |
| 40 ciclos × 7 superficies | 0 fallos de estado; PSS sin crecimiento (−10 MiB); hilos, fds e hijos constantes; 0 avisos QML nuevos fuera de las clases arnés o histórica |

## 4. Problemas detectados

**Corregidos en esta rama (solo aparato de pruebas):**

1. **H-01, socket truncado.** `launcher_harness.Session` dejaba el QML anidado sin IPC de Hyprland cuando la ruta del socket
   superaba `sun_path`. `test-bottomhub-hover-close-race.py` pasaba sin que el QML viera monitores ni foco. Por esto ayer no se
   pudieron medir 4 superficies. Se corrigió con un runtime corto propio y una aserción, probada con un mutante (TESTS.md §2).
2. **H-02, colocación de ventanas.** Los compositores anidados obedecían la regla personal `cortetsu-nested-tests` (WS 11). La regla
   de exec no alcanza a los descendientes profundos, y lanzar trabajos por el escritorio los ponía en el grupo de procesos del
   escritorio. `ws2_run.py` lo resuelve con un shim de `Hyprland` (TESTS.md §3).

**Sin corregir (código funcional, fuera de lo autorizado):** F-01 `Gpu.qml` sin `import QtCore` (error QML en producción), F-02
bucle de binding en la barra lateral, F-03 respuesta de GameMode sin validar, F-04 escritura en `power-auto-control status`, F-05
falso positivo de Wallpaper Engine, F-06 `DISPLAY_MANAGER.md` desfasado y F-07 `picker` sin `isOpen` (RISKS.md §1).

## 5. Requisitos de entrada a F1

F1 puede empezar cuando:

1. Dilan acepte este baseline y la rama `docs/f0-baseline-2026-10-20` (PR o descarte). Las correcciones H-01 y H-02 deberían
   fusionarse antes de F1: sin H-01, cualquier prueba nueva de QML anidado puede pasar sin ver Hyprland.
2. Se decida si F-01 se corrige antes de F1 (es un error de producción, independiente de la migración) o se registra como paridad
   deliberada.
3. Las decisiones D-01 (ADR del socket), D-02 (SKIP en el gate) y D-03 (pruebas huérfanas) tengan dueño. F1 puede escribir
   contratos y fixtures sin cerrarlas, pero ningún dominio afectado pasa a F2+ sin ellas.
4. Se decida sobre el tag `f0-baseline-2026-10-20` en `0a803e7` (D-04, no creado).
5. Las pruebas físicas de RISKS.md §4 se programen con Dilan antes del cutover de los dominios que cubren (display, energía, GameMode,
   teclas).

## 6. Revisión

- **Corrección y seguridad** (en línea, por la regla del proyecto de no lanzar subagentes en paralelo; sin independencia de
  revisor). Hallazgos corregidos:
  - el job del shim, con todo el entorno, podía quedar en `/tmp` si el shim moría (ahora vive en el directorio privado de
    `ws2_run`);
  - `ws2_run` no manejaba un tiempo agotado antes de que existiera el PID;
  - `setsid` cortaba la cadena de ancestros, y un `killpg` habría podido alcanzar el grupo del escritorio (ahora no hay `setsid`
    ni `killpg` sobre un grupo que no lidera el trabajo);
  - `Session.__init__` podía dejar un `/tmp/czr*` vacío.
- **Mantenibilidad** (en línea): se renombraron variables confusas y se quitó un efecto secundario dentro de una expresión en
  `nested_bench.py`, y `render_shim()` se extrajo para poder probarlo. Ningún archivo nuevo supera las 300 líneas.
- **`ai-review normal`**:
  - OpenCode/Big Pickle: 2 P2 y 2 P3, todos verificados contra el código y corregidos (docstring de `bench_latency.py`, `unlink`
    sin `missing_ok`, `set -e` en el preflight, prueba del shim).
  - AGY no se ejecutó: el modelo configurado en `ai-review` (`gemini-3.7-flash-low`) no existe en el cliente. Es una limitación de
    la herramienta y queda sin segunda opinión externa.

## 7. Cambios de esta rama

| Archivo | Cambio |
|---|---|
| `scripts/integration/launcher_harness.py` | runtime corto propio, aserción de sockets y limpieza en `stop()` (H-01) |
| `scripts/integration/ws2_run.py` | nuevo: ejecuta una orden con sus compositores anidados en un workspace (H-02) |
| `scripts/integration/f0_session.py` | nuevo: `Session` con stubs de cada orden que toca el host y arranque cronometrado |
| `scripts/integration/test-ws2-run-shim.py` | nuevo: prueba sin escritorio del shim de `ws2_run.py` |
| `scripts/integration/README.md` | uso de `ws2_run.py`, runtime corto de `Session` y `F0Session` |
| `docs/migration/F0/**` | informe, tools de medición y evidencias |

No se modificó código funcional de Cortetsu, servicios instalados ni configuraciones personales. No se instaló nada. Para revertir,
basta con descartar la rama.

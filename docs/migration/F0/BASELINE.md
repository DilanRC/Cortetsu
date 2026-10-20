# F0 · Baseline de rendimiento y metodología

Pasada de referencia: **2026-10-20**, `0a803e7` + esta rama (solo arnés y herramientas), `evidence/run-20261020/` (rc=0),
agregada en `evidence/run-20261020/baseline.json`. Reproducir: `docs/migration/F0/tools/reproduce.sh [<out>]`.

Hay dos entornos, y **sus números no se comparan entre sí**:

- **Sesión real**: la generación instalada `20261017-160736-98327` (Cortetsu@71e13b4; entre 71e13b4 y 0a803e7 solo cambiaron
  pruebas), medida con sondas de solo lectura.
- **Arnés anidado**: el shell compuesto desde el checkout, dentro de `F0Session`, con `QT_QUICK_BACKEND=software`, 3 salidas,
  HOME vacío y helpers sustituidos por stubs.

## 1. Condiciones

| Variable | Valor |
|---|---|
| Equipo | HP Victus 15-fb3xxx, kernel 7.2.10-1-cachyos |
| Versiones | Hyprland 0.56.2-4.1 · quickshell-git 0.3.2.r0.g4f508be-1 · qt6-base 6.12.0-3 · qt6-declarative 6.12.0-1.1 · kitty 0.49.2 · Python 3.14.8 · grim 1.5.0 |
| Energía | governor `powersave`, perfil `balanced`, AC conectado |
| Carga | `loadavg` 4,85 / 4,49 / 3,91 al empezar (sesión activa: navegador con un juego en el WS 3). Ayer: 2,4–3,2 |
| GPU | dGPU NVIDIA `suspended` antes y después; el arnés usa solo Mesa (Radeon integrada) |

## 2. Sesión real

**Latencia de helpers one-shot** (`bench_latency.py`, N=30, tiempo de pared desde `exec` hasta la salida, como los invoca el QML)

| Invocación | P50 ms | P95 ms | Ayer P50/P95 |
|---|---:|---:|---:|
| `python3 -c pass` (suelo del intérprete) | 11,0 | 14,3 | 10,3 / 11,8 |
| `cortetsu-keybinds list` (**Rust**) | 2,0 | 2,6 | 1,9 / 2,2 |
| `cortetsu-gamemode status` | 26,9 | 30,3 | 22,9 / 26,8 |
| `cortetsu-scheme list` | 33,5 | 39,9 | 29,5 / 34,2 |
| `cortetsu-display-probe` | 52,5 | 64,8 | 43,5 / 47,9 |
| `cortetsu-record status` | 54,4 | 75,1 | 38,4 / 43,9 |
| `cortetsu system verify` | 64,7 | 76,3 | 56,8 / 61,2 |
| `cortetsu-hardware-probe` | 112,3 | 124,4 | 92,9 / 100,3 |
| `cortetsu-power-auto-control status` | 152,3 | 178,6 | 122,1 / 130,5 |
| `cortetsu status` | 195,9 | 216,2 | 165,4 / 184,5 |

Hoy todo sale entre un 5 y un 42 % más lento, también el suelo del intérprete (+7 %). La causa es la carga del sistema, no el
código: los helpers son los mismos binarios. Por eso el gate de la matriz exige las mismas condiciones y no ejecuciones sueltas.

**Residentes** (`bench_resident.py`, 3 ventanas × 120 s; CPU por delta de `CPUUsageNSec` del cgroup, PSS por `smaps_rollup`,
procesos transitorios muestreados cada 50 ms)

| Unidad | CPU % de un núcleo (mediana, mín–máx) | PSS del árbol | Procesos transitorios / ventana |
|---|---:|---:|---|
| `cortetsu-shell` | 0,36 (0,35–0,45) | 139,0 MiB | 0, 0, 0 |
| `cortetsu-power-auto` | 0,06 (0,05–0,06) | 3,8 MiB | 0, 0, 0 |
| `cortetsu-wallpaper-color` | 0,28 (0,27–1,11) | 6,6 MiB | 0, 4, 0 (falso positivo F-05) |

**Reposo real (PERF-01, 2026-10-20 07:33–07:41, `idle_measure.sh`, 4 × 120 s, 0 interrupciones de entrada, `evidence/idle-20261020-0733/`):** shell 0,23–0,26 % y
181 MiB de PSS; power-auto 0,06 % y 3,9 MiB; wallpaper-color 0,24 % (0,75 % en las ventanas con falso positivo) y 6,7 MiB. Es la
referencia de reposo. No se repitió hoy porque exige que nadie use el equipo.

**Arranque del shell (journal, `shell_startup.py`):** de `Started Cortetsu Quickshell` a `Configuration Loaded`, n=6
(retención del journal): P50 1.118 ms, P95 1.142 ms, mín 872, máx 1.159.

**Procesos persistentes:** 8 (INVENTORY.md). En reposo no aparece ninguno transitorio.

## 3. Arnés anidado: arranque y superficies

| Medida | n | P50 | P95 | σ |
|---|---:|---:|---:|---:|
| Arranque: spawn de `qs` → `Configuration Loaded` | 20 | 1.054 ms | 1.104 ms | 29 ms |
| Arranque: spawn → responde a `drawers list` con sus capas mapeadas | 20 | 1.839 ms | 1.893 ms | 29 ms |
| Ida y vuelta de `qs ipc` (coste de la medida) | 206 | 24,6 ms | 33,2 ms | 3,1 ms |
| Captura de grim, 1/4 de escala (resolución de la medida) | 460 | 47,9 ms | 54,8 ms | 5,0 ms |

Apertura: IPC `open` → primer fotograma de `HEADLESS-1` distinto del cerrado ya estable. Cierre: IPC `close` → fotograma igual al
cerrado. Son cotas superiores que incluyen la ida y vuelta de IPC y el intervalo de captura.

| Superficie | Apertura n | P50 | P95 | σ | Cierre n | P50 | P95 | Muestras descartadas |
|---|---:|---:|---:|---:|---:|---:|---:|---|
| hardware | 8 | 80,5 | 88,6 | 3,5 | 8 | 117,4 | 125,1 | 2 sin pantalla estable |
| display | 10 | 80,1 | 82,8 | 1,6 | 10 | 78,9 | 84,0 | — |
| clipboard | 10 | 86,2 | 119,2 | 11,1 | 10 | 81,3 | 90,0 | — |
| keyboards | 10 | 82,2 | 130,5 | 15,7 | 10 | 79,7 | 82,6 | — |
| wallpapermanager | 10 | 91,7 | 134,9 | 19,1 | 10 | 280,2 | 295,9 | — |
| overview | 10 | 112,7 | 131,6 | 7,5 | 8 | 258,0 | 273,9 | 2 cierres sin volver al fotograma base en 3 s |
| calendar | 10 | 81,1 | 114,6 | 10,9 | 10 | 230,2 | 290,5 | — |

Con unos 60 ms de suelo de medida (IPC + captura), las aperturas de unos 80 ms equivalen a uno o dos fotogramas de trabajo
propio. Wallpaper, overview y calendar tardan más en cerrar: tienen animación de salida. El objetivo de `docs/PERFORMANCE.md`
(< 120 ms) se cumple en P50 en las 7 superficies. En P95, clipboard, keyboards, wallpapermanager y overview lo superan, pero
dentro de la resolución de la medida.

Una pasada anterior de hoy, con su ventana en el WS 11 y otra carga (no usada como baseline), dio aperturas con P50 de 104 a
179 ms. La diferencia entre pasadas es la variabilidad que hay que esperar: compárense siempre pasadas completas en las mismas
condiciones.

## 4. Arnés anidado: 40 ciclos (PERF-02 en el arnés)

40 ciclos × 7 superficies = 280 aperturas y 280 cierres, con `isOpen` comprobado después de cada uno.

| Ciclo | PSS MiB | RSS MiB | Hilos | fds | Descendientes de qs | CPU acumulada s |
|---:|---:|---:|---:|---:|---:|---:|
| 0 | 456,5 | 542,0 | 48 | 112 | 1 (`dbus-monitor`) | 1,57 |
| 10 | 467,0 | 555,1 | 48 | 112 | 1 | 5,87 |
| 20 | 460,0 | 543,2 | 48 | 112 | 1 | 11,73 |
| 30 | 454,1 | 534,8 | 48 | 112 | 1 | 21,03 |
| 40 | 446,1 | 525,3 | 48 | 112 | 1 | 29,16 |

- Fallos de estado: **0**.
- Crecimiento de memoria: **ninguno** (−10,4 MiB de PSS; la memoria se libera al cerrar).
- Hilos, fds y descendientes: constantes.
- Avisos QML nuevos: 643, clasificados en TESTS.md §4.7, **0 de clase «otro»**.
- El PSS del arnés (≈ 450 MiB) es mayor que el de la sesión real (≈ 140–180 MiB) por el renderizado software y las 3 salidas.

## 5. Procesos externos creados por el shell en el arnés

Los stubs registraron cada orden que habría llegado al sistema durante toda la sesión: `nmcli` 127, `busctl` 79,
`brightnessctl` 21, `notify-send` 21 y `systemd-inhibit` 21, y **0** `cortetsu-gamemode`. `brightnessctl`, `notify-send` y
`systemd-inhibit` salen 21 veces, una por cada arranque del shell (20 + 1).

## 6. Comparación con `docs/PERFORMANCE_BASELINE_2026-09-04.md`

| Métrica | 2026-09-04 | 2026-10-20 | Comparable |
|---|---:|---:|---|
| RSS de qs | 422 MiB | 134 MiB (RSS del proceso, INVENTORY.md) | parcialmente: otro build (RetainedSurfaces, perf-phase-2), otra duración de sesión |
| PSS de qs | 287 MiB | 139 MiB (árbol), 181 MiB en reposo | parcialmente |
| CPU | 2,6 % (instantáneo) | 0,36 % (delta en 120 s) | **no**: un instante frente a una ventana |
| Hilos / fds | 117 / 90 | 48 / 112 (arnés) | **no**: el valor de hoy es del arnés |
| Hijos directos del shell | 1 (`nmcli monitor`) | 5 (`dbus-monitor`, `nmcli monitor`, `systemd-inhibit`, `cortetsu-pomodoro daemon`, `sleep`) | sí: crecieron por funciones nuevas (lock antes de suspender, Focus) |

Limitaciones históricas del documento de 2026-09-04:

- Es una instantánea (una muestra, sin N ni variabilidad), de otro build y sin condiciones registradas (carga, governor, AC, dGPU).
- La CPU es instantánea, no un delta de cgroup.
- El propio documento dice que no es un gate y pide repetir tras 60 s de reposo e incluir arranque, primer fotograma, 40 ciclos,
  avisos QML y procesos externos. Este baseline cubre esos cinco puntos (§2–§5).

## 7. Cómo comparar una migración

Repetir `reproduce.sh` en el mismo equipo con governor, perfil, AC, dGPU y `loadavg` anotados, y comparar medianas y P95 de pasadas
completas. Sesión real con sesión real y arnés con arnés. Usar PSS, no `MemoryCurrent` (que incluye caché de páginas). Los gates
están en PARITY-MATRIX.md.

# F0 · Matriz de comparación futura Python / Rust / Go

Plantilla de comparación. Las cifras de la columna «Baseline Python» son **las medidas en F0** (`baseline.json`), y las
columnas Rust/Go quedan vacías hasta que exista implementación. Un componente solo cambia de propietario si cumple
**todas** las filas de paridad funcional y no empeora las de rendimiento sin una mejora funcional aceptada y explicada.
Resultados permitidos: `PASS / FAIL / NOT_TESTED / BLOCKED`. `NOT_TESTED` no equivale a aprobado.

## A. Paridad funcional (por helper)

| Criterio | Cómo se comprueba | Baseline |
|---|---|---|
| Misma forma JSON (claves/tipos) | `tools/contract_shapes.py` antes/después, diff vacío | `evidence/run-20261020/contract-shapes.json` |
| Mismos códigos de salida, incluidos los irregulares (`record status`=1, keybinds error=1 JSON, argparse=2) | igual | CONTRACTS.md |
| Misma máquina de estados y recuperación | tests runtime existentes sin modificar sus asserts (gamemode, display, generations) | PASS 182 + 1 NOT_RUN (2026-10-20) |
| Mismos archivos de estado, formato y permisos | diff de árbol en HOME temporal | CONTRACTS.md §Persistencia |
| Sin secretos en argv/env/logs/IPC | SEC-01 del estudio | NOT_TESTED |
| Diferencias deliberadas documentadas con test (p. ej. `power-auto-control status` sin escribir; Wallpaper Engine sin falso positivo) | test nuevo + nota | — |
| Respetar dGPU dormida | `runtime_status` antes/después | suspendida antes y después [obs] |

## B. Rendimiento (gates)

Baseline = pasada del 2026-10-20 (BASELINE.md, `evidence/run-20261020/baseline.json`), con `loadavg` 4,85. Una implementación
nueva se compara con una pasada completa en las mismas condiciones, no con estas cifras sueltas.

| Métrica | Método | Baseline Python (F0) | Rust | Go | Gate |
|---|---|---|---|---|---|
| `gamemode status` P50/P95 | `bench_latency.py`, N=30 | 26,9 / 30,3 ms | | | ≤ baseline |
| `scheme list` | idem | 33,5 / 39,9 ms | | | ≤ baseline |
| `display-probe` | idem | 52,5 / 64,8 ms | | | ≤ baseline |
| `record status` | idem | 54,4 / 75,1 ms | | | ≤ baseline |
| `hardware-probe` | idem | 112,3 / 124,4 ms | | | ≤ baseline |
| `power-auto-control status` | idem | 152,3 / 178,6 ms | | | ≤ baseline y sin escritura (F-04) |
| `cortetsu status` / `system verify` | idem | 195,9 / 216,2 · 64,7 / 76,3 ms | | | ≤ baseline |
| Referencia ya portada: `keybinds list` | idem | **Rust 2,0 / 2,6 ms** | — | | — |
| Suelo del intérprete `python3 -c pass` | idem | 11,0 / 14,3 ms | | | contexto |
| CPU residente `power-auto` | delta de `CPUUsageNSec`, 3×120 s | 0,06 % (0,05–0,06) | | | ≤ baseline |
| CPU residente `wallpaper-color` | idem | 0,28 % (0,27–1,11, con el falso positivo) | | | ≤ 0,24 % sin el falso positivo |
| CPU residente `cortetsu-shell` | idem | 0,36 % (0,35–0,45); reposo 0,23–0,26 % | | | no empeorar |
| PSS `power-auto` / `wallpaper-color` | `smaps_rollup` | 3,8 / 6,6 MiB | | | ≤ baseline |
| PSS árbol `cortetsu-shell` | idem | 139 MiB (activo), 181 MiB (reposo 07:33) | | | no empeorar |
| Procesos transitorios / 120 s | muestreo cada 50 ms (cota inferior) | shell 0, power-auto 0, wallpaper 0–4 | | | 0 sin disparador |
| Arranque real | journal, n=6 | P50 1.118 / P95 1.142 ms | | | no empeorar |
| Arranque en el arnés (`Configuration Loaded`) | `nested_bench.py`, n=20 | P50 1.054 / P95 1.104 ms | | | no empeorar |
| Apertura de superficie en el arnés (cota superior) | idem, n=10 por superficie | P50 80–113 ms; P95 83–135 ms (BASELINE.md §3) | | | no empeorar fuera de ±1 intervalo de captura |
| 40 ciclos × 7 superficies en el arnés | idem | 0 fallos de estado, ΔPSS −10 MiB, hilos/fds/hijos constantes | | | 0 fallos, ΔPSS ≤ +5 % |
| Avisos QML nuevos de clase «otro» en el remojo | idem | 0 | | | 0 |
| Llamadas al host por sesión del arnés | stubs | nmcli 127 · busctl 79 · brightnessctl/notify-send/systemd-inhibit 21 | | | sin llamadas nuevas no justificadas |
| Coordinador Go residente (PSS) | — | no existe | | | ≤ 35 MiB candidato (estudio §10.2), sujeto a medida |

## C. Condiciones obligatorias para que la comparación sea válida

Mismo equipo (HP Victus 15-fb3xxx), governor `powersave`, perfil `balanced`, estado de AC registrado, dGPU suspendida y
`loadavg` anotado. Hay que repetir las mismas N y ventanas, y comparar medianas y P95, no ejecuciones sueltas. La sesión
del usuario estaba **activa** durante F0 (no era un idle puro): toda comparación debe hacerse en las mismas condiciones o
repetirse el baseline. `MemoryCurrent` del shell osciló entre 121 y 274 MiB porque incluye caché de páginas: usar PSS, no
MemoryCurrent, como gate.

Las filas «en el arnés» solo se comparan con otra pasada del arnés (`nested_bench.py` con las mismas N), nunca con la sesión
real: el arnés usa renderizado software, 3 salidas, HOME vacío y stubs.

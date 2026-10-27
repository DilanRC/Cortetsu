# Fase 4 (Core y módulos): estado verificado en Agent Realms

Rama `phase4/realm-fixes` desde `db466d2` (origin/main). Fecha: 2026-10-26.
Pendientes de partida: `09-RECOMMENDATIONS-ROADMAP.md` del estudio `2026-10-24-db466d2` (R-01…R-15) y
la misión de fase 4 (C-01…C-09, fases A y B).

Cada arreglo se reprodujo primero en un realm de Agent Realms (Hyprland 0.56.2 anidado, D-Bus,
PipeWire y servicios simulados privados), se comparó con el build anterior y quedó en un commit propio.
La evidencia (scripts, salidas y capturas) está en el repositorio de Agent Realms,
`evidence/cortetsu-phase4/<id>/`.

## Matriz

| ID | Pendiente | Commit | Prueba en realm | Estado |
|---|---|---|---|---|
| C-01 / R-01 | 4 layers Overlay y 1 Top siempre mapeadas: ningún fullscreen es solitario | `b18b607` | `solitaryBlockedBy` de Hyprland pasa de `[OVERLAYS]` a `null`; mapa de superficie +4–6 ms mediana | IMPLEMENTADO Y VERIFICADO · escaneo directo: PENDIENTE DE VALIDACIÓN FÍSICA |
| C-02 / R-02 | El grab del drawer excluía el BottomHub; 250 ms de compensación | `83e8923`, `8d6f924` | campana sobre ventana no enfocada: build base 10/10, sin parche 1/10, final 40/40 | IMPLEMENTADO Y VERIFICADO |
| C-03 | Un popout del hub en B cerraba el Dashboard de A (rompe F1a O-4) | `4b73207` | dos salidas virtuales; el Dashboard de A sigue abierto, campana de B 20/20 | IMPLEMENTADO Y VERIFICADO |
| R-05 | Un vistazo por hover en B roba el teclado de A | — | las layers Exclusive y el focus grab bloquean el hover hacia B | NO REPRODUCIBLE |
| R-12 | Monitor eliminado con superficie abierta deja máscara huérfana | — | salida eliminada con superficie abierta, sin máscara | NO REPRODUCIBLE |
| C-04 / R-03 | Interpolación sin escapar en código Lua que evalúa Hyprland | `3ab746a`, `d778560` | 7 nombres hostiles (comillas, `]]`, `\`, controles, emoji) ida y vuelta | IMPLEMENTADO Y VERIFICADO |
| C-04 (hallazgo) | Botones cerrar/flotar de la tarjeta del Overview no respondían | `6c0e986` | X cierra, flotar alterna, clic en el cuerpo enfoca | IMPLEMENTADO Y VERIFICADO |
| C-05 / R-04 | `j/clients` completo por cada cambio de título | `1457dff` | 100 cambios de título: 204 → 0 refrescos, 0,33 s → 0,03 s de CPU | IMPLEMENTADO Y VERIFICADO |
| C-06 / R-11 | Quickshell no reconecta el socket de eventos (Hyprland lo corta con 64 eventos en cola) | `0b6a4dc` | SIGSTOP + 3000 cambios: estado congelado → detectado y resincronizado tras el siguiente cambio propio | IMPLEMENTADO CON LIMITACIONES (la reconexión real es upstream) |
| C-07 / R-06 | Cinco políticas de carga; el Overview recalcula cerrado | `2d2aa51` | 20 ventanas abiertas y cerradas: 1,13–1,19 s → 1,00 s de CPU; tarjetas presentes a 350 ms de abrir | IMPLEMENTADO CON LIMITACIONES (sin campo `lifecycle` común; no se hizo lazy nada sin medir) |
| R-07 | `lastIpcObject.windows` obsoleto en la máscara de arrastre | — | Cortetsu ya refresca `j/workspaces` en open/close/move; `toplevels` contaría superficies auxiliares | DESCARTADO CON JUSTIFICACIÓN |
| R-08 | Sin forma de ver el estado de superficies | `5dd3cdc` | `qs ipc call cortetsu-shell inspect` usado en todas las pruebas | IMPLEMENTADO Y VERIFICADO |
| R-09 | ADR-007 en estado PROPOSED | — | ya figura como IMPLEMENTED en `db466d2` | DESCARTADO CON JUSTIFICACIÓN (resuelto antes) |
| R-10 | Velos sumados de wrappers y host | — | solo visual, P3; requiere revisión de diseño | DESCARTADO CON JUSTIFICACIÓN (aplazado) |
| C-08 / R-13 | GameMode con cualquier fullscreen, también un vídeo | `d76a293` | instantánea real: vídeo `focused_game=false`, tag `game` → `true` | IMPLEMENTADO Y VERIFICADO · Warframe: PENDIENTE DE VALIDACIÓN FÍSICA |
| R-14 | La dGPU despierta por la sesión no se explica | `924dc82` (estado visible) | estados `suspended`/`unavailable` visibles; el motivo depende del equipo | PENDIENTE DE HARDWARE FÍSICO |
| R-15 | Helpers Rust sin `cargo-auditable` | — | herramienta no instalada; instalarla excede el alcance | BLOQUEADO |
| A-PW | PipeWire ausente al arrancar el shell = sin audio toda la sesión | `fa4a07d` | arranque sin PipeWire: FAIL → PASS; caída en vivo: PASS | IMPLEMENTADO Y VERIFICADO |
| A-NM | NetworkManager ausente al arrancar | — | Quickshell elige el backend de red al iniciar | BLOQUEADO (upstream) |
| A-BT / A-UP | BlueZ y UPower: ausentes al arrancar o reiniciados en vivo | — | sin reintento ni relectura del estado en Quickshell 0.3.2 | BLOQUEADO (upstream) |
| B-GPU | Hardware Center: Intel/desconocidas ausentes, ceros inventados, NVIDIA desaparecía si nvidia-smi fallaba | `924dc82`, `375ce3a`, `20ba0e3` | 8 escenarios simulados con capturas; sin llamadas a nvidia-smi sin NVIDIA | IMPLEMENTADO Y VERIFICADO |
| C-09 (hallazgo) | El CLI instalado dependía de python3 por una prueba | `258b157` | `build-native.sh` pasa | IMPLEMENTADO Y VERIFICADO |
| C-09 (hallazgo) | El Dashboard no se abre con hover en el borde superior | — | también en `db466d2` | PENDIENTE (no corregido) |
| C-09 (hallazgo) | Escape no cierra el Dashboard con foco OnDemand de forma fiable | — | también en `db466d2` | PENDIENTE (no corregido) |

## Rendimiento (realm `base`, un monitor, 60 s en reposo, dos rondas)

| | origin/main `db466d2` | rama |
|---|---|---|
| PSS de `qs` | 414–434 MiB | 371–379 MiB |
| Hilos de `qs` | 57–59 | 41–42 |
| CPU en reposo | 0,08 % | 0,10 % |
| `qs ipc` ida y vuelta (mediana, incluye `agent-realm run`) | 107–108 ms | 113–125 ms |

La diferencia de IPC está dentro de la variación del envoltorio `agent-realm run` (~100 ms por llamada).

## Pruebas

- QML: 216 casos en el staging del build.
- Rust: 207 pruebas en 8 crates; contratos legacy de la sonda (`legacy_contracts.py`).
- Go: `go test ./...` en `cortetsu/protocol`.
- `scripts/verification/build-regressions.sh` completo.
- `scripts/features/test-*.py` y `cortetsu/tests/test-*.py` (175 scripts): 126 pasan en la rama y 118 en
  `db466d2`. Los 49 que fallan en la rama también fallan en `db466d2` (pruebas obsoletas respecto al código
  de origin/main, por ejemplo `core/dotfiles.py`, que ya no existe). Las dos regresiones que introdujo el
  cherry-pick de `3ab746a` (`test-native-bottom-hub.py`, `test-cortetsu-session-runtime.py`) están corregidas.

## Validación física pendiente

Escaneo directo, VRR y tearing con fullscreen; suspensión de la NVIDIA y su motivo (R-14); HDMI; teclas
OMEN/Fn; consumo; latencia del panel; GameMode con Warframe.

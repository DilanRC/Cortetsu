# ADR-007: Socket de coordinación `cortetsu.ipc/1`

## Estado

**PROPOSED.** No hay evidencia suficiente para aceptar ni rechazar un coordinador residente. Este ADR fija las opciones, los
hechos verificados y las pruebas que deciden. No se implementa nada (D-01 de `docs/migration/F0/RISKS.md`).

Fecha: 2026-10-20. Base: `main` tras el baseline F0. Plan de referencia: `CORTETSU_MIGRACION_TOTAL_GO_RUST_2026-10-17.md`
§5.1–5.3, §8.5 y §10 (fuera del repo).

## Contexto

Hechos verificados el 2026-10-20 en el equipo de referencia:

| # | Hecho | Fuente |
|---|---|---|
| H1 | Cortetsu no tiene socket propio. El IPC es `qs ipc` hacia el shell y procesos one-shot lanzados desde QML (Python y un binario Rust) | F0 `CONTRACTS.md`, `INVENTORY.md` |
| H2 | Coste de un helper one-shot hoy: Rust `cortetsu-keybinds list` P50 2,0 ms; Python entre 27 ms (`gamemode status`) y 196 ms (`cortetsu status`); suelo del intérprete 11 ms | F0 `BASELINE.md` §2 |
| H3 | Las automatizaciones que necesitan estar vivas ya son servicios residentes **por usuario**: `cortetsu-power-auto` (3,8 MiB PSS, 0,06 % CPU) y `cortetsu-wallpaper-color` (6,6 MiB, 0,28 %), ambos `Type=simple`, `Restart=on-failure` | F0 `BASELINE.md`; unidades en `~/.config/systemd/user/` |
| H4 | `systemctl --user show-environment` contiene **un solo** `HYPRLAND_INSTANCE_SIGNATURE`, `WAYLAND_DISPLAY` y `XDG_RUNTIME_DIR`, y no contiene `XDG_SESSION_ID`. Un servicio de usuario ve la sesión que importó su entorno la última vez | `systemctl --user show-environment` |
| H5 | `XDG_RUNTIME_DIR` (`/run/user/<uid>`) es por usuario: dos sesiones gráficas del mismo usuario lo comparten. Hyprland separa sus sockets por instancia en `$XDG_RUNTIME_DIR/hypr/<firma>/` | F0 `TESTS.md` §2 |
| H6 | `sun_path` admite 107 bytes. Una ruta larga se trunca sin error visible para algunos clientes (H-01 de F0: el QML anidado quedó sin IPC de Hyprland y una prueba pasaba a ciegas). La firma de Hyprland tiene 61–62 caracteres | F0 `TESTS.md` §2; `${#HYPRLAND_INSTANCE_SIGNATURE}` = 61 |
| H7 | Quickshell 0.3.2 expone `Quickshell.Io.Socket`, `SocketServer` y `SplitParser` | `/usr/lib/qt6/qml/Quickshell/Io/quickshell-io.qmltypes` |
| H8 | Los locks de `wallpaper` y `power-auto` son por usuario, no por sesión. EVT-02 (dos sesiones a la vez) está `NOT_TESTED` | F0 `RISKS.md` §4 |
| H9 | `cortetsu.exec/1` **no existe** en el repo ni en el plan. El contrato de ejecución real es `cortetsu-launch-persistent --label L [--working-directory D] -- argv…`, que lanza `systemd-run --user --scope --collect` con unidad `cortetsu-app-<label saneado>-<ns>-<pid>`. No hay versión ni esquema | `cortetsu/bin/cortetsu-launch-persistent` |

## Opciones

### A. Socket por usuario

`$XDG_RUNTIME_DIR/cortetsu/ipc.sock`, un coordinador por UID, activable con `cortetsu-coordinator.socket`.

- A favor: una sola unidad systemd, sin plantillas; coincide con el alcance real de `power-auto`, `wallpaper-color` y sus locks (H3,
  H8); la CLI lo encuentra sin conocer la sesión.
- En contra: con dos sesiones, el coordinador solo conoce una instancia de Hyprland (H4). Todo evento de monitor, foco o workspace
  necesita una clave de sesión en el mensaje, y el coordinador tendría que mantener una conexión a cada `.socket2.sock`. Si no, una
  sesión recibe decisiones tomadas con el estado de la otra. Es el fallo que el plan prohíbe: «nunca buscar la primera instancia
  Hyprland que aparezca».

### B. Socket por sesión gráfica

`$XDG_RUNTIME_DIR/cortetsu/<firma Hyprland>/ipc.sock`, un coordinador por instancia de Hyprland, lanzado desde la sesión (exec del
compositor o `cortetsu-coordinator@<firma>.service` con el entorno pasado explícitamente).

- A favor: aislamiento estructural entre sesiones; el coordinador hereda el `HYPRLAND_INSTANCE_SIGNATURE` correcto sin depender de
  `show-environment` (H4); termina con su compositor.
- En contra: el estado por usuario (perfil de energía, color del wallpaper, archivos de `~/.config/cortetsu`) sigue siendo único.
  Dos coordinadores serían dos escritores sobre el mismo estado salvo que esos dominios sigan en sus servicios por usuario. Ruta:
  `/run/user/1000/cortetsu/` (24) + firma (62) + `/ipc.sock` (9) = 95 bytes; cabe, con 12 de margen, solo si `XDG_RUNTIME_DIR` es el
  real. Bajo un arnés con runtime largo, se repite H-01.

### C. Sin daemon: operaciones por CLI Rust one-shot

Mantener `qs ipc` hacia el shell y sustituir los helpers Python por subcomandos Rust con salida JSON versionada. Las automatizaciones
siguen en los servicios residentes existentes (H3).

- A favor: cero procesos nuevos, cero estado distribuido y ningún problema de sesión nuevo. El coste ya está medido: Rust 2 ms frente a
  27–196 ms de Python (H2). Recuperación trivial: cada invocación es independiente. Es el modo que el plan exige para la recuperación
  offline (§8.5).
- En contra: sin canal de eventos propio. Cada consumidor sondea o tiene su propio watcher. Las políticas que cruzan dominios (HDMI +
  energía + GameMode) no tienen un único dueño que serialice decisiones. Un `state_revision` o una idempotencia entre procesos tendrían
  que vivir en archivos con lock.

### D. Híbrido

C como base. B solo para el dominio que demuestre necesitar eventos entre dominios. El estado por usuario sigue en sus servicios.

## Evaluación por criterio

| Criterio | A (usuario) | B (sesión) | C (CLI) |
|---|---|---|---|
| Aislamiento entre dos sesiones | requiere clave de sesión en cada mensaje y una conexión por Hyprland | estructural | no aplica: cada CLI recibe el entorno de quien la llama |
| Autenticación | `SO_PEERCRED`: mismo UID. No distingue apps del mismo usuario (plan §5.2.2) | igual que A | permisos del proceso que llama. Sin superficie nueva |
| Permisos | directorio `0700` y socket `0600` en `$XDG_RUNTIME_DIR` real; nunca `/tmp` | igual que A | ninguno nuevo |
| Ciclo de vida | `systemd --user` con socket activation; vive más que cualquier sesión | nace y muere con el compositor | por invocación |
| Recuperación tras caída | `Restart=on-failure`; clientes con reconexión y `snapshot`; sin reproducir colas antiguas (§8.5) | igual, más limpieza de un socket huérfano si el compositor muere primero | no hay estado que recuperar; los journals de operación siguen en Rust |
| Versionado | `hello` con `protocol_major` y `protocol_minor` (§5.1); probar QML viejo + coordinador nuevo en rollback | igual | campo `schema` en la salida JSON de cada subcomando; la CLI y el QML de una generación se despliegan juntos |
| Compatibilidad con el lanzador actual (H9) | el socket no debe transportar argv de apps: el lanzamiento sigue por `cortetsu-launch-persistent` (plan §5.2.3, sin `exec` remoto) | igual | sin cambio |
| Riesgo de dos escritores | uno por usuario: bajo | **alto** si toca estado por usuario | igual que hoy |

Sobre H9: el encargo pide compatibilidad con `cortetsu.exec/1`. Ese contrato no existe. Si se quiere un contrato versionado de
lanzamiento, debe definirse en F1 como esquema de `cortetsu-launch-persistent` (argv, etiqueta, directorio, código de salida 2 para
uso incorrecto) y **ninguna opción de socket debe aceptar argv arbitrario**. El lanzamiento queda fuera del socket en las tres
opciones.

## Decisión provisional

Ninguna opción queda aprobada. Inclinación provisional, condicionada a P1–P4: **D**, con C como valor por defecto y un coordinador
solo si P3 demuestra que hace falta. A queda descartada mientras H4 no tenga solución probada, porque mezcla sesiones por
construcción. El lenguaje del coordinador (Go, Rust u otro) no es un criterio de este ADR.

## Pruebas necesarias para decidir

| ID | Prueba | Decide | Criterio |
|---|---|---|---|
| P1 | EVT-02 real: dos sesiones Hyprland del mismo usuario (TTY + sesión principal, o dos asientos), con `cortetsu-shell` en ambas. Registrar qué instancia ven `qs ipc`, `power-auto` y `wallpaper-color`, y qué `HYPRLAND_INSTANCE_SIGNATURE` queda en `show-environment` tras cada login | A frente a B, y si el estado por usuario ya se mezcla hoy | ninguna acción de una sesión cambia la otra; si hoy ya se mezclan, es un defecto previo a cualquier socket |
| P2 | Prototipo desechable de `SocketServer` (Quickshell) o de un listener mínimo con `SO_PEERCRED`, fuera del árbol de producto, en el arnés con runtime corto: rechazo de otro UID, límite de 1 MiB, cliente lento sin bloquear eventos y reconexión tras `kill -9` | viabilidad de A/B con Quickshell 0.3.2 | las 4 condiciones en PASS, con mutantes |
| P3 | Inventario de las políticas entre dominios que pide F1 (HDMI + energía + GameMode): cuáles necesitan serializar decisiones de dos fuentes de eventos y cuáles se resuelven en un solo servicio existente | C frente a coordinador | si ninguna necesita dos fuentes a la vez, C basta |
| P4 | Coste residente de un coordinador en reposo frente a H3, medido con `docs/migration/F0/tools/bench_resident.py` (4 × 120 s) | si un residente nuevo cabe en el presupuesto | PSS y CPU en reposo menores que la suma de lo que sustituye (plan §10) |

Con P1–P4 en evidencia, este ADR pasa a `ACCEPTED` o `REJECTED` en un cambio propio.

## Consecuencias mientras siga en PROPOSED

- F1 puede escribir `contracts/*.json` de salidas de CLI con campo `schema`, que sirven en las tres opciones.
- Ningún dominio que dependa del socket pasa a F2 o posterior.
- Toda prueba nueva que abra sockets usa un `XDG_RUNTIME_DIR` corto propio (lección de H-01).

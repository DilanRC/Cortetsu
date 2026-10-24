# ADR-007: CLI por operación y coordinador `cortetsu.ipc`

## Estado

**IMPLEMENTED — opción D, con coordinador por sesión solo para observación y políticas consentidas.** La CLI por operación sigue
siendo el camino normal; el coordinador Go no ejecuta aplicaciones ni recibe órdenes arbitrarias. Las pruebas físicas de dos
sesiones y el coste en reposo siguen pendientes, así que este estado no afirma que esas validaciones estén completas.

Fecha de decisión: 2026-10-24. Código: `cortetsu/protocol/daemon`, `cortetsu/protocol/ipcv1`,
`cortetsu/protocol/observehypr` y `cortetsu/modules/CortetsuPolicyBridge.qml`. CLI: `scripts/cortetsu` y helpers nativos.
Contratos de helpers: [`docs/migration/F0/CONTRACTS.md`](../migration/F0/CONTRACTS.md).

## Contexto

Hechos históricos verificados el 2026-10-20 en el equipo de referencia. H1 quedó superado por la implementación descrita abajo:

| # | Hecho | Fuente |
|---|---|---|
| H1 | En ese baseline, Cortetsu no tenía socket propio. El IPC era `qs ipc` hacia el shell y procesos one-shot lanzados desde QML | F0 `CONTRACTS.md`, `INVENTORY.md` |
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

## Decisión

**D**, con C como camino por defecto y B limitado a observación/políticas por sesión. El coordinador usa un socket Unix privado
por sesión, valida la firma de Hyprland, publica metadatos `cortetsu.ipc` y no acepta `argv` para lanzar procesos. El listener
`ipcv1` ofrece solo las operaciones del contrato y aplica límites de peer, frame y conexión. Los servicios con estado por usuario
siguen fuera del coordinador.

La CLI `cortetsu shell inspect` devuelve un snapshot de solo lectura con `schema_version: 1`; superficies y foco se calculan en
el shell de Quickshell. El inspector no crea un segundo canal de control.

**R-11:** Quickshell 0.3.2 mantiene una sola conexión a `.socket2.sock` y no la reabre al desconectarse. El observador Go de
`observehypr` sí reconecta con backoff acotado y exige un snapshot nuevo por época, pero ese snapshot no repara el estado interno
de `Quickshell.Hyprland`. `inspect` declara que el estado de conexión de Quickshell no se expone a QML y que el cliente no tiene
reconexión; no presenta al observador Go como failover del modelo QML. Corregir Quickshell queda fuera de este repo y debe
validarse en upstream.

## Validación pendiente

| Estado | Prueba | Evidencia requerida |
|---|---|---|
| PENDIENTE | P1: dos sesiones Hyprland simultáneas del mismo usuario | Confirmar que cada coordinador y cada shell observan solo su sesión |
| CÓDIGO + UNIT TESTS | P2: listener y reconexión | Pruebas Go de aislamiento, límites y `resync_required`; no sustituyen la prueba física de dos sesiones |
| IMPLEMENTADO | P3: políticas entre dominios | El coordinador consume snapshots de Hyprland y D-Bus; las reglas requieren consentimiento |
| PENDIENTE | P4: coste residente | Medición PSS/CPU en reposo frente a los servicios que reemplaza |

## Consecuencias operativas

- El shell sigue usando `qs ipc` para acciones interactivas; el coordinador no transporta órdenes de ventanas ni `argv` arbitrario.
- Cada observador recibe la firma de sesión explícita y vuelve a leer el dueño desde el socket de comandos después de reconectar.
- Toda prueba nueva que abra sockets usa un `XDG_RUNTIME_DIR` corto propio (lección de H-01).

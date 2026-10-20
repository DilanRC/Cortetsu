# F0 · Inventario arquitectónico y de procesos

Commit medido: `0a803e7` (main = origin/main). Entre `71e13b4`, la base del primer inventario del 2026-10-19, y `0a803e7`
solo cambiaron dos archivos de prueba (`git diff --stat 71e13b4 0a803e7`), así que las magnitudes siguen vigentes.
Fuente reproducible: `python3 -I tools/inventory.py . > evidence/run-20261020/inventory.json`. Columnas «Consumidores» y «Pruebas»:
`grep -w` del nombre del helper en QML/JS no de prueba y en `scripts/features`, `scripts/integration` y `cortetsu/tests`. Es una
coincidencia de texto: sirve como pista, no como grafo de llamadas.

## Magnitudes

| Lenguaje | Archivos | LOC | Nota |
|---|---:|---:|---|
| Python | 301 | 10.852 en bin/core/services | 277 `.py` (226 en `scripts/features`, 11 históricos en `docs/history`) y 24 sin extensión en `cortetsu/bin/` |
| QML | 496 | 65.041 | |
| Rust | 21 `.rs` + 1 `Cargo.toml` | 5.527 | crate `cortetsu/keyboards` → binario `cortetsu-keybinds` |
| Lua | 19 | 2.699 | config de Hyprland (`dotfiles/`, `config/hypr-user.lua`) |
| Shell | 37 | — | `scripts/cortetsu` (CLI) e instaladores |
| Go | 0 | 0 | instalado (1.27.1), sin uso |
| Unidades systemd de usuario | 3 | — | `config/systemd/user/` |

## Procesos persistentes de la sesión real (2026-10-20, solo lectura)

| Unidad | Proceso | RSS | Origen |
|---|---|---:|---|
| `cortetsu-shell` | `qs -p ~/.config/quickshell/cortetsu/current -n` | 134 MiB | unidad |
| | `dbus-monitor --system … login1.Manager` | 2,4 MiB | QML `CortetsuSession` (señales de logind) |
| | `nmcli monitor` | 4,5 MiB | QML `ConnectivityNmAdapter` |
| | `systemd-inhibit --what=sleep --mode=delay … sleep infinity` | 2,9 MiB | QML `IdleMonitors`: lock antes de suspender (retiene un delay lock de logind) |
| | `python3 cortetsu-pomodoro daemon` | 8,1 MiB | QML `Focus` |
| `cortetsu-power-auto` | `python3 cortetsu-power-auto` | 8,7 MiB | unidad |
| `cortetsu-wallpaper-color` | `python3 cortetsu-wallpaper-color-daemon` | 13,6 MiB | unidad |

En total hay 8 procesos persistentes. En reposo, ninguna unidad crea procesos transitorios (BASELINE.md §2). Los sondeos
periódicos de QML dependen de la visibilidad (`running: root.visible` o `root.active`), así que con todo cerrado no se ejecutan.

## Entrypoints de producción por dominio

Coste: **S** < 150 LOC sin efectos externos · **M** efectos locales o archivos · **L** transacciones o integración con
Hyprland o D-Bus · **XL** transaccional y sensible al hardware o a secretos. Frecuencia: **evento** = cuando el usuario actúa ·
**apertura** = al abrir la superficie · **sondeo N s** = temporizador activo solo con la superficie visible · **residente**.

| Dominio | Entrypoint | Lang | LOC | Consumidores | Efectos / dependencias | Persistencia | Frecuencia | Pruebas (archivos) | Coste | Destino |
|---|---|---|---:|---|---|---|---|---:|---|---|
| Generaciones | `scripts/cortetsu` | bash | 635 | usuario, instalador | qs, systemctl, cargo | — | evento | gate | L | portar (CLI) |
| Generaciones | `core/system.py`, `core/dotfiles.py`, `core/generation_gc.py` | py | 293/507/535 | CLI | escribe generaciones | `~/.local/share/cortetsu/{system,dotfiles}/builds`, `current`/`previous` | evento | recovery (fuera de gate) | XL | portar |
| Generaciones | `build-runtime.sh`, `rollback-runtime.sh`, `install*.sh` | sh | 315/55/5 | instalador | cargo test, gate | `builds/<id>`, lock | evento | 15 | L | portar |
| Diagnóstico | `core/doctor.py` | py | 128 | CLI, QML | systemctl, secret-tool | — | evento | sí | M | portar |
| Tema | `core/theme.py`, `cortetsu-scheme`, `-scheme-posthook` | py | 593/142/89 | `CortetsuColours`, `Schemes`, `M3Variants`, startup | hyprctl | `~/.local/state/cortetsu/scheme*` | evento | 8 | M | portar |
| Wallpaper | `cortetsu-wallpaper-color-daemon` | py | 122 | **unidad** | /proc, stat; lanza apply | `$XDG_RUNTIME_DIR/cortetsu-wallpaper-color-daemon/{lock,last.hash}` | residente | 3 | M | portar |
| Wallpaper | `cortetsu-wallpaper-{colours,select}`, `-apply-wallpaper-colors` | py/sh | 86/33/15 | `CortetsuWallpapers` | matugen vía scheme | `~/.local/state/cortetsu/wallpaper/path.txt` | evento | 7 | S | portar |
| Ciclo de vida | `core/shell_lifecycle.py`, `core/migrate_*.py` | py | 175/188/130 | CLI | qs, systemctl | migraciones con backup | evento | sí | M | portar o retirar tras la migración única |
| Importadores | `core/import_{hyprland,fish,desktop}.py` + wrappers | py | 320/279/397 | CLI, CI | — | — | evento | 0 directos | M | portar |
| GameMode | `cortetsu-gamemode` | py | 289 | `GameMode.qml`, startup | hyprctl eval (Lua) | `$XDG_RUNTIME_DIR/cortetsu-gamemode-<HIS>.json` + `.lock` | evento + `status` al iniciar | 2 | L | portar |
| Atajos | `cortetsu-keybinds` (crate) | **rust** | 5.527 | `KeyboardsBackend` (watch, sondeo 0,5 s activo), `ShortcutsSection` | hyprctl, /dev/input, setpriv | `~/.config/cortetsu/keyboards.json`, `keybinds.lock` | apertura + watch | cargo test + 4 integración | — | **ya portado** |
| Display | `cortetsu-display-{probe,plan,presets,transaction,persist,workspaces}` | py | 234/221/80/397/377/134 | `Editor`, `PreviewControls`, `DisplayPresets`, startup | hyprctl eval, DRM sysfs | transacción en `$XDG_RUNTIME_DIR`; `~/.config/cortetsu/display-persisted.json`, bloque marcado en `~/.config/hypr/hypr-user.lua`, snapshots | apertura + evento | 0–3 por helper (`plan`: 0) | XL | portar |
| Energía | `cortetsu-power-auto` | py | 247 | **unidad** | powerprofilesctl | `$XDG_RUNTIME_DIR/cortetsu-power-auto-state.json` | residente | 4 | L | portar |
| Energía | `cortetsu-power-auto-control` | py | 250 | `PowerAutomationPage` (sondeo 3,5 s visible) | powerprofilesctl, systemctl | `~/.config/cortetsu/power-auto.json` (**se reescribe en cada `status`**) | sondeo | 3 (1 fuera de gate) | M | portar |
| Hardware | `cortetsu-hardware-probe` | py | 760 | `HardwareTelemetry` (sondeo 1,5 s activo), `Gpu` (3 s con consumidores) | sysfs, /proc; nvidia-smi solo con la dGPU activa | `$XDG_RUNTIME_DIR/cortetsu-hardware-probe-state.json` | sondeo | 6 | L | portar |
| Hardware | `cortetsu-hardware-power` | py | 360 | `EnergyPage` (sondeo 2 s visible), `PowerPage` | powerprofilesctl, nvidia-smi | — | sondeo | 3 | L | portar |
| Hardware | `cortetsu-nvibrant` | py | 194 | `Nvibrant` | nvibrant (DRM NVIDIA) | `~/.local/state/cortetsu/nvibrant.json` + lock | evento | 1 (fuera de gate) | M | portar |
| Notificaciones | `cortetsu-notifications` | py | 153 | `CortetsuNotifications`, `Notifs` | — (servidor D-Bus en QML) | `~/.local/state/cortetsu/{notifs,notification-status}.json` | evento | 3 | M | portar |
| Focus | `cortetsu-pomodoro` | py | 259 | `Focus`, BottomHub | — | `~/.local/state/cortetsu/pomodoro-state*` | **residente** (daemon hijo del shell) | 5 | M | portar |
| Calendario | `cortetsu-calendar` | py | 585 | BottomHub, calendar `Content` | secret-tool, HTTPS Google | caché + Secret Service | apertura (`sync`) | 3 | XL (OAuth) | portar |
| Conectividad | `services/ConnectivitySecret.py` | py | 115 | QML | NetworkManager (secreto por stdin) | perfil NM | evento | sí | XL (secretos) | portar |
| Conectividad | `nmcli monitor`, `busctl`, `bluetoothctl` | externo | — | `ConnectivityNmAdapter`, `ConnectivityBluetooth`, `CortetsuSettingsNetwork` | NM, BlueZ | — | residente + evento | sí | — | externo |
| Medios | `cortetsu-record` | py | 239 | `CortetsuRecorder` (sondeo 0,3/1 s grabando) | gpu-screen-recorder, gdbus | PID propio | evento | 2 | L | portar |
| Captura | `cortetsu-area-capture` | py | 63 | `Picker` | notify-send | — | evento | 2 | S | portar |
| Arranque | `cortetsu-startup` | py | 739 | `StartupPage` | busctl, nmcli, systemctl, hyprctl, brightnessctl | inventario de inicio | apertura | 2 | L | portar |
| Apps | `cortetsu-launch-persistent` | sh | 46 | `CortetsuProcessLauncher` | systemd-run (scope) | scope transitorio | evento | 5 | S | portar |
| Apps | `cortetsu-prune-applications`, `cortetsu-emoji` | py | 74/141 | instalador, CLI | — | `apps.sqlite`, datos emoji | evento | 1/1 | S | portar |
| Build | `compose-panels.py`, `check-bottom-hub-target.py`, `normalize-*.py`, `migrate-bottom-hub-from-main.py` | py | 61–351 | build, tests | — | — | build | 1–5 | S | retirar al terminar la migración de fuentes |
| Servicio | `cortetsu-shell.service` | unit | 15 | graphical-session | qs | — | residente | sí | — | conservar (QML) |
| Servicio | `cortetsu-power-auto.service`, `cortetsu-wallpaper-color.service` | unit | 13/15 | graphical-session | Python | — | residente | sí | — | cambiar el binario, mantener la unidad |
| Config | `dotfiles/home/.config/hypr/**/*.lua`, `config/hypr-user.lua` | lua | 2.699 | Hyprland | — | generación de dotfiles | carga | sí | — | conservar (configuración, no lógica) |
| Tests/evals | `scripts/features/*`, `scripts/integration/*`, `cortetsu/tests/*` | py/qml | 259 | gates | ver TESTS.md | — | gate | — | L | portar al final |
| Histórico | `docs/history/**/*.py` | py | 11 | nadie | — | — | — | — | — | archivar |

## Contratos IPC (sin socket propio)

- **`qs ipc`**: 20 targets (`evidence/run-20261020/ipc-show.txt`), entre ellos `drawers`, `bottomHub`, `gameMode`, `keepAwake`, `lock`,
  `hardware`, `display`, `clipboard`, `keyboards`, `wallpapermanager`, `overview`, `calendar`, `picker`, `brightness`, `notifs`,
  `mpris`, `customDock` y `cortetsu-shell`. Las 7 superficies medidas exponen `open/close/isOpen`. `picker` no tiene `isOpen`.
- **QML → helper**: `Process` con argv fijo. La respuesta es JSON por stdout (CONTRACTS.md). No hay bus ni socket de Cortetsu.
- **Hyprland**: IPC `.socket.sock`/`.socket2.sock` (Quickshell) y `hyprctl eval` (gamemode, display). Atajos globales:
  `cortetsu:<nombre>` (`CortetsuShortcut`).
- **D-Bus de sesión**: Cortetsu es dueño de `org.freedesktop.Notifications` (QML) y del watcher SNI. En el bus de sistema solo
  lee: logind (`dbus-monitor`), NetworkManager y BlueZ.

## Dependencias entre módulos (resumen)

```
Hyprland ──IPC──▶ qs (Cortetsu QML) ──Process/argv──▶ cortetsu-* helpers ──▶ hyprctl eval · sysfs · NM · logind · secret-tool
                       │                                     │
                       ├── D-Bus sesión (notificaciones, SNI) └── estado: $XDG_RUNTIME_DIR, ~/.config/cortetsu, ~/.local/state/cortetsu
systemd --user ──▶ cortetsu-shell · cortetsu-power-auto · cortetsu-wallpaper-color
scripts/cortetsu ──▶ core/*.py ──▶ generaciones (~/.local/share/cortetsu) ──▶ symlink current ──▶ qs
```

Externos que no son del repo y que interactúan con Cortetsu: `~/.local/bin/hyprctl` (wrapper personal de Lua que delega en
`/usr/bin/hyprctl` y hereda el entorno, verificado) y `~/.local/bin/wallpaper-engine-render-daemon`, que provoca el falso positivo
descrito en CONTRACTS.md §5.

**Gate de inventario F0:** los 301 entrypoints Python tienen una fila de destino, individual o por grupo. Los 1.119 archivos
rastreados tienen como último autor a Dilan (`git log`), así que el gate «cero destinos sin propietario» se cumple.

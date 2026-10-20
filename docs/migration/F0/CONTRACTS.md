# F0 · Contratos funcionales observados (0a803e7)

Cada contrato tiene dos tipos de fuente: **[obs]** observado en esta máquina el 2026-10-19/20 y
**[doc]** documentado en el repo pero no reejecutado aquí. Las formas JSON (claves y tipos, sin valores
personales) están en `evidence/run-20261020/contract-shapes.json` y se regeneran con `tools/contract_shapes.py`.

## Códigos de salida y forma de respuesta [obs]

| Invocación | rc | stdout | stderr |
|---|---:|---|---|
| `cortetsu-gamemode status` | 0 | `{state, enabled, ok, error}` | — |
| `cortetsu-gamemode <inválido>` | 2 | vacío | `usage: cortetsu-gamemode enable\|disable\|recover\|status [--keyword]` |
| `cortetsu-keybinds list` | 0 | `{bindings:[{active, appQuery, chord, command, conflicts, …}], …}` | — |
| `cortetsu-keybinds <inválido>` | 1 | `{ok:false, kind, protocol, error:{code, message}}` (error en JSON) | — |
| `cortetsu-record status` (sin grabar) | **1** | vacío | — |
| `cortetsu-record <inválido>` | 2 | vacío | uso argparse |
| `cortetsu-display-probe` | 0 | `{capability_policy, drm:[…], …}` | — |
| `cortetsu-display-transaction status` | 0 | `{active:bool}` | — |
| `cortetsu-power-auto-control status` | 0 | `{config:{ac_profile, battery_profile, enabled, low_battery_enabled, …}, …}` | — |
| `cortetsu-power-auto-control <inválido>` | 2 | **estado completo en JSON** (no hay mensaje de uso) | — |
| `cortetsu-hardware-probe` | 0 | `{battery, cpu, …}` | — |
| `cortetsu-scheme list` | 0 | mapa esquema → variante → tokens | — |
| `cortetsu doctor --json` | 0 | `{schema:int, checks:[{name, status, required, detail}]}` | — |

Las convenciones son heterogéneas: Rust devuelve el error como JSON con rc 1, la mayoría del Python
responde con uso de argparse y rc 2, y `record status` usa rc 1 para «no grabando». Un reemplazo debe
reproducir estas diferencias o cambiar a la vez el consumidor QML con test (paridad deliberada, cap. 12.3
del estudio).

## Persistencia y estado [obs salvo indicación]

| Ruta | Dueño | Tipo |
|---|---|---|
| `~/.local/share/cortetsu/{builds,dotfiles/builds,system/builds}/<id>` | CLI/instalador | generaciones inmutables, `current`/`previous` |
| `~/.config/quickshell/cortetsu/{current,previous}` | constructor | symlinks atómicos |
| `$XDG_RUNTIME_DIR/cortetsu-gamemode-<HIS>.json` + `.lock` | gamemode | transacción por instancia de Hyprland (volátil) |
| `$XDG_RUNTIME_DIR/cortetsu-hardware-probe-state.json`, `cortetsu-power-auto-state.json` | probe / power-auto | caché volátil |
| `$XDG_RUNTIME_DIR/cortetsu-wallpaper-color-daemon/{lock,last.hash}` | watcher | instancia única (flock) + hash de fuentes |
| `~/.config/cortetsu/power-auto.json` | power-auto-control | preferencia; **se reescribe en cada `status`** |
| `~/.config/cortetsu/keyboards.json`, `keybinds.lock` | cortetsu-keybinds | [doc] códigos probados por modelo; lock exclusivo |
| `~/.config/cortetsu/preferences.json` | QML | preferencias (idleTimeouts, etc.) [doc] |
| `~/.local/state/cortetsu/{notifs.json, notification-status.json}` | notifications/QML | historial/DND |
| `~/.local/state/cortetsu/{pomodoro-state*, nvibrant.json, apps.sqlite, wallpaper/path.txt}` | helpers respectivos | estado persistente |

## Máquinas de estado y recuperación

**GameMode [doc + obs en Hyprland anidado]:** `INACTIVE / APPLYING / ACTIVE / RESTORING / RECOVERY_REQUIRED / UNKNOWN`.
- `enabled` es true solo en `ACTIVE`, y `recover` nunca apaga un modo activo.
- Al restaurar, una opción vuelve a su original solo si sigue con el valor de juego.
- Un archivo ilegible da `UNKNOWN` y el helper rechaza toda orden.
- La UI no muestra «on» hasta que el helper confirma.
- Un helper que no arranca deja `UNKNOWN`, no `busy`.
- 5 toggles rápidos no se solapan y gana el último.

`test-gamemode-runtime.py` verificó todo esto el 2026-10-19 en un compositor anidado (PASS, 68 s).

**Generaciones [doc + obs]:** `cortetsu rollback` valida la generación anterior (shell y hashes de dotfiles) antes de mover nada.
Si falla a mitad, restaura los `current` previos. `cortetsu system verify` ⇒ `PASS: system generation …/20261017-220915-104304` [obs].
`cortetsu gc` es de solo lectura sin `--apply --plan-id`.

**Display [doc]:**
- La preview pasa por validar → snapshot → estado en runtime → aplicar → verificar → watchdog separado.
- El watchdog revierte a los 15 s sin `Keep`.
- `Keep` dura solo la sesión de Hyprland.
- **Persistencia [código, resuelto el 2026-10-20]:** existe y está conectada. `PreviewControls.qml` invoca
  `~/.local/bin/cortetsu-display-persist`, que escribe un bloque marcado `-- CORTETSU_DISPLAY_MANAGED` en
  `~/.config/hypr/hypr-user.lua`, guarda `~/.config/cortetsu/display-persisted.json` y crea snapshots en
  `~/.local/share/cortetsu/upstream/snapshots`. `docs/DISPLAY_MANAGER.md` está desfasado: usa rutas de Caelestia y presenta la
  persistencia como «próximo bloque». No se ejecutó (escribiría la configuración real).

**Atajos (Rust) [doc]:** protocolo 1 compatible con el helper Python (ids con el mismo SHA-256, mensajes y códigos).
- Escritura con snapshot, validación Lua, recarga y rollback.
- `cortetsu:keyboards` registrado en vivo [obs, `hyprctl globalshortcuts`].

**Notificaciones [doc]:** el servidor D-Bus vive en QML (no se debe instalar un segundo daemon).
`test-notification-owner.py` [obs PASS]: el bus pertenece a `cortetsu-shell` y el instalador solo enmascara `mako.service`.

## 5. Comportamientos anómalos encontrados en F0

1. **Escritura en una lectura:** `cortetsu-power-auto-control status` llama a `save_config()`, que hace un replace atómico de
   `power-auto.json` en cada consulta. El SHA-256 no cambia, pero el mtime sí (evidencia: `evidence/run-20261020/latency.json` → `state_changed_during_run`).
   Es inocuo para los datos, pero supone una escritura en disco por cada sondeo del QML. Un reemplazo puede cambiarlo, con test.
2. **Falso positivo de Wallpaper Engine:** `engine_running()` considera que Wallpaper Engine corre si **cualquier** proceso del usuario
   tiene `linux-wallpaperengine` en su línea de comandos. El script personal `~/.local/bin/wallpaper-engine-render-daemon` ejecuta
   periódicamente `pgrep -af '(^|/|\./)linux-wallpaperengine( |$)'`, cuya propia línea de comandos coincide, así que el vigilante
   vuelve a aplicar colores sin cambio real. Se observó en 43 eventos en 370 s (auditoría del 2026-10-19 fuera del repo: `~/Documentos/Auditorias/Cortetsu-F0-2026-10-19/evidence/wpe-cmdline-sampler.log`; se reproduce con `tools/cmdline_sampler.py`), con un
   coste de 0,26–2,64 % de un núcleo frente al 0,24 % base y 0–16 procesos transitorios por ventana de 120 s.
   La cadena de padres se trazó hasta Hyprland → `wallpaper-engine-render-daemon`. No se corrigió (fuera de alcance).
3. **(Cerrado)** `test-global-shortcut-receivers.py` daba un falso negativo con los nombres reenviados
   (`name: root.shortcutName`). Se corrigió en el PR #46, que ya está en `0a803e7`. Hoy da PASS (TESTS.md).
4. **Respuesta de GameMode sin validar su forma [obs en el arnés]:** `GameMode.finish()` acepta cualquier JSON que se pueda
   parsear. Con `{}` (un helper que responde sin `state`), `status = reply.state` produce `Cannot assign [undefined] to QString`
   (`services/GameMode.qml:68`) y el estado anterior se queda. Si el JSON no se puede parsear, el resultado es `UNKNOWN`, como
   está previsto. El helper real siempre emite `state` [obs]. Un reemplazo Rust/Go debe emitir siempre `{state, enabled, ok,
   error}`, o el QML debe normalizar la respuesta (decisión de F1).
5. **`picker` [obs]:** expone `open` sin `isOpen`, y tras `close` la capa `cortetsu-area-picker` sigue mapeada en el arnés. Es la
   captura de área: no se incluyó en las medidas de superficie.

## Errores y degradación QML (de los tests runtime [obs PASS])

- Ajustes deja el control en el valor real tras un fallo y muestra por qué.
- Un backend no disponible se muestra como tal y el resto sigue funcionando.
- Un cambio externo llega a la página abierta (`test-cortetsu-settings-runtime.py`).
- GameMode notifica los errores con `notify-send`.

## GameMode sin helper [obs en el arnés, 2026-10-20]

Sin `cortetsu-gamemode` en el PATH del shell anidado, `qs ipc call gameMode status` devuelve `UNKNOWN` y el registro de stubs
no contiene ninguna llamada a `cortetsu-gamemode` (`evidence/run-20261020/nested/nested-bench.json → gamemode`). El helper instalado no es
alcanzable porque `PATH = <stubs>:/usr/bin`. `test-gamemode-runtime.py` (PR #45) comprueba lo mismo con su propio arnés.

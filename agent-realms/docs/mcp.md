# Servidor MCP

`agent-realm-mcp` expone un realm a clientes MCP (Claude Code, Codex CLI u otros) por stdio. Es una capa fina sobre el runtime: ratón, teclado, captura y ciclo de vida usan las mismas funciones que la CLI (`input.py`, `capture.py`, `runtime.py`), a través de `agent.py`.

## Instalación

```sh
scripts/setup-mcp-venv.sh        # crea .venv con mcp==2.3.0 (no toca el sistema)
```

`bin/agent-realm-mcp` usa `.venv/bin/python` si existe. El runtime y la CLI siguen sin dependencias externas.

## Perfiles: qué realm controla cada cliente

La asociación cliente → realm no la decide el modelo. Vive en `~/.config/cortetsu-agent-realms/profiles.json`, que escribe el usuario:

```sh
agent-realm profile set claude --realm claude                       # observe,control,admin por defecto
agent-realm profile set codex  --realm codex --capabilities observe,control
agent-realm profile set visor  --realm demo  --capabilities observe --no-autostart
agent-realm profile list
agent-realm profile remove visor
```

| Campo | Efecto |
| --- | --- |
| `realm` | único realm del perfil; dos perfiles no pueden compartirlo |
| `capabilities` | `observe` (estado, capturas, ventanas, logs), `control` (entrada, apps, ventanas), `admin` (`realm_start`, `realm_stop`) |
| `lifecycle` | `persistent`: desconectar el cliente no toca el realm. `ephemeral`: el servidor detiene al salir el realm que él inició y borra su HOME |
| `autostart` | inicia el realm si no existe; nunca reinicia uno detenido con `realm_stop` o `agent-realm stop` |
| `start` | `width`, `height`, `lua`, `workspace`, `readonly_workspace`, `memory_max`, `cpu_quota`, `tasks_max` |

El archivo se rechaza si es un symlink o no pertenece al usuario, si el grupo u otros pueden escribirlo a él o a su directorio, si tiene claves desconocidas o si dos perfiles comparten realm. Las apps de un realm no lo ven: su HOME es privado y `~/.config` del anfitrión no se monta.

El servidor recibe solo `--profile <nombre>` en sus argumentos de lanzamiento. **Ninguna herramienta acepta un nombre de realm**, y solo se registran las herramientas que el perfil permite: un perfil `observe` no ve `pointer` ni `keyboard` en `tools/list`, y llamarlas por nombre falla.

## Herramientas

| Herramienta | Capacidad | Qué hace |
| --- | --- | --- |
| `realm_status` | observe | binding, estado, monitores, ventana enfocada, número de apps. No inicia nada |
| `realm_diagnose` | observe | herramientas presentes, PSS/CPU/procesos, observador, últimas líneas de log |
| `realm_logs` | observe | `source` = all, supervisor o hyprland; `tail` ≤ 500 |
| `realm_start` | admin | inicia o reutiliza el realm sano; recupera una sesión caída antes de iniciar |
| `realm_stop` | admin | detiene realm y apps; queda detenido hasta `realm_start` |
| `screenshot` | observe | PNG + `frame_id`, resolución original y entregada, escala, región y monitor |
| `wait_for_change` | observe | espera a que cambien los píxeles (hasta 60 s); cancelable |
| `window_list` | observe | ventanas con dirección, clase, título, geometría y foco |
| `window_focus` / `window_close` | control | por dirección `0x…`; hyprlang o Lua según el realm |
| `app_launch` | control | argv sin shell; modo con scope (devuelve `app_id`) o `compositor_child` |
| `app_list` / `app_close` | observe / control | apps con scope vivas; cerrar detiene su scope entero |
| `pointer` | control | `move`, `click`, `double_click`, `drag`, `scroll` |
| `keyboard` | control | `key` (keysym o chord: `Return`, `CTRL+L`) o `type` (texto literal) |
| `services_status` | observe | servicios simulados: escenario, estado y grafo de audio en vivo ([simulation.md](simulation.md)) |
| `services_simulate` | control | `apply` escenario, `set` asignaciones, `event`, `reset` o `stop` |

Los esquemas limitan rangos y formatos: coordenadas de 0 a 16384, direcciones `^0x[0-9a-f]+$`, monitores `^[A-Za-z0-9_-]+$` y argv de 1 a 64 elementos. Los argumentos inválidos no llegan al backend.

## Coordenadas

`screenshot(max_width=640)` sobre un monitor de 1280×800 devuelve una imagen de 640×400 con `scale = 0.5` y su `frame_id`. Al pasar ese `frame_id` a `pointer`, `x`/`y` son píxeles de esa imagen y el servidor los transforma a coordenadas del escritorio del realm, contando el origen del monitor, la región y la escala HiDPI. El servidor rechaza:

- puntos fuera de la imagen (`out_of_bounds`; nunca se recortan al borde);
- un `frame_id` desconocido o fuera de los 16 últimos (`unknown_frame`);
- un frame de otra sesión del realm o de un monitor cuya geometría cambió (`stale_frame`).

Sin `frame_id`, las coordenadas son del escritorio del realm y deben caer dentro de un monitor.

## Errores

Cada fallo devuelve `isError: true` con contenido estructurado:

```json
{"error": {"code": "realm_stopped", "message": "el realm se detuvo explícitamente; no se reinicia solo",
           "hint": "llama a realm_start si quieres reanudarlo"}}
```

Códigos: `forbidden`, `invalid_argument`, `not_found`, `out_of_bounds`, `unknown_frame`, `stale_frame`, `realm_absent`, `realm_stopped`, `realm_paused`, `realm_degraded`, `realm_unavailable`, `backend_error`, `backend_timeout` e `internal_error` (este solo da el tipo de excepción; la traza va a stderr).

## Ciclo de vida

1. El servidor lee el perfil y fija el realm.
2. Una herramienta que necesita el escritorio comprueba el estado con los metadatos del anfitrión y systemd, nunca con `realm-report.json`.
3. Si está sano, lo reutiliza. Si no existe y `autostart` lo permite, lo inicia. Dos clientes que inician a la vez obtienen el mismo realm: el lock de ciclo de vida serializa y el segundo ve `reused: true`.
4. Si el compositor cayó, devuelve `realm_unavailable`; `realm_start` ejecuta `recover` y vuelve a iniciar.
5. Un realm detenido explícitamente devuelve `realm_stopped` y no se reinicia solo.
6. Reconectar el cliente conserva el realm persistente.

`hyprctl` siempre recibe `-i <firma>`. Antes de llamarlo se verifica que `<runtime del realm>/hypr/<firma>/.socket.sock` sea un socket propio, de modo que un error de descubrimiento no puede acabar en el Hyprland del anfitrión. La entrada usa los protocolos virtuales del compositor del realm (`zwlr_virtual_pointer_v1`, `virtual-keyboard`); no hay uinput ni ydotool. El fd 1 del servidor queda reservado para JSON-RPC: los subprocesos heredan stderr como stdout.

## Claude Code

El repositorio incluye `.mcp.json` con alcance de proyecto, sin rutas absolutas:

```json
{"mcpServers": {"agent-realms": {"type": "stdio", "command": "./bin/agent-realm-mcp",
                                  "args": ["--profile", "claude"]}}}
```

Al abrir `claude` en la raíz del repo por primera vez, Claude Code pide confiar en el proyecto y aprobar el servidor. Para no depender del diálogo en esta máquina, `.claude/settings.local.json` (ignorado por Git) contiene `"enabledMcpjsonServers": ["agent-realms"]`. `claude mcp get agent-realms` muestra el estado.

Uso sin interfaz (así se verificó):

```sh
claude -p "…" --mcp-config .mcp.json --strict-mcp-config --tools "" --allowedTools mcp__agent-realms
```

## Codex CLI (cliente futuro)

`.codex/config.toml` declara el mismo servidor con el perfil `codex`:

```toml
[mcp_servers.agent-realms]
command = "./bin/agent-realm-mcp"
args = ["--profile", "codex"]
startup_timeout_sec = 20
tool_timeout_sec = 120
```

Codex solo carga `.codex/config.toml` de proyectos de confianza y debe ejecutarse desde la raíz del repo, porque el comando es relativo. Alternativa global: copia el bloque en `~/.codex/config.toml` con la ruta absoluta del checkout. No sustituyas el archivo: las entradas `mcp_servers` existentes (Wolfram, codebase-memory, etc.) deben quedarse.

Estado: la configuración se verificó sin ejecutar Codex. `tests/test_mcp_protocol.py` parsea el TOML, lanza exactamente ese comando desde la raíz del repo y completa el handshake y `tools/list`. Si el cliente pide la versión 2026-07-28 con `initialize`, el servidor negocia 2025-11-25. **Pendiente**: una sesión real de Codex llamando herramientas. Esta misión prohibía ejecutar Codex.

## Seguridad

- El cliente solo controla su realm. Desde el MCP no hay forma de nombrar otro realm ni el compositor del anfitrión.
- Las capacidades se aplican dos veces: en el registro (herramientas ocultas) y en cada llamada.
- Títulos de ventana, logs y capturas los producen apps del realm. Son datos no confiables que llegan al modelo cliente: una app puede titular su ventana con instrucciones. El servidor lo advierte en sus `instructions`; el cliente debe tratarlos como datos.
- `app_launch` ejecuta argv dentro del sandbox del realm (bwrap, sin HOME real ni sockets del anfitrión). No es un shell del anfitrión.

## Pruebas

| Prueba | Cubre |
| --- | --- |
| `tests/test_agent.py` (22) | coordenadas, frames caducados, ciclo de vida, carreras de inicio, capacidades, dispatch Lua/hyprlang, perfiles inseguros |
| `tests/test_mcp_protocol.py` (10, 17 herramientas) | handshake 2025-03-26/06-18/11-25, descubrimiento, esquemas, perfil solo-observe, argumentos inválidos, errores estructurados, reconexión, perfiles manipulados, configs de Claude y Codex |
| `scripts/acceptance-mcp.py` | realm real: inicio, app GTK, captura reducida, move/click/type/Enter verificados por la app, `wait_for_change` positivo y negativo, cancelación, cierre, aislamiento entre realms, reconexión, caída del backend y recuperación, parada explícita, foco del anfitrión |
| Claude Code como cliente | `evidence/mcp-claude-client/transcript-summary.txt` |

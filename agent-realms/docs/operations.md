# Operación: desarrollo, diagnóstico, desinstalación y rollback

## Flujo completo

```sh
./bin/agent-realm doctor                                   # herramientas y namespaces, sin iniciar nada
./bin/agent-realm start codex --width 1440 --height 900    # realm persistente (sin --ephemeral)
./bin/agent-realm observe codex --open                     # visor autenticado en el navegador
./bin/agent-realm simulate codex --scenario charging       # servicios simulados, antes del shell
./bin/agent-realm run --detach --compositor-child codex -- /usr/bin/qs --path /workspace/...
./bin/agent-realm observe codex --revoke                   # corta el acceso del visor
./bin/agent-realm stop codex                               # para todo y revoca el visor
```

Desde un cliente MCP, el perfil sustituye a los nombres: `agent-realm profile set claude --realm claude` y el `.mcp.json` del repo. Ver [mcp.md](mcp.md).

## Desarrollo

| Comando | Qué valida | Tiempo aprox. |
| --- | --- | --- |
| `PYTHONPATH=src python3 -m unittest discover -s tests` | 140 contratos; los de MCP necesitan `.venv`, los de D-Bus PyGObject y `dbus-daemon` | 26 s |
| `scripts/acceptance-dual-realm.sh` | dos realms en paralelo, entrada y foco independientes | 40 s |
| `scripts/acceptance-observer.sh` | observador autenticado, revocación, caída, parada del realm | 30 s |
| `python3 scripts/acceptance-mcp.py` | MCP por stdio de punta a punta, simulación incluida | 60 s |
| `scripts/acceptance-simulation.sh` | servicios simulados, señales y huella del anfitrión | 40 s |
| `CORTETSU_WORKTREE=… scripts/acceptance-simulation-ui.sh` | Cortetsu real con OCR | 90 s |
| `python3 scripts/measure-performance.py` | PSS, CPU, latencias y residuos (`evidence/performance/`) | 60 s |

Reglas del código: el runtime y la CLI usan solo la biblioteca estándar. El SDK MCP vive en `.venv` (`scripts/setup-mcp-venv.sh`). PyGObject solo se importa dentro del realm (`simulation/dbus.py`, `power.py`, `network.py`, `bluetooth.py`, `audio.py`, `daemon.py`, `ctl.py`).

## Diagnóstico

| Síntoma | Comprobación |
| --- | --- |
| el realm no arranca | `agent-realm doctor`, `agent-realm logs <realm>` |
| `degraded` o `stale` | `agent-realm status <realm>`; `stop` y luego `start`, o `recover` si el compositor murió |
| el visor da 401 | ticket caducado (60 s) o sesión revocada: `observe <realm> --open` emite otro |
| el visor no abre | `observe <realm> --status`; `observe <realm> --launch-file` y abre la ruta a mano |
| MCP no conecta | `claude mcp get agent-realms`; `./bin/agent-realm-mcp --profile claude < /dev/null` muestra el error del perfil |
| herramienta MCP con `realm_stopped` | el realm se detuvo a propósito; `realm_start` |
| la UI no ve batería o perfiles | la simulación debe arrancar antes que el shell (Quickshell no reconecta UPower, PowerProfiles ni BlueZ) |
| sin audio en el shell | PipeWire arrancó después del shell: reinicia el shell o lánzalo con `QS_PIPEWIRE_IMMEDIATE_RECONNECT=1` |
| estado de la simulación | `agent-realm simulate <realm> --status` (campo `errors`) |

## Desinstalar los componentes nuevos

Nada de esto toca paquetes del sistema ni servicios del anfitrión.

```sh
./bin/agent-realm observe <realm> --stop             # por cada observador activo
./bin/agent-realm simulate <realm> --stop            # por cada simulación activa
rm -rf .venv                                         # SDK MCP
rm -f .claude/settings.local.json                    # aprobación local del servidor MCP en Claude Code
rm -f ~/.config/cortetsu-agent-realms/profiles.json  # perfiles cliente→realm
rm -f "$XDG_RUNTIME_DIR"/cortetsu-agent-realms/observers/*/.lock   # con los observadores ya detenidos
rmdir "$XDG_RUNTIME_DIR"/cortetsu-agent-realms/observers/* "$XDG_RUNTIME_DIR"/cortetsu-agent-realms/observers \
      "$XDG_RUNTIME_DIR"/cortetsu-agent-realms 2>/dev/null
```

`.mcp.json` y `.codex/config.toml` son archivos del repositorio: desaparecen al volver a una versión anterior. `~/.codex/config.toml` y `~/.claude.json` no se modificaron.

## Rollback

Los cambios están en commits locales sobre `dev`, sin push:

| Commit | Contenido |
| --- | --- |
| `fe9badd` | observador autenticado |
| `46014aa` | integración MCP |
| `a2d26f7` | servicios simulados |

```sh
git switch dev
git log --oneline b7436fc..HEAD            # commits de esta misión
git revert --no-edit <commit>...           # deshace uno o varios, conservando historia
# o bien, para probar la versión anterior sin tocar dev:
git switch --detach b7436fc
```

Antes de volver a `b7436fc`, detén los realms con la versión actual. La versión anterior apunta `DBUS_SYSTEM_BUS_ADDRESS` a `no-system-bus` y no conoce los observadores nuevos. Los realms creados por cualquiera de las dos versiones usan el mismo formato de metadatos (`schema: 1`), así que `stop` y `recover` funcionan en ambos sentidos.

# Cortetsu Agent Realms

Forma parte de [Cortetsu](../README.md): `cortetsu realm` lo usa para construir y probar el shell aislado ([docs/AGENT_REALMS.md](../docs/AGENT_REALMS.md)). Este README describe el runtime por sí mismo; los comandos `./bin/agent-realm` se ejecutan desde este directorio.

Runtime local para crear escritorios Hyprland separados del Hyprland de la sesión de usuario. Cada realm tiene HOME, XDG, D-Bus de sesión, runtimes Wayland, firma IPC, grupo de procesos y logs propios. Weston headless GL sirve como padre Wayland privado para entregar el allocator dmabuf que Aquamarine requiere; Hyprland ejecuta su propio compositor y output headless dentro del mismo namespace de bubblewrap. Ninguno recibe el socket Wayland, el D-Bus, la configuración ni los dispositivos de entrada del anfitrión.

No instala Omarchy ni sustituye el compositor principal. No usa Sway, WayVNC, TigerVNC, VNC ni espejos de terminales. El observador sirve capturas PNG autenticadas por HTTP en `127.0.0.1`; nunca captura entrada ni la reenvía.

## Requisitos

- CachyOS/Arch, Python 3.11 o más reciente, Hyprland con Aquamarine, Weston con backend headless y renderer GL, y un render node AMD.
- `bubblewrap`, `dbus-daemon`, `systemd-run`, `hyprctl`, `weston`, `grim`, `wtype` y `quickshell` para sus respectivas funciones.
- Para puntero virtual y el shim Wayland local: `wayland-scanner`, `pkg-config`, `wayland-client`, `wayland-server` y un compilador C. Ambos binarios se compilan bajo demanda en `$XDG_CACHE_HOME/cortetsu-agent-realms`; no requieren privilegios ni instalación de paquetes.
- Namespaces de usuario sin privilegios habilitados. `agent-realm doctor` comprueba el conjunto mínimo.

No se necesita un monitor conectado. El runtime prioriza la iGPU AMD y monta su render node con su nombre real. No expone nodos KMS ni `/dev/input`. Weston recibe un seat sintético sin capacidades de teclado o puntero; el compositor realm ofrece sus propios protocolos de entrada virtual. Las apps conservan acceso a red y al kernel compartido.

El shim original de `src/xdg-version-shim.c` solo se carga en el proceso Weston del realm. Weston 15 anuncia `wl_compositor` y `xdg_wm_base` v5; Aquamarine 0.15.1 solicita v6. El shim publica v6 para esas interfaces, que no añaden requests en esa versión, y añade un `wl_seat` v9 sin capacidades. No modifica paquetes ni archivos del sistema. El servidor padre debe seguir anunciando dmabuf mediante su renderer GL; Weston con renderer Pixman o sin el dispositivo AMD no sirve como allocator.

## Uso directo

```sh
./bin/agent-realm doctor
./bin/agent-realm start codex --width 1440 --height 900 --ephemeral
./bin/agent-realm run codex -- /usr/bin/kitty
./bin/agent-realm run --detach --compositor-child codex -- /usr/bin/kitty
./bin/agent-realm run --detach --compositor-child codex -- /usr/bin/qs --path /workspace/cortetsu/cortetsu/shell.qml
./bin/agent-realm inspect codex
./bin/agent-realm windows codex
./bin/agent-realm screenshot codex --output /tmp/codex.png
./bin/agent-realm click codex 300 250
./bin/agent-realm key codex CTRL+L
./bin/agent-realm type codex 'https://example.org'
./bin/agent-realm scroll codex 500 500 0 120
./bin/agent-realm logs codex --tail 200
./bin/agent-realm stop codex
```

`run` acepta argumentos separados después de `--` y, en su modo normal, no pasa por un shell: cada comando recibe su propio scope systemd y PID namespace. Para una app gráfica que deba aparecer en Overview, usa `--detach --compositor-child`; el runtime cita los argumentos y Hyprland los ejecuta mediante su IPC privado dentro del PID namespace del compositor. Esas apps heredan el scope y los límites del realm, por lo que no admiten cuotas individuales ni devuelven código de salida. `start --workspace RUTA --readonly-workspace` monta una carpeta del agente como `/workspace`. Sin esa opción no se monta ningún proyecto del anfitrión. Para una sesión reutilizable, omite `--ephemeral`: al detener conserva el HOME privado, pero no la sesión gráfica en memoria. `start --lua` genera `hyprland.lua` en vez de `hyprland.conf`: `hyprctl dispatch` evalúa entonces Lua (`hl.dsp.exec_cmd(...)`) igual que el Hyprland de Cortetsu, y `--compositor-child` usa esa sintaxis con un literal Lua escapado byte a byte. Úsalo para probar acciones de Cortetsu que despachan Lua; Hyprland 0.56 avisa además de que el formato `.conf` desaparecerá en 0.57. `recover` limpia sockets de un cierre anormal; `pause` y `resume` suspenden o reanudan el scope del compositor y los scopes de apps normales.

`start` también revisa los scopes exactos del realm si los metadatos dicen que la sesión está parada; un scope activo sin sesión válida bloquea el arranque y requiere `recover`.

Límite de confianza: el registro de sesión (`session.json`), el lock de ciclo de vida, los registros de apps y las capturas viven en `$XDG_STATE_HOME/cortetsu-agent-realms-control/<name>/`, que nunca se monta en el realm. El supervisor interno solo publica `realm-report.json` en el estado montado; el anfitrión lo trata como no confiable y acepta únicamente firma IPC, nombre de socket Wayland y bus privado validados, nunca PIDs ni unidades. La recuperación detiene primero los scopes exactos y solo señaliza procesos antiguos cuando conserva un PID y `start_time` enteros válidos. Si un registro de app está ilegible o no contiene una unidad válida ni una identidad segura, `stop`/`recover` informa el archivo y lo preserva: no puede descartarlo sin saber si oculta un proceso legacy vivo o un PID reutilizado. Inspecciona manualmente el proceso y su cgroup; cuando confirmes que no queda proceso, respalda y elimina ese registro de `$XDG_STATE_HOME/cortetsu-agent-realms-control/<name>/apps` (por defecto `~/.local/state/...`) y vuelve a ejecutar `recover`.

Los comandos de entrada escriben solo al `zwlr_virtual_pointer_v1` o al teclado virtual de Wayland, seleccionados con el socket privado del realm. `hyprctl` se invoca siempre con `-i <firma-del-realm>`. Para integración completa de Cortetsu, inicia Quickshell mediante `agent-realm run --detach --compositor-child`; así el launcher y Hyprland comparten el namespace PID. El runtime privado vive en `/tmp/ar<hash>` para que `$XDG_RUNTIME_DIR/hypr/<firma>/.socket2.sock` quepa en los 107 bytes de `sockaddr_un` (antes Quickshell no recibía eventos de Hyprland). Mientras el realm vive, un teclado virtual inactivo permanece conectado: Hyprland quita el foco de teclado de las superficies cuando desaparece el último teclado, y sin él el launcher perdía el teclado tras el primer `type`.

`scripts/realm-cortetsu.sh REALM WORKTREE [RUNTIME]` hace todo lo de esta sección: enlaza los helpers nativos del worktree, instala el adaptador, cierra cualquier otra instancia de Quickshell del realm (dos builds a la vez contaminan cualquier comparación) y espera a que el IPC del shell responda. `CORTETSU_REALM_ENV="VAR=valor ..."` añade entorno al shell, por ejemplo un escenario de GPU (`scripts/realm-gpu-scenario.py`, ver [docs/simulation.md](docs/simulation.md)).

El launcher de Cortetsu también espera `cortetsu-launch-persistent`, que normalmente usa systemd de usuario. El D-Bus privado del realm no ofrece ese servicio. Para ejecutar el launcher allí, prepara el adaptador en el worktree antes de montarlo read-only y enlázalo dentro del HOME del realm:

```sh
install -D -m 0755 scripts/realm-cortetsu-launch-persistent \
  /ruta/al/worktree/.realm-tools/bin/cortetsu-launch-persistent
./bin/agent-realm start cortetsu --workspace /ruta/al/worktree --readonly-workspace
./bin/agent-realm run cortetsu -- mkdir -p /home/agent/.local/bin
./bin/agent-realm run cortetsu -- ln -sfn \
  /workspace/.realm-tools/bin/cortetsu-launch-persistent \
  /home/agent/.local/bin/cortetsu-launch-persistent
```

El runtime antepone `/home/agent/.local/bin` a PATH. El adaptador conserva el directorio de trabajo y ejecuta el argv que Cortetsu entrega; el proceso hereda el scope del compositor. Esto aplica solo al launcher del realm y no instala ni cambia unidades systemd del anfitrión.

Para probar Quickshell desde un checkout aislado:

```sh
./bin/agent-realm start cortetsu --workspace /ruta/al/worktree --readonly-workspace
./bin/agent-realm run --detach --compositor-child cortetsu -- /usr/bin/qs --path /workspace/cortetsu/shell.qml
./bin/agent-realm inspect cortetsu
./bin/agent-realm stop cortetsu
```

Consulta los valores de `qs --help` para elegir `--path` según el layout concreto del build. `agent-realm run` monta las rutas de sistema en solo lectura; el worktree indicado se conserva solo lectura con el flag anterior.

## Observación independiente

```sh
./bin/agent-realm observe codex --open      # inicia el observador si hace falta, autoriza y abre el navegador
./bin/agent-realm observe codex --status    # puerto, PID y sesiones activas
./bin/agent-realm observe codex --revoke    # invalida todas las sesiones del visor
./bin/agent-realm observe codex --stop      # cierra el observador; el realm sigue activo
```

Cada `--open` crea un archivo de lanzamiento privado con un ticket de un solo uso que caduca en 60 s; el navegador lo canjea por un token que solo vive en la memoria de la página. No hay contraseñas ni tokens en URLs de la CLI, en argv ni en logs. El visor solo puede leer estado y frames. Cerrar el navegador o el observador no detiene el realm; `agent-realm stop` revoca el acceso y termina el observador. Sin visores, el observador sale a los 15 minutos (`--idle-timeout`). `--launch-file` imprime la ruta del archivo de lanzamiento para abrirlo en otro navegador; `--foreground` sirve en la terminal actual.

Modelo de amenazas, límites y pruebas: [docs/security-observer.md](docs/security-observer.md).

## MCP

```sh
scripts/setup-mcp-venv.sh                              # .venv con mcp==2.3.0
./bin/agent-realm profile set claude --realm claude    # el cliente "claude" controla el realm "claude"
claude                                                 # en este repo: .mcp.json ya declara agent-realms
```

`agent-realm-mcp --profile <nombre>` habla MCP por stdio y ofrece 17 herramientas: ciclo de vida, capturas con `frame_id` y transformación de coordenadas, espera de cambios visuales, ventanas, apps, ratón, teclado, logs, diagnóstico y servicios simulados. El perfil fija el realm y las capacidades (`observe`, `control`, `admin`); ninguna herramienta acepta un nombre de realm. `.codex/config.toml` deja preparado Codex CLI con el perfil `codex`. Detalles, errores y seguridad: [docs/mcp.md](docs/mcp.md).

## Servicios simulados

```sh
./bin/agent-realm simulate --list
./bin/agent-realm simulate codex --scenario battery-low        # antes de lanzar el shell
./bin/agent-realm simulate codex --set upower.battery.percentage=50 --event wifi-scan
./bin/agent-realm simulate codex --stop
```

Cada realm puede tener un bus de sistema privado con UPower, power-profiles-daemon, NetworkManager y BlueZ simulados, y un PipeWire privado con dispositivos null. Todo corre dentro del realm y nunca toca el hardware ni los servicios del anfitrión. Escenarios versionados en `scenarios/` (`battery-low`, `charging`, `gaming`, `services-failing`, `desktop`); los cambios emiten las señales D-Bus reales. Arquitectura, transiciones, hallazgos sobre Quickshell y límites: [docs/simulation.md](docs/simulation.md).

## Aislamiento, recursos y límites

- Bubblewrap oculta el HOME y el runtime del host, da a la sesión HOME/XDG, dos runtimes Wayland y D-Bus privados, separa namespaces de usuario/PID/UTS y le da `/tmp` privado. Solo monta `/usr`, `/etc` y `/sys` de solo lectura, el HOME del realm, el render node AMD, los runtimes del realm y, si está elegido, un workspace. El namespace de red y la GPU son recursos compartidos.
- El `PATH` del realm antepone `/home/agent/.local/bin`, que pertenece al HOME efímero o persistente del realm; no hereda rutas de binarios del HOME anfitrión.
- El contenedor no es una frontera frente a código hostil ejecutado por el mismo usuario: comparte kernel, credenciales Unix del usuario, red y render node. No se deben montar secretos en el workspace.
- Cada compositor y cada comando de `run` normal quedan en scopes transitorios de systemd con `MemoryMax`, `CPUQuota` y `TasksMax`. Los límites predeterminados son 6 GiB, 2 cores y 512 procesos por scope. Los scopes se recolectan al terminar; la cuota de `run` normal es por app. `--compositor-child` comparte el scope del realm, cuyas cuotas siguen limitando el total.
- `inspect` mide CPU acumulada y PSS de todos los procesos en los cgroups exactos del realm. GPU busy es una muestra global del dispositivo AMD y no se puede atribuir a una sesión en concreto.
- El backend headless no equivale a conectar el realm a un puerto HDMI. Para visualizarlo se abre el observador en un monitor elegido. La conexión física no interviene en el ciclo de vida.
- Aquamarine y la GPU pueden variar entre versiones. `doctor`, `logs` y las capturas permiten diagnosticar fallos; no se debe asumir compatibilidad a partir de una compilación exitosa.

## Desarrollo y pruebas

```sh
PYTHONPATH=src python -m unittest discover -s tests -v   # las pruebas MCP se omiten sin .venv
./bin/agent-realm doctor
scripts/acceptance-dual-realm.sh   # dos realms reales en paralelo; escribe evidence/acceptance-dual-realm/
scripts/acceptance-observer.sh     # observador autenticado contra un realm real; escribe evidence/observer-security/
python3 scripts/acceptance-mcp.py  # MCP por stdio contra realms reales; escribe evidence/mcp-acceptance/
scripts/acceptance-simulation.sh   # servicios simulados y huella del anfitrión; escribe evidence/simulation-acceptance/
CORTETSU_WORKTREE=/ruta scripts/acceptance-simulation-ui.sh   # Cortetsu real + OCR de Quick Settings
```

`acceptance-dual-realm.sh` arranca los realms `codex-<pid>` y `claude-<pid>`, les envía clic, texto y Enter a la vez y exige que cada uno escriba solo su marcador en su HOME privado, que el foco del anfitrión no cambie y que al parar no queden scopes. Registra la latencia IPC del anfitrión, PSS y CPU por realm.

`status` informa `supervised`. Si el supervisor interno muere, el compositor puede seguir sirviendo IPC, pero nadie registraría una caída posterior: el estado pasa a `degraded` y `stop` limpia el scope completo.

La integración de compositor debe ejecutarse en una sesión de prueba de esta CLI y comprobarse con su firma privada. Nunca ejecutes `hyprctl`, `qs` o `wtype` de prueba con las variables del escritorio anfitrión. Las referencias revisadas, sus contratos y las decisiones de implementación están en [`docs/reference-review.md`](docs/reference-review.md).

# F0 · Reproducir la sesión de depuración (Kitty + Hyprland anidado en el WS 2)

Estas son las órdenes ejecutadas el 2026-10-20. Todas se lanzan desde la raíz del repo, en la sesión Hyprland real.

## 1. Comprobar el escritorio sin cambiarlo

```sh
hyprctl monitors -j | jq -c '.[]|{name,activeWorkspace,focused}'
hyprctl workspaces -j | jq -c '.[]|{id,monitor,windows}'
hyprctl clients -j | jq -c '.[]|{class,title,ws:.workspace.id}'
command -v Hyprland qs kitty grim dbus-daemon cc wayland-scanner pkg-config
```

`hyprctl` en el PATH es `~/.local/bin/hyprctl`, un wrapper personal que solo traduce `dispatch` a Lua y delega en `/usr/bin/hyprctl`
heredando el entorno. Por eso respeta `HYPRLAND_INSTANCE_SIGNATURE`. Los scripts de F0 llaman a `/usr/bin/hyprctl` directamente.

## 2. Terminal de depuración en el WS 2

```sh
/usr/bin/hyprctl dispatch 'hl.dsp.exec_cmd("kitty --title Cortetsu-F0-Debug --class cortetsu-f0-debug -o allow_remote_control=socket-only --listen-on unix:@cortetsu-f0-debug --directory <repo>", { workspace = "2 silent" })'
hyprctl clients -j | jq -c '.[]|select(.class=="cortetsu-f0-debug")|{title,ws:.workspace}'   # → ws 2
hyprctl activeworkspace -j | jq .id                                                            # sin cambios
```

Es una instancia propia de Kitty: no usa `--single-instance` y no toca la instancia `rice` de Dilan. La regla `workspace = "2 silent"`
de `exec_cmd` hace que la ventana nazca en el WS 2 sin mover el foco. No se añade ninguna regla a la configuración.

Pestañas de observación, abiertas por control remoto:

```sh
kitty @ --to unix:@cortetsu-f0-debug launch --type=tab --tab-title "F0 logs"     docs/migration/F0/tools/watch-logs.sh    # qs.log, hyprland.log anidado, stubs
kitty @ --to unix:@cortetsu-f0-debug launch --type=tab --tab-title "F0 procesos" docs/migration/F0/tools/watch-procs.sh   # procesos con XDG_RUNTIME_DIR=/tmp/czr*, estado de la dGPU
kitty @ --to unix:@cortetsu-f0-debug launch --type=tab --tab-title "F0 banco"    tail -F <out>/nested.log
```

`watch-procs.sh` filtra por `XDG_RUNTIME_DIR=/tmp/czr*` en `/proc/<pid>/environ`. Es el mismo criterio que usa el arnés para su
barrido, así que solo muestra procesos de la prueba.

## 3. Hyprland anidado con Cortetsu del checkout

```sh
python3 scripts/integration/ws2_run.py --timeout 1800 <out>/nested.log -- \
    python3 docs/migration/F0/tools/nested_bench.py <out>/nested --starts 20 --opens 10 --cycles 40 --hold 90
```

- `ws2_run.py` ejecuta la orden como hijo normal, con un shim `Hyprland` primero en el PATH. Cada vez que algo arranca `Hyprland`,
  el shim pide al Hyprland real que lance `/usr/bin/Hyprland` directamente con la regla `workspace = "2 silent"`. El compositor
  es el proceso que lanza el escritorio, así que la regla se aplica y gana a la regla personal `cortetsu-nested-tests` (WS 11).
  El shim reenvía TERM/INT/HUP y termina con el compositor.
- `nested_bench.py` usa `F0Session` (`scripts/integration/f0_session.py`), una subclase de `launcher_harness.Session`:
  - Hyprland anidado con la configuración Lua del repo. Los programas de inicio y los binds `exec` se sustituyen por `true`, se
    desactivan el teclado y el puntero del escritorio y se crean 3 salidas (`WAYLAND-1`, `HEADLESS-1`, `HEADLESS-2`).
  - Shell compuesto desde el checkout (`compose_runtime`), no el build instalado.
  - `HOME`, `XDG_CONFIG_HOME`, `XDG_STATE_HOME`, `XDG_DATA_HOME` y `XDG_CACHE_HOME` temporales.
  - `XDG_RUNTIME_DIR` propio y corto (`/tmp/czr…`), un `dbus-daemon` privado sin directorios de servicio y
    `PATH = <stubs>:/usr/bin`, sin `~/.local/bin`.
  - Stubs que registran los argumentos de cada orden que alcanzaría el sistema real (`systemctl`, `nmcli`, `busctl`,
    `brightnessctl`, `systemd-inhibit`, `notify-send`, `powerprofilesctl`, … y todos los nombres `cortetsu-*`).
  - Solo Mesa (`nested_gpu.py`): la dGPU NVIDIA no despierta.
- Con `--hold N`, la sesión sigue viva N segundos al final y abre las superficies por turnos. Se puede ir al WS 2 para verla. La
  salida `WAYLAND-1` solo pinta cuando el escritorio pinta su ventana; las medidas usan `HEADLESS-1`, que tiene reloj propio.

Capturas de la interfaz renderizada: `evidence/run-20261020/nested/surface-*.png` (Hardware, Pantallas, Portapapeles, Atajos, Wallpaper
Orbital, Overview y Calendario).

## 4. Suite completa en el WS 2

```sh
python3 scripts/integration/ws2_run.py --timeout 3600 <out>/suite.log -- \
    python3 -I docs/migration/F0/tools/run_suite.py . <out>/cortetsu-test-entries.txt <out>/suite.json
```

`run_suite.py` toma una huella de la sesión real antes y después de cada prueba (`tools/real_snapshot.sh`: opciones, monitores,
hash de binds, hash de atajos globales y transacción de GameMode real).

Para auditar dónde caen las ventanas mientras corre algo: `docs/migration/F0/tools/ws-audit.sh > ws-audit.txt &`.

## 5. Todo de una vez

```sh
docs/migration/F0/tools/reproduce.sh [<out>]
```

## 6. Cierre y comprobaciones

```sh
ls -d /tmp/czr* /tmp/czf* 2>/dev/null                       # vacío: el arnés borra su runtime y su base
for p in /proc/[0-9]*; do grep -qz '^XDG_RUNTIME_DIR=/tmp/czr' $p/environ 2>/dev/null && echo ${p#/proc/}; done   # vacío
cat /sys/bus/pci/devices/0000:01:00.0/power/runtime_status  # suspended
docs/migration/F0/tools/real_snapshot.sh                    # igual que antes
kitty @ --to unix:@cortetsu-f0-debug close-window --match all   # cierra solo la terminal F0
```

## Por qué hizo falta cambiar el arnés

- **Colocación.** `Session.start()` arranca Hyprland como hijo. El escritorio coloca esa ventana según sus reglas: aquí la regla
  personal `cortetsu-nested-tests` la manda al WS 11; sin ella caería en el workspace activo. El guard de ayer (`ws2_guard.py`)
  la movía después de mapearla. La regla de exec solo alcanza al proceso lanzado y a un hijo directo, no a los descendientes de
  una suite, por eso se usa un shim (TESTS.md §3).
- **Socket truncado.** `XDG_RUNTIME_DIR` dentro de la base podía superar los 107 bytes de `sun_path`. Hyprland truncaba los sockets
  (ambos se convertían en `.socket.so`), `hyprctl` seguía funcionando y Quickshell no conectaba, así que el QML anidado no tenía
  monitores ni foco (TESTS.md §2).

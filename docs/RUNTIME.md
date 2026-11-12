# Runtime versionado de Cortetsu

Cortetsu nunca escribe `/etc/xdg/quickshell/caelestia`. El constructor toma el baseline vendorizado bajo `cortetsu/base`, ejecuta gates en staging y sólo entonces promueve una generación. `cortetsu/base/PROVENANCE.md` conserva la procedencia y licencia de los archivos aún en migración.

```text
~/.local/share/cortetsu/builds/<build-id>
~/.config/quickshell/cortetsu/current
~/.config/quickshell/cortetsu/previous
~/.config/quickshell/cortetsu/legacy-previous   # sólo snapshot pre-v2, si existe
```

Variables canónicas:

```text
CORTETSU_DATA_ROOT
CORTETSU_RUNTIME_ROOT
```

No existen fallbacks activos a variables CaeRice.

El flujo construye desde el repositorio en `.staging-*`, genera `BUILD.json`, convierte la salida en una ruta inmutable y conmuta `current` mediante symlink temporal + `mv -T`.

## Generaciones

`current` y `previous` sólo son válidos cuando contienen `BUILD_ID`, `BUILD.json`, `compatibility.json`, `composition.json` y módulos esenciales. El rollback rechaza cualquier destino que no cumpla ese contrato.

Durante la migración única a v2, un runtime pretransaccional puede conservarse en `legacy-previous`. Es un snapshot archivado para diagnóstico y nunca participa en rollback automático.

## Rollback

```bash
cortetsu-rollback
```

El rollback comparte el lock del constructor y conmuta enlaces atómicamente. El instalador coloca únicamente helpers `cortetsu-*`, la CLI, el wrapper de Caelestia, configuración Hyprland, bridge de temas y unidades systemd de usuario.

## Ciclo de vida y recuperación

`cortetsu-shell.service` (unidad de usuario) es el único dueño del proceso `qs`. No lances `qs -d` ni uses `pkill -x qs`: un shell fuera de la unidad no se recupera y deja helpers sin dueño.

```bash
cortetsu shell reload                         # recarga QML en el mismo proceso
systemctl --user restart cortetsu-shell.service  # proceso nuevo, cgroup limpio
```

La unidad arranca Quickshell con `QS_DISABLE_CRASH_HANDLER=1` y `Restart=on-failure`. El gestor de fallos de Quickshell reinicia con `execve` dentro del mismo PID, así que los helpers de la imagen anterior (`nmcli monitor`, el inhibidor de suspensión) seguían vivos sin dueño y el fork del volcado quedaba zombi. Sin él, un fallo termina la unidad, systemd mata el cgroup entero y la relanza en un segundo. La evidencia queda en `coredumpctl list qs` y `journalctl --user -u cortetsu-shell`.

Comprobación tras un fallo: `systemctl --user status cortetsu-shell` debe mostrar un único `qs` y sus helpers bajo el cgroup de la unidad, y `ps -eo stat,ppid,comm | awk '$1 ~ /Z/'` no debe listar hijos de `qs`. `scripts/features/test-shell-lifecycle.py` fija el contrato de la unidad.

## Saludo de SDDM en el portátil híbrido

Síntoma: tras arrancar queda una tty sin pantalla de inicio de sesión y hay que ejecutar `systemctl restart sddm`. En el journal, `sddm` registra `Greeter stopped` un segundo después de `Greeter session started successfully`.

Causa: Weston (el compositor del saludo) elige la tarjeta DRM por su cuenta. Si en ese instante no puede tomar la AMD (`Could not take device: Device or resource busy`), usa la NVIDIA, cuyo único conector es el HDMI externo. Sin monitor conectado no hay salida que activar, Weston termina y SDDM no vuelve a lanzar el saludo.

`config/sddm/cortetsu-greeter-compositor` lanza Weston con `--drm-device` apuntando a la tarjeta que tiene el conector eDP (los números `cardN` cambian entre arranques) y lo reintenta hasta seis veces si muere en menos de cinco segundos. Es configuración del sistema y `cortetsu install` no la toca:

```bash
sudo scripts/install-sddm-greeter.sh            # instala y cambia CompositorCommand en /etc/sddm.conf
sudo scripts/install-sddm-greeter.sh --remove   # lo deshace
```

Queda una copia en `/etc/sddm.conf.cortetsu-backup`. Cada reintento se registra en `journalctl -b -u sddm` con el prefijo `cortetsu-greeter-compositor`.

## Migración v2

`scripts/migrate-cortetsu-v2.sh` es idempotente. Antes de retirar nombres instalados antiguos crea un backup timestamped en `~/.local/share/cortetsu/migrations/`, migra Calendar/Pomodoro al namespace XDG de Cortetsu, migra el secreto de Calendar sin imprimirlo y conserva el opt-in del servicio de energía.

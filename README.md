# Cortetsu

> Dotfiles personal para CachyOS/Arch: Hyprland, Quickshell, Qt 6/QML y un escritorio rápido, reversible y visualmente coherente.

**Cortetsu** combina Cortés con *tetsu* (鉄, hierro/acero): una identidad propia inspirada en disciplina samurái, tinta sumi, acero ennegrecido, índigo y bermellón. La referencia es estética y de producto; no depende de la identidad de ningún shell upstream.

## Qué es ahora

Cortetsu ya no es sólo un patchset de shell. Es una plataforma de dotfiles que construye el escritorio como un sistema versionado:

1. **shell runtime**: generación inmutable de Quickshell;
2. **dotfiles runtime**: configuración de usuario inmutable y hasheada;
3. **helpers runtime**: generación inmutable de ejecutables Rust/Go y launchers;
4. **system generation**: fija shell, dotfiles y helpers con manifiestos y hashes;
5. **profile**: selección declarativa de capacidades y paquetes;
6. **doctor**: comprobación del sistema antes de asumir que una función existe.

`cortetsu rollback` restaura shell, dotfiles y helpers de la generación anterior. El instalador nativo, su recuperación y los helpers de primera parte ya no requieren Python. El coordinador Go observa la sesión; cada dominio de automatización requiere activación expresa. Consulta el [contrato nativo y las pruebas](docs/migration/NATIVE-RUNTIME.md) y el [estado de entrega](docs/migration/STATUS-2026-10-22.md).

## Principios

- cero escrituras sobre el runtime del paquete en `/etc`;
- generaciones de usuario inmutables con `current`, `previous` y rollback verificable;
- archivos preexistentes respaldados antes de ser adoptados;
- namespace activo exclusivamente `cortetsu-*` / `CORTETSU_*`;
- nada de `sh -c` en QML;
- paneles ocultos sin polling continuo;
- procesos y telemetría compartidos en vez de duplicados por vista;
- secretos fuera del repositorio mediante Secret Service;
- cambios críticos con staging, hashes, pruebas y verificación real;
- historial anterior preservado sólo como procedencia, nunca como dependencia activa.

## Stack confirmado

- CachyOS / Arch Linux;
- Hyprland, con version instalada verificada en la maquina de destino; la referencia historica fue 0.56.2;
- Quickshell compatible con Qt 6 y el empaquetado de CachyOS/Arch; 0.3.1 fue una referencia anterior, no una version actualmente comprobada;
- Caelestia Shell 2.4.0 como fuente de procedencia congelada para el staging, no como dependencia activa instalada;
- Qt 6 / QML para interfaz;
- Rust para CLI, estado, helpers y recuperación; Go para coordinación y políticas;
- PipeWire/WirePlumber, NetworkManager, UPower y systemd --user para integración del sistema.

La base actual de Caelestia se reconstruye desde `v2.4.0` commit `24aa15eefdb146350d2548c0a015b04eddbd1008`. Cortetsu aplica adapters y módulos sólo dentro de staging. La dirección del proyecto es reducir progresivamente esos adapters hasta que el shell sea completamente propio.

## Generaciones

```text
# Shell
~/.local/share/cortetsu/builds/<build-id>
~/.config/quickshell/cortetsu/current
~/.config/quickshell/cortetsu/previous

# Dotfiles
~/.local/share/cortetsu/dotfiles/builds/<build-id>
~/.local/share/cortetsu/dotfiles/current
~/.local/share/cortetsu/dotfiles/previous

# Helpers
~/.local/share/cortetsu/helpers/builds/<build-id>/HELPERS.json
~/.local/share/cortetsu/helpers/current
~/.local/share/cortetsu/helpers/previous

# Sistema completo
~/.local/share/cortetsu/system/builds/<build-id>/SYSTEM.json
~/.local/share/cortetsu/system/current
~/.local/share/cortetsu/system/previous
```

`SYSTEM.json` schema 2 fija las rutas y los hashes de shell, dotfiles y helpers. `cortetsu verify` comprueba archivos, manifiestos, enlaces activos y launchers; `cortetsu-rescue verify` funciona también sin QML, Go ni checkout. `/etc/xdg/quickshell/caelestia` es referencia de solo lectura.

## Perfil personal

`profiles/personal.toml` hereda de `profiles/base.toml`. El manifest `dotfiles/manifest.toml` decide qué archivos pertenecen a Cortetsu y `packages/arch.toml` describe dependencias por grupos. Nada instala paquetes automáticamente todavía: `doctor` detecta drift antes de que `bootstrap` se convierta en una operación de sistema.

## Módulos

- Bottom Hub: dock/taskbar contextual por monitor;
- Overview: ventanas y workspaces con previews;
- Clipboard: historial Clipse en QML;
- Hardware: rendimiento, procesos, sensores, energía e I/O;
- Display: topologías, preview, persistencia y rollback;
- Wallpaper: selector orbital con prefetch limitado;
- Calendar: Google Calendar de solo lectura;
- Focus/Pomodoro: ciclo persistente con descansos cortos y largos.

## CLI

```bash
cortetsu status
cortetsu plan
cortetsu install
cortetsu verify
cortetsu generations
cortetsu rollback
cortetsu recover
cortetsu doctor
cortetsu shell adopt
cortetsu test
cortetsu audit
cortetsu legacy-processes scan
cortetsu legacy-processes migrate
```

`cortetsu install` compila el bundle Rust/Go, construye shell y dotfiles y promueve una generación schema 2 bajo journal recuperable. Conserva un checkpoint de la instalación anterior, incluso si utilizaba schema 1. No reinicia ni recarga el shell automáticamente: así las aplicaciones abiertas conservan sus superficies Wayland y su bandeja. Para adoptar la generación sin cerrar el proceso de Quickshell, usa `cortetsu shell reload`; verifica que el mismo proceso siga activo. Las operaciones que detienen, reinician o deshabilitan el shell requieren una orden explícita.

`cortetsu legacy-processes scan` audita launchers y procesos visibles de los daemons legacy. `migrate` respalda y reemplaza referencias de Pomodoro y wallpaper-color cuando los helpers Cortetsu existen. La implementación usa el contrato `scheme.json` que consume el runtime actual; la frontera con el generador upstream queda documentada en el helper. Esta operación no envía señales, no usa `pkill` y no mata grupos de procesos.

## Calidad

CI valida los ocho crates Rust con rustfmt/Clippy/tests, el coordinador Go con detector de carreras y vet, contratos y paridad, QML real y la instalación de dos generaciones con rollback completo. El instalador se ejecuta en un HOME temporal cuyo PATH no contiene Python. Python permanece en herramientas de desarrollo y referencias congeladas, nunca en los launchers instalados del runtime nuevo. Las pruebas físicas de AMD/NVIDIA, HDMI y suspensión se registran aparte.

Los objetivos de rendimiento están en [`docs/PERFORMANCE.md`](docs/PERFORMANCE.md), el lenguaje visual en [`docs/DESIGN_SYSTEM.md`](docs/DESIGN_SYSTEM.md) y la plataforma de configuración en [`docs/DOTFILES_PLATFORM.md`](docs/DOTFILES_PLATFORM.md).

## Procedencia

Cortetsu mantiene documentación histórica y atribución explícita en [`docs/PROVENANCE.md`](docs/PROVENANCE.md) y `docs/history/`. La procedencia se conserva; el código activo no depende del namespace anterior.

# Generation storage and garbage collection

Cortetsu stores immutable generations in four coordinated layers:

- `~/.local/share/cortetsu/builds`: shell runtimes;
- `~/.local/share/cortetsu/dotfiles/builds`: dotfiles generations;
- `~/.local/share/cortetsu/helpers/builds`: native executable bundles;
- `~/.local/share/cortetsu/system/builds`: promotion metadata linking all components.

`current` is the active generation. `previous` is the rollback generation. A
system generation is retained together with the shell, dotfiles and helper generations
named by its `SYSTEM.json`; deleting any of those references would make the
rollback contract invalid.

Collection is always a separate, explicit operation. `cortetsu install`
never deletes generations: after promoting, it only prints what a collection
would remove at that moment.

```bash
cortetsu gc                      # read-only plan (default); prints PLAN_ID
cortetsu gc --keep 8             # same, with a larger retention window
cortetsu gc --apply --keep 5 --plan-id <PLAN_ID>             # delete that plan
cortetsu gc --apply --keep 5 --plan-id <PLAN_ID> --archive   # archive first
```

Every generation listed by the plan carries its retention reason:
`current` and `previous` (always kept), `additional` (the newest `--keep`
system generations beyond those two), `referenced` (shell, dotfiles and helper
components of a retained system generation) and `pinned`. Each deletion
candidate is listed by name with its size, plus `TOTAL_RECLAIM`.

`--apply` takes every generation lock without waiting (`install.lock`,
`build.lock`, `system/system.lock`, `helpers/helpers.lock`, `gc.lock`) and refuses if an install,
build, promotion or rollback is running. Under those locks it recomputes the
plan; if its `PLAN_ID` differs from the approved one (a new promotion, a pin,
a moved link, a different `--keep`) nothing is deleted and the plan must be
reviewed again. Drift between layers, broken or outside links, invalid
metadata and unsafe paths abort before any deletion.

`gc-backups/<stamp>/` holds metadata only (plan, links, `BUILD.json`,
`MANIFEST.json`, `SYSTEM.json` of the kept generations). It is **not** a copy
of deleted generations. With `--archive`, a verified `tar.gz` of each deleted
generation is written to `gc-backups/<stamp>/archives/<layer>/` first; the
run aborts before writing anything if free space is below the allocated size
being collected plus 16 MiB, and aborts before deleting if an archive does not
list every file of its generation.

Recovering an archived generation is a manual, separate step; Cortetsu never
restores history on its own:

```bash
tar -tzf ~/.local/share/cortetsu/gc-backups/<stamp>/archives/shell/<name>.tar.gz   # inspect
tar -xzf .../archives/shell/<name>.tar.gz -C ~/.local/share/cortetsu/builds/
tar -xzf .../archives/dotfiles/<name>.tar.gz -C ~/.local/share/cortetsu/dotfiles/builds/
tar -xzf .../archives/helpers/<name>.tar.gz -C ~/.local/share/cortetsu/helpers/builds/
tar -xzf .../archives/system/<name>.tar.gz -C ~/.local/share/cortetsu/system/builds/
cortetsu gc   # the restored generations must appear without INVALID entries
```

Pointing `current` or `previous` at a restored generation is a deliberate
rollback decision; restore the system generation together with the shell,
dotfiles and helpers generations its `SYSTEM.json` names. `cortetsu system gc` and
`cortetsu dotfiles gc` no longer delete anything, because a single layer cannot
see the references held by the others.

Manual pins are one generation name per file:

```text
~/.local/share/cortetsu/pins/shell.txt
~/.local/share/cortetsu/pins/dotfiles.txt
~/.local/share/cortetsu/pins/helpers.txt
~/.local/share/cortetsu/pins/system.txt
```

Blank lines and `#` comments are ignored. A pin must name an existing
generation. Rollback remains available with `cortetsu rollback`.

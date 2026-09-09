# Cortetsu

> Dotfiles personal para CachyOS/Arch: Hyprland, Quickshell, Qt 6/QML y un escritorio rápido, reversible y visualmente coherente.

**Cortetsu** combina Cortés con *tetsu* (鉄, hierro/acero): una identidad propia inspirada en disciplina samurái, tinta sumi, acero ennegrecido, índigo y bermellón. La referencia es estética y de producto; no depende de la identidad de ningún shell upstream.

## Qué es ahora

Cortetsu ya no es sólo un patchset de shell. Es una plataforma de dotfiles que construye el escritorio como un sistema versionado:

1. **shell runtime**: generación inmutable de Quickshell;
2. **dotfiles runtime**: configuración de usuario inmutable y hasheada;
3. **system generation**: registra el par exacto shell + dotfiles que forma el escritorio activo;
4. **profile**: selección declarativa de capacidades y paquetes;
5. **doctor**: comprobación del sistema antes de asumir que una función existe.

`cortetsu rollback` revierte shell y dotfiles coordinadamente a la generación de sistema anterior. Los rollbacks específicos de cada capa quedan como herramientas de recuperación avanzada.

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
- Hyprland `0.56.2`;
- Quickshell `0.3.1` o build git compatible;
- Caelestia Shell `2.4.0` como adapter temporal del shell;
- Qt 6 / QML para interfaz;
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

# Sistema completo
~/.local/share/cortetsu/system/builds/<build-id>/SYSTEM.json
~/.local/share/cortetsu/system/current
~/.local/share/cortetsu/system/previous
```

`SYSTEM.json` fija las rutas exactas de la generación de shell y de dotfiles. `cortetsu verify` comprueba que los tres niveles coincidan. `/etc/xdg/quickshell/caelestia` es referencia de solo lectura.

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
cortetsu doctor
cortetsu shell adopt
cortetsu test
cortetsu audit
cortetsu legacy-processes scan
cortetsu legacy-processes migrate
```

`cortetsu install` construye shell, dotfiles e integración y al final promueve una única generación de sistema. No reinicia el shell automáticamente: así las aplicaciones abiertas conservan sus superficies Wayland y su bandeja. Para adoptar la generación de forma explícita, usa `cortetsu shell restart`; el comando queda protegido mientras ChatGPT Desktop esté abierto y requiere `CORTETSU_RESTART_SHELL=1` para anular esa protección.

`cortetsu legacy-processes scan` audita launchers y procesos visibles de los daemons legacy. `migrate` respalda y reemplaza referencias de Pomodoro y wallpaper-color cuando los helpers Cortetsu existen. La implementación usa el contrato `scheme.json` que consume el runtime actual; la frontera con el generador upstream queda documentada en el helper. Esta operación no envía señales, no usa `pkill` y no mata grupos de procesos.

## Calidad

CI valida sintaxis, Python, Bash, namespace, ausencia de shell arbitrario en QML, Calendar/Pomodoro, composición de overlays, transacciones de dotfiles, generaciones unificadas y el flujo E2E `upstream exacto -> sistema 1 -> sistema 2 -> rollback completo`.

Los objetivos de rendimiento están en [`docs/PERFORMANCE.md`](docs/PERFORMANCE.md), el lenguaje visual en [`docs/DESIGN_SYSTEM.md`](docs/DESIGN_SYSTEM.md) y la plataforma de configuración en [`docs/DOTFILES_PLATFORM.md`](docs/DOTFILES_PLATFORM.md).

## Procedencia

Cortetsu mantiene documentación histórica y atribución explícita en [`docs/PROVENANCE.md`](docs/PROVENANCE.md) y `docs/history/`. La procedencia se conserva; el código activo no depende del namespace anterior.

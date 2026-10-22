# Cortetsu dotfiles platform

Cortetsu no trata los dotfiles como enlaces sueltos al repositorio. Construye generaciones de shell, dotfiles y helpers, y una generación de sistema schema 2 que fija exactamente sus versiones. La plataforma y recuperación son Rust; el [contrato nativo](migration/NATIVE-RUNTIME.md) describe su implementación y pruebas.

## Modelo

| Capa | Generación |
| --- | --- |
| Shell | `~/.local/share/cortetsu/builds/<id>` |
| Dotfiles | `~/.local/share/cortetsu/dotfiles/builds/<id>/home/...` |
| Helpers | `~/.local/share/cortetsu/helpers/builds/<id>` |
| Sistema | `~/.local/share/cortetsu/system/builds/<id>/SYSTEM.json` |

Los targets administrados de usuario apuntan a la ruta estable `~/.local/share/cortetsu/dotfiles/current/home/...`. El shell usa `~/.config/quickshell/cortetsu/current`. Los launchers apuntan a `helpers/current`. El sistema verifica los tres componentes, sus manifiestos y enlaces frente a `SYSTEM.json`.

## Rollback completo

`cortetsu rollback` es la operación de producto. Antes de cambiar nada valida la generación de sistema anterior, su shell, dotfiles, helpers y launchers. Después mueve coordinadamente:

```text
system/current
shell/current
shell/previous
dotfiles/current
dotfiles/previous
helpers/current
helpers/previous
system/previous
```

Si una operación intermedia falla, restaura los `current` anteriores y no acepta la nueva combinación como válida. `cortetsu-rollback` también delega al rollback completo. El journal duradero permite recuperar una interrupción sin seleccionar capas incompatibles por separado.

## Seguridad

- paths absolutos y `..` son rechazados por schema;
- un archivo existente no administrado se respalda antes de adoptarlo;
- directorios completos existentes no se reemplazan automáticamente;
- cada archivo de una generación de dotfiles tiene SHA-256 registrado;
- `verify` valida hashes, perfil, enlaces administrados y coherencia shell/dotfiles/helpers/system;
- `rollback` sólo usa generaciones previamente verificables;
- `gc` nunca elimina `current` ni `previous`;
- el runtime del paquete bajo `/etc` sigue siendo sólo referencia.

## Perfiles

`profiles/base.toml` contiene el contrato mínimo. `profiles/personal.toml` hereda de base y activa escenas e integraciones personales. `CORTETSU_PROFILE` permite seleccionar otro perfil sin modificar el repositorio.

## Comandos

```bash
cortetsu plan
cortetsu install
cortetsu verify
cortetsu generations
cortetsu rollback
cortetsu recover
cortetsu doctor

cortetsu system status
cortetsu system rollback
cortetsu dotfiles status
cortetsu dotfiles verify
cortetsu gc            # plan de recolección, solo lectura
```

La recolección de generaciones es explícita y coordinada; ver la sección *Generation storage and garbage collection* del README. `cortetsu install` nunca borra generaciones.

`cortetsu install` compila los owners, valida el shell y fija sus recursos al bundle. Bajo el journal de instalación activa las capas, aplica integraciones y verifica el conjunto antes de commit. El servicio `cortetsu-shell.service` se instala pero no se habilita automáticamente mientras exista la posibilidad de un autostart previo.

## Dirección

El siguiente crecimiento de esta misma plataforma incorpora Hyprland completo, terminal, shell interactivo, Git, GTK/Qt, apps, package bootstrap, themes compilados y scenes al manifest. Caelestia permanece temporalmente como adapter del shell; no es dueño del sistema ni de los dotfiles.

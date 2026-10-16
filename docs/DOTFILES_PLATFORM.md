# Cortetsu dotfiles platform

Cortetsu no trata los dotfiles como enlaces sueltos al repositorio. Construye tres capas inmutables: shell, dotfiles y una generación de sistema que fija exactamente qué versión de ambas forma el escritorio activo.

## Modelo

```text
repo
  dotfiles/manifest.toml
  profiles/*.toml
  packages/arch.toml
       │
       ├── shell build
       │     ~/.local/share/cortetsu/builds/<id>
       │
       ├── dotfiles build
       │     ~/.local/share/cortetsu/dotfiles/builds/<id>/home/...
       │
       └── system generation
             ~/.local/share/cortetsu/system/builds/<id>/SYSTEM.json
                    │
                    ├── shellGeneration
                    └── dotfilesGeneration
```

Los targets administrados de usuario apuntan a la ruta estable `~/.local/share/cortetsu/dotfiles/current/home/...`. El shell usa `~/.config/quickshell/cortetsu/current`. La generación de sistema verifica que ambos `current` coinciden exactamente con el par registrado en `SYSTEM.json`.

## Rollback completo

`cortetsu rollback` es la operación de producto. Antes de cambiar nada valida la generación de sistema anterior, su shell y todos los hashes de sus dotfiles. Después mueve coordinadamente:

```text
system/current
shell/current
shell/previous
dotfiles/current
dotfiles/previous
system/previous
```

Si una operación intermedia falla, restaura los `current` anteriores y no acepta la nueva combinación como válida. `cortetsu-rollback` sigue instalado únicamente como herramienta de recuperación de bajo nivel para el shell.

## Seguridad

- paths absolutos y `..` son rechazados por schema;
- un archivo existente no administrado se respalda antes de adoptarlo;
- directorios completos existentes no se reemplazan automáticamente;
- cada archivo de una generación de dotfiles tiene SHA-256 registrado;
- `verify` valida hashes, perfil, enlaces administrados y coherencia shell/dotfiles/system;
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
cortetsu doctor

cortetsu system status
cortetsu system rollback
cortetsu dotfiles status
cortetsu dotfiles verify
cortetsu gc            # plan de recolección, solo lectura
```

La recolección de generaciones es explícita y coordinada; ver la sección *Generation storage and garbage collection* del README. `cortetsu install` nunca borra generaciones.

`cortetsu install` construye primero un shell válido, promueve los dotfiles, ejecuta integraciones y finalmente crea una generación de sistema que fija ese par. El servicio `cortetsu-shell.service` se instala pero no se habilita automáticamente mientras exista la posibilidad de un autostart previo.

## Dirección

El siguiente crecimiento de esta misma plataforma incorpora Hyprland completo, terminal, shell interactivo, Git, GTK/Qt, apps, package bootstrap, themes compilados y scenes al manifest. Caelestia permanece temporalmente como adapter del shell; no es dueño del sistema ni de los dotfiles.

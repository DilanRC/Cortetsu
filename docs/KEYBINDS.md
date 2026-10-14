# Atajos editables

Un único editor (Hardware › Teclas) y una lista de solo lectura en Ajustes ›
Atajos leen el mismo helper, `cortetsu-keybinds`.

## Capas y precedencia

| Capa | Archivo | Dueño |
|---|---|---|
| Valores por defecto | `~/.config/hypr/variables.lua`, `hyprland/keybinds.lua` | generación (solo lectura) |
| Usuario | `~/.config/hypr/hypr-user.lua` | generación (solo lectura) |
| Ediciones | `~/.config/cortetsu/keybinds.json` → `~/.config/hypr/cortetsu-keybinds.lua` | el editor |

`hyprland.lua` aplica las ediciones así: las variables `kb*` cambiadas antes
de cargar los módulos; las combinaciones quitadas (`hl.unbind`) y los binds
añadidos después de `hypr-user.lua`. Gana la edición, luego `hypr-user.lua`,
luego los valores por defecto. El archivo de ediciones vive fuera de las
generaciones: promover, actualizar o hacer rollback no lo toca. Si está roto,
Hyprland lo ignora, avisa y carga el resto.

## Lo que hace el editor

- Variables `kb*`: cambiar, quitar, restablecer. Los prefijos de modificadores
  (`kbGoToWs`…) no se ofrecen.
- `hypr-user.lua`: un bind que solo lanza un comando o un global se mueve
  quitando su combinación y añadiéndolo en la capa de ediciones; el archivo no
  se reescribe. Uno con lógica Lua se edita a mano.
- Aplicaciones: añadir y quitar.
- Teclas fijas de `keybinds.lua` (brillo, volumen, multimedia): solo lectura.

Cada cambio guarda un snapshot en `~/.local/share/cortetsu/snapshots/keybinds/`,
escribe de forma atómica, valida el Lua con `luac`, recarga Hyprland y
comprueba en `hyprctl binds -j` la combinación nueva con su descripción
(`cortetsu:<variable>` o `cortetsu-keybinds:<id>`). Si no coincide, restaura el
snapshot y recarga.

## Combinaciones aceptadas

- Con Super, o con Ctrl + Alt.
- Solas: teclas XF86 (multimedia, OMEN = `XF86Launch2`, calculadora), `Print`
  y F13–F24 (Copilot es `SUPER + SHIFT + F23`).
- Rechazadas: Ctrl/Alt/Shift sin Super (son de las aplicaciones: `CTRL + End`,
  `CTRL + Down`), F1–F12 solas, AltGr (escribe caracteres en latam) y las que ya
  usa otra acción.

## Migración

`~/.config/hypr/hypr-vars.lua`, donde escribía el editor anterior, nunca se
cargó. No se importa: sus valores cambiarían atajos que hoy funcionan. Se deja
en su sitio para consultarlo.

## Reversión

Borrar `~/.config/cortetsu/keybinds.json` y `~/.config/hypr/cortetsu-keybinds.lua`
y ejecutar `hyprctl reload` vuelve a los atajos de la generación.

# Atajos de utilidades: portapapeles, emojis, capturas, color y avisos

Estos atajos ya no abren programas ajenos al shell. Las combinaciones están en
`dotfiles/home/.config/hypr/variables.lua` y las órdenes en
`dotfiles/home/.config/hypr/hyprland/keybinds.lua`. Después de `cortetsu
install`, Hyprland solo carga los atajos nuevos con `hyprctl reload`.

| Atajo | Qué hace |
|---|---|
| `SUPER+V` | Abre el historial del portapapeles (`modules/clipboard`). `clipse -listen` sigue guardando el historial. |
| `SUPER+.` | Abre el launcher en modo emoji. Si el launcher ya está abierto, lo cierra. |
| `Print`, `SUPER+SHIFT+S` | Captura de un área con la pantalla congelada (`picker openFreeze`). |
| `SUPER+SHIFT+ALT+S` | Captura de un área sin congelar (`picker open`). |
| `CTRL+ALT+R` y variantes | Grabación con `cortetsu-record` (sin cambios). |
| `SUPER+SHIFT+P` | `hyprpicker -a`, más un toast con el color copiado. |

## Emojis

`cortetsu emoji -p` llama a `qs ipc call customDock emoji`. El launcher se
abre con el texto `>emoji ` y se comporta como los demás modos (`>calc`,
`>scheme`):

- Para encontrar un emoji hay que escribir todas las palabras buscadas, en
  cualquier orden: `>emoji cara risa`, `>emoji 👍`, `>emoji nf-md-firefox`.
  Se muestran hasta 64 resultados.
- Con Enter o un clic se copia el carácter con `wl-copy`, se cierra el
  launcher y aparece un toast.
- Los datos salen de `cortetsu-emoji` sin argumentos. Si `cortetsu emoji -f`
  ya descargó la versión actualizada, se usa
  `~/.cache/cortetsu/emojis.txt`; si no, `data/emojis.txt`. Se cargan la
  primera vez que se usa el modo emoji y se quedan en memoria hasta recargar
  el shell.
- Si quieres que el modo aparezca en la lista de `>`, añade a `actions` en
  `~/.config/cortetsu/preferences.json` una acción con
  `"command": ["autocomplete", "emoji"]`.

El filtro está en `modules/launcher/services/EmojiSearch.js` y lo prueba
`tests/qml/launcher`.

## Capturas

1. `AreaPicker` muestra el selector. Al soltar, se oculta y 120 ms después
   ejecuta `cortetsu-area-capture <geometría> <png>`, para que la captura no
   incluya el oscurecido del selector.
2. La imagen se guarda en `$XDG_RUNTIME_DIR/cortetsu/cortetsu-shot-*.png`
   (`~/.cache/cortetsu` si la variable no existe), un directorio 0700 que el
   helper crea si no existe.
3. Aparece la vista previa (`modules/areapicker/ScreenshotPreview.qml`) en la
   esquina inferior derecha de la pantalla de la captura. Solo responde al
   ratón y no le quita el teclado a la aplicación activa.

| Botón | Acción del helper | Resultado |
|---|---|---|
| Copiar | `--copy` y después `--discard` | La imagen va al portapapeles y se borra el archivo temporal. |
| Guardar | `--save` | Se mueve a `<Imágenes>/Capturas/Captura_AAAA-MM-DD_HH-MM-SS.png` (`xdg-user-dir PICTURES`; si falla, `~/Pictures`). Si ese nombre ya existe, se añade `_2`, `_3`, etc. Un toast muestra la ruta. |
| Editar | `--edit` | La vista previa se oculta mientras swappy está abierto (`swappy -f <png> -o <png>`). Al cerrarlo, vuelve con la imagen editada y el plazo de guardado empieza de cero. |
| Descartar | `--discard` | Borra el archivo temporal. |

Si no eliges nada en 10 s, la captura se guarda. El plazo se detiene mientras
el puntero está sobre la tarjeta o hay una acción en marcha. Si haces otra
captura con la vista previa abierta, la anterior se guarda y la tarjeta
muestra la nueva. Si la anterior sigue abierta en swappy, se guarda al cerrar
el editor. Cada acción recuerda su archivo, así que una captura nueva nunca
recibe la acción de la anterior. El modo portapapeles (`picker openClip` y
`openFreezeClip`) no abre vista previa: copia, avisa con una notificación y
borra la imagen.

El helper solo acepta en sus acciones archivos llamados
`cortetsu-shot-*.png`, para no mover ni borrar otro archivo por un error. Lo
prueban `area_capture_keeps_the_preview_image_and_runs_its_actions` en
`desktop-runtime-rs/tests/contracts.rs` y `tests/qml/areapicker`.

Si el shell se cierra con una vista previa abierta, el archivo temporal se
queda en `$XDG_RUNTIME_DIR`, que se vacía al cerrar la sesión.

## Toasts desde Hyprland o scripts

`modules/Shortcuts.qml` publica la IPC `toaster`:

```sh
cortetsu shell ipc toaster info "Título" "Mensaje" icono   # icono Material; vacío = info
cortetsu shell ipc toaster error "Título" "Mensaje"        # estilo urgente
```

La usan el atajo de `hyprpicker` y `utils/functions.lua` cuando
`~/.config/caelestia/cli.json` no es JSON válido. Antes ese aviso llamaba a
`caelestia shell toaster`, que ya no existe.

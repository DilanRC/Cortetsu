# Atajos editables

Un único editor (Hardware › Teclas) y una lista de solo lectura en Ajustes ›
Atajos leen el mismo helper, `cortetsu-keybinds` (Rust, `cortetsu/keyboards`;
ver [KEYBOARDS.md](KEYBOARDS.md)).

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

Cada cambio guarda un snapshot (nombre en UTC; se conservan 20) en
`~/.local/share/cortetsu/snapshots/keybinds/`,
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

## Teclas del HP Victus

| Tecla | Evento | Acción por defecto |
|---|---|---|
| OMEN | `KEY_PROG2` en «HP WMI hotkeys» → `XF86Launch2` (latam) | Hardware Center salvo con pantalla completa (`cortetsu:hardwareKey`) |
| Copilot | Super+Shift+`KEY_F23` en el teclado AT | Panel de acciones rápidas (`cortetsu:osd`) |
| Calculadora | `KEY_CALC` → `XF86Calculator` | Sin asignar: no hay calculadora gráfica instalada; el cálculo del lanzador es `>calc` |
| Fn+Esc | `KEY_FN_ESC` (465) en «HP WMI hotkeys» → `XF86Fn_Esc` (latam) | Sin asignar |

- Los binds viven en `config/hypr-user.lua`; el editor (Hardware > Teclas) los
  muestra como editables: cambiarlos o quitarlos es la reversión de cada uno.
- Eventos comprobados por capacidad del dispositivo y keymap latam; la
  pulsación física está pendiente (abajo).
- Fn+Esc: `libinput debug-events` registró `KEY_FN_ESC (465)` en el
  dispositivo HP WMI (2026-10-14). Otra comprobación no vio nada porque buscaba
  `hp_wmi: Unknown key code` en el journal, y ese mensaje solo sale para
  códigos sin mapear; Fn+Esc está mapeado. Las dos observaciones son
  compatibles. El keymap latam lo traduce a `XF86Fn_Esc`, así que se podría
  enlazar; no se asigna hasta confirmar que llega en cada arranque y elegir
  una acción.
- `F23` y `Shift+F23` solos no se capturan; quedan para las aplicaciones, y
  Copilot no dispara el lanzador de la liberación de Super.
- OMEN no hace nada si el monitor enfocado muestra una ventana a pantalla
  completa (un juego, un vídeo): una pulsación accidental no le quita el foco
  ni el teclado. Un fullscreen en otro monitor no la bloquea, y una ventana
  maximizada tampoco. `SUPER + H` (`cortetsu:hardware`) abre el Hardware Center
  siempre. La regla está en `cortetsu/modules/CortetsuFullscreen.js` y la prueba
  `cortetsu/tests/qml/hardware/tst_OmenFullscreen.qml`. Copilot tampoco abre
  nada sobre pantalla completa: el atajo `osd` de
  `cortetsu/modules/Shortcuts.qml` lo ignora.
- Regresión: `scripts/integration/test-hp-keys.py` pulsa esos códigos con un
  teclado virtual `latam` contra un Hyprland anidado con los mismos binds.

### Gestos del touchpad ELAN

Sin cambios: tres dedos arriba/abajo abren o alternan el workspace especial,
cuatro en horizontal cambian de workspace y cuatro hacia abajo abren el menú de
sesión (nunca suspenden directamente). No se añade un gesto de cinco dedos sin
comprobar que el touchpad lo reporta.

### Pruebas físicas pendientes (PENDING_PHYSICAL)

1. OMEN: pulsarla abre el Hardware Center; otra vez lo cierra. Con Core Keeper
   a pantalla completa no debe pasar nada; `SUPER + H` sí lo abre.
2. Copilot: abre el panel de acciones rápidas; con un juego en primer plano no
   debe interferir con el juego.
3. Fn+Esc: `sudo libinput debug-events` y pulsar Fn+Esc en dos arranques
   distintos; anotar si aparece `KEY_FN_ESC (465)` en el dispositivo «HP WMI
   hotkeys» (el número `eventN` cambia entre arranques; búscalo en
   `/proc/bus/input/devices`). Si no aparece, mirar `journalctl -kf` por
   `hp_wmi: Unknown key code`.
4. Calculadora: `KEY_CALC` en el teclado AT; sin acción hasta elegir una.
5. Cinco dedos: `sudo libinput debug-events` con el touchpad ELAN y apoyar
   cinco dedos; si aparece `GESTURE_SWIPE_BEGIN ... 5`, el gesto es viable. En
   la sesión del 2026-10-14 solo se vieron gestos de 2, 3 y 4 dedos.

## Migración

`~/.config/hypr/hypr-vars.lua`, donde escribía el editor anterior, nunca se
cargó. No se importa: sus valores cambiarían atajos que hoy funcionan. Se deja
en su sitio para consultarlo.

## Reversión

Borrar `~/.config/cortetsu/keybinds.json` y `~/.config/hypr/cortetsu-keybinds.lua`
y ejecutar `hyprctl reload` vuelve a los atajos de la generación.

## Lanzador: apertura y cierre

- El lanzador es un único estado entre pantallas: como mucho una lo tiene
  abierto. Super (y `drawers toggle launcher`, `customDock launcher`) lo
  cierra esté donde esté; antes, con el puntero en el otro monitor, lo movía
  allí en lugar de cerrarlo.
- Escape lo cierra; un clic dentro de su pantalla pero fuera del panel también,
  igual que Hardware, Portapapeles, Pantallas y Fondos.
- Super como modificador (`SUPER + 1`, `SUPER + arrastre`) no lo abre: Hyprland
  descarta el bind de liberación de `SUPER_L` cuando hubo otra tecla o botón.
- Diagnóstico: `cortetsu shell ipc drawers launcherScreens` lista las pantallas
  con el lanzador abierto. Si se ve abierto y la salida está vacía, el estado
  ya cerró y la superficie no recibió un fotograma nuevo (compositor); si la
  salida no está vacía, el fallo es de estado.
- Regresión: `scripts/integration/test-launcher-dismiss.py`.

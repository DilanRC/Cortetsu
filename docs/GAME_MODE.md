# Modo juego

`services/GameMode.qml` es el modo juego visual de Cortetsu. Lo aplica
`cortetsu-gamemode`, que habla con el Hyprland en ejecución.

## Qué cambia

| Opción | En modo juego |
|---|---|
| `animations:enabled` | `false` |
| `decoration:shadow:enabled`, `decoration:blur:enabled` | `false` |
| `general:gaps_in`, `general:gaps_out` | `0` |
| `general:border_size` | `1` |
| `decoration:rounding` | `0` |
| `general:allow_tearing` | `true` |

`allow_tearing` no hace que todo el escritorio tenga tearing. Solo permite que
lo use una ventana con la regla `immediate`, y en `rules.lua` esa regla solo la
tienen las ventanas con la etiqueta de juego.

No toca Feral GameMode (`gamemoded`), los perfiles de energía ni la GPU que
elige cada juego.

## Cómo se revierte

- **Al activar**, guarda el valor efectivo de cada opción (`hyprctl getoption`)
  en `$XDG_RUNTIME_DIR/cortetsu-gamemode-<instancia>.json`. Si se activa dos
  veces, se conserva la primera instantánea.
- **Al desactivar**, restaura solo las opciones que siguen teniendo el valor de
  juego. Si algo se cambió desde Ajustes mientras estaba activo, se conserva.
  No ejecuta `hyprctl reload`.
- **Si el shell se reinicia** con el modo activo, la instantánea de esa
  instancia de Hyprland lo muestra activo, y al apagarlo se restaura.
- **Si Hyprland se reinicia**, la instantánea deja de aplicar, porque va unida a
  `HYPRLAND_INSTANCE_SIGNATURE`.

Prueba: `scripts/features/test-gamemode-runtime.py` usa un Hyprland anidado y
compara el valor vivo de todas las opciones (`hyprctl descriptions`) antes de activar y después de
desactivar.

## Prueba física pendiente (PENDING_PHYSICAL)

Warframe es el caso principal y Core Keeper el secundario. Para cada uno:

1. Apunta el redondeo y los huecos actuales:
   `hyprctl getoption decoration:rounding; hyprctl getoption general:gaps_in`.
2. Activa el modo juego (botón «Activar modo juego» del panel de acciones, o
   `cortetsu shell ipc gameMode enable`) y abre el juego.
3. Comprueba que el juego funciona: no hay parpadeo ni tearing fuera de la
   ventana del juego, y el foco y el cursor van bien.
4. Cierra el juego y desactiva el modo juego.
5. Vuelve a mirar las opciones del paso 1: deben coincidir. Las animaciones, el
   blur y las sombras deben volver.

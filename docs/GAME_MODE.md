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

## Estados

`cortetsu-gamemode` guarda una transacción en
`$XDG_RUNTIME_DIR/cortetsu-gamemode-<HYPRLAND_INSTANCE_SIGNATURE>.json`
(escritura atómica, un `flock` para todas las órdenes). Sin archivo, el estado
es `INACTIVE`.

| Estado | Significado |
|---|---|
| `INACTIVE` | Desactivado; no hay nada que restaurar |
| `APPLYING` | Originales guardados; valores de juego aún sin verificar |
| `ACTIVE` | Valores de juego escritos y releídos con `hyprctl getoption` |
| `RESTORING` | Devolviendo los originales |
| `RECOVERY_REQUIRED` | Una reversión o restauración no se pudo confirmar; los originales se conservan |
| `UNKNOWN` | Solo informativo: archivo ilegible o Hyprland no responde. No se borra nada |

Con `UNKNOWN` por archivo ilegible, el helper rechaza toda orden. Comprueba
las opciones a mano (paso 1 de la prueba física) y, si son las tuyas, borra
`$XDG_RUNTIME_DIR/cortetsu-gamemode-$HYPRLAND_INSTANCE_SIGNATURE.json`.

Cada orden imprime `{"state", "enabled", "ok", "error"}`. `enabled` es `true`
solo en `ACTIVE`; la existencia del archivo no basta.

| Orden | Estado | Resultado |
|---|---|---|
| `enable` | `INACTIVE` | Guarda los originales, aplica y relee. Si algo falla, revierte: `INACTIVE` con el error, o `RECOVERY_REQUIRED` si la reversión tampoco se confirma |
| `enable` | `ACTIVE` | Nada; conserva la primera instantánea |
| `enable` | pendiente | Error; no toca la instantánea |
| `disable` | `ACTIVE` o pendiente | Restaura y relee |
| `disable` | `INACTIVE` | Nada |
| `recover` | `APPLYING`, `RESTORING` interrumpidos o `RECOVERY_REQUIRED` | Restaura y relee |
| `recover` | `ACTIVE` o `INACTIVE` | Nada (a diferencia de `disable`, nunca apaga un modo activo) |
| `status` | cualquiera | Solo lectura |

Al restaurar, una opción vuelve a su original solo si todavía tiene el valor de
juego. Si se cambió desde Ajustes mientras el modo estaba activo, se conserva.
La misma regla sirve para desactivar, para revertir una aplicación parcial y
para recuperar. Nunca se usa `hyprctl reload`.

- **Reinicio o recarga del shell:** `GameMode.qml` pregunta `status` y muestra
  lo que diga el helper; no vuelve a aplicar nada.
- **Fallo del shell o del helper a mitad:** la transacción queda en
  `APPLYING` o `RESTORING`; el shell lo muestra como error y el botón restaura.
- **Reinicio de Hyprland o del equipo:** la instancia es otra (o el directorio
  de ejecución se vacía) y el modo empieza desactivado.

En la interfaz, el botón muestra «Aplicando…» mientras corre el helper, nunca
«activado» antes de la confirmación, y en un estado pendiente pide restaurar.
Desde terminal: `cortetsu shell ipc gameMode status` y
`cortetsu shell ipc gameMode recover`.

## Pruebas

- `scripts/features/test-gamemode-helper.py` (CI): máquina de estados con un
  `hyprctl` falso que falla entero, a medias, al leer o al restaurar; también
  el backend `--keyword` (hyprlang).
- `scripts/features/test-gamemode-runtime.py` (local, Hyprland anidado; el
  gemelo real del anterior): compara
  el valor vivo de todas las opciones (`hyprctl descriptions`) antes de activar
  y después de desactivar, provoca fallos parciales reales del `eval`, carreras
  entre helpers, reinicio y recarga del shell, y comprueba el botón QML con el
  helper real.

## Prueba física pendiente (PENDING_PHYSICAL)

Con la versión nueva desplegada, en **Core Keeper**:

1. Guarda las opciones actuales:
   `for o in animations:enabled decoration:blur:enabled decoration:shadow:enabled general:border_size general:gaps_in general:gaps_out decoration:rounding general:allow_tearing; do hyprctl getoption $o; done > /tmp/gm-antes.txt`
2. Activa el modo juego (botón «Activar modo juego» del panel de acciones, o
   `cortetsu shell ipc gameMode enable`) y abre Core Keeper.
3. Comprueba foco, cursor, estabilidad visual, rendimiento aparente y que no
   hay tearing fuera de la ventana del juego.
4. Sal del juego y desactiva el modo juego.
5. Repite el paso 1 en `/tmp/gm-despues.txt` y compara con
   `diff /tmp/gm-antes.txt /tmp/gm-despues.txt` (sin diferencias). Animaciones,
   blur, sombras, bordes y huecos deben verse como antes.
6. Activa y desactiva varias veces seguidas; al final
   `cortetsu shell ipc gameMode status` debe decir `INACTIVE` y el paso 5 seguir
   sin diferencias.

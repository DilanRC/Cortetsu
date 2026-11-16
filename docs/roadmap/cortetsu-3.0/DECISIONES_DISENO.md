# Decisiones de diseño de la ola de construcción 3.0

Complementa [ADR-008](../../architecture/adr-008-premium-sobria.md); no lo
sustituye. Estado de lo que describe: `IMPLEMENTADO_SIN_VERIFICAR`.

## Identidad

- Los cinco SVG oficiales del Evolving Mark no se tocaron.
- Bloqueo: sin cambios en esta ola (Ascended / Monster / Cosmic ya seguía a
  PAM desde la fase 7; `Pam.qml` intacto).
- Centro de control: Ascended quieto y monocromo, 28 px. Antes pasaba a
  Awakening con el puntero y a Monster al pulsar, lo que daba a Monster un
  significado distinto del fallo de autenticación.
- Sesión: se conserva Awakening al abrir; no se tocó la cabecera.

## Tokens

No se añadieron tokens ni se editó `CortetsuDesign.qml` (generado). Los
divisores escritos a mano (`Rectangle { height: 1 }` con alfa fija) pasan a
`CortetsuDivider`, que lee `separator_alpha` por tema: Ink 0,36, Washi 0,6,
Kurogane 0,8. En Washi y Kurogane las filas de Ajustes ganan contraste de
separación; es el valor que ADR-008 ya fijó para esos temas.

## Primitivas

| Cambio | Motivo |
| --- | --- |
| `CortetsuActionTile.compact` | Interruptores densos (56 px, una línea de detalle) sin crear otra primitiva |
| `SettingSliderRow.mutable` | Un nivel silenciable lleva su botón de silencio; evita una fila deshabilitada sin salida |
| `osd/LevelRow.qml` | Cabecera de nivel (silencio, nombre, valor, desplegable); archivo propio para no romper la recarga suave con un *inline component* |
| `CortetsuInkLabel` borrado | Sin usos tras el rediseño del centro de control |

## Interacción

| Superficie | Teclado | Ratón |
| --- | --- | --- |
| Centro de control | Tab recorre niveles, conexiones, interruptores y perfiles; la barra de perfiles es una parada con ←/→ | Botón de silencio, desplegable de dispositivos |
| Launcher | Tab sigue moviendo por resultados; Ctrl+←/→ cambia de categoría solo con la búsqueda vacía; las categorías no son paradas de Tab | Clic en categoría devuelve el foco a la búsqueda |
| Sesión | Primer Escape desarma una confirmación; el segundo cierra | La fila armada muestra los segundos que quedan |
| Polkit | Bloq Mayús visible antes del intento | — |
| Notificaciones | Búsqueda del historial: Escape la vacía antes de cerrar el panel | Quitar una entrada |

## Geometría

- Centro de control: 520 px de ancho como antes; el alto baja porque los
  cuatro interruptores pasan de 76 a 56 px y los dos de conexión comparten
  fila. Lista de dispositivos plegada por defecto.
- Notificaciones: lo que está en pantalla ocupa hasta el 55 % del panel; el
  historial, el resto.
- Launcher: la fila de categorías resta su alto del máximo de la lista.

## Accesibilidad

- `Accessible.role` en toasts (alerta), indicadores del dashboard y pestañas
  del dashboard.
- Ningún estado se comunica solo por color: el micrófono silenciado dice
  «Silenciado»; la GPU sin lectura lo dice.
- Movimiento: no se añadió ninguna animación en reposo.

## Temas

Ninguna superficie tocada fija un color fuera de los tokens. Washi no se
oscureció ni se recoloreó. Kurogane conserva radios 2/4/6/8.

## Datos y honestidad

- Perfil de energía: la selección es lo que informa el daemon.
- Ecualizador: sin nodo no hay controles.
- UPower sin estimación no se muestra como «Calculando…».
- Recientes del launcher: estado de ejecución en
  `~/.local/state/cortetsu/launcher-recent.json`, solo ids.

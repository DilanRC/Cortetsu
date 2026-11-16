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

## Segunda ola (2026-11-16)

Estado de todo lo descrito: `IMPLEMENTADO_SIN_VERIFICAR`.

### Composición

| Superficie | Decisión | Motivo |
| --- | --- | --- |
| Widgets de escritorio | Un `CortetsuSurface` por widget con `colorSurfaceGlass` al 82 % y `radiusLarge`; sin lavado de acento | Sobre el fondo, cada widget es su propio marco; el lavado es del protagonista de una vista y aquí no hay vista |
| Editor del escritorio | Velo del host (0,34), widgets dibujados encima, panel lateral en el lado opuesto al Hub, área útil marcada con una línea fina | Se ve lo que se edita sin las ventanas, y el panel no tapa el borde ocupado |
| Hoja de atajos | Un panel; grupos sin tarjeta, encabezados en el acento, filas con divisor; teclas con `KeyCap` | Datos, no controles: filas abiertas (ADR-008 §2.3) |
| Centro de control | Lo que suena y el mezclador entran solo cuando tienen con qué trabajar (reproductor, flujos) y el mezclador vive en el pliegue de audio | Progresión: compacto primero, detalle a demanda |
| Portapapeles | Filtros como `CortetsuTabBar`; limpiar armado en dos pasos | ADR-008 §2.6: lo destructivo se confirma |
| Popouts de teclado y Bloq Mayús | `CortetsuPopoutHeader`; Bloq Mayús/Num como `CortetsuFact` | Una familia; una lectura no reacciona al puntero (H-22) |

### Identidad

Sin cambios en los SVG del Evolving Mark. Ninguna superficie nueva usa
Monster ni Cosmic: siguen reservados al fallo y al éxito de PAM.

### Tokens

Ningún token nuevo ni edición de `CortetsuDesign.qml`. `EqCurve.qml` usa
`materialSeparatorAlpha` para su rejilla. El portapapeles deja de aclarar
sus tarjetas en Washi: oscurece sobre fondo claro como `CortetsuSurface`.

### Interacción

| Superficie | Teclado | Ratón |
| --- | --- | --- |
| Editor del escritorio | Tab/Mayús+Tab eligen; flechas mueven 8 px (Mayús, 32); + y − cambian el tamaño; Supr quita; Ctrl+Z / Ctrl+Mayús+Z / Ctrl+Y; Intro o Escape salen | Arrastre con guías y fantasma de destino; clic en el vacío deselecciona |
| Hoja de atajos | Se abre en la búsqueda; RePág/AvPág desplazan; Escape vacía y luego cierra | Editar abre Atajos y teclados |
| Vista general | `/` o Ctrl+F filtran; Intro enfoca la primera; Abajo vuelve a la rejilla; Escape vacía y luego cierra el filtro | — |
| Portapapeles | P fija, Intro copia, Supr borra (las acciones por fila no son paradas de Tab) | Botones con su tecla en el texto emergente |
| Lanzador | `>files texto` | Clic abre con `xdg-open` |

### Datos y honestidad

- Widgets: «Leyendo…» hasta la primera muestra; la batería no se ofrece sin
  batería; la galería de Ajustes dice por qué un tipo no está disponible.
- Luz nocturna: el estado del mosaico es el de `DisplayCalibration`
  (aplicando, falló, temperatura real).
- Ecualizador: la curva dibujada es la misma que dimensiona el preamp.
- Archivos: el estado vacío dice que el índice es de `plocate` y su edad.

### Movimiento

Sin animaciones en reposo nuevas. El medidor de nivel solo existe mientras
suena algo con el dashboard abierto. Los fundidos de la hoja y del editor
usan `motionFastMs`, que vale 0 con movimiento reducido.

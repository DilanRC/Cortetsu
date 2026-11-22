# Cierre Premium sobria (misión del 2026-11-21)

Registro de la misión `CORTETSU_3_0_GOAL_CIERRE_PREMIUM_SOBRIA.md`: requisito,
referencia, implementación, diferencia observada, corrección, prueba, evidencia
y estado. Se actualiza en cada commit de la misión.

## Punto de partida

- Checkout: `/home/dilan/Documentos/GitHub/Cortetsu`, remoto
  `github.com/DilanRC/Cortetsu`, rama `main`, HEAD inicial `5c2c09e0`,
  sin commits sin publicar. Cambios ajenos: `.codebase-memory/` (no se tocan).
- Generación instalada: `current_revision=5c2c09e0` (shell
  `20261121-105020-362729`). El checkout y lo que ejecuta Quickshell coinciden
  al empezar.
- Versiones: Quickshell 0.3.2 (`4f508be`), Qt 6.12.0, Hyprland 0.57.2,
  rustc 1.100.0.
- Referencias examinadas píxel a píxel: los ocho `assets/*.webp` del paquete
  Premium sobria (1440×810). Capturas de deficiencias del 21-11: no están en
  disco (se adjuntaron en otra conversación); se usó el vídeo
  `~/Vídeos/Kooha/Kooha-2026-11-21-13-13-43.mp4`, que muestra el centro de
  notificaciones a altura completa y la bandeja con el damero magenta.
  Las dos fotos del bloqueo Nebula tampoco están en disco.
- `MIGRACION_PROYECTO_ARCH_2026-09-02.md`: no encontrado; no se infiere su contenido.
- Nebula: `LilaccFlowerr/Nebula` en `9749c304` (2026-11-14), AGPL-3.0. Se
  estudió la composición de `widgets/lock/LockScene.qml` y sus piezas; no se
  copió código ni recursos.

## Herramienta de verificación

`scripts/verification/qml-stage.sh BODY.qml OUT.png` renderiza una pieza del
shell offscreen con bus D-Bus, estado y configuración privados y sin socket de
Wayland/Hyprland: no puede tocar el escritorio. `SETUP='notify-send …'` envía
avisos reales al servidor de notificaciones aislado. Limitación conocida: el
render por software no pinta `MultiEffect` ni los `Shape` del Evolving Mark;
esas piezas se comprueban en Agent Realms (`cortetsu realm up .`).

## Requisitos

| Requisito | Ref. | Implementación | Diferencia observada → corrección | Prueba / evidencia | Estado |
| --- | --- | --- | --- | --- | --- |
| Pills cápsula en todos los temas | 03, 05 | `CortetsuTab`, pista de `CortetsuTabBar`, `ChoiceChip` y `CortetsuButton.pill` usan radio = mitad de la altura | Kurogane las volvía cuadradas (`radiusSmall`/`radiusMedium`) → radio de cápsula sin excepción por tema | Realm: categorías del Launcher; escenario: filtros del centro | Hecho |
| `CortetsuTabBar` sin bucle de polish | — | `implicitWidth` fijo por pestaña con `fill` | El ancho de la barra y el de sus pestañas se perseguían (aviso de polish loop) | `qml-stage.sh` sin avisos | Hecho |
| Mini OSD arriba al centro del monitor | 06 | Cápsula en `drawers/Panels.qml`, por monitor, bajo un Hub superior | Estaba a la derecha, dentro del centro de control → separada; sin región de entrada | `test-cortetsu-osd-focus.sh`, escenario `osd.png` | Hecho (realm sin backlight ni PipeWire: disparo real pendiente de sesión) |
| OSD de música: carátula, título, artista, sin repeticiones | 06 | `osd/Wrapper.announceMedia()` con clave reproductor+pista+estado | Solo play/pausa, sin pista ni carátula | Escenario | Hecho |
| Tray sin textura | 04 | `Icons.getTrayIcon` resuelve tema → carpeta de la app (`IconThemePath`) → entrada; `TrayIconName.js` | La «textura» era el damero magenta de icono no encontrado: `item.icon \|\| getTrayIcon(...)` nunca llegaba al resolvedor | `tst_BottomHubTrayPolicy` (8/8) | Hecho |
| Centro de notificaciones proporcionado | 05 | `sidebar/Content.qml` alto según contenido, sobre el borde del Hub, columna lateral en pantallas anchas | Panel de altura completa para un vacío → 1 estado vacío corto | Realm `sidebar` y escenario con 6 avisos | Hecho |
| Semántica real del almacenamiento | — | Textos y filtros: «Todas / En pantalla / Anteriores» | `notifs.json` guarda las no descartadas; «Historial» duplicaba las vivas y «las que descartes se guardan aquí» era falso | Escenario `sf3` | Hecho |
| Variantes por contenido | 05 | `notifications/NotificationKind.js` (categoría FDO, `value`, urgencia, `desktop-entry` de MPRIS) | Icono por palabras del título → por metadatos | Escenario: progreso, mensaje, captura, red, urgente | Hecho |
| Modo privado | 05 | `CortetsuConfig.notificationPrivate`: oculta título, cuerpo e imagen en avisos, centro e historial | — | Escenario | Hecho |
| Launcher expandido | 03 | `LauncherNav` (vistas reales), `LauncherFavourites`, `Apps.browse` con `all/favourites/recent/homeRest` | Sin navegación ni fila de favoritos | Realm `launcher.png` | Hecho |
| Bloqueo rico | 07 + Nebula | `lock/LockCard.qml`: marca con halo y horizonte, reloj, cápsula de usuario y de contraseña, estado PAM, alas, barra inferior, modo ambiente | Escena plana | `test-cortetsu-lock-card-runtime.py`, `test-cortetsu-lock-runtime.py`, escenario `lock-after.png` | Hecho (PAM con credenciales reales: lo prueba el propietario) |
| Hub movible a lo largo del borde | 04 | `HubAnchor.packedStart/sanitizeOffsets`, `bottomHub.offsets` por monitor, «Distancia a la esquina» en Ajustes → Hub | Solo ocho anclajes fijos → desplazamiento acotado al área útil | `tst_HubAnchor` (562), realm `hop2` (abajo‑izquierda +400 px) | Hecho |
| Centro de notificaciones sigue al Hub | 04, 05 | `ScreenState.sidebarAlong` publicado por el Hub; `HubAnchor.popoutPosition`; región de entrada en su posición | Abría siempre en el borde derecho | Realm `hop2`, `hop3` (lateral derecho) | Hecho |
| Vista «Favoritos» del Launcher | 03 | `Apps.browse` | Un `const favourites` local sombreaba la función: `ReferenceError` | `test-cortetsu-launcher-apps-runtime.py` (rojo sin el arreglo) | Corregido |
| Ajustes → Wi‑Fi | 01 | Ya existente: héroe, propiedades, copiar contraseña, desconectar, olvidar | Sin «Uso de la red»: no hay contador real | `test-cortetsu-settings-runtime.py` + render `page-wifi.png` | Conforme |
| Capa de `cortetsu-background` | — | `bottom` siempre | Sesión real: `bottom` solo la contiene a ella, `background` vacía; widgets dentro de la misma ventana | `hyprctl layers -j` | Sin regresión con Orbital apagado |
| Orbital, compilación y pruebas | — | `desktop-runtime-rs` | `orbital_session.rs` compila; 105 pruebas en verde | `cargo test` | Hecho |
| Orbital, protocolo del supervisor | — | binario instalado, estado privado | Scene y Video compatibles; Image → flujo estático; proyecto roto, ruta inexistente, JSON inválido, monitor inexistente y línea > 64 KiB con su motivo; segundo supervisor bloqueado sin tocar el primero; EOF sale limpio sin escribir `orbital.json` | ejecución manual registrada | Hecho |
| Orbital, reproducción real | — | `test-orbital-nested-playback.py` en `nested-regressions.py` | Video `1129108416` y Scene `1182650930` llegan a Activo solo con su superficie en la salida; `busy` rechazado; stop y EOF no dejan motor ni superficie. El mensaje de `transition-timeout` ahora distingue «sin superficie» de «cubierta sin confirmar» | Hyprland anidado en WS 9, Mesa | Hecho |
| Ajustes rápidos amplio | 02 | `osd/FullContent` en rejilla de dos columnas, acciones de seis en fila, conmutador persistido | Solo columna única | `test-cortetsu-quick-settings-runtime.py`, realm `quick-settings-wide` | Hecho |
| Widgets | 08 | Reloj protagonista sin caja; tarjetas con icono y nombre; clima en español desde el código WMO | Tarjetas sin cabecera; «Clear» en inglés | realm `widgets`, `test-weather-refresh.py` | Hecho |
| Pills en los tres temas | 03 | — | — | escenario `pills-ink-washi-kurogane` | Hecho |

## Adaptaciones deliberadas

- Bloqueo: sin botones de apagar/reiniciar/suspender en la escena (el
  concepto los dibuja): no hay confirmación posible sin sesión y no aportan
  al desbloqueo. Sin selector de usuario: una sesión, un usuario.
- Centro de notificaciones: sin «No leídas» ni gráfico de actividad: el
  almacenamiento no registra lectura ni actividad diaria.
- Favoritos: sin botón «Añadir» en la fila; fijar sigue siendo el clic
  derecho sobre una app (no existe un selector que justifique el botón).

## Instalación

Push → instalar → recargar → journal, por revisión: `abf0174a`, `605a91c1`,
`c865c69b` (actual). Generación anterior conservada; `cortetsu rollback`.
Medición en reposo tras dos recargas suaves: 0,1 % de CPU, RSS 594 MiB
(las recargas suaves retienen memoria del motor anterior; no es comparable
con los 503,8 MiB de cgroup del arranque).

## Revisión

Corrección y mantenibilidad revisadas por el mismo agente, en secuencia y
sin subagentes (preferencia registrada): no hay independencia entre revisor y
autor. Hallazgos corregidos durante la misión: bucle de polish de
`CortetsuTabBar`, bucle de layout del centro de notificaciones (congelaba el
shell), `ReferenceError` en la vista Favoritos, duplicado historial/en
pantalla, textos falsos sobre el almacenamiento, región de entrada del centro
anclada al borde derecho, mensaje de timeout de Orbital engañoso.

## Pendiente

- Sesión física (teclas multimedia y de brillo, bandeja con Spotify/Chrome,
  PAM real, `showOnHover`): «Cierre Premium sobria» en `QA_POSTERIOR.md`.
- Orbital en la sesión física: GPU (dGPU suspendida durante Scene/Video),
  batería, DPMS, suspensión y dos salidas reales; propietario externo y
  `kill -9` del motor (escenarios de la sección Orbital de `QA_POSTERIOR.md`).
- Ajustes rápidos: la referencia muestra tres columnas con navegación
  lateral; la vista amplia es de dos columnas sin navegación propia (las
  páginas de detalle siguen en Ajustes).
- Widgets: anillos de rendimiento y monitores del concepto 08 no se
  implementaron; los widgets existentes muestran sus datos reales en barras.

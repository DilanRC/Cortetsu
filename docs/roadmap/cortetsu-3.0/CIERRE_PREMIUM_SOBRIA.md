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
| Bloqueo: PAM real en la sesión | 07 | — | Contraseña errónea: Monster en rojo, borde y mensaje; correcta: Cosmic verde, halo, «Desbloqueando…» | 16 capturas en vivo (`lock-live-rejected-monster`, `lock-live-accepted-cosmic`) | Hecho |
| Bloqueo rico | 07 + Nebula | `lock/LockCard.qml`: marca con halo y horizonte, reloj, cápsula de usuario y de contraseña, estado PAM, alas, barra inferior, modo ambiente | Escena plana | `test-cortetsu-lock-card-runtime.py`, `test-cortetsu-lock-runtime.py`, escenario `lock-after.png` | Hecho (PAM con credenciales reales: lo prueba el propietario) |
| Hub movible a lo largo del borde | 04 | `HubAnchor.packedStart/sanitizeOffsets`, `bottomHub.offsets` por monitor, «Distancia a la esquina» en Ajustes → Hub | Solo ocho anclajes fijos → desplazamiento acotado al área útil | `tst_HubAnchor` (562), realm `hop2` (abajo‑izquierda +400 px) | Hecho |
| Centro de notificaciones sigue al Hub | 04, 05 | `ScreenState.sidebarAlong` publicado por el Hub; `HubAnchor.popoutPosition`; región de entrada en su posición | Abría siempre en el borde derecho | Realm `hop2`, `hop3` (lateral derecho) | Hecho |
| Vista «Favoritos» del Launcher | 03 | `Apps.browse` | Un `const favourites` local sombreaba la función: `ReferenceError` | `test-cortetsu-launcher-apps-runtime.py` (rojo sin el arreglo) | Corregido |
| Launcher: Sistema, Ordenar y Ver | 03 | Tarjeta Sistema (CPU/RAM/disco en anillos, muestreo solo con el Launcher abierto); «Aplicaciones · N»; orden nombre/recientes y vista cuadrícula/lista, persistidos | Faltaban | realm `launcher-system-card`, `launcher-list-sort` | Hecho |
| Launcher al pasar el puntero | — | Preferencia `launcher.showOnHover` del propietario a `false` (copia `preferences.json.bak-*`) | El Launcher se abría al acercar el puntero al Hub: la opción estaba activada en su archivo (por defecto viene apagada) | petición del propietario | Hecho |
| Hallazgo previo | — | — | `test-cortetsu-launcher.py:99` falla desde antes de la misión (`M3Variants.qml` sin cambios); ninguna suite de `cortetsu test` lo ejecuta | — | Anotado |
| Ajustes → Wi‑Fi | 01 | Ya existente: héroe, propiedades, copiar contraseña, desconectar, olvidar | Sin «Uso de la red»: no hay contador real | `test-cortetsu-settings-runtime.py` + render `page-wifi.png` | Conforme |
| Capa de `cortetsu-background` | — | `bottom` siempre | Sesión real: `bottom` solo la contiene a ella, `background` vacía; widgets dentro de la misma ventana | `hyprctl layers -j` | Sin regresión con Orbital apagado |
| Orbital, compilación y pruebas | — | `desktop-runtime-rs` | `orbital_session.rs` compila; 105 pruebas en verde | `cargo test` | Hecho |
| Orbital, protocolo del supervisor | — | binario instalado, estado privado | Scene y Video compatibles; Image → flujo estático; proyecto roto, ruta inexistente, JSON inválido, monitor inexistente y línea > 64 KiB con su motivo; segundo supervisor bloqueado sin tocar el primero; EOF sale limpio sin escribir `orbital.json` | ejecución manual registrada | Hecho |
| Orbital, reproducción real | — | `test-orbital-nested-playback.py` en `nested-regressions.py` | Video `1129108416` y Scene `1182650930` llegan a Activo solo con su superficie en la salida; `busy` rechazado; stop y EOF no dejan motor ni superficie. El mensaje de `transition-timeout` ahora distingue «sin superficie» de «cubierta sin confirmar» | Hyprland anidado en WS 9, Mesa | Hecho |
| Orbital, fallos y propiedad | — | misma prueba anidada | `kill -9` del motor: dos reinicios en 120 s y al tercero «restart limit»; motor lanzado fuera de Orbital: `foreign-owner`, su proceso intacto; `orbital.json` corrupto, de versión 99 o con campo desconocido: el supervisor se detiene con motivo y no reescribe el archivo; `--volume`/`--silent` nunca juntos (prueba unitaria) | `test-orbital-nested-playback.py` | Hecho |
| Orbital en la sesión real | — | fondo animado activo en eDP‑1 (proyecto `3499970162`, 30 FPS, `--hwdec no`, GPU integrada) | dGPU NVIDIA en `suspended` durante la reproducción; motor: 26 % de un núcleo, 197 MiB RSS, con AC | `/sys/bus/pci/devices/0000:01:00.0/power/runtime_status`, `/proc` | Medido |
| Orbital con batería (sesión real) | — | `pauseOnBattery` (por defecto) | Desenchufado (descargando, 100 %): el motor queda dormido, 0 % de CPU en 20 s; equipo a 27,8 W. La dGPU estaba activa por Steam (abierto desde «Steam Workshop»), no por el motor, que no tiene abierto ningún `/dev/nvidia*` | `/proc`, `power_now`, `fuser /dev/nvidia*` | Medido |
| Orbital y DPMS (sesión real) | — | — | Un ciclo apagar/encender pantalla con Orbital pausado por batería: mismo PID del motor, capas sin cambios (cubierta estática), pantalla de vuelta, journal sin errores | `hyprctl` y journal | Hecho |
| Orbital con dos monitores (sesión real) | — | IPC `orbital copy` | eDP‑1 y HDMI‑A‑1 a la vez, un motor y una superficie por salida, HDMI animado | `orbital-hdmi-suspend-timeline.log` 23:58:07 | Hecho |
| Desconectar y reconectar HDMI | — | `Session.lost`: lo que sonaba vuelve al reconectar | Volvía en `stopped` (dependía de restoreOnStart, apagado tras Detener) → ahora vuelve a `active` en 5 s; eDP‑1 intacto | registro 00:07:44–00:09:16; prueba anidada con salida virtual (roja antes, verde después) | Corregido y verificado |
| Suspender y despertar | — | `TICK_FAILURE_LIMIT` = 3 | Tras despertar, un fallo de `hyprctl` dejaba ambos monitores en `error compositor` → ahora `paused resume` y `active` a los 12 s | registro 00:12:29–00:12:41 | Corregido y verificado |
| Avisos al quitar un monitor | — | `modelData?.name`, `root.screen?.name` | 4 TypeError en el journal | journal | Corregido |
| Fondo Steam reproduciendo con batería (sesión real) | — | «Reproducir también con batería» / IPC `orbital replay eDP-1 false`; doble clic aplica | «No se aplicaba»: se aplicaba y la pausa por batería lo detenía al instante | estado `active`, superficie `linux-wallpaperengine` mapeada, dos fotogramas distintos; motor 11 % de un núcleo, equipo 38,4 W, dGPU `suspended` | Hecho |
| Portadas de la biblioteca | — | Revertido `retainWhileLoading` en `CortetsuRoundedImage` | Regresión propia: todas las tarjetas a «Sin portada» en la sesión real | captura en vivo tras el arreglo | Corregido |
| Hub: ocho anclajes con el centro abierto | 04 | IPC `bottomHub setAnchor/setOffset` | El centro sigue abierto y se recoloca junto a la campana, hacia dentro, en los ocho | `hub-eight-anchors-center-open-realm` | Hecho |
| Hub: autohide, pantalla completa | 04 | `tst_BottomHubAutoHide` (6); `test-cortetsu-hub-fullscreen-nested.py`: shell real en Hyprland anidado, Hub en la capa `top` (la que cubre una ventana a pantalla completa), ventana en `fullscreen 2`, el centro de notificaciones no se abre encima | — | pruebas QML y anidada | Hecho |
| Ajustes → Wi‑Fi completo | 01 | Tarjetas «Uso de la red» (contadores del kernel desde el arranque y último minuto) y «Tema y apariencia» (Ink/Washi/Kurogane) | Faltaban las dos tarjetas del concepto | `test-cortetsu-settings-runtime.py`, `settings-wifi-harness.png` | Hecho |
| Spotify: letra y ventana | — | Spicetify reaplicado tras la actualización de Spotify; Spotify fuera de `special:music`, SUPER+M lo enfoca o abre en el espacio activo | La letra no llegaba (Spotify cargaba su `xpui.spa` original); la ventana se abría como capa especial encima de todo | `lyrics status`: `source spotify, synced, 20 lines`; `hyprctl clients`: ws 1, fullscreen 0 | Hecho |
| Biblioteca de fondos | — | Imágenes y Workshop en una biblioteca amplia, tarjetas clicables, botón Steam Workshop, vista compacta opcional | Steam separado, había que pulsar el nombre | sesión real: 40 imágenes + 153 Workshop, `wallpaper-library-realm.png` | Hecho |
| Ajustes rápidos amplio | 02 | Columna de navegación (Resumen, Conectividad, Audio, Notificaciones, Energía, Acciones), tres columnas de tarjetas, tarjeta de notificaciones, conmutador persistido | Solo columna única | `test-cortetsu-quick-settings-runtime.py`, realm `quick-settings-three-columns` | Hecho |
| Widgets | 08 | Reloj protagonista sin caja; tarjetas con icono y nombre; anillos de CPU/GPU/memoria con temperatura; widget Monitores con datos de Hyprland y acceso a Ajustes → Pantalla; clima en español desde el código WMO | Tarjetas sin cabecera, barras, sin monitores, «Clear» en inglés | realm `widgets`, `widgets-rings-monitors` | Hecho |
| Teclas multimedia (camino MPRIS) | 06 | — | Play, siguiente, volumen y pausa: una cápsula por cambio, con portada, título y artista reales, bajo el Hub superior; suprimida sobre ventanas a pantalla completa, por política | `mini-osd-media-volume-live` | Hecho |
| Hub sobre una ventana a pantalla completa (sesión real) | 04 | — | Con kitty en `fullscreen 2` el Hub no se ve en ninguna captura | capturas de la sesión | Observado |
| Bandeja con apps reales | 04 | `Icons.getTrayIcon`: pixmap de revisión 0 = sin icono; respaldo por id, tooltip y título, búsqueda por nombre visible y `/usr/share/pixmaps` | Linux Wallpaper Engine (Electron) no publica icono: salía el damero | `tray-live-before-checker` → `tray-live-fixed`; IPC `bottomHub trayIcons` | Hecho |
| Mini OSD en la sesión real | 06 | — | — | `wpctl` +1 % y brillo 95 % sobre eDP‑1, restaurados: `mini-osd-volume-live`, `mini-osd-brightness-live` | Hecho |
| Matriz visual oficial | todas | `cortetsu realm qa .` | 155 comprobaciones, 0 fallos, 80 capturas (fondo oscuro/claro, transparencia, movimiento reducido); 5 avisos sin clasificar, todos `text-input-v3` de Qt | `qa-light-wallpaper-realm` | Hecho |
| Tres temas | todas | `render-cortetsu-theme-surfaces.py` | Ink, Kurogane y Washi conservan su identidad; cápsulas en los tres | `surfaces-ink-kurogane-washi-harness`, `pills-ink-washi-kurogane-stage` | Hecho |
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

- Independiente: Codex `gpt-6-luna`, solo lectura, sobre todo el diff
  `5c2c09e0..HEAD`. Corrección: un P2 válido (la búsqueda del modo privado
  comparaba el texto oculto y el contador lo delataba), corregido en
  `09c5463e`. Mantenibilidad: dos P3 válidos (comentario de filtros
  desfasado, aserción literal duplicada), corregidos en `1ed70116`.
- Del autor, durante la misión: bucle de polish de `CortetsuTabBar`, bucle de
  layout del centro (congelaba el shell), `ReferenceError` en Favoritos,
  duplicado historial/en pantalla, textos falsos sobre el almacenamiento,
  región de entrada anclada al borde derecho, mensaje de timeout de Orbital.

## Pendiente (solo lo que exige al propietario)

- Teclas multimedia pulsadas físicamente (el camino MPRIS que siguen ya está verificado en vivo).
- Orbital en hardware: suspensión (el propietario despierta el equipo) y dos
  salidas físicas (no hay un segundo monitor conectado). Batería pausada y
  reproduciendo, dGPU dormida y DPMS ya medidos. Abrir la Workshop arranca Steam, que despierta
  la dGPU: es Steam, no Orbital.

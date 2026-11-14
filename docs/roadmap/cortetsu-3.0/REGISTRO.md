# Cortetsu 3.0: registro por fase

Plan: [`CORTETSU_3_0_PLAN_MAESTRO.md`](../CORTETSU_3_0_PLAN_MAESTRO.md).
Decisiones: [ADR-008](../../architecture/adr-008-premium-sobria.md).
Estados: `NOT_STARTED`, `IN_PROGRESS`, `PARTIAL`, `DONE_WITH_CONCERNS`, `VERIFIED`.
Un estado solo sube con la evidencia que cita. Lo que no se probó se dice.

| Fase | Estado |
| --- | --- |
| 0 Línea base y mapa de propiedad | DONE_WITH_CONCERNS |
| 1 Biblioteca Premium sobria y marca | IN_PROGRESS |
| 2 Settings integral y Launcher | IN_PROGRESS |
| 3 Hub multiposición | DONE_WITH_CONCERNS |
| 4 Islas, popouts y tray | DONE_WITH_CONCERNS |
| 5 OSD 3.0 y Ajustes rápidos | PARTIAL |
| 6 Centros de servicio | NOT_STARTED |
| 7 Lockscreen, Dashboard y widgets | PARTIAL |
| 8 Audio avanzado y superficies restantes | NOT_STARTED |
| 9 Certificación | NOT_STARTED |

#### Fase 0 - Línea base y mapa de propiedad

- Estado: DONE_WITH_CONCERNS
- Fecha / rama / HEAD inicial: 2026-11-12, `main`, `36dea6db` (8 commits por delante de `origin/main` `97d40b4c`, el HEAD que cita el plan).
- Propiedad de archivos y backups: todo lo tocado está en Git. Generación instalada `20261112-123052-132232` (fuente `0b2fc365`), anterior `20261112-120953-59643`; no se instaló ni se recargó nada. `.codebase-memory/` tenía cambios ajenos y no se toca.
- Inventario: [`qml-inventory.md`](qml-inventory.md), generado por `scripts/verification/qml-inventory.py` (`--check` lo compara con el árbol). 403 QML: 326 propios, 61 de prueba, 7 de compatibilidad, 1 generado y 7 que nada referencia.
- QML sin referencias (candidatos a borrar al rediseñar su zona, no ahora): `components/CAnim.qml`, `modules/bar/components/Clock.qml`, `modules/bar/components/StatusIcons.qml`, `services/UsageFmt.qml`, `utils/CortetsuUtils.qml`, `utils/NetworkConnection.qml`, `utils/SysInfo.qml`.
- Capturas: [`docs/evidence/cortetsu-30-baseline-20261112/`](../../evidence/cortetsu-30-baseline-20261112/): superficies compartidas y Settings (Inicio, Wi-Fi) en Ink, Washi y Kurogane. La matriz completa de Settings (540 capturas) se regenera con `scripts/features/test-cortetsu-settings-visual.py`.
- Medición: [`baseline.json`](../../evidence/cortetsu-30-baseline-20261112/baseline.json). Shell en vivo: PSS 353 MiB, 70 hilos, 7 procesos hijo, 0 reinicios; NVIDIA `suspended`; linter de diseño con 29 hallazgos.
- Limitaciones: `HDMI-A-1` no estaba conectado, así que no hay línea base de dos monitores. `MIGRACION_PROYECTO_ARCH_2026-09-02.md` no existe en el equipo (búsqueda en todo el disco). No se midió primer fotograma ni CPU a 60 s por superficie; `docs/PERFORMANCE.md` conserva la referencia anterior.
- Mockups: `docs/roadmap/assets/` son referencia de composición. No son fuente de datos, marcas ni funciones.
- Rollback: `git revert` de los commits de la fase; nada instalado.
- Decisión de gate: se continúa. La línea base de HDMI queda pendiente para la fase 9.

#### Fase 1 - Biblioteca Premium sobria y marca

- Estado: IN_PROGRESS
- Hecho: ADR-008; tokens `separator_alpha` y `hero_wash_alpha` en `ui.toml` con valor por tema; `CortetsuDivider`, `CortetsuHero`, `CortetsuFact`, `CortetsuTabBar`; superficie piloto: Settings → Wi-Fi.
- Pruebas: `tests/qml/components/tst_PremiumSobria.qml` (7), `cortetsu theme check`, gate de Settings con contraste en los tres temas.
- Pendiente: galería de la biblioteca, migrar los divisores y barras de pestañas escritos a mano en las superficies aún no rediseñadas.

#### Fase 2 - Settings integral y Launcher

- Estado: IN_PROGRESS
- Hecho: Settings en un solo marco (barra lateral y página comparten hoja); Wi-Fi y Bluetooth sin paneles de 580 px, con altura según contenido; hero de red; olvidar red o perfil pide confirmación; selector de posición del Hub.
- Pruebas: `scripts/features/test-cortetsu-settings-runtime.py` (navegación, estados, teclado, persistencia, contraste), 30 destinos renderizados en Ink, Washi, Kurogane y ventana estrecha.
- Launcher (2026-11-13): ya abría compacto; las celdas dejan de llevar un marco cada una (solo la selección tiene fondo y borde) y un nombre largo ocupa dos líneas antes de cortarse. Captura: `docs/evidence/cortetsu-30-launcher-20261113/`. Pasan `tests/qml/launcher` y `scripts/integration/test-launcher-dismiss.py` (anidado, 25 comprobaciones).
- Fallos previos, no causados por este trabajo (fallan igual en `f47f9c0c`): `test-cortetsu-launcher-apps-runtime.py` y `test-cortetsu-launcher-mode-actions-runtime.py`; tampoco pasan `test-cortetsu-native-design-system.py` ni `test-cortetsu-button-tooltip.py`. Ninguno está en un gate.
- Inicio (2026-11-13): las cuatro tarjetas iguales (red, Bluetooth, sonido, energía) pasan a un grupo "Estado" de filas que abren su página; una alerta se nombra en bermellón y lo normal queda en una línea. El bloque del escritorio es el `CortetsuHero` de la página.
- Pendiente: repaso de las páginas restantes contra ADR-008, modo de exploración del Launcher (categorías, recientes).

#### Fase 3 - Hub multiposición

- Estado: DONE_WITH_CONCERNS
- Fecha / rama: 2026-11-13, `cortetsu-3.0-hub-wip` fusionada en `main`.
- QML / servicios / tokens: `HubAnchor.js` (modelo), `HubFlow.qml`, `BottomHub.qml`, `CortetsuBottomHubView.qml`, los cinco segmentos, `StatusPill`, `HubButton`, `CortetsuTooltip` (colocación `below` y `left`), `bar/popouts/{Wrapper,ClipWrapper}.qml`, `drawers/Panels.qml`, `sidebar/Wrapper.qml`, `dashboard/Wrapper.qml`, `CortetsuConfig.qml`, `settings/controls/HubAnchorPicker.qml`, `settings/sections/BottomHubSection.qml`.
- Funcionalidad nueva: ocho anclajes, Hub lateral con islas apiladas, anclaje por monitor, selector en Ajustes, IPC `anchor`/`clearAnchor`/`anchors`, máscara de entrada ajustada a las islas (antes toda la franja capturaba el puntero), denominación visible "Hub".
- Funcionalidad conservada: `bottom-center` es el valor por defecto y de recuperación; destinos IPC, namespace y claves de preferencias sin cambios.
- Capturas: [`docs/evidence/cortetsu-30-hub-20261113/`](../../evidence/cortetsu-30-hub-20261113/).
- Pruebas: `tst_HubAnchor.qml` (445 comprobaciones de geometría), `scripts/integration/test-hub-anchors.py` (compositor real anidado: capa, zona reservada, popout, hover y clic reales en los ocho anclajes, anclaje por monitor, valor inválido, persistencia, log limpio), `test-bottomhub-hover-close-race.py`, `test-bottomhub-wayland-policy.py`, `test-hover-edges.py`, `test-launcher-dismiss.py`, `test-native-bottom-hub.py`, `cortetsu test` completo.
- Limitaciones: no instalado en la sesión real; sin prueba en `eDP-1` + `HDMI-A-1` físicos con anclajes distintos ni a escala 1.25; fullscreen y modo juego solo probados con el Hub abajo; el modo de edición con arrastre no existe (se elige en Ajustes o por IPC); el launcher y la cuenta de `bottomHubHeight` del OSD compacto no se revisaron con el Hub lateral.
- Rollback: `qs ipc call bottomHub -- anchor "" bottom-center` devuelve el Hub abajo sin tocar código; `git revert` del commit de la fase.
- Decisión de gate: código y pruebas anidadas en verde; la matriz física queda para la fase 9.

#### Fase 4 - Islas, popouts y tray

- Estado: DONE_WITH_CONCERNS (certificación física hecha el 2026-11-14; quedan tres huecos, ver "Certificación física")
- Fecha / rama: 2026-11-13, `main`.
- QML modificados: `bar/popouts/{CortetsuPopoutHeader (nuevo),CortetsuNetworkPopup,CortetsuBluetoothPopup,CortetsuAudioPopup,CortetsuTrayMenu,Wrapper}.qml`, `components/CortetsuTooltip.qml`, `BottomHub.qml`, `CortetsuBottomHubView.qml`, `CortetsuTraySegment.qml`, `drawers/ContentWindow.qml`.
- Popouts de servicio (nivel 1 de ADR-008): una cabecera común con el estado, el interruptor del servicio y el enlace a su página de Ajustes, que cierra el popout. Red: el interruptor de Wi-Fi espera a NetworkManager, dice "Aplicando…" y muestra el rechazo; "No hay otras redes" si ya hay una conectada. Bluetooth: una línea en lugar de cabecera más tarjeta que la repetía; la batería solo si BlueZ la informa; apagado es un estado, no un error. Audio: la entrada (micrófono) junto a la salida, con nivel, silencio y elección de dispositivo. Plurales correctos ("1 conectado", "1 dispositivo", "1 red").
- Bandeja, tres defectos previos (presentes en `a352a342`):
  1. **Solo el primer clic derecho llegaba al icono.** El tooltip del Hub es un `Popup` que se mantiene dentro de la ventana del Hub (74 px de alto); sin sitio encima del icono se colocaba sobre él y se quedaba el clic. Un tooltip de dos líneas (título y descripción, lo normal en la bandeja) tapaba el centro del icono. Ahora cada tooltip informa de su tamaño al Hub, que reserva ese espacio en su lado interior de forma permanente y fuera de la máscara de entrada: el tooltip sale encima del icono y el clic pasa. No crece al pasar el puntero, porque redimensionar la ventana bajo un puntero quieto hacía que Hyprland descartara el siguiente clic (medido). El ancho del tooltip queda limitado a 320 px con elipsis.
  2. **El teclado no llegaba al menú.** Un menú abierto con clic derecho o la tecla Menú recibe ahora las flechas, Inicio/Fin, Intro, Espacio y Escape escritas en el icono: el Hub ya tiene el teclado tras el clic (OnDemand) y se las pasa al menú. La ventana del popout no toma el teclado. Un menú abierto por hover no captura nada. Intro activaba el icono en vez de la fila, porque `Keys` emite `returnPressed` antes que `pressed`.
  3. **Un menú abierto por hover no se cerraba** si el puntero salía del icono sin pasar por el menú: la bandeja no avisaba de la salida al controlador de hover. El menú abierto con clic se comporta como uno nativo: no se cierra al salir el puntero y sí con un clic fuera (focus grab).
- Pruebas: `scripts/integration/test-popout-cycles.py` (gate de la fase, Hyprland anidado con dos salidas y un proveedor SNI/DBusMenu real: 40 popouts de servicio en un solo monitor, 10 menús de bandeja con clic derecho real y teclado, cierre por Escape, clic fuera y salida del hover; capas iguales al final, RSS sin crecer, log limpio). `scripts/features/test-cortetsu-service-popouts-runtime.py` (15 comprobaciones, añadida a `build-regressions.sh`). `test-cortetsu-button-tooltip.py` ahora comprueba en todo el árbol que ningún botón solo icono queda sin tooltip; antes miraba una lista fija que había quedado obsoleta (fallaba por `Dash.qml`). Se borró `eval-cortetsu-button-tooltip.py`, que duplicaba esa prueba con cadenas obsoletas y ya fallaba (auditoría del 2026-10-23).
- Tooltip de la bandeja: no aparece mientras su propio menú está abierto (en el Hub lateral tapaba una fila) ni por el foco que deja un clic; sí con el foco de Tab.
- Resultados: el gate pasó en 12 de 13 ejecuciones completas (40 popouts y 10 o 20 menús por ejecución; 6 seguidas con 20 menús). La ejecución fallida fue un cierre de Quickshell al abrir un menú de bandeja, con el gestor de fallos reiniciando el shell. No se reprodujo en las 12 siguientes y no hay volcado: queda como riesgo abierto. RSS entre −3 y +8 MiB tras 50 a 60 ciclos. También pasan `test-hub-anchors.py`, `test-bottomhub-hover-close-race.py`, `test-hover-edges.py`, `test-launcher-dismiss.py`, `test-bottomhub-wayland-policy.py`, `cortetsu test` completo y `build-regressions.sh` sobre un runtime preparado en un directorio temporal.
- Capturas: [`docs/evidence/cortetsu-30-popouts-20261113/`](../../evidence/cortetsu-30-popouts-20261113/): los tres popouts en reposo y en estados (Wi-Fi rechazado, Bluetooth apagado, sin audio) y el menú de bandeja con el Hub abajo, a la derecha y arriba a la izquierda. Solo Ink.
- Coste: la ventana del Hub crece en su lado interior lo que mide el tooltip más grande (en la prueba, 118 px de alto abajo y 365 px de ancho en lateral, antes 74 y unos 66). Esa franja es transparente y está fuera de la máscara de entrada; no cambia la zona reservada.
- Fallo previo no causado por esto: `eval-bottom-hub-design.py` ("centro geométrico") falla igual en `a352a342`; no está en ningún gate.
- No probado: sesión real, `HDMI-A-1`, escala 1.25, aplicaciones reales de bandeja (Steam, Discord, nm-applet) con menús de varios niveles, lector de pantalla.
- Pendiente de la fase (resuelto en el bloque 2): morphing de islas, vista previa de ventanas en el carril de aplicaciones, modo de edición del Hub con arrastre.
- Rollback: `git revert` del commit; ningún contrato de IPC cambió (se añade `trayButton`, de solo lectura, y `keyboardHeld` en `inspect`).

#### Fase 4, bloque 2 - Cierre intermitente, islas, vista previa y modo de edición (2026-11-13)

- HEAD inicial `91570fb3`; commits `6a83bdb6` (bandeja), `52030618` (cajones), `3b74932b` (modo de edición), `38c5b8f3` (vista previa), `17e750a7` (islas) y los de arnés y documentación que siguen. Sin push, sin instalar, sin recargar la sesión.
- Evidencia completa: [`docs/evidence/cortetsu-30-phase4-20261113/`](../../evidence/cortetsu-30-phase4-20261113/README.md).
- **Cierre intermitente: causa confirmada.** Defecto de Qt 6.12 en el backend por software con render en hilo (`QQuickShapeSoftwareRenderNode::render` lee la ventana de un `Shape` destruido en mitad del fotograma), disparado por Cortetsu: cerrar un menú de bandeja por teclado o acción hacía parpadear `hasCurrent` y `Content.qml` reconstruía el menú visible. Dos volcados en `systemd-coredump`, reproductor con 2 caídas en 4 ejecuciones antes y 0 en 6 después. Corregido: el menú reabierto se reinicia en el sitio. Regresión en el gate que falla contra `91570fb3`.
- Segundo disparador del mismo defecto, previo y sin relación con la bandeja: `test-bottomhub-hover-close-race` caía 2 de 5 veces también en `91570fb3` (un popout destruido justo al terminar su fundido). Antes pasaba sin que se viera porque el gestor de fallos reinicia el shell y el informe se borraba con el HOME temporal. Las pruebas anidadas pasan a renderizar como la sesión (RHI sobre Mesa; `CORTETSU_TEST_QUICK_BACKEND=software` devuelve el modo anterior) y el arnés conserva y señala todo informe de fallo.
- Islas: estados de reposo, hover, foco y `engaged` (índigo, inclinación de 2 px hacia el popout), elevación según el tema, grupos a 12 px y Sistema a 4 px, deslizamiento al crecer, cambio de borde instantáneo, popouts que nacen de su control, tooltips que se apartan. Sin animaciones en reposo; movimiento reducido instantáneo.
- Vista previa de ventanas: hover (450 ms) o tecla Menú; miniatura de un fotograma o icono; título, espacio, cerrar, traer aquí, nueva ventana, fijar; teclado completo; una ventana cerrada se lleva su tarjeta. Desactivable en Ajustes (hover y miniaturas).
- Modo de edición: arrastre con destino iluminado, ajuste al soltar, flechas, Inicio, Intro, Escape; guarda por monitor; termina si el monitor se va; la posición propia vuelve al reconectar, también a escala 1.25.
- Pruebas nuevas: `tst_HubIslands`, `tst_WindowPreview`, 115 casos más en `tst_HubAnchor` (560), `test-cortetsu-hub-islands-runtime.py` (en `build-regressions.sh`), `scripts/integration/test-hub-previews-edit.py` (gate anidado), regresión de reapertura en `test-popout-cycles.py`.
- Rendimiento (anidado, antes/después): PSS en reposo 300–303 / 296–299 MiB; CPU en reposo igual; +8 % de CPU en 40 ciclos de popout; apertura de la vista previa ~97 ms; NVIDIA `suspended` antes y después en el arnés (que fuerza Mesa).
- Fallos previos que siguen y no están en ningún gate: `test-bottom-hub-v3.py` (ya fallaba en `91570fb3`), `eval-bottom-hub-design.py`.
- Riesgos: el defecto de Qt sigue para cualquier `Shape` con backend por software (la sesión usa RHI); `BottomHub.qml` sigue por encima de mil líneas (deuda previa; el IPC debería salir a su archivo); la franja transparente del Hub lateral (~365 px) se mantiene a propósito.
- No probado: sesión real, `HDMI-A-1`, aplicaciones reales de bandeja con menús de varios niveles, miniaturas con la RTX 3050 conectada a una salida, lector de pantalla.
- Rollback: `git revert` de los commits del bloque, en orden inverso. Las claves nuevas `bottomHub.windowPreviews` y `windowThumbnails` se ignoran al volver atrás; la posición por monitor usa el esquema de fase 3. Para devolver el Hub abajo sin tocar código: `qs ipc call bottomHub -- anchor "" bottom-center` y `clearAnchor <monitor>`.

#### Fase 4, certificación física (2026-11-14)

- Estado: DONE_WITH_CONCERNS. HEAD inicial `edd6633e`, final `58ec59b2`; sin push. Instalado: generación `20261114-114246-2201182`, adoptada por recarga suave.
- Evidencia: [`docs/evidence/cortetsu-30-phase4-physical-20261114/`](../../evidence/cortetsu-30-phase4-physical-20261114/README.md) (matriz PASS/FAIL/NOT_TESTED, métricas, capturas sin datos privados, volcados, NVIDIA, rollback).
- Sesión real, puntero y teclado virtuales con guardas de presencia: tres temas desde Ajustes, ocho anclajes por arrastre en el modo edición, persistencia tras reinicio, bandeja con ZapZap, Claude Desktop, Wallpaper Engine UX, Steam y Legcord (cambio de anclaje y app que se cierra con el menú abierto), vistas previas con ventanas propias, movimiento reducido, escala 1.25, `HDMI-A-1` desactivado y reactivado. 0 volcados de Quickshell.
- Defectos que solo salían en la sesión real, corregidos con prueba (control rojo y verde) y verificados en vivo:
  - `7f6b62a9`: `install` abortaba por una edición dentro de la generación sellada.
  - `4da2b15b`: la recarga suave rechazaba *inline components* nuevos.
  - `a470cd61`: `shell reload` informaba de éxito en falso.
  - `3b08a1ed`/`73895399`: auto-hide inalcanzable desde el borde real, Hub en el borde viejo tras cambiar el anclaje oculto, hover colgado.
  - `61c47e9a`: fila del menú de bandeja invisible al teclado.
  - `2ac0d34d`: anillo, filo y tooltip de foco fijos tras un clic.
- Pruebas nuevas: `test-hub-autohide-edge.py` (anidado), `test-hub-button-focus-runtime.py` (en `build-regressions.sh`), aserción de fila marcada en `test-popout-cycles.py`. Pasan `cortetsu test`, `build-regressions.sh`, nueve pruebas anidadas y la recarga suave de la generación viva a la nueva.
- Rendimiento en vivo: 40 popouts p50 179 ms (antes de los arreglos 181), 5,07 s de CPU (5,13); vista previa p50 530 ms (con 450 de permanencia); reposo 0,19–0,59 % de CPU; el shell solo usa la iGPU AMD; la NVIDIA solo trabaja para Hyprland por el HDMI. Los 20 s de NVIDIA del informe anterior coinciden con el arranque de Legcord, que deja un SIGTRAP propio.
- Huecos que impiden VERIFIED: ninguna app instalada tiene menús de bandeja de varios niveles; PSS ~500 MiB en un arranque limpio sin línea base comparable (el proceso de horas baja a ~300 MiB con swap); suspensión/reanudación sin ejecutar (requiere aprobación). Bloqueo: NOT_TESTED (Dilan, "ahora no").
- Riesgos abiertos: con `follow_mouse`, mover el puntero sobre un popout abierto por teclado da el teclado a la ventana de debajo; el perfil de Washi en `scheme.json` se regeneró desde el fondo al visitarlo.
- Revisión: Thermos en línea y en secuencia, sin subagentes; no es independiente. Encontró y corrigió la tira sustituida bajo el puntero y el contrato textual roto.
- Rollback: `git revert` en orden inverso; `cortetsu rollback` y después `cortetsu shell restart` (no recarga suave hacia atrás).

#### Fase 7 - Lockscreen, Dashboard y widgets

- Estado: PARTIAL (bloqueo hecho en código; Dashboard y widgets sin empezar)
- Fecha: 2026-11-13.
- QML modificados: `modules/lock/{Lock,LockSurface,LockCard}.qml`. `base/modules/lock/Pam.qml` no se tocó: la ruta de autenticación y de liberación es la misma.
- Cambios: el emblema sigue a PAM (Ascended bloqueado, Monster tras rechazo o demasiados intentos, Cosmic tras éxito); "Demasiados intentos" tenía su mensaje tapado por el de contraseña incorrecta y ahora se muestra; "autenticación no disponible" ya no se pinta como contraseña errónea; el fondo es el wallpaper atenuado y no una captura del escritorio; la lectura de distribución y Bloq Mayús/Num es una sola para todas las pantallas y solo corre con la sesión bloqueada (antes una por superficie); con movimiento reducido el rechazo no sacude el campo.
- Pruebas: `test-cortetsu-lock-card-runtime.py` (19 comprobaciones de estados, antes 10), `scripts/integration/test-lock-surface-nested.py` (la superficie real carga y bloquea dos salidas en un Hyprland anidado; no envía contraseña), `test-cortetsu-lock-runtime.py` (PAM real con `pam_permit`/`pam_deny`: solo el éxito libera).
- No probado: desbloqueo con la contraseña real en la sesión física, huella, suspensión y reanudación bloqueado, conexión de un monitor con la sesión bloqueada con estos cambios. El emblema no se dibuja con render por software, así que su tamaño y color nuevos no tienen captura.
- Seguridad: no hay ruta nueva de desbloqueo ni IPC nuevo; el bloqueo no se instaló. **Antes de `cortetsu install`, probar bloqueo y desbloqueo a mano con una TTY abierta como salida.**
- Rollback: `git revert` del commit; `Pam.qml` intacto.

#### Fase 5 - OSD 3.0 y Ajustes rápidos

- Estado: PARTIAL
- Fecha: 2026-11-13.
- Punto de partida real: el OSD transitorio (`osd/MiniSlider.qml`) y el centro de control (`osd/FullContent.qml`) ya eran dos superficies con un solo dueño (`osd/Wrapper.qml`); `utilities/` no tiene host visual. No hubo que separar nada.
- OSD transitorio: nuevo estado de micrófono (silenciado en bermellón, activo, no disponible), sin barra porque es un estado y no un nivel; una salida silenciada dice "Silenciado" en vez de un porcentaje; el volumen nombra el dispositivo de salida; un cambio de silencio que llega con un micrófono nuevo no se anuncia. Los valores siguen siendo lectura de PipeWire y del monitor, no la intención de la orden. Sin foco ni puntero (`test-cortetsu-osd-focus.sh`).
- Ajustes rápidos: el mosaico de red era `clickable: false`; ahora enciende y apaga el Wi-Fi con `ConnectivityWifi.setEnabled`, espera la respuesta de la radio, dice por qué se rechazó un cambio y queda como lectura sin acción si no hay dispositivo o está bloqueado por hardware. Nuevo mosaico de micrófono. Se quitó la línea "Conexión", que repetía el mosaico.
- Pruebas: `tests/qml/surfaces/tst_MiniSlider.qml` (10), `scripts/features/test-cortetsu-quick-settings-runtime.py` (13 comprobaciones, añadida a `build-regressions.sh`), `test-cortetsu-notice-cards-runtime.py`, gate de Settings.
- Decisión: Bloq Mayús/Num, distribución, cambio de dispositivo, carga y modo juego siguen siendo toasts (`CortetsuToaster`), con sus interruptores en Ajustes. Pasarlos al OSD crearía un segundo dueño del mismo aviso.
- Pendiente: OSD de perfil de energía; secciones expandibles en el centro de control; medir latencia; probar el OSD con el Hub lateral y en `HDMI-A-1`; sesión real.

#### Revisión del bloque de la fase 4 (2026-11-13)

- Thermos en línea y en secuencia, sin subagentes; no son independientes del autor.
  - Corrección: un comentario culpaba al modo Exclusive del clic perdido cuando la traza demostró que era el tooltip; corregido. `detach()` no limpiaba `keyboardHeld`; ahora sí.
  - Mantenibilidad: las teclas del menú pasan de dos copias (filas y Hub) a una función `handleKey`; el ramal de flechas y Tab se simplificó.
- Revisión externa: Codex `gpt-6-luna`, solo lectura, estática (no lanzó compositores). Tres hallazgos verificados contra el código: uno real (P2: la prueba de ciclos describía dos pulsaciones de Down donde hay una y no comprobaba `keyboardHeld` tras el clic derecho; corregido y la prueba vuelve a pasar) y dos falsos (la tecla Menú pasa por `secondaryRequested` → `openTrayMenu`, que sí activa `keyboardHeld`; el test de popouts sí falla ante `SETTINGS_FAIL`).

#### Revisión del bloque 2026-11-12/13

- Thermos: las dos pasadas (corrección/seguridad y mantenibilidad) se hicieron en línea y en secuencia, sin subagentes, por preferencia de Dilan; no son independientes del autor.
  - Corrección: un hallazgo propio resultó falso al verificarlo (un `CortetsuActionTile` no pulsable ya está `enabled: false`, así que no recibe teclas); se deshizo el cambio y quedó solo una comprobación de nulo en el micrófono. Hallazgo real P3: el fondo del bloqueo leía `CortetsuWallpapers.current`, que durante una vista previa es la imagen previsualizada; ahora usa `actualCurrent`.
  - Mantenibilidad: sin código muerto nuevo; `HubAnchor.nearest` (sin uso) se retiró antes del commit del Hub.
- Revisión externa: Codex `gpt-6-luna`, solo lectura, sobre `36dea6db..HEAD`: sin defectos confirmados en Hub, bloqueo, Ajustes rápidos, Settings ni mantenibilidad. Estática: no ejecutó pruebas.
- Gate de instalación (`build-regressions.sh` sobre un runtime preparado en un directorio temporal, sin instalar) encontró tres regresiones de este trabajo, ya corregidas: el inventario de procesos de arranque apuntaba a la sonda de teclado en `LockSurface.qml` (ahora en `Lock.qml`); dos fixtures copiaban `CortetsuConfig.qml` sin `HubAnchor.js`; una aserción exigía el Hub anclado abajo. Pasa completo.
- Fallos previos, ajenos a 3.0 (fallan igual en `36dea6db`): `test-cortetsu-idle-runtime.py`, `test-gamemode-runtime.py`, `test-cortetsu-brightness.py`.

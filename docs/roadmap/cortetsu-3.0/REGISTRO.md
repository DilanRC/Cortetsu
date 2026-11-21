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
| 4 Islas, popouts y tray | VERIFIED |
| 5 OSD 3.0 y Ajustes rápidos | PARTIAL (ola 2026-11-16: código sin verificar) |
| 6 Centros de servicio | PARTIAL (ola 2026-11-16: código sin verificar) |
| 7 Lockscreen, Dashboard y widgets | PARTIAL |
| 8 Audio avanzado y superficies restantes | PARTIAL (ola 2026-11-16: código sin verificar) |
| 9 Certificación | NOT_STARTED |

Las dos olas de construcción continua del 2026-11-16 (sin pruebas) están al
final: [primera ola](#ola-de-construcción-continua-2026-11-16) y
[segunda ola](#segunda-ola-de-construcción-2026-11-16). Tras la segunda, el
código de las fases 5 a 8 está escrito en todas las superficies activas
(`COBERTURA_FINAL_QML_3_0.md`: ninguna en `PENDIENTE`) y **nada está
verificado en ejecución**.

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

- Estado: VERIFIED (certificación física del 2026-11-14, ver "Certificación física")
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

- Estado: VERIFIED (DONE_WITH_CONCERNS por la mañana; los tres huecos se cerraron por la noche). HEAD inicial `edd6633e`, final `0b61673a` más la documentación; sin push. Instalado: generación `20261114-222216-44629`, adoptada por recarga suave.
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
- Cierre de los huecos (noche del 2026-11-14), apartado 14 de la evidencia:
  - Menús de varios niveles: un indicador real `libayatana-appindicator` (la pila de `nm-applet`; `scripts/integration/ayatana-indicator-fixture.py`) en la sesión real, con tres niveles por teclado y ratón, filas que cambian en vivo y la app cerrándose en el nivel 3. Salieron dos defectos, corregidos con prueba: casilla y radio sin estado (`e8165147`) y popout fantasma con el teclado retenido por dos registros de claves de la bandeja (`462a59c2`, `test-tray-relaunch.py`).
  - Memoria: A/B de arranque limpio contra `a352a342` (antes de la fase 4), tres ejecuciones cada uno; PSS 417–423 frente a 420–422 MiB. La fase 4 no la cambia.
  - Suspensión: s2idle y reanudación en la sesión real con bloqueo y desbloqueo por PAM (un rechazo y un éxito); mismo PID, sin volcados ni avisos; NVIDIA de vuelta a `suspended`. Sin HDMI conectado.
- Gates sobre el árbol final: `cortetsu test`, `build-regressions.sh` y diez pruebas anidadas (con `test-tray-relaunch.py`).
- Riesgos que siguen: `follow_mouse` da el teclado a la ventana bajo un popout abierto por teclado; perfil de Washi en `scheme.json` regenerado; reanudación con HDMI no repetida.
- Siguiente: fase 5 (OSD 3.0 y Ajustes rápidos), sin empezar en este bloque.

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

#### Ola de construcción continua (2026-11-16)

- Estado: **PARTIAL_NO_VERIFICADO**. Plan: `CORTETSU_3_0_PLAN_MAESTRO_CONSTRUCCION_CONTINUA.md` (versión `3.0-construction-first-2`, entregado por Dilan; prevalece sobre el plan anterior en el proceso, no en las decisiones de ADR-008).
- Rama `main`, HEAD inicial `6299f21f`. Commits locales `aefc805b` a `df78aae0` más la documentación. Sin push.
- Ejecutado: **0 pruebas, 0 builds de QA, 0 lints, 0 instalaciones, 0 recargas, 0 push.** Solo lectura de código, `git`, `gh api` de lectura sobre los tres proyectos de referencia, y `scripts/verification/qml-inventory.py` para regenerar el inventario (genera documentación; no comprueba nada).
- Archivos ajenos: `.codebase-memory/` tenía cambios previos; no se tocaron ni se incluyeron.
- Entregables: [`INVENTARIO_QML_3_0.md`](INVENTARIO_QML_3_0.md), [`COMPARATIVA_Y_MEJORAS.md`](COMPARATIVA_Y_MEJORAS.md), [`DECISIONES_DISENO.md`](DECISIONES_DISENO.md), [`QA_POSTERIOR.md`](QA_POSTERIOR.md), [`../../AUDIO_EQ.md`](../../AUDIO_EQ.md).

| Commit | Módulo | Estado |
| --- | --- | --- |
| `aefc805b` | Centro de control por frecuencia, dispositivos a demanda, OSD de perfil | IMPLEMENTADO_SIN_VERIFICAR |
| `a2a49b7b` | Notificaciones: grupos, búsqueda, quitar del historial | IMPLEMENTADO_SIN_VERIFICAR |
| `56ea7e9e` | Launcher: modo explorar | IMPLEMENTADO_SIN_VERIFICAR |
| `ca549d14` | Popout de energía | IMPLEMENTADO_SIN_VERIFICAR |
| `919f8bab` | Sesión: grupos, cuenta atrás, Escape | IMPLEMENTADO_SIN_VERIFICAR |
| `d8acfb41` | Polkit: Bloq Mayús, «Comprobando…» | IMPLEMENTADO_SIN_VERIFICAR |
| `6cd2d6f0` | Divisores con token | IMPLEMENTADO_SIN_VERIFICAR |
| `2447be32` | Ajustes → Sonido; búsqueda abre grupos plegados | IMPLEMENTADO_SIN_VERIFICAR |
| `9f04ba43` | Ajustes → Energía | IMPLEMENTADO_SIN_VERIFICAR |
| `48383261` | Dashboard: GPU sin lectura, pestañas accesibles | IMPLEMENTADO_SIN_VERIFICAR |
| `0269d7ac` | Toasts | IMPLEMENTADO_SIN_VERIFICAR |
| `9aa1341a` | Ecualizador opcional de 10 bandas | IMPLEMENTADO_SIN_VERIFICAR |
| `df78aae0` | Limpieza y rango del volumen | IMPLEMENTADO_SIN_VERIFICAR |


- Dependencias nuevas: ninguna. El ecualizador usa `pw-cli` (PipeWire, ya instalado) y un archivo de configuración que el usuario copia a mano.
- Preferencias nuevas: `eqEnabled`, `eqGains` (versiones anteriores las ignoran). Estado nuevo: `~/.local/state/cortetsu/launcher-recent.json`.
- Compatibilidad: `objectName` de las pruebas del centro de control conservados (`quickWifi`, `quickMicrophone`, `quickEnergy`); ningún destino IPC cambió.
- Bloqueo: no se tocó. Sin prueba manual inmediata, la ruta PAM no se edita.
- No implementado (por eso PARTIAL): páginas de Ajustes no revisadas (lista en el inventario), widgets de escritorio con edición, Overview, Wallpaper, Display, Portapapeles, Calendario, Grabación, Compartir pantalla, Teclados, Secretos; galería de la biblioteca; luz nocturna y cheatsheet (pendientes de backend o decisión).
- Riesgos sin descartar: QML sin compilar (tipos, imports, `uniformCellWidths` en `GridLayout`, `PowerProfiles.hasPerformanceProfile`), pruebas de cadenas que fallarán (lista en QA), `bq_highshelf` a 0 Hz como preamp, `pw-cli set-param` sobre un filter-chain estéreo, foco con `follow_mouse` en el centro de control, Hub lateral con el centro de control, HDMI y escala 1.25.
- Revisión: Thermos en línea y en secuencia, sin subagentes (preferencia de Dilan); no independiente. Hallazgo corregido: el deslizador de volumen del centro de control usaba un rango distinto del de Ajustes.
- Rollback: `git revert` de los commits de la ola en orden inverso. Nada instalado.
- Siguiente misión: `QA INTEGRAL 3.0`, **pendiente de autorización**.

#### Segunda ola de construcción (2026-11-16)

- Estado: **IMPLEMENTADO_SIN_VERIFICAR**. Misión «Cortetsu 3.0 — misión
  maestra, segunda ola» (entregada por Dilan): investigar end-4, Caelestia y
  Nebula en su código, completar todas las superficies activas y documentar,
  sin pruebas, builds, lints, instalaciones, recargas ni push.
- Rama `main`, HEAD inicial `3b4e7c2f`. Commits locales `d574fa85` a
  `35c5bdef` más esta documentación. Sin push.
- Ejecutado: **0 pruebas, 0 builds, 0 lints, 0 instalaciones, 0 recargas,
  0 push.** Solo lectura de código, `git`, clones de solo lectura de las
  referencias y de PipeWire 1.6.11 en `../cortetsu-references/`, lecturas del
  sistema (`quickshell --version`, `hyprctl version`, `systemctl --user cat
  hyprsunset.service`, `cortetsu-keybinds list`, existencia de `plocate`,
  `cava`, `xdg-open`) y los generadores de documentación
  `scripts/verification/qml-inventory.py` y `qml-coverage.py` (generan texto;
  no comprueban el shell).
- Versiones leídas: Quickshell 0.3.2 (`4f508be5`, la misma revisión que fija
  end-4), Qt 6.12.0, Hyprland 0.57.2, PipeWire 1.6.11, hyprsunset 0.4.0.
- Archivos ajenos: `.codebase-memory/` sigue modificado por otro proceso; no
  se tocó ni se incluyó.
- Entregables: [`REFERENCIAS_END4_CAELESTIA_NEBULA.md`](REFERENCIAS_END4_CAELESTIA_NEBULA.md),
  [`MEJORAS_CREATIVAS_3_0.md`](MEJORAS_CREATIVAS_3_0.md),
  [`COBERTURA_FINAL_QML_3_0.md`](COBERTURA_FINAL_QML_3_0.md) (generada) y
  actualizados el inventario, la comparativa, las decisiones y el QA.

| Commit | Módulo | Estado |
| --- | --- | --- |
| `d574fa85` | Ecualizador: preamp sobre la curva real, `mixer` lineal, curva en Ajustes | IMPLEMENTADO_SIN_VERIFICAR |
| `65db6bf5` | Visualizador: configuración propia de cava, barras estables | IMPLEMENTADO_SIN_VERIFICAR |
| `2dd6c60b` | Luz nocturna programada; mosaicos de luz nocturna y captura | IMPLEMENTADO_SIN_VERIFICAR |
| `48e87e30` | Hoja de atajos (SUPER+F1) | IMPLEMENTADO_SIN_VERIFICAR |
| `33ed5a57` | Widgets de escritorio, editor y página de Ajustes | IMPLEMENTADO_SIN_VERIFICAR |
| `91b34b14` | Divisores por token, portapapeles en Washi, siete QML muertos borrados | IMPLEMENTADO_SIN_VERIFICAR |
| `4559b844` | Grabaciones recientes; avisos del grabador en español | IMPLEMENTADO_SIN_VERIFICAR |
| `d3b6aff6` | Silenciar notificaciones por aplicación | IMPLEMENTADO_SIN_VERIFICAR |
| `1e1ff69d` | Vista general: filtro de ventanas | IMPLEMENTADO_SIN_VERIFICAR |
| `2c06d320` | Portapapeles: controles reales, limpiar con confirmación | IMPLEMENTADO_SIN_VERIFICAR |
| `7dd2fcf7` | Fichas de fondos y de compartir pantalla accesibles | IMPLEMENTADO_SIN_VERIFICAR |
| `96eeaad5` | Centro de control: lo que suena y mezclador por app | IMPLEMENTADO_SIN_VERIFICAR |
| `31eed0a8` | Dashboard: medidor de nivel sin cava | IMPLEMENTADO_SIN_VERIFICAR |
| `c5235016` | Lanzador: búsqueda de archivos con `plocate` | IMPLEMENTADO_SIN_VERIFICAR |
| `5d26c43a` | Ajustes: biblioteca de componentes | IMPLEMENTADO_SIN_VERIFICAR |
| `b1794f43` | Popouts de teclado y Bloq Mayús en la familia | IMPLEMENTADO_SIN_VERIFICAR |
| `af2b2a0c` | Correcciones de la revisión Thermos (widgets) | IMPLEMENTADO_SIN_VERIFICAR |
| `35c5bdef` | Ajustes → Diagnóstico con `cortetsu doctor` a demanda | IMPLEMENTADO_SIN_VERIFICAR |

- Cobertura: 415 archivos activos (QML y JS del shell): 80
  `IMPLEMENTADO_SIN_VERIFICAR` entre las dos olas, 335
  `CONSERVADO_JUSTIFICADO` con motivo por familia, 0 `BLOQUEADO_DOCUMENTADO`,
  0 `PENDIENTE`. Ocho QML borrados (siete sin referencias desde la fase 0 y
  el reloj de escritorio sustituido por los widgets).
- Dependencias nuevas: ninguna. Se usan `plocate`, `xdg-open`,
  `hyprsunset.service`, `PwNodePeakMonitor`, `FolderListModel` y `cava`
  opcional, todos ya presentes o ya opcionales.
- Preferencias nuevas: `desktopWidgets` (con migración del reloj 2.x),
  `displayCalibration.schedule`, `mutedNotificationApps`. Versiones
  anteriores las ignoran. Atajo nuevo en `config/hypr-user.lua`:
  `SUPER + F1` → `cortetsu:cheatsheet` (requiere `hyprctl reload`).
- Contratos: superficies retenidas nuevas `cheatsheet` y `desktopWidgets`
  (registro, `ScreenState`, `CortetsuScreenState`, IPC homónimos); ningún
  destino IPC existente cambió. El grafo del ecualizador pasa a la versión 2;
  la 1 sigue funcionando.
- Bloqueado o pendiente de decisión (no de código): ninguno de los
  elementos de la misión quedó sin implementar por un bloqueo técnico. Se
  conservan sin tocar, con motivo, el bloqueo (PAM), Polkit y Secretos
  (lógica sensible), y el Hub de la fase 4.
- Revisión: Thermos en línea y en secuencia, sin subagentes (preferencia de
  Dilan); no es independiente del autor. Hallazgos corregidos en `af2b2a0c`:
  el editor movía un widget de otro monitor; las filas de Sistema y Red se
  recreaban en cada muestra. Antes, durante la construcción: `cx = 0` leído
  como 0,5, un clic sin arrastre colocaba el widget en (0, 0), el `Binding`
  de posición devolvía x a 0 al empezar a arrastrar, búsquedas de archivos
  que no se relanzaban y respuestas viejas que pisaban la consulta nueva.
- Riesgos sin descartar: todo lo de `QA_POSTERIOR.md` §9; en particular, QML
  sin compilar (importación cualificada de `settings` desde el centro de
  control, `Binding` con `restoreMode`, `ScriptModel` de ids), pruebas de
  cadenas que fallarán por archivos borrados y textos movidos, el `mixer` con
  `inputs`/`outputs` en un grafo estéreo, el coste de los widgets a la vista,
  `follow_mouse` con el centro de control.
- Rollback: `git revert` de `d574fa85..35c5bdef` en orden inverso. Nada
  instalado. Las preferencias nuevas se ignoran al volver atrás; el reloj
  2.x vuelve con su preferencia `desktopClockEnabled`, que no se tocó.
- Siguiente misión: `QA INTEGRAL 3.0`, **pendiente de autorización**.


#### Misión maestra «implementación integral sin QA» (2026-11-19)

- Estado: **PARCIAL_SIN_VERIFICAR**. Rama `main`, HEAD inicial `09980b73`.
  Sin push. **0 pruebas, 0 builds, 0 lints, 0 instalaciones, 0 recargas.**
- Archivos ajenos: `.codebase-memory/` seguía modificado; no se tocó.
- Implementado: Contextos (fase 5) con servicio, página de Ajustes, acciones
  del Launcher, IPC y pausa de Orbital por contexto (fase 1). Ver
  [CONTEXTS](../../CONTEXTS.md).
- Conservado sin cambios por estar ya implementado en olas anteriores
  (`IMPLEMENTADO_SIN_VERIFICAR`): Orbital completo salvo la pausa por
  contexto, Overview, Launcher, Dashboard, utilidades, centro de control,
  OSD, Hub con anclaje por monitor y Ajustes (ver las olas 1 y 2 arriba y
  `COBERTURA_FINAL_QML_3_0.md`).
- No hecho en esta misión (por eso PARCIAL): pasada visual transversal de la
  fase 7, edición del Hub por arrastre más allá del anclaje existente,
  consolidación de código obsoleto de la fase 6 y extracción de paleta desde
  un fondo animado. Ninguno tiene un bloqueo técnico; quedan para la
  siguiente ola.
- Dependencias nuevas: ninguna. Estado nuevo: `contexts.json`. Campo nuevo
  `hold` en el `heartbeat` de Orbital (un supervisor anterior lo ignora).
- Rollback: `git revert` de los commits de la misión en orden inverso.

- Fase 2 (misma fecha): vista general con dígitos y Alt+dígito para mover
  ventanas por teclado; Dashboard con controles rápidos (No molestar, modo
  juego, perfil de energía, salir del contexto). Revisados sin cambios por
  estar completos: Launcher (favoritos, historial, archivos, explorar),
  portapapeles, notificaciones, capturas y calendario. IMPLEMENTADO_SIN_VERIFICAR.
- Fase 3 (misma fecha): Hub con separación entre islas configurable y orden
  invertido (preferencias `bottomHub.spacing` y `bottomHub.mirrored`); OSD
  mini de multimedia para pausar y reanudar; mosaico «Contextos» en el centro
  de control. Ya existían y se conservaron: 8 anclajes por monitor, modo
  «Mover el Hub», Wi-Fi, Bluetooth, audio por app, micrófono, brillo, No
  molestar, modo juego, luz nocturna, perfiles de energía y Orbital en el
  centro de control; OSD de volumen, brillo, micrófono y perfil. No hecho:
  reordenar islas libremente (el cálculo de posiciones tuvo bucles de
  bindings; sin pruebas, el reflejo es el cambio seguro). IMPLEMENTADO_SIN_VERIFICAR.
- Fase 4 (misma fecha): Ajustes → Fondo con el estado de Orbital por
  pantalla (Detener, Restaurar anterior); las fuentes del tema rechazan
  familias no instaladas. Ya existían: temas, esquemas, transparencia,
  movimiento, geometría, Hub, perfiles visuales, pantallas con
  confirmación, sonido, Wi-Fi, Bluetooth, energía, diagnóstico, búsqueda con
  revelado del control y migas.
- Fase 5: completada al inicio de la misión; se añade «Separación del Hub»
  como ajuste de contexto (Gaming la pone compacta).
- Fase 6: `docs/IPC.md` generado por `scripts/verification/ipc-inventory.py`
  (29 destinos, incluidos los de `RetainedSurfaceController`); todos los
  destinos llamados desde Hyprland, la CLI y el Launcher existen. Barrido de
  QML sin referencias: ninguno. Corregido: un `preferences.json` dañado se
  sobrescribía con los valores por defecto al primer cambio sin dejar copia;
  ahora se guarda en `preferences.json.damaged` y se avisa.
  IMPLEMENTADO_SIN_VERIFICAR.

#### Instalación de las olas 3.0 (2026-11-20)

- Por orden de Dilan («perfecciona, instala y recarga»). Primera vez que se
  compilan y prueban las olas 1, 2, Orbital y esta misión.
- Antes de instalar, en una generación de prueba (sin tocar la sesión):
  `cargo test` del runtime, `build-runtime.sh`, `build-regressions.sh` y
  `cortetsu test`, todo en verde tras las correcciones. `prompter.rs`
  falló una vez de nueve por tiempo (pasa al repetir; no se tocó).
- Fallos que las olas sin verificar habían dejado, corregidos: dobles de
  pruebas sin `cheatsheet`/`desktopWidgets`, sin `DesktopLayout.js` ni
  `mutedNotificationApps`; tres QML borrados aún exigidos por el build;
  hash de la referencia congelada del grabador; cinco procesos sin entrada
  en el inventario de arranque; centro de control a 798 px (límite 700);
  tres hallazgos del lint de diseño; `execDetached` en una vista de Ajustes.
- Fallo real encontrado en el journal tras instalar y corregido: el menú
  de sesión no creaba ninguna fila (`index` requerido sin asignar desde
  `919f8bab`). Sus pruebas no estaban en ninguna suite; ahora sí.
- Instalado `dba936ca` con `cortetsu install`, `cortetsu shell reload` con
  «Configuration Loaded» y el journal limpio. SUPER+F1 ya estaba cargado en
  Hyprland. IPC `contexts` responde.
- Sin ejecutar (requieren Hyprland anidado o la sesión con Dilan
  presente): `test-cortetsu-lock-runtime`, `-idle-runtime`,
  `test-gamemode-runtime`, `test-keybind-editor-runtime` y
  `-launcher-mode-actions-runtime` (lleva un `loginctl lock-session` real).
  `test-cortetsu-settings-runtime.py` está desfasado desde que los widgets
  sustituyeron al reloj de escritorio (`33ed5a57`): hay que reescribir sus
  escenarios del reloj sobre los widgets.
- Rollback: `cortetsu rollback` vuelve a la generación anterior.

#### Perfeccionamiento continuo (2026-11-20, instalado en `6d45a1f6`)

Cada tanda pasó compilación, `build-regressions.sh` y `cortetsu test` en una
generación de prueba antes de instalarse; tras cada `cortetsu shell reload`
el journal quedó sin avisos.

- Funciones: orden libre de las islas del Hub (6 órdenes, migra
  `mirrored`); «Usar sus colores» en Orbital (paleta de la portada, primer
  fotograma); en Ajustes, un resultado sobre un control deshabilitado enfoca
  el control que lo habilita.
- Pasada visual sobre capturas reales (33 páginas × Ink/Washi/Kurogane,
  centro de control, popouts, Hub): contextos incluidos como valores,
  resumen de cabecera alineado, Orbital y Contextos al final de la rejilla.
- Diseño: 0 hallazgos del lint en los 376 archivos, ahora exigido en el
  gate; objetivos de 36 px para interruptor, deslizador y bandeja.
- Pruebas: `test-cortetsu-settings-runtime.py` reescrita sobre los widgets y
  en el gate; 7 pruebas de ejecución más en el gate; prueba unitaria de
  `ContextModel.js` y de la pausa de Orbital; `nested-regressions.py` para
  lock, idle, modo juego y editor de atajos (las cuatro pasan). La de modo
  juego tenía un bucle de carrera que pasaba sin ejecutarse.
- Limpieza: rama `modeSwitch` inalcanzable del Launcher, dos curvas sin uso,
  clippy limpio en todos los crates y `go vet` limpio.
- No tocado a propósito: 54 contratos `scripts/features/` en rojo que solo
  citan las evidencias de las migraciones F0/F9; el oráculo histórico los
  ejecuta desde `ce9523ea`, no desde HEAD. Ascended, Monster y Cosmic
  comprobados en código y en la prueba de la tarjeta de bloqueo.
- Revisión externa (`ai-review deep`, 2026-11-20) del diff de código de la
  3.0 en un bloque: OpenCode sin cuota (INCOMPLETE); AGY, 4 hallazgos, los
  4 falsos positivos tras comprobarlos (`let` chains estables en la edición
  2024, secuencias QML con métodos de Array, singleton `ShellState` en la
  misma carpeta, pruebas excluidas del diff a propósito). Instalado
  después `d65419b6` (editar el contexto activo lo aplica al momento).

#### Perfeccionamiento continuo, segundo tramo (2026-11-20, instalado `8c70e256`)

Mismo procedimiento: gate completo en una generación de prueba antes de
cada instalación; journal limpio tras cada recarga.

- Fallos corregidos al revisar código propio: la pausa de Orbital por
  contexto no volvía tras reiniciar la sesión hasta abrir una superficie
  (ahora `Orbital.hold` se enlaza a `CortetsuContexts.orbitalHold`); editar
  el contexto activo no se aplicaba; el resultado de «Usar sus colores» se
  mostraba en el panel de otro fondo; en el Hub lateral repartido, el grupo
  central se solapaba con un Sistema largo (acotado entre vecinos).
- Mejoras: Contextos avisa antes de activar qué ajustes conserva la
  automatización; el botón de contextos del Dashboard abre Ajustes →
  Contextos sin ninguno activo; paradas de Tab condicionales que conservan
  la bandera mientras tienen el foco.
- Pruebas nuevas o ampliadas: dígitos de la vista general
  (`OverviewKeys.js`), Hub en laterales (170 comprobaciones), contextos
  (editar activo, exportar/importar, arranque solo con Orbital),
  `preferences.json` dañado, fuentes no instaladas, mosaicos del centro de
  control, mini-OSD multimedia, contrato de foco del OSD. El arnés de
  Ajustes ya no puede mostrar notificaciones reales (`notify-send` falso).
- `scripts/features/INDEX.md`: qué comprobaciones ejecuta cada suite (50) y
  cuáles son contratos archivados (200).
- Pendiente de la sesión física: lo listado en la tabla de estado de
  `QA_POSTERIOR.md`.

#### Teclado en los controles rápidos del Dashboard (2026-11-20)

- En Inicio, Abajo entra en los controles rápidos; Izquierda y Derecha se
  mueven entre ellos y paran en los extremos; Arriba vuelve a las zonas.
  Tab, un dígito o Escape desde un control salen y siguen llegando al
  Dashboard.
- Fallos encontrados al escribir la prueba de `513cad9f`: Arriba no hacía
  nada (`forceActiveFocus` sobre el `FocusScope` devolvía el foco al botón
  que lo conservaba) y Tab lo tragaba la cadena de tabulación de Qt, que
  saltaba al botón siguiente y dejaba las flechas muertas. Corregidos en
  `9361c6a4` y `9e1d4c62`: el control suelta el foco antes de salir y los
  cuatro botones salen de la cadena de Tab.
- Prueba: `test-cortetsu-dashboard-dismiss-runtime.py` pasa de 13 a 27
  comprobaciones; 3 fallan sin el primer arreglo y 2 sin el segundo.
- Gate: compilación en scratch, `build-regressions.sh` y `cortetsu test`.
  Revisión: `ai-review fast` INCOMPLETE (OpenCode sin cuota); Codex
  `gpt-6-luna` sin hallazgos.

#### Cierre Premium sobria (2026-11-21)

Detalle, requisitos y evidencias en
[CIERRE_PREMIUM_SOBRIA.md](CIERRE_PREMIUM_SOBRIA.md).

- Pills en cápsula en los tres temas; mini OSD arriba al centro del monitor;
  bandeja sin el damero de icono no encontrado; centro de notificaciones del
  alto de su contenido, con variantes por tipo y modo privado; Launcher con
  navegación y favoritos; bloqueo como escena completa.
- Corrección de semántica: `notifs.json` guarda lo no descartado; el centro
  ya no lo lista dos veces ni dice que lo descartado se guarda.
- Orbital: `desktop-runtime-rs` compila y pasa sus pruebas (incluido
  `orbital_session.rs`); `cortetsu-background` en `bottom` sin otros clientes
  en esa capa en la sesión real.
- Gate: `cortetsu test` en verde.

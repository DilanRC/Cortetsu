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
| 4 Islas, popouts y tray | NOT_STARTED |
| 5 OSD 3.0 y Ajustes rápidos | NOT_STARTED |
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
- Pendiente: Inicio (cuatro tarjetas iguales), repaso de las páginas restantes contra ADR-008, Launcher compacto y exploración.

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

#### Fase 7 - Lockscreen, Dashboard y widgets

- Estado: PARTIAL (bloqueo hecho en código; Dashboard y widgets sin empezar)
- Fecha: 2026-11-13.
- QML modificados: `modules/lock/{Lock,LockSurface,LockCard}.qml`. `base/modules/lock/Pam.qml` no se tocó: la ruta de autenticación y de liberación es la misma.
- Cambios: el emblema sigue a PAM (Ascended bloqueado, Monster tras rechazo o demasiados intentos, Cosmic tras éxito); "Demasiados intentos" tenía su mensaje tapado por el de contraseña incorrecta y ahora se muestra; "autenticación no disponible" ya no se pinta como contraseña errónea; el fondo es el wallpaper atenuado y no una captura del escritorio; la lectura de distribución y Bloq Mayús/Num es una sola para todas las pantallas y solo corre con la sesión bloqueada (antes una por superficie); con movimiento reducido el rechazo no sacude el campo.
- Pruebas: `test-cortetsu-lock-card-runtime.py` (19 comprobaciones de estados, antes 10), `scripts/integration/test-lock-surface-nested.py` (la superficie real carga y bloquea dos salidas en un Hyprland anidado; no envía contraseña), `test-cortetsu-lock-runtime.py` (PAM real con `pam_permit`/`pam_deny`: solo el éxito libera).
- No probado: desbloqueo con la contraseña real en la sesión física, huella, suspensión y reanudación bloqueado, conexión de un monitor con la sesión bloqueada con estos cambios. El emblema no se dibuja con render por software, así que su tamaño y color nuevos no tienen captura.
- Seguridad: no hay ruta nueva de desbloqueo ni IPC nuevo; el bloqueo no se instaló. **Antes de `cortetsu install`, probar bloqueo y desbloqueo a mano con una TTY abierta como salida.**
- Rollback: `git revert` del commit; `Pam.qml` intacto.

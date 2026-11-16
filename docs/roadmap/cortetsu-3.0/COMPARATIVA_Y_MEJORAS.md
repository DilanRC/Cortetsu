# Comparativa con end-4, Caelestia y Nebula, y mejoras decididas

Olas de construcción 3.0, 2026-11-16. Estado de todo lo implementado:
`IMPLEMENTADO_SIN_VERIFICAR`. La segunda ola clonó los tres proyectos y
leyó su código: el detalle por archivo y commit está en
[`REFERENCIAS_END4_CAELESTIA_NEBULA.md`](REFERENCIAS_END4_CAELESTIA_NEBULA.md).

## Qué se leyó y qué no

Lectura por la API de GitHub (`gh api`), sin clonar ni ejecutar nada:

| Proyecto | Rama y fecha del último push | Licencia | Leído |
| --- | --- | --- | --- |
| [end-4/dots-hyprland](https://github.com/end-4/dots-hyprland) | `main`, 2026-11-15 | GPL-3.0 | árbol de QML de `ii` y `waffle`: quick toggles, mezclador, OSD, centro de notificaciones, cheatsheet |
| [caelestia-dots/shell](https://github.com/caelestia-dots/shell) | `main`, 2026-11-15 | GPL-3.0 | árbol de QML: `nexus` (ajustes), dashboard, lock, launcher, utilities, toasts |
| [LilaccFlowerr/Nebula](https://github.com/LilaccFlowerr/Nebula) | `main`, 2026-11-14 | AGPL-3.0 | árbol de QML y `services/Equalizer.qml` completo |

No se vieron capturas ni se ejecutó ningún shell. Las comparaciones de
abajo se apoyan en qué superficies y servicios existen en cada árbol, no en
su aspecto. No se copió código: las tres licencias son copyleft y Cortetsu
solo toma principios.

## Matriz

| # | Referencia | Carencia de Cortetsu | Decisión | Cambio | Archivos | Estado |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | end-4 `WNotificationGroup` | El centro listaba avisos sueltos; con tres de la misma app se repetía el nombre en cada tarjeta | Adoptar el principio | Agrupación por app en orden de llegada, una cabecera con recuento | `sidebar/Content.qml` | Implementado |
| 2 | end-4 `AudioDeviceSelectorButton` | Cambiar de salida exigía abrir el popout del Hub o Ajustes | Adaptar | Lista de salidas y entradas plegable bajo el volumen del centro de control | `osd/FullContent.qml`, `osd/LevelRow.qml` | Implementado |
| 3 | end-4 `AndroidPowerProfileToggle` | El perfil solo se elegía en el popout de batería | Adaptar | Perfil en el centro de control y en Ajustes → Energía, siempre leído de `power-profiles-daemon` | `osd/FullContent.qml`, `settings/sections/PowerSection.qml` | Implementado |
| 4 | end-4 OSD (`OsdValueIndicator`) | Un cambio de perfil no se anunciaba | Adaptar | Mini OSD de perfil, como estado y no como barra; no se anuncia el valor inicial | `osd/Wrapper.qml`, `osd/MiniSlider.qml` | Implementado |
| 5 | end-4 `volumeMixer` | Un stream silenciado en Ajustes quedaba con el deslizador deshabilitado y sin forma de reactivarlo | Corregir | Botón de silencio por app | `settings/controls/SettingSliderRow.qml`, `settings/sections/AudioSection.qml` | Implementado |
| 6 | Nebula `Equalizer` (filter-chain + `pw-cli`) | Sin ecualizador | Adaptar con límites propios | Nodo opt-in que el usuario instala; preamp contra saturación; bypass plano sin cambiar de dispositivo; sin reiniciar PipeWire desde el shell | `services/CortetsuEqualizer.qml`, `data/pipewire/cortetsu-eq.conf`, `docs/AUDIO_EQ.md` | Implementado |
| 7 | end-4 `waffle/startMenu`, Caelestia launcher | El launcher vacío era una lista alfabética | Adaptar | Modo explorar: favoritas, recientes y resto; categorías solo con apps instaladas | `launcher/services/Apps.qml`, `launcher/{Content,ContentList,AppList}.qml` | Implementado |
| 8 | Caelestia `utilities/toasts` | Toast urgente con cuatro marcas a la vez | Simplificar | Sin barra lateral; mensaje vacío sin línea | `utilities/toasts/ToastItem.qml` | Implementado |
| 9 | Caelestia `lock`, Nebula lock | Caps Lock solo se avisaba en el bloqueo | Adoptar | Aviso en el diálogo de Polkit y estado «Comprobando…» | `polkit/PolkitDialog.qml` | Implementado |
| 10 | Nebula, animación de bloqueo de 3,4 s | — | Descartar | El desbloqueo depende de PAM, no de una escena; el plan lo excluye | — | No aplica |
| 11 | Nebula `WavyProgress`, `MorphButton`, `FloatingShapes` | — | Descartar | Movimiento decorativo en reposo; choca con ENERGY 1 / MOTION 1 de la dirección vigente | — | No aplica |
| 12 | end-4 `aiChat` | — | Descartar | AGENTS.md prohíbe APIs externas de LLM sin instrucción expresa | — | No aplica |
| 13 | end-4 `services/Hyprsunset.qml`, `AndroidNightLightToggle` | Sin luz nocturna programada | Adaptar (ola 2) | El dueño ya existía (`DisplayCalibration` sobre `hyprsunset.service`; la ola 1 lo pasó por alto). Horario con retención manual hasta el siguiente cambio; mosaico en el centro de control | `services/{DisplayCalibration.qml,NightLight.js}`, `settings/display/DisplayColour.qml`, `osd/FullContent.qml` | Implementado |
| 14 | end-4 `cheatsheet/` | Los atajos solo se ven en Ajustes → Atajos | Adaptar (ola 2) | Superficie retenida en SUPER+F1 (SUPER+/ es del centro de control en latam) con el ayudante `cortetsu-keybinds`, búsqueda y conflictos | `cheatsheet/`, `CheatsheetController.qml`, `config/hypr-user.lua` | Implementado |
| 15 | Nebula `services/{Widgets,WidgetSnap}.qml` | Widgets de escritorio sin edición | Adaptar (ola 2) | Nueve tipos, editor con guías, centro relativo por monitor, borde del Hub reservado | `desktop/`, `services/DesktopWidgets.qml`, `settings/sections/WidgetsSection.qml` | Implementado |
| 16 | end-4 `AndroidScreenSnipToggle` | La captura no está en el centro de control | Adoptar (ola 2) | Mosaico que abre el selector existente tras cerrar el panel | `osd/FullContent.qml`, `shell.qml` | Implementado |
| 17 | Propia | La sesión decía «Pulsa otra vez en 4 segundos» fijo | Corregir | Cuenta atrás viva; Escape desarma antes de cerrar | `session/Content.qml`, `SessionHost.qml` | Implementado |
| 18 | Propia | El centro de control cambiaba la marca a Monster al pulsar | Corregir | Monster significa fallo de autenticación (ADR-008); la marca queda en Ascended quieta | `osd/FullContent.qml` | Implementado |
| 19 | Propia | El historial de notificaciones se pintaba deshabilitado (opacidad 0,46) | Corregir | Filas legibles con botón de quitar | `sidebar/Content.qml` | Implementado |
| 20 | Propia | El dashboard dibujaba 0 % para una GPU sin lectura | Corregir | «Sin lectura» | `dashboard/DashGauge.qml`, `dashboard/Dash.qml` | Implementado |
| 21 | Propia | La búsqueda de Ajustes no abría el grupo plegado que contenía la fila buscada | Corregir | Abre todos los grupos plegados de la cadena | `settings/Content.qml` | Implementado |
| 22 | Propia | El popout de energía decía «Calculando…» cuando UPower no daba estimación | Corregir | Sin estimación no hay texto; «Conectado, sin cargar» como estado propio | `bar/popouts/CortetsuBatteryPopup.qml` | Implementado |
| 23 | PipeWire 1.6.11 `biquad.c`, `plugin_builtin.c` | El preamp solo cubría la banda más alta y dependía de un caso especial (`highshelf` a 0 Hz) | Corregir | Margen sobre la curva real de la cascada; preamp con el `mixer` lineal; grafo versionado y compatible | `services/{CortetsuEqualizer.qml,EqResponse.js}`, `data/pipewire/cortetsu-eq.conf`, `settings/controls/EqCurve.qml` | Implementado |
| 24 | Nebula `services/Cava.qml` | cava dependía del archivo de configuración del usuario; las barras se recreaban por muestra | Adaptar | Configuración propia en `XDG_RUNTIME_DIR`; modelo por número de barras | `services/CortetsuSpectrum.qml`, `background/Visualiser.qml` | Implementado |
| 25 | Caelestia `utilities/cards/RecordingList.qml` | No se veían las grabaciones hechas | Adaptar sin plugin | `FolderListModel` en Ajustes → Capturas; reproducir y abrir carpeta, sin borrar | `settings/sections/RecordingsSection.qml`, `CortetsuRecorder.qml` | Implementado |
| 26 | end-4 `NotificationGroup` | Una app ruidosa solo se callaba con No molestar | Propia | Silenciar por app desde su grupo; críticas siempre visibles; lista en Ajustes | `services/Notifs.qml`, `sidebar/Content.qml`, `settings/sections/NotificationsSection.qml` | Implementado |
| 27 | end-4 `overview/SearchWidget.qml` | La vista general no se podía filtrar | Adaptar | Filtro de ventanas con `/` o Ctrl+F; la F sigue siendo flotar | `overview/Content.qml` | Implementado |
| 28 | Propia | Limpiar el portapapeles borraba todo de un clic; controles sin teclado | Corregir | Pestañas y botón armado en dos pasos | `clipboard/*.qml` | Implementado |
| 29 | end-4 `volumeMixer` | El mezclador por app solo estaba en Ajustes | Adaptar | Hasta cuatro apps en el pliegue de audio del centro de control | `osd/FullContent.qml` | Implementado |
| 30 | Nebula `MediaIsland` | Sin reproductor en el centro de control | Adaptar | Fila de lo que suena solo con un reproductor | `osd/FullContent.qml` | Implementado |
| 31 | Nebula `Visualizer`, `MirroredCava` | Sin visualizador sin cava | Propia | Medidor de picos con `PwNodePeakMonitor` en el dashboard | `dashboard/DashLevelMeter.qml` | Implementado |
| 32 | Caelestia launcher | Sin búsqueda de archivos | Propia | `>files` sobre el índice de `plocate` ya instalado | `launcher/services/Files.qml` | Implementado |
| 33 | Propia (fase 1 pendiente) | Sin galería de la biblioteca | Propia | Ajustes → Avanzado → Biblioteca de componentes | `settings/sections/ComponentGallerySection.qml` | Implementado |
| 34 | Propia | Diagnóstico mandaba a una terminal | Propia | `cortetsu doctor --json` a demanda | `settings/sections/DiagnosticsSection.qml` | Implementado |
| 35 | Caelestia popouts | Teclado y Bloq Mayús fuera de la familia; lecturas pulsables | Corregir | Cabecera común; `CortetsuFact` | `bar/popouts/Cortetsu{Keyboard,LockStatus}Popup.qml` | Implementado |
| 36 | Propia | Fichas de fondos y de compartir pantalla anónimas | Corregir | Rol, nombre, selección | `wallpaper/WallpaperTile.qml`, `screenshare/ScreenSharePanel.qml` | Implementado |
| 37 | Propia | Avisos del grabador en inglés | Corregir | Español en Rust y en el runtime de referencia | `desktop-runtime-rs/src/recorder.rs` | Implementado |
| 38 | Nebula `WidgetsWindow` (imagen), `TerminalWidget` | — | Descartar | Imagen exige `zenity`; fetch es decorativo | — | No aplica |


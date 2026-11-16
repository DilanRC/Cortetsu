# Inventario de superficies QML: resultado de las olas 3.0

Por archivo, con clase, usos y pruebas: [`qml-inventory.md`](qml-inventory.md)
(regenerado en la segunda ola: 356 propios, 7 de compatibilidad, 1
generado, 66 de prueba, **0 sin referencias**). Matriz exhaustiva por
archivo con estado previo, referencias, cambios, riesgos y QA:
[`COBERTURA_FINAL_QML_3_0.md`](COBERTURA_FINAL_QML_3_0.md), generada por
`scripts/verification/qml-coverage.py`.

Aquí, una fila por superficie activa. Ninguna está verificada en ejecución.

Estados: `IMPLEMENTADO_SIN_VERIFICAR`, `CONSERVADO_JUSTIFICADO`,
`BLOQUEADO_DOCUMENTADO`, `PENDIENTE`. Ola 1 = commits `aefc805b..df78aae0`;
ola 2 = `d574fa85..af2b2a0c`.

| Superficie | Archivos principales | Estado | Ola | Qué cambió o por qué se conserva |
| --- | --- | --- | --- | --- |
| Centro de control | `osd/FullContent.qml`, `osd/LevelRow.qml` | IMPLEMENTADO_SIN_VERIFICAR | 1 y 2 | Niveles primero, dispositivos a demanda (1); lo que suena, mezclador por app, luz nocturna y captura (2) |
| OSD transitorio | `osd/MiniSlider.qml`, `osd/Wrapper.qml` | IMPLEMENTADO_SIN_VERIFICAR | 1 | Perfil de energía como estado; teclado y dispositivos siguen como toasts (un dueño por aviso) |
| Centro de notificaciones | `sidebar/Content.qml` | IMPLEMENTADO_SIN_VERIFICAR | 1 y 2 | Grupos, búsqueda, historial (1); silenciar por aplicación (2) |
| Tarjeta de notificación | `notifications/Notification.qml` | CONSERVADO_JUSTIFICADO | — | Ya opaca, con acciones reales y urgencia |
| Toasts | `utilities/toasts/*.qml` | IMPLEMENTADO_SIN_VERIFICAR | 1 | Una sola señal de urgencia |
| Utilidades | `utilities/Content.qml`, `Wrapper.qml` | CONSERVADO_JUSTIFICADO | — | Tarjetas existentes; su función principal (toggles, grabar) vive en el centro de control |
| Lanzador | `launcher/*.qml`, `launcher/services/*.qml` | IMPLEMENTADO_SIN_VERIFICAR | 1 y 2 | Modo explorar (1); archivos con `plocate`, acciones nuevas (2) |
| Popouts de energía, teclado, Bloq Mayús | `bar/popouts/Cortetsu{Battery,Keyboard,LockStatus}Popup.qml` | IMPLEMENTADO_SIN_VERIFICAR | 1 y 2 | Cabecera común con enlace a su página |
| Popouts de red, Bluetooth, audio, bandeja, vista previa | `bar/popouts/` | CONSERVADO_JUSTIFICADO | — | VERIFIED en la fase 4 |
| Información de ventana | `bar/popouts/CortetsuWindowInfoPopup.qml` | IMPLEMENTADO_SIN_VERIFICAR | 1 | Divisor con token |
| Hub e islas | `BottomHub.qml`, `CortetsuBottomHubView.qml`, segmentos, `Hub*.qml` | CONSERVADO_JUSTIFICADO | — | VERIFIED en la fase 4; no se reabre |
| Cajones | `drawers/*.qml` | CONSERVADO_JUSTIFICADO | — | Fase 4; los widgets y el editor respetan su borde |
| Sesión | `session/Content.qml`, `SessionHost.qml` | IMPLEMENTADO_SIN_VERIFICAR | 1 | Grupos, cuenta atrás, Escape |
| Polkit | `polkit/PolkitDialog.qml` | IMPLEMENTADO_SIN_VERIFICAR | 1 | Bloq Mayús, «Comprobando…»; lógica intacta |
| Bloqueo | `lock/*.qml` | CONSERVADO_JUSTIFICADO | — | Fase 7; sin prueba manual inmediata la ruta PAM no se toca |
| Secretos | `prompt/SecretPrompt.qml`, `SecretPromptHost.qml` | CONSERVADO_JUSTIFICADO | — | Superficie sensible con fixture propio; sin defectos encontrados |
| Ajustes → Sonido | `settings/sections/AudioSection.qml`, `controls/EqCurve.qml` | IMPLEMENTADO_SIN_VERIFICAR | 1 y 2 | Dispositivos primero (1); curva del ecualizador y aviso de grafo antiguo (2) |
| Ajustes → Energía | `settings/sections/PowerSection.qml` | IMPLEMENTADO_SIN_VERIFICAR | 1 | Fuente primero, perfil en el sitio |
| Ajustes → Pantalla | `settings/display/*.qml` | IMPLEMENTADO_SIN_VERIFICAR | 2 | Luz nocturna programada en `DisplayColour.qml`; disposición y presets conservados |
| Ajustes → Atajos | `settings/sections/ShortcutsSection.qml` | IMPLEMENTADO_SIN_VERIFICAR | 2 | Acceso a la hoja de atajos |
| Ajustes → Capturas | `RecorderSection.qml`, `RecordingsSection.qml`, `ScreenshotSection.qml` | IMPLEMENTADO_SIN_VERIFICAR | 2 | Grabaciones recientes |
| Ajustes → Fondo | `settings/sections/WallpaperSection.qml`, `VisualiserSection.qml` | IMPLEMENTADO_SIN_VERIFICAR | 2 | El reloj pasa a enlace a Widgets |
| Ajustes → Widgets | `settings/sections/WidgetsSection.qml` | IMPLEMENTADO_SIN_VERIFICAR | 2 | Nueva: por monitor, quitar con confirmación, galería con motivo |
| Ajustes → Notificaciones | `settings/sections/NotificationsSection.qml` | IMPLEMENTADO_SIN_VERIFICAR | 2 | Aplicaciones silenciadas |
| Ajustes → Biblioteca de componentes | `settings/sections/ComponentGallerySection.qml` | IMPLEMENTADO_SIN_VERIFICAR | 2 | Nueva |
| Ajustes → Wi-Fi, Bluetooth, Inicio, Hub | `settings/network/`, `settings/bluetooth/`, `pages/HomePage.qml`, `BottomHubSection.qml` | CONSERVADO_JUSTIFICADO | — | Rediseñadas en las fases 1-3 (Bluetooth: divisores por token en la ola 2) |
| Ajustes → Diagnóstico | `settings/sections/DiagnosticsSection.qml` | IMPLEMENTADO_SIN_VERIFICAR | 2 | `cortetsu doctor --json` a demanda, solo lo que necesita atención |
| Ajustes, resto de páginas | Temas, Colores, Paneles, Lanzador, Indicadores, Teclado, Automatización, Clima, Movimiento, Sincronización, Perfiles, Acerca de | CONSERVADO_JUSTIFICADO | — | Leídas en la ola 2: Teclado, Indicadores, Capturas, Clima, Movimiento y Sincronización (grupos con título, filas abiertas, validación en el campo, error y guardado). Temas, Colores, Paneles, Lanzador, Automatización, Perfiles y Acerca de, revisadas solo por búsqueda en todo el árbol (divisores a mano, colores literales, textos en inglés, fechas sin locale): sin hallazgos. La navegación por página y la búsqueda ya existían |
| Ajustes, marco | `settings/Content.qml`, controles | IMPLEMENTADO_SIN_VERIFICAR | 1 | Búsqueda que abre grupos plegados; silencio en filas de nivel |
| Dashboard | `dashboard/*.qml` | IMPLEMENTADO_SIN_VERIFICAR | 1 y 2 | GPU sin lectura, pestañas (1); medidor de nivel, selector de reproductor (2) |
| Widgets de escritorio | `desktop/*.qml`, `services/DesktopWidgets.qml` | IMPLEMENTADO_SIN_VERIFICAR | 2 | Nuevo: nueve tipos, editor, migración del reloj 2.x |
| Fondo y visualizador | `background/*.qml`, `services/CortetsuSpectrum.qml` | IMPLEMENTADO_SIN_VERIFICAR | 2 | Barras estables, configuración propia de cava |
| Hoja de atajos | `cheatsheet/*.qml`, `CheatsheetController.qml` | IMPLEMENTADO_SIN_VERIFICAR | 2 | Nueva (SUPER+F1) |
| Vista general | `overview/*.qml` | IMPLEMENTADO_SIN_VERIFICAR | 1 y 2 | Filtro de ventanas; cabecera muerta retirada |
| Wallpaper Orbital | `wallpaper/*.qml` | IMPLEMENTADO_SIN_VERIFICAR | 2 | Fichas accesibles; el resto (órbita, cuadrícula, teclado) se conserva |
| Gestor de pantallas | `display/Wrapper.qml`, `DisplayController.qml` | CONSERVADO_JUSTIFICADO | — | Aloja la página Pantalla de Ajustes |
| Portapapeles | `clipboard/*.qml` | IMPLEMENTADO_SIN_VERIFICAR | 2 | Controles reales, limpiar con confirmación, Washi |
| Calendario y Pomodoro | `calendar/*.qml`, `pomodoro/` | CONSERVADO_JUSTIFICADO | — | Fechas localizadas, «Hoy», teclado por día y mes, estados de sincronización |
| Grabación | `CortetsuRecorder.qml`, runtime `recorder.rs` | IMPLEMENTADO_SIN_VERIFICAR | 2 | Carpeta expuesta; avisos en español |
| Captura de área | `areapicker/*.qml` | CONSERVADO_JUSTIFICADO | — | Completa; ahora también desde el centro de control |
| Compartir pantalla | `screenshare/*.qml` | IMPLEMENTADO_SIN_VERIFICAR | 2 | Fichas con rol y acción |
| Teclados | `keyboards/*.qml` | IMPLEMENTADO_SIN_VERIFICAR | 2 | `KeyCap` compartido con la hoja; editor conservado |
| Hardware | `hardware/**/*.qml` | CONSERVADO_JUSTIFICADO | — | Rediseñado y probado antes de 3.0 |
| Biblioteca | `components/*.qml` | CONSERVADO_JUSTIFICADO | — | Primitivas conformes a ADR-008, visibles en la galería |

## Borrados en la ola 2

`components/CAnim.qml`, `modules/bar/components/Clock.qml`,
`modules/bar/components/StatusIcons.qml`, `services/UsageFmt.qml`,
`utils/CortetsuUtils.qml`, `utils/NetworkConnection.qml`, `utils/SysInfo.qml`
(sin referencias desde la fase 0) y `modules/background/DesktopClock.qml`
(sustituido por el widget de reloj). En la ola 1 se borró
`components/CortetsuInkLabel.qml`.

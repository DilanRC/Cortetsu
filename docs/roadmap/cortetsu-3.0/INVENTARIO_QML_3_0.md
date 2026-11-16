# Inventario de superficies QML: resultado de la ola 3.0

Lista por archivo, clase, usos y pruebas: [`qml-inventory.md`](qml-inventory.md)
(regenerada en esta ola por `scripts/verification/qml-inventory.py`: 340
propios, 66 de prueba, 7 de compatibilidad, 1 generado, 7 sin referencias).

Aquí, una fila por superficie activa con lo que pasó en la ola del
2026-11-16. Ninguna fila está verificada.

Resultados: **rediseñada** (cambio de composición o comportamiento en esta
ola), **corregida** (defecto puntual), **conservada** (sin cambios, con
motivo), **pendiente** (no se llegó; queda para otra ola).

| Superficie | Archivos principales | Resultado | Motivo o cambio |
| --- | --- | --- | --- |
| Centro de control (Ajustes rápidos) | `osd/FullContent.qml`, `osd/LevelRow.qml`, `osd/Content.qml` | Rediseñada | Niveles primero, conexión en pareja, 4 interruptores compactos, energía y perfil, dispositivos a demanda |
| OSD transitorio | `osd/MiniSlider.qml`, `osd/Wrapper.qml` | Rediseñada | Perfil de energía como estado |
| Centro de notificaciones | `sidebar/Content.qml` | Rediseñada | Grupos por app, búsqueda, quitar del historial, DND como fila |
| Tarjeta de notificación | `notifications/Notification.qml` | Conservada | Ya opaca, con acciones reales y estados urgentes |
| Toasts | `utilities/toasts/*.qml` | Corregida | Una sola señal de urgencia |
| Launcher | `launcher/*.qml`, `launcher/services/Apps.qml` | Rediseñada | Modo explorar con favoritas, recientes y categorías |
| Popout de energía | `bar/popouts/CortetsuBatteryPopup.qml` | Rediseñada | Cabecera común, carga como protagonista, perfil leído de vuelta |
| Popouts de red, Bluetooth, audio | `bar/popouts/Cortetsu{Network,Bluetooth,Audio}Popup.qml` | Conservada | Certificados en la fase 4 |
| Bandeja y menús | `bar/popouts/CortetsuTrayMenu.qml`, `CortetsuTraySegment.qml` | Conservada | Certificados en la fase 4 |
| Vista previa de ventanas | `bar/popouts/CortetsuWindowPreview.qml` | Conservada | Fase 4 |
| Información de ventana | `bar/popouts/CortetsuWindowInfoPopup.qml` | Corregida | Divisor con token |
| Hub e islas | `BottomHub.qml`, `CortetsuBottomHubView.qml`, segmentos, `Hub*.qml` | Conservada | Fase 4 VERIFIED; no se reabrió |
| Sesión | `session/Content.qml`, `SessionHost.qml` | Rediseñada | Grupos, cuenta atrás viva, Escape desarma |
| Polkit | `polkit/PolkitDialog.qml` | Corregida | Bloq Mayús, «Comprobando…», foco del campo |
| Bloqueo | `lock/*.qml` | Conservada | Fase 7 ya en código; sin prueba manual disponible en esta ola no se toca la ruta PAM |
| Ajustes → Sonido | `settings/sections/AudioSection.qml` | Rediseñada | Dispositivos primero, silencio por app, ecualizador opcional, límites plegados |
| Ajustes → Energía | `settings/sections/PowerSection.qml` | Rediseñada | Fuente primero, perfil en el sitio, excepciones plegadas |
| Ajustes, filas | `settings/controls/SettingRow.qml`, `SettingSliderRow.qml` | Corregida | Divisor con token; silencio opcional |
| Ajustes, búsqueda | `settings/Content.qml` | Corregida | Abre grupos plegados en la cadena |
| Ajustes → Wi-Fi, Bluetooth, Inicio, Hub | `settings/network/`, `settings/bluetooth/`, `settings/pages/HomePage.qml`, `BottomHubSection.qml` | Conservada | Rediseñadas en las fases 1–3 |
| Ajustes, resto de páginas | Pantalla, Atajos, Captura, Entrada, Temas, Colores, Fondo, Paneles, Lanzador, Notificaciones, Indicadores, Automatización, Clima, Movimiento, Sincronización, Perfiles, Diagnóstico, Acerca de | Pendiente | No revisadas contra ADR-008 en esta ola |
| Dashboard | `dashboard/Dash.qml`, `DashGauge.qml` | Corregida | GPU sin lectura; pestañas accesibles |
| Widgets de escritorio | `background/DesktopClock.qml`, `background/Visualiser.qml` | Pendiente | Sin edición por monitor ni ajuste a rejilla (ver comparativa, fila 15) |
| Overview | `overview/*.qml` | Corregida | Divisor invisible eliminado; composición pendiente |
| Wallpaper Orbital | `wallpaper/*.qml` | Pendiente | |
| Hardware | `hardware/**/*.qml` | Conservada | Rediseñado y probado antes de 3.0 (`docs/HARDWARE_CENTER_QA.md`); no revisado contra ADR-008 |
| Display Manager | `settings/display/*.qml`, `display/` | Pendiente | |
| Portapapeles | `clipboard/*.qml` | Pendiente | |
| Calendario y Pomodoro | `calendar/*.qml`, `pomodoro/` | Pendiente | |
| Grabación y captura | `CortetsuRecorder.qml`, `areapicker/` | Pendiente | El botón de grabar del centro de control usa el dueño existente |
| Compartir pantalla | `screenshare/*.qml` | Pendiente | |
| Teclados | `keyboards/*.qml` | Pendiente | |
| Secretos | `prompt/`, `SecretPromptHost.qml` | Pendiente | |

## Sin referencias

`components/CAnim.qml`, `modules/bar/components/Clock.qml`,
`modules/bar/components/StatusIcons.qml`, `services/UsageFmt.qml`,
`utils/CortetsuUtils.qml`, `utils/NetworkConnection.qml`, `utils/SysInfo.qml`.
Siguen en el árbol: borrarlos cuando se rediseñe su zona, como fijó la fase 0.
`components/CortetsuInkLabel.qml` se borró en esta ola.

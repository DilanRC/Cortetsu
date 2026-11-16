# Comparativa con end-4, Caelestia y Nebula, y mejoras decididas

Ola de construcción 3.0, 2026-11-16. Estado de todo lo implementado:
`IMPLEMENTADO_SIN_VERIFICAR`.

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
| 13 | end-4 `AndroidNightLightToggle`, `GammaIndicator` | Sin luz nocturna | Propuesta | Necesita un dueño de gamma (hyprsunset o `DisplayCalibration`) y su ciclo de vida; no se dibuja un interruptor sin él | — | Pendiente de backend |
| 14 | end-4 `cheatsheet` | Los atajos solo se ven en Ajustes → Atajos | Propuesta | Superposición SUPER+/ con la tabla de `Shortcuts`; sin implementar en esta ola | — | No implementado |
| 15 | Nebula `WidgetSnap`, `EditToolbar` | Widgets de escritorio sin edición ni ajuste a rejilla | Propuesta | Requiere modelo de posición por monitor y colisión con el Hub; ver bloque H en `REGISTRO.md` | — | No implementado |
| 16 | end-4 `AndroidScreenSnipToggle`, `ColorPicker` | La captura no está en el centro de control | Propuesta | `areapicker` existe; falta decidir si va al centro de control o se queda en atajos | — | No implementado |
| 17 | Propia | La sesión decía «Pulsa otra vez en 4 segundos» fijo | Corregir | Cuenta atrás viva; Escape desarma antes de cerrar | `session/Content.qml`, `SessionHost.qml` | Implementado |
| 18 | Propia | El centro de control cambiaba la marca a Monster al pulsar | Corregir | Monster significa fallo de autenticación (ADR-008); la marca queda en Ascended quieta | `osd/FullContent.qml` | Implementado |
| 19 | Propia | El historial de notificaciones se pintaba deshabilitado (opacidad 0,46) | Corregir | Filas legibles con botón de quitar | `sidebar/Content.qml` | Implementado |
| 20 | Propia | El dashboard dibujaba 0 % para una GPU sin lectura | Corregir | «Sin lectura» | `dashboard/DashGauge.qml`, `dashboard/Dash.qml` | Implementado |
| 21 | Propia | La búsqueda de Ajustes no abría el grupo plegado que contenía la fila buscada | Corregir | Abre todos los grupos plegados de la cadena | `settings/Content.qml` | Implementado |
| 22 | Propia | El popout de energía decía «Calculando…» cuando UPower no daba estimación | Corregir | Sin estimación no hay texto; «Conectado, sin cargar» como estado propio | `bar/popouts/CortetsuBatteryPopup.qml` | Implementado |

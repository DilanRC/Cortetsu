# Mejoras creativas de Cortetsu 3.0 (segunda ola)

Mejoras que el plan original no pedía o que van más allá de la referencia
que las inspiró. Todas en estado `IMPLEMENTADO_SIN_VERIFICAR`: escritas y
revisadas a mano, nunca ejecutadas (ver `QA_POSTERIOR.md`).

## 1. Widgets que duermen cuando no se ven

- **Deficiencia.** Un widget de sistema en el fondo muestrea CPU y memoria
  cada 2 s aunque las ventanas lo tapen todo el día.
- **Referencia.** Nebula (`services/Widgets.qml`) y end-4
  (`widgetCanvas/`) pintan sus widgets siempre; Caelestia no tiene widgets.
- **Propuesta.** `ServiceUse.qml` toma el contador `consumers` del
  servicio (el mismo que usan el dashboard y Hardware) solo mientras el
  escritorio de ese monitor está a la vista: ninguna ventana en mosaico en
  su espacio activo (`DesktopWidgetLayer.qml`).
- **Justificación.** El coste solo existe cuando hay alguien mirando.
- **Archivos.** `modules/desktop/{ServiceUse,DesktopWidgetLayer,DesktopWidget}.qml`.
- **Dependencias.** `Cpu`, `Memory`, `Gpu`, `Storage`, `NetworkUsage`.
- **Riesgos.** El criterio «solo ventanas flotantes» deja muestrear con
  una ventana flotante grande encima; el mismo criterio que el visualizador.
- **Estado.** IMPLEMENTADO_SIN_VERIFICAR.

## 2. Posición relativa y consciente del Hub

- **Deficiencia.** Guardar píxeles (end-4) o píxeles más el tamaño del
  monitor de origen (Nebula) obliga a reescalar y no sabe dónde está la
  barra.
- **Propuesta.** El centro de cada widget en fracciones del monitor; el
  área útil resta un margen y el borde que el Hub ocupa en ese monitor
  (`HubAnchor.reserved`, el modelo de la fase 3). El panel del editor se
  pone en el lado contrario al Hub.
- **Archivos.** `modules/desktop/DesktopLayout.js`, `services/DesktopWidgets.qml`, `modules/desktop/Editor.qml`.
- **Riesgos.** Un widget grande en un monitor pequeño se pega al borde del
  área (se recorta su centro, no el widget).
- **Estado.** IMPLEMENTADO_SIN_VERIFICAR.

## 3. Continuidad Ajustes → superficie → Ajustes

- **Deficiencia.** Cada superficie era una isla: el centro de control no
  llevaba al sonido, Ajustes no llevaba al widget.
- **Propuesta.** Ajustes → Widgets abre el editor en el monitor del widget
  y con él seleccionado; el pliegue de audio del centro de control abre
  Ajustes → Sonido; los popouts de teclado llevan a Ajustes → Teclado; la
  hoja de atajos abre el editor de atajos; Ajustes → Atajos abre la hoja.
- **Archivos.** `settings/sections/{WidgetsSection,ShortcutsSection}.qml`, `osd/FullContent.qml`, `bar/popouts/CortetsuKeyboardPopup.qml`, `cheatsheet/Content.qml`.
- **Estado.** IMPLEMENTADO_SIN_VERIFICAR.

## 4. Luz nocturna sin un segundo dueño

- **Deficiencia.** La ola 1 creyó que faltaba backend; existía.
- **Referencia.** end-4 `Hyprsunset.qml` (mata y relanza `hyprsunset` con
  `bash -c`).
- **Propuesta.** El horario vive en el mismo `DisplayCalibration` que ya
  restaura el filtro al arrancar, a través de `hyprsunset.service`. Un
  cambio manual se mantiene hasta el siguiente límite del horario y Ajustes
  dice «cambio manual hasta las HH:mm».
- **Archivos.** `services/{DisplayCalibration.qml,NightLight.js}`, `settings/display/DisplayColour.qml`, `osd/FullContent.qml`.
- **Riesgos.** El minuto de cambio depende del `SystemClock`; un retraso
  de hasta un minuto si el tic llega antes del límite.
- **Estado.** IMPLEMENTADO_SIN_VERIFICAR.

## 5. Preamp calculado sobre la curva que se oye

- **Deficiencia.** «Menos la banda más alta» no cubre el solape de bandas
  vecinas.
- **Referencia.** Nebula no tiene preamp; AutoEQ usa `highshelf` a 0 Hz.
- **Propuesta.** `EqResponse.js` evalúa la cascada con las fórmulas de
  PipeWire 1.6.11 en 241 frecuencias y los centros de banda; el preamp es el
  `mixer` lineal; Ajustes dibuja la curva y la salida tras el preamp.
- **Riesgos.** Frecuencia de muestreo supuesta 48 kHz (comentario
  `ponytail:` con el techo).
- **Estado.** IMPLEMENTADO_SIN_VERIFICAR.

## 6. Visualizador sin dependencias

- **Deficiencia.** cava no está instalado en este equipo y el dashboard no
  tenía visualización de audio.
- **Propuesta.** `PwNodePeakMonitor` (Quickshell) sobre la salida por
  defecto: dos barras de pico, activas solo con el dashboard abierto y la
  música sonando.
- **Archivos.** `modules/dashboard/DashLevelMeter.qml`.
- **Riesgos.** Frecuencia de actualización de los picos sin medir.
- **Estado.** IMPLEMENTADO_SIN_VERIFICAR.

## 7. Búsqueda de archivos sobre lo que ya hay

- **Deficiencia.** El lanzador no encontraba archivos.
- **Propuesta.** `>files texto` pregunta al índice de `plocate` (instalado,
  con su temporizador diario), solo en la carpeta personal y sin rutas
  ocultas, con espera de 180 ms, relanzado si la consulta cambia y sin
  respuestas viejas.
- **Archivos.** `launcher/services/Files.qml`, `launcher/{AppList,ContentList}.qml`, `launcher/services/Actions.qml`.
- **Riesgos.** El índice tiene hasta un día de antigüedad; lo dice el
  estado vacío.
- **Estado.** IMPLEMENTADO_SIN_VERIFICAR.

## 8. Silencio por aplicación con escape para lo crítico

- **Deficiencia.** Solo había No molestar, todo o nada.
- **Propuesta.** Silenciar una app desde su grupo; sus avisos van al
  historial; uno crítico aparece igual.
- **Archivos.** `services/Notifs.qml`, `sidebar/Content.qml`, `settings/sections/NotificationsSection.qml`, `CortetsuConfig.qml`.
- **Riesgos.** Apps que cambian el nombre que envían.
- **Estado.** IMPLEMENTADO_SIN_VERIFICAR.

## 9. La biblioteca como herramienta de QA

- **Deficiencia.** Los tres temas se juzgaban sobre superficies
  concretas, con datos que cambian.
- **Propuesta.** Ajustes → Avanzado → Biblioteca de componentes: cada
  primitiva en todos sus estados, con el tema activo.
- **Archivos.** `settings/sections/ComponentGallerySection.qml`.
- **Estado.** IMPLEMENTADO_SIN_VERIFICAR.

## 10. Diagnóstico sin terminal

- **Deficiencia.** Ajustes → Diagnóstico mandaba a escribir `cortetsu doctor`.
- **Propuesta.** El mismo informe de solo lectura, a demanda, con lo que
  necesita atención y la hora.
- **Archivos.** `settings/sections/DiagnosticsSection.qml`.
- **Estado.** IMPLEMENTADO_SIN_VERIFICAR.

## Descartado por complejidad sin beneficio

- Overlay de widgets sobre las ventanas (end-4): duplica el centro de
  control.
- Selector de imagen para widgets (Nebula): necesita `zenity`.
- Movimiento expresivo en reposo (Nebula): contrario a MOTION 1.

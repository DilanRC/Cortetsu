# QA posterior de la ola de construcción 3.0

## Orbital Steam: escenarios añadidos, sin ejecutar

- Compilar el helper y ejecutar sus pruebas unitarias cuando se autorice QA.
- Steam principal, symlinks, Flatpak, bibliotecas adicionales, VDF antiguo y
  moderno, escapes y archivo malformado; discos desconectados y duplicados.
- project.json ausente, corrupto, sobredimensionado, FIFO y archivo no regular;
  preview fuera del proyecto, symlink, nombre con espacios y caracteres URL.
- Límites de catálogo: errores visibles y truncado explícito; ningún escaneo
  recursivo de disco ni ejecución del contenido.
- Bundle con cortetsu-orbital, helper ausente, salida inválida, error y reintento.
- QML: apertura/cierre/retorno, Tab, Enter, Escape, foco visible, búsqueda sin
  resultados, filtros, portadas fallidas, texto largo y catálogo grande.
- Ink/Washi/Kurogane, escala fraccional, pantalla estrecha y ausencia de overflow.
- Regresión del apply estático, ACK y pipeline de colores; abrir Steam no aplica
  fondos ni cambia paletas. La instalación activa debe seguir intacta.
- Antes de certificar reproducción futura: ownership por salida, conflicto
  externo, crash, fallback, lock duplicado, reconexión, orientación, reanudación,
  widgets/input, Scene/Video/Web y propiedades reales del motor.
- Antes de certificar políticas futuras: batería/AC, juegos fullscreen,
  maximización, bloqueo, suspensión e inactividad; medir GPU/CPU/VRAM y consumo
  por backend. No inferir ahorro desde la configuración de FPS.
- Antes de certificar persistencia futura: migración, corrupción, playlists,
  perfiles, rutas desaparecidas, importación/exportación y rollback de generación.

## Orbital reproducción: escenarios sin ejecutar

Construcción del 2026-11-17 sobre `17021636`. Nada de esto se compiló ni se
ejecutó. Hacerlo **en una sesión anidada o en un WS libre** (ver memoria del
proyecto) salvo la sección física.

Estático y unidades:

- `cargo build` y `cargo test` del runtime: las 6 pruebas de
  `orbital_session.rs` y las del catálogo. Clippy sin avisos nuevos.
- qmllint de `services/Orbital.qml`, `SteamPlayback.qml`, `SteamLibrary.qml`,
  `Background.qml`, `Content.qml`, `Actions.qml`, `FullContent.qml`,
  `WallpaperSection.qml` y `OrbitalField.qml`.
- `cortetsu-orbital session` con stdin manual en un Hyprland anidado: snapshot
  inicial, `inspect` de Scene/Video/Web/Image/roto, `apply` con monitor
  inexistente, JSON inválido, línea > 64 KiB y EOF (debe salir y matar hijos).
- Segundo supervisor con el lock tomado: error claro, sin tocar el primero.

Ownership y transición (anidado, dos salidas virtuales):

- Aplicar Scene en una salida: `preparing` → acuse `covered` → proceso →
  superficie mapeada → `applying` → `revealed` → `active`. Ningún «Activo»
  antes de la superficie; la otra salida no cambia.
- Cambiar de Scene a Video en la misma salida: nunca dos PIDs propios mapeados a
  la vez (`hyprctl layers -j` en bucle durante la transición).
- Propietario externo: lanzar `linux-wallpaperengine` o `swww` a mano en la
  capa `background`; Aplicar debe dar `foreign-owner` sin tocar ese proceso.
- Motor que no mapea (monitor mal escrito o assets ausentes): `transition-timeout`
  a los 15 s, cubierta estática y stderr visible.
- `kill -9` del motor activo: dos reinicios en 120 s, al tercero error y fondo
  estático. Con `unshare` o PID propio; **nunca** `pkill` global.
- `kill -9` del supervisor: el motor muere por `PDEATHSIG`; Quickshell
  reintenta dos veces y luego muestra el error.
- Recarga del shell: el motor muere con stdin, y al volver se restaura si
  `restoreOnStart`.
- Desconectar y reconectar una salida; desactivarla con `hyprctl keyword monitor`;
  cambiar escala y orientación.
- Detener: cubierta, motor fuera y, con el fondo estático desactivado en
  Ajustes, la cubierta desaparece tras el acuse.
- Restaurar anterior tras dos aplicaciones distintas.
- Aplicar un fondo estático desde Orbital con un animado activo: solo se detiene
  el animado de ese monitor.

Energía y GPU (sesión física, con Dilan presente):

- Política integrada: `nvidia-smi` y `/sys/bus/pci/devices/0000:01:00.0/power/runtime_status`
  deben seguir en `suspended` durante Scene y Video. Comparar con «GPU del sistema».
- Batería/AC con `pauseOnBattery`, DPMS apagado/encendido, pantalla completa de un
  juego, suspensión y reanudación (una vez; ver memoria NVIDIA).
- Medir CPU, GPU, VRAM y consumo a 15/30/60 FPS por tipo. No se afirma ahorro.

Interfaz:

- Estados visibles: Preparando, Aplicando, Activo, Detenido, En pausa (con
  motivo), Error (con código y stderr) e Incompatible (Web, Image, roto).
- Teclado y foco en todos los controles nuevos; texto largo de propiedades con
  HTML del autor; combos con 32+ opciones; lista de rotación con 100 entradas.
- Ink, Washi y Kurogane; escala fraccional; panel estrecho sin desbordes.
- Launcher «Fondos animados de Steam», Ajustes → Fondo y Ajustes rápidos
  abren la biblioteca Steam, también con Orbital ya abierto.
- Bloqueo de pantalla con fondo animado: imagen estática, sin parpadeo.
- Widgets del escritorio y visualizador visibles sobre el fondo animado, con
  `cortetsu-background` en la capa `bottom` también sin Orbital.

Persistencia:

- `orbital.json` ausente, corrupto, versión 2 y campo desconocido: el supervisor
  se detiene con el error y el archivo queda intacto.
- Ruta de Workshop borrada con restauración pendiente: error `restore`, fondo
  estático.
- Playlists, perfiles, colecciones y carpetas adicionales sobreviven a la recarga.
- Rollback de generación con `orbital.json` presente: la generación anterior lo
  ignora y conserva su fondo estático.

Revisión estática de esta entrega: ver el informe final de la misión. Las
dos pasadas Thermos se hicieron en línea, en secuencia y sin subagentes, por
preferencia registrada de Dilan; no son revisiones independientes.

Estado: **pendiente de autorización**. Nada de esta lista se ejecutó en las
dos olas del 2026-11-16 (ola 1: `aefc805b` a `df78aae0`; ola 2: `d574fa85` a
`35c5bdef`, más su documentación). La ola 2 está en la sección 9.
Este archivo no contiene resultados: es el orden y el alcance de la misión
`QA INTEGRAL 3.0`.

Regla para esa misión: un fallo se corrige en ella, con prueba que falle
antes y pase después. No se reescribe una prueba para que pase sin que el
comportamiento cambie.

## 0. Antes de nada

```bash
git -C ~/Documentos/GitHub/Cortetsu status --short   # .codebase-memory/ es ajeno
git -C ~/Documentos/GitHub/Cortetsu log --oneline 6299f21f..HEAD
quickshell --version; qmake6 --version | tail -1; hyprctl version | head -1
```

## 1. Estático (sin abrir el shell)

| Orden | Comando | Qué busca |
| --- | --- | --- |
| 1 | `/usr/lib/qt6/bin/qmllint` sobre los QML tocados (lista en §6) | tipos, imports, propiedades inexistentes |
| 2 | `./scripts/cortetsu theme check` | tokens generados al día; no se tocó la fuente de tokens |
| 3 | `python3 scripts/verification/qml-inventory.py --check docs/roadmap/cortetsu-3.0/qml-inventory.md` | inventario al día |
| 4 | linter de diseño (el que usa `build-regressions.sh`) | `layout-nested-surface`, literales de color |

## 2. QML aislado

```bash
QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -input cortetsu/tests/qml/surfaces/tst_MiniSlider.qml
QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -input cortetsu/tests/qml/polkit/tst_PolkitDialog.qml
QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -input cortetsu/tests/qml/components
QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -input cortetsu/tests/qml/focus
```

Pruebas nuevas que faltan (escribirlas en QA, no antes):

| Pieza | Prueba de comportamiento |
| --- | --- |
| `MiniSlider` kind `profile` | nombre e icono por perfil; sin barra; `available` siempre |
| `osd/Wrapper` | un cambio de perfil antes de 3 s no se anuncia; después sí, solo en la pantalla activa; con el centro de control abierto no sale el mini OSD |
| `osd/FullContent` + `LevelRow` | silenciar desde el botón; lista de dispositivos plegada al abrir y al cerrar; perfil leído de vuelta (un rechazo deja la pestaña anterior) |
| `sidebar/Content` | agrupación: orden de llegada entre grupos y dentro; cabecera solo en el primero; contador; búsqueda con más de 8 entradas; quitar una entrada llama a `cortetsu-notifications dismiss <id>` |
| `launcher/services/Apps` | `browse("home")`: favoritas, recientes por orden, resto; categoría vacía no aparece; archivo de recientes ausente, corrupto, con no-cadenas o con más de 12 |
| `launcher/Content` | Ctrl+←/→ cambia de categoría solo con la búsqueda vacía; cerrar vuelve a «Inicio» |
| `session/Content` | cuenta atrás 4→1 en la fila; Escape desarma sin cerrar; segundo Escape cierra |
| `PolkitDialog` | aviso de Bloq Mayús solo con `canRespond`; «Comprobando…» entre envío y respuesta |
| `CortetsuEqualizer` | sin nodo no lanza procesos; con nodo, payload de `pw-cli` exacto; ±12 dB; preamp = −máx(ganancias positivas); apagado = 0 dB; reaplica al volver el nodo |
| `SettingSliderRow` `mutable` | el botón alterna el silencio del stream aunque el deslizador esté deshabilitado |
| `settings/Content.revealSetting` | una búsqueda que apunta a una fila dentro de un grupo plegado lo abre |
| `DashGauge` | `available: false` dibuja «Sin lectura» y ningún porcentaje |

## 3. Pruebas existentes que dependen de lo cambiado

Muchas son comprobaciones de cadenas (hallazgo H-24). Las que fallen por un
texto movido se sustituyen por una prueba de comportamiento, no se amplían.

| Área | Archivos |
| --- | --- |
| Centro de control | `test-cortetsu-quick-settings-runtime.py` (en el gate; usa `quickWifi`, `quickMicrophone`, `quickEnergy`, que se conservaron), `test-cortetsu-wave4-quick-settings-osd.py` y `test-osd-host.py` (**fallarán**: buscan `CortetsuInkLabel`, «Controles», «Niveles» y la nota de energía, que ya no existen), `test-cortetsu-osd*.py`, `test-cortetsu-power.py`, `test-cortetsu-static-brand-surfaces.py`, `test-cortetsu-native-design-system.py`, `test-cortetsu-native-popups.py`, evals homónimos |
| OSD transitorio | `tests/qml/surfaces/tst_MiniSlider.qml`, `test-cortetsu-osd-focus.sh`, `render-cortetsu-theme-surfaces.py` |
| Notificaciones | `test-cortetsu-native-notification-center.py`, `test-cortetsu-quality.py`, `eval-cortetsu-native-notification-center.py` |
| Energía | `test-cortetsu-power.py`, `test-cortetsu-hub-controls-runtime.py`, `test-cortetsu-progress-bar.py`, `test-stable-interaction-bounds.py`, `test-cortetsu-ink-material.py`, `test-cortetsu-native-popups.py` |
| Sesión | `test-cortetsu-session-host.py`, `test-cortetsu-session-runtime.py`, `test-session-host.py` |
| Polkit | `tests/qml/polkit/tst_PolkitDialog.qml`, `tests/realm/polkit-preview.qml` |
| Launcher | `test-launcher-focus-runtime-contract.py`, `test-cortetsu-launcher-identity.py`, `test-launcher-process-scope.py`, `test-retained-overlay-wiring.py`, `scripts/integration/test-launcher-dismiss.py`, `test-cortetsu-launcher-apps-runtime.py` (ya fallaba antes de la ola) |
| Toasts | `test-cortetsu-toasts.py`, `test-cortetsu-notice-cards-runtime.py` |
| Dashboard | `test-cortetsu-dashboard-typography.py`, `test-dashboard-host.py`, `cortetsu/tests/test-regional.py` |
| Controles | `tests/qml/components/tst_AccessibleControls.qml`, `tests/qml/focus/tst_DisabledControlFocus.qml` |
| Arranque | `test-cortetsu-config.py`, `tst_SpectrumLifecycle.qml` y el inventario de procesos de arranque de `build-regressions.sh`: `ServiceLoader` instancia ahora `CortetsuEqualizer` (sin nodo no lanza nada) |

## 4. Gates completos

```bash
./scripts/cortetsu test
./scripts/build-regressions.sh          # sobre un runtime preparado en un directorio temporal
```

## 5. Anidado (Hyprland en el primer WS libre de eDP-1)

| Escenario | Prueba |
| --- | --- |
| Centro de control con el Hub en los 8 anclajes | abrir, plegar/desplegar dispositivos, cerrar por Escape y clic fuera |
| OSD de perfil | cambiar el perfil desde el popout y desde Ajustes; un solo OSD |
| Launcher | categorías con apps reales; recientes tras lanzar; Ctrl+←/→; `test-launcher-dismiss.py` |
| Notificaciones | ráfaga de 3 apps; agrupación; quitar del historial |
| Sesión | confirmación, cuenta atrás, Escape doble (sin ejecutar la acción) |
| Polkit | `AuthFlow` falso (memoria: contraseñas reales bloquean la cuenta 10 min) |
| Ecualizador | PipeWire en un `XDG_RUNTIME_DIR` aislado con `cortetsu-eq.conf`; `pw-dump` antes y después de cada ajuste |

## 6. Sesión física (solo con Dilan presente)

- Tres temas (Ink, Washi, Kurogane) por superficie tocada; capturas solo de
  espacios vacíos.
- `eDP-1` + `HDMI-A-1`, escala 1.25.
- Perfil de energía real con `power-profiles-daemon` (activo hoy; sin él, la
  barra de perfiles queda sin selección: comprobar que no promete nada).
- Ecualizador: instalar el `.conf`, reiniciar PipeWire, elegir la salida,
  medir que el preamp evita la saturación, quitarlo. Comprobar si la ruta HDMI
  despierta la RTX 3050.
- `cortetsu shell logs 200` sin `TypeError`, `ReferenceError`, `Binding loop`,
  `Unable to assign`, `is not a type`.
- Recarga suave: no se añadieron *inline components* (`LevelRow` es un
  archivo propio); `cortetsu shell reload` debería bastar. Verificarlo.

## 7. Rendimiento

- PSS en reposo y CPU a 60 s antes/después (línea base: fase 4, 417–423 MiB
  en arranque limpio).
- Apertura del centro de control y del launcher (primer fotograma).
- Que el ecualizador sin nodo no lance procesos y con nodo lance uno por cambio.

## 8. Instalación y rollback

```bash
./scripts/cortetsu install     # solo tras 1–7 en verde
cortetsu status; cortetsu doctor; cortetsu audit
cortetsu rollback && cortetsu shell restart    # ensayo de vuelta atrás
```

## QML tocados en la ola

`components/CortetsuActionTile.qml`, `components/CortetsuInkLabel.qml` (borrado),
`modules/osd/{FullContent,LevelRow,MiniSlider,Wrapper}.qml`,
`modules/sidebar/Content.qml`, `modules/launcher/{Content,ContentList,AppList}.qml`,
`modules/launcher/services/Apps.qml`, `modules/bar/popouts/{CortetsuBatteryPopup,CortetsuDetachedPopup,CortetsuWindowInfoPopup}.qml`,
`base/modules/bar/popouts/Content.qml`, `modules/session/Content.qml`,
`modules/SessionHost.qml`, `modules/polkit/PolkitDialog.qml`,
`modules/settings/{Content.qml,controls/SettingRow.qml,controls/SettingSliderRow.qml,sections/AudioSection.qml,sections/PowerSection.qml}`,
`modules/overview/Content.qml`, `modules/dashboard/{Dash,DashGauge}.qml`,
`modules/utilities/toasts/ToastItem.qml`, `modules/ServiceLoader.qml`,
`modules/CortetsuConfig.qml`, `services/CortetsuEqualizer.qml`.

## 9. Segunda ola (`d574fa85` a `35c5bdef`)

### 9.1 Estático

- `qmllint` sobre todo lo que lista `git diff --name-only 3b4e7c2f..HEAD -- '*.qml'`.
  Puntos con más riesgo de no compilar: importación cualificada
  `import "../settings" as SettingsModule` en `osd/FullContent.qml` (singleton
  por directorio con calificador); `Binding { restoreMode: Binding.RestoreNone }`
  en `desktop/Editor.qml`; `ScriptModel` de cadenas en
  `desktop/{DesktopWidgetLayer,Editor}.qml`; `QtObject` (`ServiceUse`) como
  hijo de `ColumnLayout`; `font.features` en `DesktopWidget.qml`;
  `property string state` en `cheatsheet/Content.qml` (mismo patrón que
  `ShortcutsSection.qml`); `Keys.onShortcutOverride` en campos de búsqueda.
- `python3 scripts/verification/qml-inventory.py --check docs/roadmap/cortetsu-3.0/qml-inventory.md`
  y `python3 scripts/verification/qml-coverage.py` (sale 1 si queda un archivo sin familia).
- `cargo check` del runtime de escritorio por el cambio de textos de `recorder.rs`.

### 9.2 Pruebas existentes que fallarán y deben sustituirse por pruebas de comportamiento

| Prueba | Por qué falla |
| --- | --- |
| `scripts/features/test-cortetsu-config.py` | Lee `background/DesktopClock.qml`, `bar/components/{Clock,StatusIcons}.qml`, `utils/{SysInfo,CortetsuUtils}.qml`, `services/UsageFmt.qml`, borrados |
| `cortetsu/tests/test-regional.py` | Lee `background/DesktopClock.qml` |
| `cortetsu/tests/test-runtime-contract.py` | Nombra `utils/NetworkConnection.qml` |
| `scripts/features/test-cortetsu-settings-runtime.py` | Monta `DesktopClock` y busca las filas del reloj en Fondo, que pasan a Ajustes → Widgets |
| `scripts/features/test-cortetsu-screen-state.py` | Su lista fija de siete banderas retenidas; ahora son nueve (`cheatsheet`, `desktopWidgets`) |
| `scripts/features/test-cortetsu-power.py`, `test-bottom-hub-v3.py` | Nombran `StatusIcons` o el reloj de escritorio |
| Pruebas de equivalencia del grabador | El runtime de Rust y el de referencia en Python cambiaron igual sus textos; comprobar que la equivalencia compara lo mismo |
| Inventario de procesos de arranque de `build-regressions.sh` | Procesos nuevos solo a demanda: `cortetsu:cheatsheet-keybind-list`, `cortetsu:launcher-file-search`, `cortetsu:settings-doctor`; `cortetsu:spectrum` ahora con `-p` |

### 9.3 Pruebas nuevas que faltan (escribirlas en QA)

| Pieza | Comportamiento |
| --- | --- |
| `desktop/DesktopLayout.js` | `rectFor` con `cx = 0` y `1`; área con el Hub en cada borde; `snap` a borde, centro y otro widget, y a rejilla sin guía; `sanitiseList` con basura, duplicados y más de 24; `legacyClock` por posición |
| `services/DesktopWidgets.qml` | `add` respeta `available` y el máximo; `placeAt` guarda el centro y el monitor; deshacer/rehacer; `ownerScreen` con monitor ausente; `beginSession` conserva una selección válida |
| `desktop/Editor.qml` | Clic sin arrastre no mueve; arrastre con guías; flechas, + y −, Supr; selección de otro monitor ignorada; Escape guarda y sale |
| `desktop/DesktopWidget.qml` | «Leyendo…» antes de la primera muestra; GPU en reposo; batería ausente; sin reproductor; nota vacía; filas de Sistema y Red **no** recreadas tras una muestra (contador en `Component.onCompleted`) |
| `desktop/DesktopWidgetLayer.qml` + `ServiceUse` | Consumidores 0 con una ventana en mosaico; 1 por servicio con el escritorio vacío; liberados al destruir |
| `CortetsuConfig` | Migración: `desktopClockEnabled: true` sin `desktopWidgets` crea un reloj en su posición; con lista vacía, no |
| `services/NightLight.js` | `inRange` con rango que cruza medianoche y rango vacío; `nextBoundary` el mismo día y el siguiente |
| `services/DisplayCalibration.qml` | Horario enciende y apaga; un cambio manual se mantiene hasta el siguiente límite y luego sigue el horario |
| `services/EqResponse.js` | Plano = 0 dB; una banda +6 → pico ≈ 6 dB; 64 y 125 Hz a +6 → pico > 6 dB; preamp nunca positivo; `linear(-6) ≈ 0.501` |
| `services/CortetsuEqualizer.qml` | Payload `"eq_preamp:Gain 1"` lineal con grafo 2; `"eq_preamp:Gain"` en dB sin la propiedad; nada antes de `node.ready` |
| `services/CortetsuSpectrum.qml` | Sin `visualiserEnabled` no escribe ni lanza; con él escribe el archivo y lanza `cava -p`; cambiar las barras relanza |
| `cheatsheet/Content.qml` + `Columns.js` | Agrupa, filtra, reparte en columnas; Escape con texto vacía sin cerrar; error del ayudante |
| `launcher/services/Files.qml` | Menos de dos letras no busca; espera 180 ms; consulta cambiada en curso relanza; respuesta vieja descartada; código ≠ 0/1 = «no disponible»; filtra ocultos y fuera de HOME |
| `services/Notifs.qml` | App silenciada: sin emergente y en historial; crítica de app silenciada: con emergente |
| `clipboard/Content.qml` | Limpiar arma, se desarma a los 4 s, borra al segundo clic y conserva los fijados |
| `overview/Content.qml` | `/` y Ctrl+F abren el filtro; F sola sigue alternando flotante |
| `settings/sections/DiagnosticsSection.qml` | Informe con avisos y errores; salida vacía con código; repetir |

### 9.4 Anidado

| Escenario | Prueba |
| --- | --- |
| Editor del escritorio | Abrir por IPC `desktopWidgets open`; añadir los nueve tipos; arrastrar; Hub en los ocho anclajes (el área y el panel cambian de lado); dos salidas con «Llevar a» |
| Hoja de atajos | `hyprctl reload`; SUPER+F1 abre y cierra; con pantalla completa |
| Centro de control | Pliegue con flujos reales (`pw-play` en el `XDG_RUNTIME_DIR` aislado); lo que suena con un reproductor MPRIS de prueba; mosaico de captura abre el selector tras cerrar |
| Luz nocturna | Con `hyprsunset` en la sesión anidada: horario con el reloj desplazado (`faketime` o cambio de las horas) |
| Lanzador | `>files` con un doble de `plocate` delante en `PATH=<doble>:/usr/bin:/bin` (patrón de los arneses; memoria: no conservar el `PATH` del usuario) que imprime rutas fijas, tarda y sale con 0, 1 y 2 |
| Notificaciones | `notify-send -a App` silenciada y crítica |

### 9.5 Sesión física (con Dilan presente)

- Widgets sobre los tres temas, `eDP-1` y `HDMI-A-1` a escala 1.25;
  desconectar el HDMI con widgets en él y reconectarlo.
- Medidor de nivel del dashboard con música real.
- Ecualizador: **volver a copiar** `cortetsu-eq.conf` (grafo 2), reiniciar
  PipeWire, `pw-dump` del nodo `cortetsu_eq` (dos entradas y dos salidas, no
  dieciséis), escuchar la curva «Graves» sin saturación.
- Biblioteca de componentes en Ink, Washi y Kurogane.
- `cortetsu shell logs 200` limpio tras abrir cada superficie nueva.

### 9.6 Rendimiento (medir, no se afirma nada)

- PSS y CPU en reposo con 0, 3 y 9 widgets a la vista y tapados.
- Frecuencia de `PwNodePeakMonitor.peaks` y CPU del dashboard con música.
- Latencia de `>files` con la base real (`plocate.db` de ~1,4 GB en este equipo).
- Primer fotograma de la hoja de atajos con 119 atajos.

### 9.7 Instalación

- `config/hypr-user.lua` gana `SUPER + F1`: tras `cortetsu install`, hace
  falta `hyprctl reload` (memoria: install no recarga Hyprland).
- Preferencias nuevas: `desktopWidgets`, `displayCalibration.schedule`,
  `mutedNotificationApps`. Probar la migración del reloj con una copia de
  `preferences.json` real, no la viva.

### QML y JS tocados en la ola 2

`components/ScreenState.qml`, `base/modules/bar/popouts/Content.qml`,
`modules/{CheatsheetController,CortetsuConfig,CortetsuRecorder,CortetsuRegional,CortetsuScreenState,DesktopWidgetsController,RetainedSurfacesHost}.qml`,
`modules/SurfaceRegistry.js`, `modules/background/{Background,Visualiser}.qml`,
`modules/bar/popouts/Cortetsu{Keyboard,LockStatus}Popup.qml`,
`modules/cheatsheet/{Columns.js,Content.qml,Wrapper.qml}`,
`modules/clipboard/{ClipboardItem,Content}.qml`,
`modules/dashboard/{DashLevelMeter,DashMediaPlayer}.qml`,
`modules/desktop/{DesktopLayout.js,DesktopWidget,DesktopWidgetLayer,Editor,EditorWrapper,ServiceUse}.qml`,
`modules/keyboards/{KeyCap,KeyCaps}.qml`,
`modules/launcher/{AppList,ContentList}.qml`, `modules/launcher/services/{Actions,Files}.qml`,
`modules/osd/FullContent.qml`, `modules/overview/Content.qml`,
`modules/screenshare/ScreenSharePanel.qml`,
`modules/settings/{PageRegistry,SettingsController}.qml`,
`modules/settings/bluetooth/DeviceDetailPanel.qml`, `modules/settings/controls/EqCurve.qml`,
`modules/settings/display/DisplayColour.qml`,
`modules/settings/sections/{AudioSection,ComponentGallerySection,DiagnosticsSection,NotificationsSection,RecordingsSection,ShortcutsSection,WallpaperSection,WidgetsSection}.qml`,
`modules/sidebar/Content.qml`, `modules/wallpaper/WallpaperTile.qml`,
`services/{CortetsuEqualizer,CortetsuSpectrum,DesktopWidgets,DisplayCalibration,Notifs,Weather}.qml`,
`services/{EqResponse,NightLight}.js`, `shell.qml`.


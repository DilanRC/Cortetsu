# QA posterior de la ola de construcción 3.0

Estado: **pendiente de autorización**. Nada de esta lista se ejecutó en la ola
del 2026-11-16 (commits `aefc805b` a `df78aae0` y la documentación que sigue).
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

# Cortetsu 2.0 · F1a: registro único de superficies

Fecha: 2026-10-20. Rama `feat/f1a-surface-registry` sobre `main` = `898024d` (contiene F0, el hotfix GPU #48 y ADR-007
PROPOSED #49). Versiones: Hyprland 0.56.2 · Quickshell 0.3.2 (4f508be) · Qt 6.12.0 · node 26.11.1. F1b no se ha iniciado.

## 1. Qué cambia

Antes había siete copias del inventario de superficies, en JS y QML, y dos de ellas se contradecían:

| Copia (en `main`) | Contenido | Estado |
|---|---|---|
| `OverlayPolicy.closeOtherPanels` | 6 transitorias + 7 retenidas | igual que `closeAll` |
| `OverlayPolicy.closeForWallpaper` / `hasCompetingPanel` | lo mismo sin `wallpaperManager` | dos copias escritas a mano |
| `CortetsuOverlayPolicy.retainedFlags` + `closeAll` | 7 retenidas + 6 transitorias | |
| `CortetsuScreenState.setFlag` / `setRetained` / `closeRetainedOverlays*` | cuatro listas de retenidas, una de transitorias (con `osd`) | |
| `CortetsuScreenState` derivados | `requiresWindowKeyboardFocus` = retenidas + launcher + session | **en uso** (ContentWindow) |
| `ScreenState` derivados | lo mismo **+ settings** | **sin lectores**, contradictoria |
| `ScreenState.resetTransientState`, `Shortcuts` (`drawers`) | 15 flags; 5 «exclusivas por IPC» | |

Ahora:

- `cortetsu/modules/SurfaceRegistry.js` es la única tabla: nombre, tipo (`retained`, `transient`, `chrome`) y tres atributos
  (`exclusive`, `ownsKeyboard`, `ipcExclusive`). Exporta grupos congelados y validadores. No importa nada, así que no hay orden de
  inicialización ni ciclos (`CortetsuOverlayPolicy.js` → `OverlayPolicy.js` → `SurfaceRegistry.js`).
- Las dos políticas, `CortetsuScreenState`, `ScreenState` y `Shortcuts` derivan de ella todos sus grupos. Contratos y tipos en
  [`docs/SCREEN_STATE_MIGRATION.md`](../../SCREEN_STATE_MIGRATION.md).
- `OverlayPolicy.setFlag` escribe siempre a través de `cortetsuState.setFlag` (y este de `setRetained`), tanto si recibe el estado
  tipado como el `ScreenState` heredado. Los objetos planos de los tests QML se siguen escribiendo directamente.
- `setFlag`, `setRetained`, `drawers toggle|isOpen|list` y `toggleExclusive` rechazan nombres que no están en el registro.
- Se borran los cuatro derivados muertos de `ScreenState`. La única definición vive en `CortetsuScreenState`.
- `hasCompetingPanel` y `retainedOverlayOpen` aceptan también el estado tipado (antes, con él, `hasCompetingPanel` no veía las
  transitorias). Ningún llamador lo usaba así; cierra una trampa.

QML no puede generar propiedades: `ScreenState` declara un `bool` por entrada y `CortetsuScreenState` uno de solo lectura por
retenida. Un gate falla si divergen (§4).

## 2. Matriz de comportamiento, antes y después

Observada en Hyprland anidado con `docs/migration/F1a/tools/nested_contracts.py`, el mismo script contra `main` y contra la rama
(195 comprobaciones cada una, `evidence/contracts-{before,after}.json`). Salidas `HEADLESS-1` y `HEADLESS-2`, cliente Kitty con la
entrada en un archivo.

| Contrato | main | F1a |
|---|---|---|
| Cada retenida (7) abre en la pantalla con foco y solo en ella, en ambas pantallas | 14/14 | 14/14 |
| Con una retenida abierta, una tecla no llega al cliente | 14/14 | 14/14 |
| Escape la cierra y el teclado vuelve al cliente | 14/14 + 14/14 | 14/14 + 14/14 |
| Exclusividad retenida → retenida (42 pares, misma pantalla) | 42/42 | 42/42 |
| Exclusividad retenida → retenida en la otra pantalla | 37/42 | 37/42 (mismos 5, ver O-1) |
| Transitoria exclusiva (launcher, session, dashboard, utilities, settings) cierra Hardware y viceversa | 10/10 | 10/10 |
| OSD coexiste con Hardware en ambos órdenes | sí | sí |
| `drawers toggle sidebar` sobre Hardware deja ambos abiertos (O-2) | sí | sí |
| Wallpaper Manager se cierra al abrir otra retenida en la otra pantalla | 2/2 | 2/2 |
| `drawers toggle sidebar` cierra el Wallpaper Manager y deja la barra lateral | 9/10 | 9/10 (O-3) |
| `toggle` desde otra pantalla cierra; `open` la mueve a la pantalla con foco | sí | sí |
| SUPER+CTRL+K abre y cierra Atajos y teclados; SUPER+H, Hardware; el teclado vuelve | 6/6 | 6/6 |
| Clic en el borde de la pantalla: cierra Hardware y Portapapeles, Calendario sigue | igual | igual |
| Pantalla completa cierra la retenida | sí | sí |
| Estado final: los 15 flags cerrados en ambas pantallas y el teclado en el cliente | sí | sí |
| `drawers isOpen retainedOverlayOpen` / `requiresFullInputMask` | `0` | `unknown` |
| `drawers list` | 15 flags + 4 derivados | 15 flags |
| `drawers toggle retainedOverlayOpen` | `TypeError: Cannot assign to read-only property` en el log | ignorado |

Las tres últimas filas son las únicas diferencias de las 195 comprobaciones, y son el cambio buscado: los derivados no son
superficies. Nadie consume `drawers list` salvo como sonda de arranque (código de salida) en el arnés.

En los 40 ciclos × 7 superficies del banco de F0: 0 fallos de estado en las cuatro pasadas (§5).

### Pruebas automáticas nuevas

- `cortetsu/tests/qml/surfaces/tst_SurfaceRegistry.qml` (Qt Quick Test, 15 casos): inventario completo y congelado; rechazo de
  nombres; `setFlag` por tipo; derivados que siguen al registro (incluido que `settings` no pide teclado, como en F0); `closeOtherPanels`
  respeta OSD y barra; exclusión de Wallpaper en ambos sentidos; toda escritura pasa por `setFlag` (espía); `openExclusive`
  idempotente; 40 ciclos sin retenidas residuales; pantallas independientes; compatibilidad con objetos planos.
- `scripts/features/test-cortetsu-surface-registry.py`: evalúa el registro con node (`surface_registry.py`) y comprueba que
  `ScreenState` y `CortetsuScreenState` declaran exactamente sus flags, que ningún módulo propio mantiene una lista literal de
  superficies (con dos excepciones justificadas que no son clasificación) y que el registro y su test entran en ambos gates.
- `docs/migration/F1a/tools/mutants.sh`: 12 mutantes (OSD exclusivo, falta `keyboards`, `settings` pide teclado, escritura que
  esquiva `setFlag`, nombre desconocido aceptado, lista paralela reintroducida…). **12/12 eliminados.**

### Gates existentes actualizados

Cuatro comprobaban el texto de la implementación antigua (que cada nombre apareciera literalmente en `OverlayPolicy.js`). Ahora
comprueban el contrato: el nombre está en el grupo correcto del registro evaluado y la política usa ese grupo. No se quitó ninguna
aserción: `test-cortetsu-screen-state.py`, `eval-cortetsu-state-boundary.py`, `test-retained-overlay-wiring.py` y
`test-wallpaper-manager.py`. En este último, la aserción sobre los controladores estaba fuera del bucle y solo miraba el último
(señalado por ai-review); ahora se aplica a los cuatro.

## 3. Rutas encontradas que no cambia F1a

F1a centraliza la clasificación; no cambia quién abre qué. Estas rutas existen igual en `main` y se registran para F1b:

| ID | Hallazgo | Evidencia |
|---|---|---|
| O-1 | `CalendarController.open` cierra los demás paneles solo en su propia pantalla (los otros controladores, en todas). Abrir Calendario en la otra pantalla deja abierta la retenida anterior | 5 FAIL idénticos en ambas versiones (`exclusive … then calendar, other screen`) |
| O-2 | `drawers toggle sidebar\|osd\|<retenida>` alterna sin política: la barra lateral se apila sobre Hardware. El atajo SUPER+N sí es exclusivo | `cross-kind` |
| O-3 | Carrera intermitente: al cerrar el Wallpaper Manager por la barra lateral, a veces se cierran ambos | 1/10 en ambas versiones (`evidence/wallpaper-repeat-*.json`) |
| O-4 | Unos 60 puntos de los cajones heredados (launcher, session, dashboard, Interactions, ContentWindow…) escriben flags transitorios directamente en `ScreenState`. Son cierres o aperturas propias del cajón; pasarlos por `setFlag` no cambia el resultado y no se hizo para no tocar código upstream sin necesidad | `grep` en §2 de la investigación |
| O-5 | `hyprctl activelayer` no existe en Hyprland 0.56: `launcher_harness.Session.keyboard_layer()` siempre devuelve `""`. Ninguna prueba existente lo usa para afirmar nada; el script de F1a mide el foco por dónde cae una tecla | `unknown request` |

## 4. Gates ejecutados

| Gate | Resultado |
|---|---|
| Qt Quick Test: `surfaces` (nuevo), `bottomhub`, `components`, `focus`, `hardware`, `hypr`, `keyboards`, `settings`, `wallpaper/tests` | 15, 49, 15, 10, 31, 7, 34, 9, 19 PASS |
| Estáticos de screen state, retenidas, wallpaper, atajos, foco, popouts, OSD (20 scripts) | PASS |
| `cortetsu test` completo en el WS 2 (`run_suite.py`, 185 entradas) | **184 PASS, 0 FAIL, 1 NOT_RUN** (el mismo que F0: crea un scope en el systemd real). La primera pasada dio 1 FAIL de aparato: `run_suite.py` tenía fija la lista de directorios QML y ejecutó `tests/qml/surfaces` como Python; ahora trata cualquier directorio como Qt Quick Test, igual que `run_qml_test`, y la nueva pasada de las entradas QML dio 9/9 PASS. Ninguna entrada cambió la huella de la sesión real. H-05 no apareció |
| Construcción aislada de dos generaciones y rollback (`test-cortetsu-build.py`, el job de runtime de la CI) | PASS, con `tests/qml/surfaces` y el gate nuevo dentro de `build-runtime.sh` |
| Mutantes | 12/12 |
| CI de GitHub | ver la PR |

## 5. Rendimiento frente a F0

Banco de F0 (`nested_bench.py`, 20 arranques, 10 aperturas, 40 ciclos × 7) en condiciones iguales: el mismo arnés, la misma
máquina, `main` (`898024d`) y la rama alternados en dos pares, primero main→F1a y luego F1a→main (`evidence/perf-table.txt`).

| Pasada | Apertura P50 (ms) hw / disp / clip / kbd / wall / ovw / cal | Arranque P50 (σ) | ida y vuelta IPC |
|---|---|---|---|
| 1 main | 78 / 78 / 81 / 79 / 87 / 110 / 80 | 1003 (50) | 22 |
| 1 F1a | 88 / 85 / 88 / 87 / 101 / 121 / 92 | 1255 (186) | 29 |
| 2 F1a | 78 / 79 / 84 / 79 / 92 / 116 / 82 | 1053 (84) | 23 |
| 2 main | 156 / 86 / 89 / 94 / 88 / 108 / 80 | 1029 (101) | 24 |
| F0 (2026-10-20, `0a803e7`) | 80–113 | 1054 (29) | 44 |

La segunda pasada de cada par sale más lenta sea cual sea la versión, y la diferencia sigue al tiempo de ida y vuelta de `qs ipc`,
que no depende del QML. La resolución del método es la del fotograma más la captura (~60 ms de suelo según F0). **No hay
diferencia atribuible al código**: el registro añade una búsqueda en un array de 15 entradas por escritura.

Recursos en los 40 ciclos, las cuatro pasadas: 0 fallos de estado; hilos 48→48 (49→49 en una), fds 112→112 (113→113), 1
descendiente; PSS de −0,2 a +6,3 MiB sin tendencia entre versiones; 0 avisos QML de clase «other». En el escenario de contratos,
F1a no añade ningún tipo de aviso y elimina los dos únicos `TypeError` que producía `main`.

## 6. Depuración gráfica y aislamiento

- Kitty propia `Cortetsu-F1a-Debug` (clase `cortetsu-f1a-debug`) en el WS 2 con `exec_cmd(…, { workspace = "2 silent" })`, con
  pestañas de logs, procesos y contratos (procedimiento de `docs/migration/F0/DEBUG-SESSION.md`). La instancia `rice` no se tocó.
- Cada sesión anidada se lanzó con `ws2_run.py` y `F0Session` (shell compuesto desde el checkout, `XDG_RUNTIME_DIR` corto
  propio, D-Bus privado, stubs para toda orden que toca el host, solo Mesa). Las ventanas `aquamarine` aparecieron en el WS 2; el
  workspace activo del escritorio siguió en el 3.
- `real_snapshot.sh` antes y después de la suite: `unchanged` (`evidence/real-diff.txt`). dGPU NVIDIA: `suspended`. Ningún `/tmp/czr*`
  ni proceso con su runtime tras cada pasada (`leftover_pids = []`, `runtime_dir_removed = true`).

Reproducir:

```sh
S=<salida>
python3 scripts/integration/ws2_run.py --timeout 1800 $S/c.log -- \
    python3 docs/migration/F1a/tools/nested_contracts.py <checkout> $S/contracts.json   # main o la rama
ONLY=wallpaper REPEAT=10 python3 scripts/integration/ws2_run.py --timeout 1500 $S/w.log -- \
    python3 docs/migration/F1a/tools/nested_contracts.py <checkout> $S/wallpaper.json
python3 scripts/integration/ws2_run.py --timeout 3000 $S/b.log -- \
    python3 <checkout>/docs/migration/F0/tools/nested_bench.py $S/bench --starts 20 --opens 10 --cycles 40
docs/migration/F1a/tools/mutants.sh
```

## 7. Riesgos y compatibilidad

| Riesgo | Mitigación |
|---|---|
| Un consumidor externo leía `screenState.retainedOverlayOpen` o los otros derivados del `ScreenState` heredado | `grep` en `cortetsu/` (incluido `base/`), `scripts/`, `dotfiles/`, `~/.config/hypr` y `~/.local/bin`: ninguno. Siguen en `cortetsuState` |
| Un script dependía de los 4 derivados en `drawers list` | solo el arnés lo usa, por su código de salida |
| Las dependencias de los bindings derivados ya no son lecturas estáticas sino `anyOpen(legacyState, grupo)` | Qt captura también lecturas dinámicas; `test_derived_flags_follow_the_registry` lo verifica flag a flag en el motor QML |
| Orden de cierre: `CortetsuOverlayPolicy.closeAll` cerraba antes las retenidas y ahora sigue el orden del registro | las escrituras son síncronas en la misma llamada y el estado final es idéntico; la matriz observada no cambia |
| `surface_registry.py` necesita node | el job de runtime de la CI ya instala `nodejs`; `cortetsu test` ya ejecuta pruebas node |
| Añadir una superficie exige tocar tres sitios | los dos gates nombran el que falta |

Fuera de F1a y sin cambios: H-05 (no apareció en estas pasadas; sigue con su propio seguimiento), D-02, D-03, ADR-007 (PROPOSED),
F-02…F-07 y las pruebas físicas `NOT_TESTED` de F0.

## 8. Rollback

El cambio es solo de QML/JS del shell y de pruebas; no toca servicios, helpers ni configuración.

- Sin desplegar: cerrar la PR o `git revert` de su merge.
- Desplegado: `cortetsu rollback` vuelve a la generación anterior (valida shell y hashes antes de mover los symlinks); `cortetsu
  system verify` confirma. No hay estado persistente que migrar: los flags de superficie se reinician en cada arranque
  (`resetTransientState`).

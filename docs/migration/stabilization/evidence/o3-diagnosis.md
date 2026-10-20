# O-3 · Diagnóstico de la carrera Wallpaper/Sidebar

Entorno: Hyprland anidado en el WS 2 (`ws2_run.py` + `F0Session`), salidas `HEADLESS-1/2`, escenario `wallpaper` de
`docs/migration/F1a/tools/nested_contracts.py` (abre el Wallpaper Manager en `HEADLESS-1` y llama a
`drawers toggle sidebar`). Árbol: un worktree temporal de `main` (`3c432ea`) con registros `O3DBG`. `o3/instrumentation.diff` es su diff
final: los registros de la pasada A y la corrección probada en la pasada B.

- `ScreenState.onSidebarChanged`: valor, hora y pila de llamadas;
- `wallpaper/Wrapper.onGlobalOtherOverlayOpenChanged`: qué instancia (visible u oculta) reacciona;
- `HyprlandFocusGrab` de `ContentWindow`: `onActiveChanged` y `onCleared`, con la hora.

## Pasada A · `main` instrumentado, 15 repeticiones

`o3/o3a-sidebar-checks.json`: **4 FAIL de 15** (las dos superficies cerradas). `o3/o3a-events.log`: hay exactamente
cuatro `grab cleared`, uno por fallo, entre 20 y 40 ms después de `grab active=true`, siempre con `sidebar=true`
justo antes. En las 11 repeticiones correctas no hay ningún `cleared`.

```
O3DBG sidebar=true t=1792529548530            ← drawers toggle sidebar (Shortcuts.qml → setFlag)
O3DBG wrapper(false) other=true active=false   ← copia oculta del Wrapper en la ventana de cajones
O3DBG wrapper(true) other=true active=true     ← Wrapper visible: cierra el Wallpaper Manager
O3DBG grab active=true t=1792529548531 sidebar=true retained=false
O3DBG wrapper(false) …                         ← la copia oculta de la otra pantalla, dos veces
O3DBG grab cleared t=1792529548553 sidebar=true   ← 22 ms después: onCleared cierra la barra lateral
```

Cada evento del Wrapper aparece varias veces porque cada pantalla tenía dos instancias (la visible en
`RetainedSurfacesHost` y la oculta en `drawers/Panels.qml`).

## Mecanismo (código de Hyprland v0.56.2 y Quickshell 4f508be)

- Quickshell crea el grab en cuanto `active` pasa a `true` (`HyprlandFocusGrab::tryActivate`), pero el cambio de
  `keyboardFocus` de una capa se aplica en el siguiente `commit` de su superficie (`LayerSurface::commit`, al pulir la
  ventana).
- Al activarse, el grab de Hyprland enfoca la ventana de cajones (`CFocusGrab::refocusKeyboard`).
- Si después llega el `commit` en que esa capa pasa de `OnDemand` a `none` y era la última enfocada, Hyprland llama a
  `refocusLastWindow` (`LayerSurface.cpp`), que reenfoca por el puntero; la superficie bajo el puntero no está en el
  grab y `mouseMoveUnified` lo termina (`setGrab(nullptr)` → `cleared`).
- La ventana de cajones estaba en `OnDemand` porque el Wallpaper Manager es dueño de teclado
  (`requiresWindowKeyboardFocus`) y pasa a `None` al cerrarse; la barra lateral no es dueña de teclado. El orden
  entre la creación del grab y ese `commit` decide el resultado.

## Pasada B · la misma rama con la corrección, 20 repeticiones

Corrección: la ventana de cajones mantiene `OnDemand` mientras quiere el grab (y un solo binding escribe el modo).
Así no pasa por `none` bajo un grab vivo. `o3/o3b-sidebar-checks.json`: **0 FAIL de 20**; `o3/o3b-events.log`:
20 `grab active=true`, **0 `cleared`**.

La corrección en la rama es la misma condición, con el grab como propiedad de la ventana
(`ContentWindow.wantsFocusGrab`). Su verificación final está en `stab-after.json` (O-3 por las tres rutas) y en la
repetición de 20 vueltas (§6 del informe).

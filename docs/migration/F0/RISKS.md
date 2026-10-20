# F0 · Riesgos, incertidumbres y pendientes

Estados posibles: `OPEN` (requiere una decisión), `NOT_TESTED` (no se puede reproducir de forma segura aquí) y `FINDING`
(defecto observado, sin corregir porque F0 no autoriza cambiar código funcional). Ninguno cuenta como superado.

## 1. Hallazgos de código funcional (sin corregir)

| ID | Severidad | Hallazgo | Evidencia | Impacto |
|---|---|---|---|---|
| F-01 | Media | `services/Gpu.qml:32` usa `StandardPaths` sin `import QtCore` | journal real: `@services/Gpu.qml[32:-1]: ReferenceError: StandardPaths is not defined` (2026-10-19 22:30); el HEAD no tiene el import | el sondeo `--gpus` de ese servicio no se ejecuta; sus consumidores quedan sin datos de GPU |
| F-02 | Baja | Bucle de binding en `modules/sidebar/Content.qml:142` (`model`) | journal real, 2 avisos por arranque | trabajo de re-evaluación; no se observó fallo visible |
| F-03 | Baja | `GameMode.finish()` no valida la forma de la respuesta | arnés: `{}` produce `Cannot assign [undefined] to QString` (`GameMode.qml:68`) | un reemplazo del helper que omita `state` deja el estado anterior en la UI |
| F-04 | Baja | `cortetsu-power-auto-control status` reescribe `power-auto.json` en cada consulta | mtime nuevo con el mismo SHA-256 (`latency.json → state_changed_during_run`) | una escritura en disco por cada sondeo de la página de energía |
| F-05 | Baja | Falso positivo de Wallpaper Engine (`engine_running()` busca por subcadena) | `pgrep` periódico de un script personal externo; reaplicaciones de color | CPU residente de `wallpaper-color` de 0,24 % a 0,75–2,6 % |
| F-06 | Doc | `docs/DISPLAY_MANAGER.md` desfasado (rutas de Caelestia, persistencia como «próximo bloque») | `cortetsu-display-persist` existe y está conectado (CONTRACTS.md) | lectores y F1 partirían de un contrato falso |
| F-07 | Baja | `picker` sin `isOpen`; la capa `cortetsu-area-picker` sigue tras `close` en el arnés | sondeo de superficies | la captura de área no tiene un contrato de cierre verificable |

## 2. Riesgos del aparato de pruebas (corregidos en esta rama)

| ID | Riesgo | Estado |
|---|---|---|
| H-01 | `launcher_harness.Session` dejaba el QML anidado sin IPC de Hyprland cuando la ruta del socket superaba `sun_path`. `test-bottomhub-hover-close-race.py` pasaba con 5 errores `ServerNotFound` | corregido, con aserción de regresión y mutante (TESTS.md §2) |
| H-02 | Las ventanas de los compositores anidados se colocaban según la regla personal `cortetsu-nested-tests` (WS 11), no en el WS 2 pedido | `ws2_run.py` (shim de Hyprland), auditado por muestreo (TESTS.md §3) |
| H-03 | Las pruebas con su propio `XDG_RUNTIME_DIR` largo (`test-hp-keys.py`, `test-clipboard-sensitive-history.py`, `test-keyboards-{scope,probe,capture}.py`) siguen truncando el socket | **residual**: no arrancan `qs` y `hyprctl` trunca igual que Hyprland, así que hoy no fallan. Cualquier prueba nueva que arranque QML con ese patrón quedaría ciega. Recomendación para F1: usar `Session` o un runtime corto |
| H-04 | Arranque del Hyprland anidado colgado de forma intermitente: se queda en la negociación `zwp_linux_dmabuf_v1` con el escritorio y no crea su socket | **residual**: 2 cuelgues seguidos (2026-10-20, con el juego del WS 3 en pantalla completa y `ai-review` en marcha) y después 6 arranques correctos con las mismas versiones; ninguno en las pasadas completas. Las pruebas lo reportan como FAIL por timeout (20 s), nunca como PASS. Si reaparece en CI local, repetir antes de investigar el código |

## 3. Decisiones abiertas (bloquean fases posteriores, no F0)

| ID | Decisión | Estado | Bloquea |
|---|---|---|---|
| D-01 | ADR del socket `cortetsu.ipc/1`: coordinador con activación systemd frente a CLI one-shot, autenticación por UID del par, límites, versión | OPEN. Hoy no existe ningún socket de Cortetsu: el IPC es `qs ipc` más procesos lanzados desde QML | F4, F7 y el diseño de `contracts/*.json` |
| D-02 | ¿El gate cuenta los SKIP? 9 entradas de `cortetsu test` salen con exit 0 y SKIP sin Wayland | OPEN | confianza en CI |
| D-03 | Pruebas huérfanas (20) fuera de todo gate, dos de recuperación | OPEN | cobertura de recuperación |
| D-04 | Tag del estado previo `f0-baseline-2026-10-20` sobre `0a803e7` | OPEN. Crear o subir tags no está autorizado | rollback de referencia |

## 4. Pruebas físicas y de sesión — NOT_TESTED

Ninguna es reproducible de forma segura en una sesión anidada ni sin la presencia de Dilan.

| ID | Escenario | Por qué no aquí |
|---|---|---|
| SLP-01 | Suspend/resume con HDMI | suspende el equipo real |
| SLP-02 | GameMode activo al suspender | idem, y toca el GameMode real |
| DSP-01/02/03 | Preview sin confirmar, desconexión de HDMI durante la preview, mantener 1080p144 | solo `eDP-1` conectado; cambia la pantalla principal |
| KEY-01…04 | Super/Esc, OMEN en fullscreen, Copilot, Fn+Esc, LATAM en el teclado físico | el arnés usa un teclado virtual: cubre la ruta de Hyprland, no el firmware ni el keymap físico |
| POW-01/02 | AC↔batería, batería crítica sin hibernación | requiere desenchufar el equipo |
| EVT-02 | Dos sesiones de producto a la vez sin mezclar estado | dos sesiones de usuario reales; los locks de wallpaper y power-auto son por usuario, no por sesión |
| GameMode | `PENDING_PHYSICAL` de `docs/GAME_MODE.md` | GameMode real |
| PERF-02 real | 40 ciclos de overlays en la sesión real | se midió en el arnés (BASELINE.md §4). En la sesión real roba el teclado a Dilan (memoria del proyecto) |

PERF-01 (reposo real, 4 × 120 s sin entrada) se midió el 2026-10-20 a las 07:33 y está en BASELINE.md §2. No se verificó que
ningún panel estuviera abierto.

## 5. Incertidumbres de medida

- **El arnés no es la sesión real.** Usa `QT_QUICK_BACKEND=software`, 3 salidas, HOME vacío y helpers ausentes. Sus números solo
  sirven para comparar arnés con arnés (antes y después de una migración), nunca con la sesión real ni con el baseline de
  2026-09-04.
- **Aperturas y cierres medidos por fotograma** son cotas superiores: incluyen la ida y vuelta de `qs ipc` (P50 ≈ 44 ms) y el
  intervalo de captura de grim (P50 ≈ 58 ms). Un cambio menor que unos 60 ms no se puede resolver con este método.
- **Las sondas reales** se tomaron con la sesión activa (navegador en el WS 3). Se anotan `loadavg`, governor y perfil.
- **Conteo de procesos transitorios:** muestreo cada 50 ms, así que es una cota inferior.
- **Inventario:** las referencias son por coincidencia de texto. El dominio y el coste de migración se asignaron por juicio y deben
  confirmarse en F1.

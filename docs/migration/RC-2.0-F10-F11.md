# Cortetsu 2.0 · Release candidate (F10 física y F11 aceptación)

Fecha: 2026-10-22/23. Equipo: HP Victus (Ryzen HawkPoint2 + RTX 3050 6 GB Laptop), CachyOS, kernel
`7.2.10-1-cachyos`, Hyprland 0.56.2, NVIDIA open 615.78.08. Sin cambios de kernel, drivers ni paquetes.

Candidata: **`HEAD` de `main`** (arreglos en §5) (instalada, `cortetsu verify` y `cortetsu-rescue verify` PASS). Partida: `78c03fa`.
Evidencia local (no versionada, puede contener datos de la sesión): `~/.local/state/cortetsu/qa/f10-2026-10-23/`.
Parte de la evidencia del 22 se perdió al reiniciarse el equipo (vivía en `/tmp`); se indica abajo.

## 1. GC

- Pins oficiales añadidos (`~/.local/share/cortetsu/pins/{system,shell,dotfiles}.txt`) para el checkpoint
  previo a 2.0 `b586c90`: sistema `20261021-152748-337166`, shell `20261021-092620-333858`, dotfiles
  `20261021-152747-337139-b586c90d`. Antes solo lo retenía un hueco de `--keep 5`.
- Plan `637608351c7e4992` (el anterior `ed54062b60e90d1e` cambió al crear los pins), aplicado con `--archive`:
  21 generaciones borradas, 100,37 MiB liberados, 65 MiB de archivo. Ahorro neto ≈ 35 MiB.
- Archivo: 21 tar.gz, lista de rutas verificada por el GC, CRC gzip de las 21 extracciones correcto, SHA-256 en
  `gc-backups/20261023-045113-704083-242298769/ARCHIVES.sha256`. Las generaciones antiguas no tienen manifiesto de
  hashes, así que el contenido no puede compararse con el original.
- Conservadas: current `78c03fa`, previous `568eb0f`, checkpoint `b586c90` (pinned) y las 5 adicionales.

## 2. Matriz F10

| Área | Prueba | Resultado |
|---|---|---|
| Interfaz | 7 superficies retenidas: abren, toman el teclado, Escape cierra, teclado vuelve (eDP-1) | PASS 28/28 |
| Interfaz | Exclusividad retenida×retenida, retenida→transitoria, OSD coexistente (eDP-1) | PASS 56/56 |
| Interfaz | SUPER+H, SUPER+SHIFT+C, SUPER+N reales | PASS |
| Interfaz | Fullscreen modo 2: Sidebar y OSD bloqueados, Hardware permitido | PASS |
| Interfaz | 280 ciclos abrir/cerrar: sin estados atascados ni fuga (PSS −8 MiB) | PASS |
| Multimonitor | Driver `physical_qa.py` A1–A4 en eDP-1 + HDMI-A-1 | **PASS 197/197** |
| Notificaciones | Avisos `-1` (notify-send) caducan | **FAIL → corregido** (`72f2af3`, `113f7a4`) |
| Teclado | Volumen, silencio, brillo con OSD | PASS |
| Teclado | OMEN abre/cierra Hardware; Copilot abre acciones rápidas | PASS |
| Teclado | Micrófono mudo | NOT_TESTED (sin tecla) |
| Teclado | Fn+Esc | NOT_TESTED (sin acceso a evdev; sin acción asignada) |
| Teclado | Play/Pause | NOT_TESTED (sin reproductor) |
| Gestos | 4 dedos horizontal, 3 dedos arriba (especial), 4 dedos abajo (sesión) | PASS |
| GPU | `qs` en la Radeon (`renderD129`); sin procesos en la NVIDIA en reposo; sin errores DRM | PASS |
| GPU | Terraria eligió la RTX 3050 por sí mismo; Cortetsu no fuerza GPU | PASS |
| Suspensión | eDP-1, 7,5 min: bloqueo, Pomodoro FOCUS→BREAK, un aviso visto | PASS (transición 14 s tras reanudar: espera monótona de hasta 30 s, corregida en `8332b87`) |
| Suspensión | HDMI conectado, 33 min | PASS (el monitor estaba en reposo por inactividad; sin congelado; `HDMI-S2IDLE.md` §6) |
| Gaming | Modo juego: 8 opciones aplicadas y restauradas idénticas; `qs` 0,25 % CPU durante el juego | PASS |
| Gaming | Warframe | NOT_TESTED (no instalado) |
| Diseño | Animaciones, DPI, accesibilidad, transparencia | NOT_TESTED (sin observación dedicada) |

## 3. Métricas medidas

| Medida | Valor | Condición |
|---|---|---|
| CPU `qs` en reposo | 0,18–0,2 % | 60 s, superficies cerradas |
| CPU con Hardware abierto | 2,5 % | 15 s, telemetría en vivo |
| CPU con otras superficies | 0,1–0,9 % | 15 s cada una |
| CPU durante 280 ciclos | 38,7 % | 126 s de estrés |
| CPU `qs` en reposo tras H-45 | 1,2 % (60 s y 3×10 s), PSS 465 MiB | eDP-1 + HDMI-A-1, sin reproductor ni eventos de Hyprland |
| CPU `qs` en reposo, solo eDP-1 | 0,28 % y 5,5 despertares/s; 0,25 % y 5,3/s con `Time` por minutos | mismo proceso, PSS 477 MiB tras recargas suaves |
| PSS `qs` proceso nuevo | 554 → 514 MiB con el fondo a resolución de pantalla | dos monitores, 20 s tras arrancar |
| PSS tras 6 recargas suaves | +80 MiB en la primera, luego estable (595–620 MiB) | mismo proceso |

No hay baseline del proceso nuevo con un solo monitor; el valor de la mañana (204 MiB) era un proceso de 14 h con
191 MiB en swap y no es comparable. La recarga suave no fuga: crece en la primera y se estabiliza.

## 4. F11

| Gate | Resultado |
|---|---|
| `cortetsu test` | PASS |
| Tests nuevos (`test-notification-*`, `test-shell-adopt-scope.py`, Rust `cpu_temp_*`) | PASS; rojos con el código anterior |
| `cargo clippy -D warnings`, `cargo fmt` (hardware-runtime) | PASS |
| `cortetsu install` × 3, `verify`, `cortetsu-rescue verify` | PASS |
| Rollback `30ad4dc`→`113f7a4`→`30ad4dc` con verify en cada paso | PASS |
| CI remota de `b07ac18` y `3cd13d6` | PASS 13/13 cada uno |

**Veredicto F11: PASS.** Los criterios críticos de F10 se cumplen; las pruebas NOT_TESTED
no son críticas.

## 5. Cambios desde `78c03fa`

- `72f2af3`, `113f7a4`: los avisos con `expire_timeout -1` usan `notificationDefaultExpireTimeout`; con
  `notificationExpire` desactivado no caducan. Antes nunca caducaban.
- `76f1990`: `cortetsu shell adopt` ya no ejecuta `pkill -x qs`; solo termina `qs` de este usuario con `-p` dentro
  del runtime de Cortetsu y fuera de `cortetsu-shell.service`.
- `30ad4dc`: el dashboard muestra la temperatura del sensor de CPU (k10temp/zenpower/coretemp), la misma que Hardware
  Center, sin shell (antes `acpitz`). `VPN.qml` pasa la interfaz como `$1`.

- `590978f`: Spectrum ejecuta cava directamente y Bluetooth lee el código y stderr de busctl desde `Process`. Queda
  una sola excepción de shell en QML (portapapeles: `wl-copy` lee la imagen de stdin; la ruta es `$1`).
- `977dfeb`: `notificationFullscreenExpireTimeout` se aplica a los avisos `-1` con una ventana a pantalla completa.
- `perf(background)`: el fondo se decodifica a la resolución de la pantalla (4625×2600 → 1921×1080), −40 MiB medidos.

## 6. Riesgos y pendientes

- HDMI tras `s2idle`: la prueba de hoy no reprodujo el congelado de 2026-10-20 (el monitor estaba en reposo); sigue
  abierto con una sola muestra a favor y otra en contra.
- Bucle de despertares con la tapa cerrada en batería: diagnosticado (EC por IRQ 9 + UPower sin hibernación).
  Mitigado: UPower apaga en batería crítica y `acpi.ec_no_wakeup=1` (tapa probada; batería baja no reproducida).
- Pomodoro: resuelto en `8332b87`. El daemon se reejecuta en la generación promovida (comprobado en vivo: mismo PID
  207873, helpers nuevos tras `install`) y duerme sobre `CLOCK_BOOTTIME`.
- Retraso de Pomodoro tras reanudar: causa encontrada (espera monótona de hasta 30 s) y corregida en `8332b87`;
  falta repetir una suspensión real para observarlo.
- H-45 resuelto en `b07ac18` (con Codex): 8 preferencias con efecto e interruptores en Ajustes; las de la barra
  retirada y los límites del lanzador se retiran. CPU en reposo tras el cambio: 0,27 % (una muestra, con vídeo).
- Falta baseline de memoria con un solo monitor.
- CPU en reposo con dos monitores: 1,2 % y 13 despertares/s; con solo eDP-1, 0,28 % y 5,5/s. El coste extra lo pone
  el HDMI: está en la NVIDIA y el shell pinta en la Radeon, así que cada fotograma de esa salida se copia entre GPUs.
  Con `gdb` se vio que lo que se marca para repintar son textos del OSD de ajustes rápidos (oculto) y del reloj, menos
  de una vez por segundo; los ~3 eventos/s por ventana no están explicados del todo. `Time` pasa a tick por minuto
  (nadie leía segundos): mejora dentro del ruido. Baseline de memoria de proceso nuevo con un monitor: sigue sin medir.

## 7. Rollback

`cortetsu rollback` vuelve a `113f7a4` (probado). El checkpoint `b586c90` está fijado; su restauración se describe
en `README.md` (GC y pins).

# Incidencia de plataforma · HDMI congelado tras `s2idle`

Estado: **abierta, causa no determinada**. Separada de la PR #51: el QML de Cortetsu no gestiona salidas DRM, y el
fallo siguió con el shell instalado (anterior a la PR). Este informe no atribuye la causa al controlador ni al
compositor; reúne lo observado y lo que falta medir.

Origen: prueba B de `PHYSICAL-QA.md` (2026-10-20), cuyo resultado se mantiene: **`PHYSICAL_SUSPEND_POMODORO_FAIL`**.
Evidencia nueva de este informe: `evidence/physical/hdmi/` (recogida el 2026-10-20 a las 22:55, sin suspender, sin root
y sin cambiar nada del sistema).

## 1. Síntoma

| Hora (CST) | Hecho | Fuente |
|---|---|---|
| 21:21:04 → 21:21:16 | Intento 1: despertó solo a los 12 s (IRQ 9, ACPI/EC, «Unexpected lid state»). No se comprobó la imagen del HDMI | `kernel-journal.txt` |
| 21:22:32 → 21:53:48 | Intento 2: 31 min en `s2idle` | `suspend-kernel.log` |
| tras 21:53:48 | `grim -o HDMI-A-1` se cuelga; `grim -o eDP-1` funciona; Dilan confirma la imagen congelada. Hyprland da HDMI-A-1 activo, `dpmsStatus` encendido, sin `monitoradded/removed` | `PHYSICAL-QA.md` §4.4 |
| tras restaurar el shell instalado | sigue congelado | `PHYSICAL-QA.md` §4.4 |
| ≈21:54:26 | `hl.dsp.dpms({ action = "off" })` y `"on"`: vuelve la imagen y `grim` funciona | aviso `RLD` de esa hora en `kernel-journal.txt`; `PHYSICAL-QA.md` §4.4 |

## 2. Plataforma

| | |
|---|---|
| Salidas | `eDP-1` en la iGPU AMD (`06:00.0`, amdgpu, primaria de Hyprland) · `HDMI-A-1` en la dGPU NVIDIA (`01:00.0`, renderizador secundario de aquamarine) |
| Kernel | `7.2.10-1-cachyos`, `mem_sleep` = `[s2idle]` (no hay `deep`) |
| NVIDIA | módulo abierto `615.78.08` (`linux-cachyos-nvidia-open 7.2.10-1`); `PreserveVideoMemoryAllocations=1`, `TemporaryFilePath=""`, `EnableS0ixPowerManagement=0`, `DynamicPowerManagement=2`; `nvidia-suspend`, `nvidia-resume` y `nvidia-hibernate` habilitados y ejecutados en cada ciclo |
| Compositor | Hyprland 0.56.2 (`efb5099`), aquamarine 0.15.1, Mesa 26.2.4 |
| systemd | 262; `SYSTEMD_SLEEP_FREEZE_USER_SESSIONS=0` (las sesiones de usuario no se congelan) |
| Pila sin cambios desde | 2026-10-14 (última actualización de kernel y NVIDIA en `pacman.log`) |

Todo en `evidence/physical/hdmi/platform.txt`.

## 3. Evidencias

**Journal del kernel** (`kernel-journal.txt`):

- `[nvidia-drm] [GPU ID 0x00000100] Failed to register auto-value-update on pre-wait value for sync FD semaphore
  surface` (`__nv_drm_semsurf_wait_fence_work_cb`, nivel `*ERROR*`) una vez en cada suspensión: 21:21:15.55 (al
  reanudar el intento 1) y 21:22:33.62 (al entrar en el intento 2). En este arranque no aparece en ningún otro momento.
  En las suspensiones de los arranques anteriores con la misma pila (2026-10-16 a 19) no aparece. `PHYSICAL-QA.md`
  §4.4 decía que el journal solo mostraba el aviso de reloj de píxel; este error no estaba recogido.
- `nvidia-modeset: WARNING: … RLD advertized maximum pixel clock 300000 KHz violates maximum pixel clock constraint for
  HDMI` al arrancar (20:04:05), al reanudar (21:21:16, 21:53:48) y tras el ciclo DPMS (21:54:26). Aparece en cada
  configuración de modo del HDMI, también en arranques sin incidencia: no distingue el fallo.
- Ningún error de amdgpu, ni de enlace, EDID o hotplug del HDMI.

**Log de Hyprland** (`hyprland-log-excerpt.txt`; el log vive en `/run` y no tiene marcas de tiempo, así que se
conservan los rangos de líneas y los recuentos):

| Rango | Momento | `atomic drm request: failed to commit: Invalid argument` |
|---|---|---|
| 1–1189 | arranque de la sesión (20:03) | 39 |
| 1190–84560 | de la sesión hasta el ciclo DPMS (incluye la QA multimonitor y las dos suspensiones) | 83 206 |
| 84561–84650 | ciclo DPMS: se desactivan ambas salidas, aquamarine desinicializa el renderizador secundario de `card1` (NVIDIA) y lo vuelve a crear | 2 |
| 84651–final (≈1 h después) | tras el ciclo | 0 |

Los fallos de commit (`ATOMIC_NONBLOCK PAGE_FLIP_EVENT`) existían antes de suspender, cuando el HDMI funcionaba y la
QA multimonitor pasaba (198/198), así que no bastan para explicar el congelado. El log no dice a qué salida pertenece
cada commit. Que desaparezcan después de recrear el renderizador secundario es una correlación, no una causa.

**Lo que no hizo Cortetsu:** el shell candidato y el instalado mostraron el mismo congelado; el QML no abre ni
configura salidas DRM; la recuperación vino de un ciclo DPMS del compositor, sin reiniciar el shell.

## 4. Hipótesis (ninguna demostrada)

| Hipótesis | A favor | En contra o sin medir |
|---|---|---|
| El error de semáforo de `nvidia-drm` deja una sincronización explícita (sync FD) colgada para la salida NVIDIA | aparece solo en las suspensiones de este arranque; la imagen se recupera al recrear el renderizador secundario | no se sabe si ocurrió también en las suspensiones anteriores sin congelado, porque allí no aparece; no hay traza de qué fence quedó pendiente |
| El renderizador secundario de aquamarine (copia iGPU → dGPU) queda en mal estado tras `s2idle` | DPMS off/on lo desinicializa y lo recrea, y eso basta para recuperar la imagen | sin traza de aquamarine con marcas de tiempo durante la reanudación |
| `s2idle` con `EnableS0ixPowerManagement=0` deja la dGPU sin una ruta de suspensión completa | es la combinación activa y la única `mem_sleep` disponible | no probado; cambiarlo está fuera de esta tarea |

## 5. Siguientes pasos (no ejecutados: requieren autorización)

1. Reproducir sin Cortetsu: `systemctl --user stop cortetsu-shell`, `s2idle` con el HDMI conectado, y anotar si el
   error de `nvidia-drm` y el congelado aparecen juntos. Varias repeticiones, incluida una suspensión corta.
2. Activar antes el log de Hyprland con marcas de tiempo para fechar los fallos de commit frente a `PM: suspend exit`.
3. Con root: `/sys/kernel/debug/dri/1/state` y `nvidia-bug-report.sh` antes y después de reanudar.
4. Buscar el mensaje exacto en los gestores de incidencias de NVIDIA (open-gpu-kernel-modules) y de aquamarine/Hyprland.
5. Solo como mitigación y si se decide: un ciclo DPMS tras reanudar. No resuelve la causa y no se añadió.

En esta tarea no se ejecutó ninguna suspensión ni se cambiaron drivers, kernel o configuración de energía.

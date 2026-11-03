# Cortetsu performance contract

Cortetsu optimiza experiencia percibida y trabajo real, no números aislados.

## Presupuestos

- shell idle: sin subprocesses recurrentes de alta frecuencia;
- módulos cerrados: sin polling periódico salvo servicios compartidos del upstream;
- apertura de overlay: objetivo < 120 ms hasta primer frame útil en hardware objetivo;
- hover/toggle: respuesta visual inmediata, animación breve;
- imágenes: carga asíncrona, tamaños de decodificación acotados y prefetch limitado;
- telemetría: una fuente compartida por métrica siempre que exista API nativa;
- QML: ningún `sh -c`; acciones externas explícitas y auditables;
- runtime: promoción y rollback atómicos.

## Política de timers

Un `Timer` repetitivo debe cumplir al menos una condición:

1. sólo corre mientras la superficie que consume el dato está visible;
2. representa tiempo real visible al usuario (por ejemplo Pomodoro activo);
3. no existe una señal/evento nativo equivalente.

Debounce y timers one-shot no se consideran polling.

## Prioridad de backends

1. señales/modelos nativos de Caelestia/Qt ya disponibles;
2. D-Bus/IPC/eventos del sistema;
3. helpers Cortetsu especializados;
4. polling únicamente como fallback medido.

Caelestia 2.4 ya ofrece servicios C++ para CPU, memoria, GPU, red, PipeWire y sensores. Cortetsu debe reutilizarlos antes de duplicar telemetría.

## Medición

Antes de una release mayor se registran:

- tiempo de arranque del shell;
- RSS estable tras idle;
- CPU idle;
- latencia de apertura/cierre de Bottom Hub y overlays;
- número de procesos externos lanzados durante 60 s de idle;
- errores/warnings QML;
- 40 ciclos consecutivos de apertura/cierre para superficies críticas.

Una optimización no se acepta si reduce un benchmark pero empeora interacción, estabilidad o mantenibilidad.

## Residentes medidos (ciclo 2, fase 2)

Medición: cgroup `CPUUsageNSec` en unidades transitorias de 60 s con HOME
aislado, mismo `/proc` y los mismos archivos de wallpaper y perfil que la sesión.

| Residente | Antes | Después | Qué cambió |
|---|---|---|---|
| `cortetsu-wallpaper-color-daemon` | 1028 ms/min, ~7 procesos cada 2 s | 218 ms/min, 0 procesos en reposo | Python en un solo proceso: lee `/proc` y hace `stat` sin lanzar `pgrep`/`jq`/`sha256sum`. Mismo hash que la versión bash, así que actualizar no recolorea. RSS 3,7 → 8 MB. |
| `cortetsu-power-auto` | 1249 ms/min, 15 `powerprofilesctl` por minuto | 150 ms/min, 1 llamada | Sólo pregunta a power-profiles-daemon cuando cambia el perfil que pide la regla, o hasta verificarlo. Un perfil elegido a mano, o puesto por otra herramienta o por power-profiles-daemon al reiniciarse, se respeta hasta la siguiente transición AC/batería o cambio de configuración; antes se revertía cada 4 s. `power-auto-control status` lee el perfil vivo. |

Ambos siguen sondeando (2 s y `poll_seconds`): arrancar o parar Wallpaper
Engine no emite eventos sin una dependencia nueva, y leer
`/sys/class/power_supply` en proceso cuesta menos que mantener un monitor
D-Bus residente. El sondeo también recupera lo que un evento perdido no traería
tras reanudar.

El shell en reposo no lanza procesos durante 30 s de muestreo del cgroup
`cortetsu-shell.service`; sus timers ya dependen de visibilidad.

### Tests anidados y la dGPU

Un Hyprland anidado despertaba la NVIDIA por dos vías: glvnd/Vulkan cargando el
vendor NVIDIA, y el propio Hyprland ejecutando `lspci -vnn` al arrancar para su
log. `scripts/integration/nested_gpu.py` fuerza Mesa y antepone un `lspci` vacío
sólo para el compositor. Muestreando `power/runtime_status` cada 250 ms, el test
de inactividad pasó de ~52 % de muestras activas a 0, y los cinco tests anidados
quedan en 0.

## Revisión 2.1 (2026-11-02)

Sesión real, eDP-1 1920×1080 a 144 Hz en la Radeon, HDMI desconectado,
superficies cerradas. CPU: `usage_usec` del cgroup `cortetsu-shell.service`
durante 60 s; procesos nuevos: muestreo de `cgroup.procs` cada 0,2 s; PSS de
`/proc/<pid>/smaps_rollup`.

| | 2.0 (b285b97) | 2.1 |
|---|---|---|
| PSS de `qs` | 270 MiB | 232 MiB, poco después de `shell reload` |
| Hilos / procesos del servicio | 43 / 9 | 43 / 9 |
| CPU en reposo | 281 ms/min (Bottom Hub oculto) | 381 ms/min (Bottom Hub visible) |
| Procesos lanzados en 60 s | 0 | 0 |

2.1 no añade temporizadores, procesos ni capas; las diferencias se deben al
estado del Bottom Hub y a la recarga, no a los cambios. Los temporizadores
siempre activos siguen siendo de baja frecuencia y sin evento nativo
equivalente: LED de Bloq Mayús/Num (sysfs, 1 s, solo con avisos de teclado
activados), uptime (15 s) y clima (1 h). La latencia hasta el primer
fotograma no se midió: el IPC del realm añade ~100 ms por llamada y medirla
exigiría instrumentar el shell.

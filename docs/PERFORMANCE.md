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

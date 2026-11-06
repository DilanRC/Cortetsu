# Cortetsu 2.2: despliegue y validación en sesión real

Fecha: 2026-11-06. Validación en la sesión Wayland ya iniciada después del
reinicio del portátil. Esto registra el despliegue autorizado y la evidencia
observada; no certifica hardware que no estuvo conectado ni pruebas de energía
que no se ejecutaron.

## Instalación y generación activa

El checkout personal estaba en `fe158a7` y conservaba cambios locales en
`.codebase-memory/artifact.json` y `graph.db.zst`. Se utilizó un clon limpio
de Cortetsu, en `main`, para el commit certificado por CI
`a46dd497665b7709bd25e1b402cebcc969afa50c`.
No se ejecutó Codebase Memory sobre el checkout personal, ni se copiaron o
escribieron sus artefactos.

La instalación mediante `scripts/cortetsu install`, verificación, promoción
schema 2 y recarga suave terminaron correctamente. La generación activa es:

- Shell: `/home/dilan/.local/share/cortetsu/builds/20261106-080519-11371`.
- Sistema: `/home/dilan/.local/share/cortetsu/system/builds/20261106-140527-11717-519893164`.
- Dotfiles: `/home/dilan/.local/share/cortetsu/dotfiles/builds/20261106-140527-11700-474370081-a46dd497`.
- Helpers: `/home/dilan/.local/share/cortetsu/helpers/builds/helpers-18e579c8067efa97-11618`.
- `current_revision`: `a46dd497665b7709bd25e1b402cebcc969afa50c`.
- Generación anterior retenida: revisión `720538224f298ea2c5fce589d9237c652734f98d`.

`cortetsu verify` pasó para la generación activa, la anterior, los temas,
dotfiles y la generación de sistema. El proceso Quickshell permaneció en PID
3363 tras la recarga. No se reinició Hyprland ni el equipo. Después de instalar,
`hyprctl reload` aplicó el bind nuevo y mantuvo el PID del compositor.

Versiones activas: Hyprland 0.57.1 (`acc1aa0`), Quickshell 0.3.2
(`4f508be`), kernel `7.3.1-1-cachyos` y NVIDIA open 615.78.08. La única salida
conectada fue eDP-1, 1920×1080 a 144 Hz, escala 1. La NVIDIA estaba
`suspended` en reposo. No se actualizó el sistema en esta tarea.

Las preferencias, atajos y configuración energética conservaron sus hashes
previos. `power-auto` no se reinició y siguió en `balanced` con alimentación
AC. `wallpaper-color` se reinició como parte de la instalación. Pomodoro
permaneció en `IDLE`; el propietario de notificaciones D-Bus siguió siendo
Quickshell. Mako permaneció en su estado previo inactivo y enmascarado.

## Superficies y teclado

Se abrieron y cerraron en la sesión instalada: launcher, Dashboard, calendario,
overview, Hardware Center, Display, Keyboards, Wallpaper Manager, Clipboard,
sesión, utilidades, sidebar, ajustes, OSD y popouts de audio, red, Bluetooth,
batería y distribución del teclado. `shell inspect` terminó con estados,
overlays, transiciones y conflictos vacíos. El launcher abrió con contenido y
foco de búsqueda. Las capturas de inspección se conservaron localmente en
`/tmp/cortetsu-22-launcher.png` y `/tmp/cortetsu-22-dashboard.png`; no están en
Git y esas rutas no son portables.

El cursor inicialmente estaba dentro de la zona inferior que activa la vista
previa del launcher. Al moverlo al centro de eDP-1, el cierre explícito pasó;
no se consideró eso un defecto del launcher.

La tecla física Copilot sí activó el OSD. La prueba controlada observó el OSD
abierto por IPC. Escape no lo cerró durante la observación de 12 segundos y el
OSD no tomó el foco; en una consulta posterior el estado ya era cerrado. Por
tanto, la activación física está comprobada y el cierre por Escape no. El OSD
es una superposición no enfocada con temporizador de ocultación; no se afirma
que Escape lo cierre ni que se haya medido el tiempo de ocultación. La primera
prueba de Escape coincidió con el cierre de una pregunta de chat y no cuenta
como evidencia para el OSD.

El bind `SUPER+SHIFT+code:201` aparece en Hyprland. No se conectó teclado
externo, así que F23 independiente no se probó físicamente. No se abrió un
juego fullscreen; GameMode real con juego queda sin certificar.

## Servicios, logs y límites físicos

El shell siguió en el mismo PID y `cortetsu verify` siguió pasando. No se
observaron errores QML nuevos atribuibles a la recarga; el journal mostró
avisos conocidos de Qt `textinput-v3`. Los overlays quedaron cerrados al final.
No se reinició `power-auto`.

HDMI-A-1 estaba desconectado. No se probaron monitor externo, hotplug ni ruta
NVIDIA con pantalla. No se ejecutó suspensión o reanudación. La certificación
física en esas rutas permanece pendiente. No se simuló hardware ni se despertó
la GPU con `nvidia-smi`.

## Rendimiento observado

Condiciones: eDP-1 1920×1080 a 144 Hz, escala 1, AC, perfil `balanced`, HDMI
desconectado, NVIDIA suspendida, Quickshell PID 3363. CPU se expresa como
porcentaje de un núcleo durante muestras de 60 s; no como porcentaje de los 12
hilos del equipo.

| Estado | Muestras | CPU de cgroup | PSS Quickshell | Tareas |
|---|---:|---:|---:|---:|
| Reposo, superficies cerradas | 3 × 60 s | 0.33%, 0.34%, 0.34% | 464→463, 463→462, 462→462 MiB | 78 estables |
| Dashboard abierto y estable | 2 × 60 s | 0.20%, 0.20% | 453→450, 450→449 MiB | 85 estables |
| Hardware Center abierto | 3 × 60 s | 4.73%, 4.79%, 4.71% | 454→450, 450→449, 449→447 MiB | 85→85, 85→85, 85→87 |
| 60 s después de cerrar Hardware Center | 1 × 60 s | 0.18% | 436→436 MiB | vuelve a 78 |

El muestreo de diez segundos con Hardware Center visible atribuyó 1.70% de un
número de CPU a Quickshell y 0.00% a cada helper muestreado. La lectura es
compatible con el sondeo visible de telemetría de 1500 ms; al cerrar la
superficie, CPU y tareas regresaron al nivel de reposo. PSS bajó desde los
valores iniciales y quedó en 436 MiB en la única muestra posterior, que no es
pareada con las tres muestras iniciales. No se cambió el sondeo: estas
mediciones no muestran crecimiento de memoria ni justifican reducir la
frecuencia de telemetría visible.

El informe 2.1 registra 232 MiB de PSS para `qs`, 43 hilos y 9 procesos, bajo
condiciones y un runtime distintos. Esta sesión midió aproximadamente 435–436
MiB de PSS y 49 hilos. La diferencia de PSS es grande y queda como seguimiento
para una medición pareada del mismo runtime, superficies, herramientas y
sesión; no se atribuye como regresión de 2.2. Las mediciones actuales tampoco
son comparación antes/después: no hubo línea base del runtime anterior en la
misma sesión. No se reclama una mejora de rendimiento.

Los valores de la tabla son transcripciones de las muestras observadas en la
sesión; no se guardaron registros crudos de cada intervalo. Las capturas y las
rutas de generación nombradas en este informe son evidencia local de esta
máquina y no forman parte del repositorio.

## Gate de pruebas

Después de documentar, `./scripts/cortetsu test` pasó los tests anteriores a
Prompter, pero el test de arranque repetido del binario instalado
`/usr/bin/pinentry-gnome3` falló en la ronda 159 con salida 139 (SIGSEGV). Es
la carrera conocida de pinentry 1.3.3 descrita en
[`DEVELOPMENT_2_2.md`](DEVELOPMENT_2_2.md#comparación-y-medidas). El binario
aislado corregido usado en la validación previa ya no estaba en `/tmp` y no se
reconstruyó: `pkg-config` no encontró `libgpg-error` y no se instalaron
paquetes. Esta ejecución local queda FAIL en el pinentry del anfitrión; no se
atribuye al cambio documental ni se presenta como suite completamente verde.
La compilación e instalación de `a46dd49` pasaron antes de este cambio.

## Rollback y estado de cierre

La generación previa permanece disponible. Si hiciera falta volver atrás,
usar el rollback soportado por Cortetsu (`cortetsu rollback`) y después
comprobar `cortetsu verify`, `cortetsu generations` y `cortetsu shell status`.
No se ejecutó rollback porque la generación activa está íntegra.

Estado: `DONE_WITH_CONCERNS`. Despliegue y verificaciones de software: PASS.
Límites pendientes: HDMI físico, suspensión/reanudación, F23 independiente,
GameMode con juego fullscreen y comparación pareada del PSS. Copilot abre el
OSD; Escape no lo cerró durante la observación y la ocultación automática no
tiene una medición de latencia reproducible en esta pasada.

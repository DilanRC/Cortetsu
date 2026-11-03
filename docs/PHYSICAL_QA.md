# QA física en el portátil

Lo que un realm no puede validar: hardware, PAM real, dos monitores físicos,
la ruta NVIDIA y el ciclo de energía. Cada prueba indica su estado, cómo
ejecutarla, cuándo es PASS o FAIL y cómo volver atrás. Los comandos son de
fish. Ninguna se automatiza contra la sesión real.

Equipo de referencia: eDP-1 (BOE, 1920×1080 @ 144 Hz) en la Radeon integrada
(`0000:06:00.0`, amdgpu) y HDMI-A-1 (1920×1080 @ 60 Hz) en la RTX 3050 Laptop
(`0000:01:00.0`, nvidia, `card1`). Hyprland 0.56.2 en las pasadas del
2026-11-02; 0.57.0 desde la revisión 2.1. Driver NVIDIA open 615.78.08.

## Estado (2026-11-02)

Dos pasadas en la sesión real. La de tarde, con la generación
`20261102-120925` (commit 24b87d1), tras `cortetsu install`,
`cortetsu shell reload` (mismo PID 3249) y `hyprctl reload`. La de noche, sobre
esa misma generación, cerró los pendientes; las correcciones de abajo se
instalaron después. Las superficies se abren y cierran por IPC: inyectar Escape
con `wtype` llega a la terminal enfocada. Las teclas del launcher y las
contraseñas las escribió Dilan.

| # | Escenario | Estado | Evidencia |
|---|---|---|---|
| 1 | Polkit: diálogo, monitor, foco, cancelación | PASS | tarde: Escape en HDMI-A-1 y eDP-1, `pkexec` sale con 126 y no queda capa. Noche: el diálogo aparece en el monitor del cursor (capa `cortetsu-polkit` en eDP-1 y en HDMI-A-1) |
| 1b | Polkit: contraseña correcta | PASS | cuatro `pkexec true` con la contraseña escrita por Dilan, dos en cada monitor: salida 0, sin capa residual, `faillock` vacío |
| 1c | Polkit: cancelar no cuenta para faillock | PASS con el override | ver hallazgo 1. Cancelación real en la cuenta principal (fin de `pkexec` con la petición abierta): `conversation failed` → `pam_authenticate failed` en el journal y `faillock` sigue vacío. Escape a mano no se repitió: recorre la misma ruta PAM |
| 1d | Polkit: contraseña errónea y reintento | NOT_TESTED en vivo | a propósito: no se arriesga la cuenta. Cubierto en la pila PAM aislada (`test-polkit-cancel-faillock.py`) y en `tst_PolkitDialog.qml` |
| 2 | Overlays en dos monitores | PASS | HDMI-A-1: Dashboard, Calendario, sesión, launcher, Ajustes rápidos y popouts de red, audio y batería abren en ese monitor y cierran. eDP-1 con un navegador en fullscreen 2: launcher, sesión y Dashboard no abren (`fullscreenGuard`, previsto); Calendario sí |
| 2b | Teclado en el launcher | PASS (informe de Dilan) | SUPER en eDP-1 y en HDMI-A-1: búsqueda con foco al abrir (captura con el cursor en el campo), escritura, flechas, Enter abre la app, Escape cierra y el foco vuelve a la ventana anterior, siempre en el monitor enfocado. El registro por IPC muestra ráfagas de abrir y cerrar cada ~0,45 s, compatibles con toques repetidos de SUPER; no se observó parpadeo |
| 3 | HDMI en la ruta NVIDIA | PASS | las superficies se dibujan en HDMI-A-1 (`card1`, nvidia) con transparencia |
| 4 | GameMode | PASS | dos ciclos enable/disable: activo cambia animaciones, blur, sombras, huecos, rounding y tearing como la tabla de [GAME_MODE.md](GAME_MODE.md); al desactivar, `diff` vacío y estado `INACTIVE` |
| 5 | NVIDIA en reposo sin HDMI | PASS con 7.3.1-1-cachyos | con 7.3.0-5 fallaba (`Runtime D3 status: Not supported`, 0 ms suspendida). Con 7.3.1-1: `Enabled (fine-grained)`, `Video Memory: Off`, 12/12 muestras `suspended`, 192502 ms suspendida en la medición. Ver hallazgo 3 |
| 6 | Suspensión y reanudación | PASS con reserva en 7.3.0-5; NOT_TESTED_ON_7.3.1 | ver hallazgo 2. Con la corrección, la suspensión de Dilan (21:55) recupera HDMI enseguida; una suspensión encadenada con capturas en bucle (21:56) bloqueó la sesión. Sin suspensión con el kernel nuevo todavía |

### Hallazgo 1: cancelar polkit contaba para faillock

**Síntoma.** Cada Escape en el diálogo dejaba un fallo `polkit-1` en
`faillock --user $USER`. Tres cancelaciones bloqueaban la cuenta diez minutos.

**Causa.** No está en Cortetsu. El diálogo llama a
`cancelAuthenticationRequest()` y nunca envía una respuesta
(`tst_PolkitDialog.qml` lo comprueba con Escape, con «Cancelar» y durante la
verificación). polkit 128 cierra entonces el socket de
`polkit-agent-helper-1`; su conversación PAM falla y `pam_unix` (PAM 1.7.3)
devuelve `PAM_AUTHTOK_ERR` sin haber leído contraseña. El `system-auth` de
CachyOS pone `pam_unix` bajo `[success=1 default=bad]`, así que cualquier
resultado distinto de éxito, incluido ese, pasa por `pam_faillock authfail`.
polkit-gnome usa la misma API y acabaría igual.

**Reproducción aislada.** `scripts/features/test-polkit-cancel-faillock.py`
compila `pam-cancel-probe.c` y ejecuta `pam_authenticate()` con
`pam_start_confdir()` sobre copias de la pila y `pam_faillock dir=<tmp>`: no lee
contraseñas ni toca `/run/faillock`. Con la pila de CachyOS, una cancelación
suma un fallo. Con el override, tres cancelaciones dejan el contador en 0,
tres contraseñas erróneas siguen bloqueando y la cuenta bloqueada rechaza
incluso la correcta. `--live` informa sobre la pila instalada.

**Corrección.** `cortetsu/system/pam/polkit-1`, instalado a mano en
`/etc/pam.d/polkit-1` (prevalece sobre `/usr/lib/pam.d/polkit-1`). Copia la
sección `auth` de `system-auth` y solo cambia el control de `pam_unix` a
`[success=1 authtok_err=die conv_err=die default=bad]`: un fallo de
conversación termina la transacción sin pasar por `authfail`. `deny`,
`unlock_time` y el resto de la pila no cambian. Si CachyOS modifica
`system-auth`, `--live` avisa de la divergencia.

```fish
sudo install -m 0644 cortetsu/system/pam/polkit-1 /etc/pam.d/polkit-1
python3 scripts/features/test-polkit-cancel-faillock.py --live
```

Rollback: `sudo rm /etc/pam.d/polkit-1` (vuelve la pila del paquete).
Instalado en el portátil el 2026-11-02 a las 21:06.

### Hallazgo 2: HDMI tardaba 30 s en volver tras s2idle

**Síntoma.** Tras despertar, eDP-1 y el shell responden enseguida; HDMI-A-1
(NVIDIA) no entrega imagen ni responde a `grim` durante ~30 s y después se
recupera solo.

**Secuencia (12:45, sin corrección).** `PM: suspend exit` a las 12:46:24.41;
nvidia-modeset lee el EDID a las 24.32. Durante 27 s la NVIDIA no emite ningún
evento DRM y Hyprland no registra errores: el primer flip de HDMI-A-1 queda
pendiente. A las 12:46:51–53 el monitor baja y sube el hot-plug
(`HDMI-A-1 disconnected`), el kernel registra
`nvidia-drm: Flip event timeout on head 0` (12:46:54.35, 30,0 s tras
despertar), se relee el EDID y Hyprland vuelve a hacer el modeset (salida
nueva a las 54.79). Un ciclo de hot-plug sin suspensión (18:31:48) recupera la
imagen en 0,5 s y sin timeout: el enlace solo vuelve con un modeset nuevo.

**Capa responsable.** Driver NVIDIA 615.78.08 (kernel 7.3.0-5-cachyos,
`PreserveVideoMemoryAllocations=1`, `EnableS0ixPowerManagement=0`) con este
monitor. Ni Cortetsu ni `power-auto` intervienen: el shell renderiza en la
Radeon (`renderD129`) y conserva su PID.

**Medida manual (21:14).** Sin intervenir, HDMI siguió sin fotogramas 11,6 s
tras despertar; un ciclo DPMS solo en HDMI-A-1, lanzado a mano, los devolvió
3,0 s después.

**Corrección.** Al despertar, `IdleMonitors.qml` lista las salidas NVIDIA
conectadas con `cortetsu-nvibrant status` (solo lee sysfs) y, 2 s después de
despertar, las apaga y enciende por DPMS, cada una por su nombre. eDP-1 y las
salidas de otras GPU no se tocan.

**Resultado con la corrección (21:55, suspensión de Dilan desde SUPER+X).**
`PM: suspend exit` 21:55:25.30; el ciclo corre y no aparece
`Flip event timeout` ni otro error del driver. Dilan confirma que HDMI volvió
enseguida, frente a ~30 s sin la corrección.

**Incidente (21:56, suspensión lanzada por el agente).** 54 s después de la
anterior y con `grim -o HDMI-A-1` en bucle cada 0,3 s para medir. El driver ya
despertó mal (`nvidia-drm: Failed to register auto-value-update`, antes del
ciclo) y después registró `Lost display notification` (+4,4 s). HDMI no volvió,
Hyprland dejó de responder y hubo que reiniciar. La corrección se revirtió y se
restauró tras comprobar la suspensión de las 21:55. No está demostrado qué
provocó el cuelgue; para medir, no captures en bucle una salida NVIDIA colgada
ni encadenes suspensiones.

**Estado.** Corregido en uso normal, con una reserva: la reanudación del
driver NVIDIA 615.78.08 en s2idle sigue siendo frágil. Si HDMI se cuelga,
reinicia; desconectar el cable no lo recuperó.

**Alternativas no aplicadas.** `NVreg_EnableS0ixPowerManagement=1` (el driver
informa de soporte S0ix y estado desactivado) cambia la gestión de energía de
la dGPU en s2idle; requiere medir consumo y estabilidad antes de proponerlo.
Desconectar HDMI antes de suspender evita el problema.

### Hallazgo 3: RTD3 volvió con el kernel 7.3.1-1-cachyos (cerrado)

**Antes (kernel `7.3.0-5-cachyos`, 2026-11-02).**
`/proc/driver/nvidia/gpus/0000:01:00.0/power` informaba
`Runtime D3 status: Not supported`, con `DynamicPowerManagement=2`, el puerto
PCIe `0000:00:01.1` con `power_resources_D3hot` y `d3cold_allowed=1`. Con el
cable fuera durante 2 min 20 s, `runtime_suspended_time` siguió en 0.

**Después (kernel `7.3.1-1-cachyos`, instalado el 2026-11-02 a las 22:43,
mismo driver 615.78.08).** `Runtime D3 status: Enabled (fine-grained)` y
`Video Memory: Off`. Con HDMI desconectado, 12 de 12 muestras de
`power/runtime_status` dieron `suspended` y `runtime_suspended_time` acumuló
192502 ms en esa medición. La revisión 2.1 lo volvió a leer el 2026-11-03 con
el escritorio en reposo: `suspended`.

**Causa.** Lo observado en este portátil es solo el antes y el después del
cambio de kernel; Cortetsu, el driver y la configuración no cambiaron entre
las dos medidas. La explicación viene de reportes externos, no de una prueba
propia: atribuyen la pérdida de RTD3 a la regresión de `nullfs` de la serie
7.3.0 y señalan que CachyOS incorporó el parche en 7.3.1-1. Aquí no se
reprodujo esa regresión aislada ni se comprobó el parche. Si RTD3 vuelve a fallar tras otra
actualización, empieza por `uname -r` y la línea `Runtime D3 status`.

## 1. Polkit real

Riesgo: cada contraseña errónea cuenta para `pam_faillock` (`deny=3`,
`unlock_time=600`). Usa **una sola** contraseña errónea por intento. Sin el
override del hallazgo 1, cada cancelación también cuenta.

```fish
faillock --user $USER                     # debe estar vacío antes de empezar
pkexec true; echo "salida $status"
```

1. Aparece el diálogo de Cortetsu sobre el monitor enfocado, con el campo con
   foco y el material Ink del tema actual (claro y oscuro).
2. Escribe una contraseña errónea y Enter: el diálogo marca el error en
   bermellón, vacía el campo y vuelve a darle foco. Sin cerrar.
3. Escribe la contraseña correcta: `salida 0`.
4. Repite con Escape o «Cancelar»: `salida 126` y el foco vuelve a la ventana
   anterior.

PASS: los cuatro pasos como se describen, sin teclas perdidas ni el diálogo
detrás de otra capa. FAIL: cualquier otro resultado; guarda
`journalctl --user -b -t quickshell --since -5min`.
Rollback: `faillock --user $USER --reset` si acumulaste fallos.

## 2. Overlays y foco en dos monitores

```fish
hyprctl layers -j | jq -r 'to_entries[] | .key as $m | .value.levels[][] | "\($m) \(.namespace)"' | sort
```

Con el cursor en cada monitor por turno: `SUPER+K` (Dashboard), el launcher,
`SUPER+X` (sesión), Ajustes rápidos y los popouts de red, audio y batería.

PASS: cada superficie aparece en el monitor del cursor, recibe el teclado
(escribe en el launcher), se cierra con Escape y el foco vuelve a la ventana
de antes. FAIL: aparece en el otro monitor, no recibe teclas o el foco queda
en ninguna parte. Rollback: no cambia nada persistente.

## 3. HDMI en la ruta NVIDIA

```fish
cat /sys/class/drm/card1-HDMI-A-1/status
cat /sys/bus/pci/devices/0000:01:00.0/power/runtime_status
hyprctl monitors -j | jq -c '.[] | {name, refreshRate, scale}'
```

Repite la lista del punto 2 en HDMI-A-1 y mueve una superficie abierta entre
monitores (cambia el foco con el cursor).

PASS: transparencia, desenfoque y animaciones iguales en ambas salidas, sin
parpadeo ni fotogramas negros. FAIL: artefactos solo en HDMI; anota
`hyprctl monitors -j` y una captura de cada salida con `grim -o HDMI-A-1`.
Rollback: no cambia nada persistente.

## 4. GameMode y fullscreen

El procedimiento completo, con el `diff` de opciones de Hyprland antes y
después, está en [GAME_MODE.md](GAME_MODE.md#prueba-física-pendiente-pending_physical).
Ejecútalo con un juego en fullscreen, por ejemplo Core Keeper:

- en fullscreen, la capa `cortetsu-drawers` desaparece de ese monitor
  (`hyprctl layers -j`) y vuelve al salir;
- una notificación durante el juego no roba el foco;
- `cortetsu shell ipc gameMode status` termina en `INACTIVE` y el `diff` está
  vacío.

Rollback: `cortetsu shell ipc gameMode disable`.

## 5. Consumo y activación de la GPU

Sin HDMI conectado, la NVIDIA debe dormir con el escritorio en reposo; mirar
sysfs no la despierta (`nvidia-smi` sí, no lo uses aquí).

```fish
for i in (seq 12); cat /sys/bus/pci/devices/0000:01:00.0/power/runtime_status; sleep 5; end
```

1. Con HDMI desconectado y sin juegos abiertos: abre y cierra Dashboard,
   launcher y Hardware Center (`SUPER+H`) durante el minuto de muestreo.
2. Repite con HDMI conectado.

PASS: (1) `suspended` en las 12 muestras; (2) `active`, esperable porque la
NVIDIA alimenta la salida. Comprueba primero que el driver informa
`Runtime D3 status: Enabled (fine-grained)`
(`cat /proc/driver/nvidia/gpus/0000:01:00.0/power`); con `Not supported`
(kernel 7.3.0-5) (1) no puede pasar. FAIL: `active` en (1); busca el proceso con
`lsof /dev/nvidia*` y anótalo. Rollback: no cambia nada persistente.

## 6. Suspensión y reanudación

Requiere tu autorización: suspende el equipo de verdad. Guarda tu trabajo.

```fish
cortetsu shell status
systemctl suspend                         # o SUPER+SHIFT+L
# tras despertar:
cortetsu shell status
journalctl --user -b -t quickshell --since -5min | grep -E 'WARN|ERROR'
hyprctl monitors -j | jq -c '.[] | {name, dpmsStatus}'
```

PASS: el Lock aparece al despertar en ambos monitores, desbloquea, el shell
sigue vivo (mismo PID) y HDMI-A-1 vuelve a mostrar imagen. FAIL: shell
reiniciado, Lock ausente o HDMI congelado (defecto conocido del driver, ver
hallazgo 2).
Rollback: si HDMI queda congelado, desconecta y reconecta el cable; si el shell
no responde, `cortetsu shell reload`.

# QA física en el portátil

Lo que un realm no puede validar: hardware, PAM real, dos monitores físicos,
la ruta NVIDIA y el ciclo de energía. Cada prueba indica su estado, cómo
ejecutarla, cuándo es PASS o FAIL y cómo volver atrás. Los comandos son de
fish. Ninguna se automatiza contra la sesión real.

Equipo de referencia: eDP-1 (BOE, 1920×1080 @ 144 Hz) en la Radeon integrada
(`0000:06:00.0`, amdgpu) y HDMI-A-1 (1920×1080 @ 60 Hz) en la RTX 3050 Laptop
(`0000:01:00.0`, nvidia, `card1`). Hyprland 0.56.2.

## Estado (2026-11-01)

| # | Escenario | Estado | Evidencia |
|---|---|---|---|
| 1 | Polkit real: contraseña errónea, reintento, cancelación, foco | NOT_TESTED tras el material Ink | prueba real previa del agente: [POLKIT.md](POLKIT.md#verificación) (2026-10-27) |
| 2 | Overlays y foco en los dos monitores | PARCIAL: presencia de capas observada; foco NOT_TESTED | ver abajo |
| 3 | HDMI en la ruta NVIDIA | PARCIAL: salida detectada y activa; superficies NOT_TESTED | ver abajo |
| 4 | GameMode y fullscreen (Warframe) | NOT_TESTED | procedimiento en [GAME_MODE.md](GAME_MODE.md#prueba-física-pendiente-pending_physical) |
| 5 | Consumo y activación de la GPU | NOT_TESTED | — |
| 6 | Suspensión y reanudación | NOT_TESTED: requiere autorización explícita | — |

Observado el 2026-11-01 sin interactuar con el shell (solo `hyprctl` de lectura
y sysfs):

- Los dos conectores están `connected`; HDMI-A-1 cuelga de `card1` (nvidia).
- `cortetsu-background` existe en ambos monitores. `cortetsu-drawers` existe en
  HDMI-A-1 y no en eDP-1, donde había un navegador en fullscreen 2: es el
  comportamiento previsto (`ContentWindow.visible` se apaga sobre fullscreen).
- La NVIDIA estaba en `runtime_status=active`, esperable con HDMI conectado.

## 1. Polkit real

Riesgo: cada contraseña errónea cuenta para `pam_faillock` (`deny=3`,
`unlock_time=600`). Usa **una sola** contraseña errónea por intento.

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
Ejecútalo con Warframe además de Core Keeper:

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
NVIDIA alimenta la salida. FAIL: `active` en (1); busca el proceso con
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
reiniciado, Lock ausente o HDMI congelado (antecedente conocido tras s2idle).
Rollback: si HDMI queda congelado, desconecta y reconecta el cable; si el shell
no responde, `cortetsu shell reload`.

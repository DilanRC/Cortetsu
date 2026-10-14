# Energía, suspensión e inactividad

Cortetsu es el único dueño de las acciones por inactividad. No corre hypridle ni
ninguna unit de inhibición permanente.

## Quién hace qué

| Pieza | Responsabilidad |
|---|---|
| `services/CortetsuSession.qml` | Pregunta a logind `CanSuspend`, `CanHibernate` y `CanSuspendThenHibernate` (al cargar, al abrir el menú de sesión, al reanudar y antes de actuar por batería crítica). `request(modo)` pide solo el modo nombrado y devuelve `false` si logind respondió que lo rechazaría; una respuesta desconocida no bloquea la petición. Emite `aboutToSleep`/`resumed` desde `PrepareForSleep`. |
| `modules/IdleMonitors.qml` | Las entradas de `idleTimeouts` (`lock`, `dpms`, `suspend` u otra acción) con `IdleMonitor` (ext-idle-notify, sin sondeo). Bloquea antes de dormir y retiene un inhibidor `delay` de logind mientras la sesión está desbloqueada. |
| `modules/CortetsuIdleInhibitor.qml` | Interruptor keep-awake. Desactivado al arrancar el shell. |
| `modules/session/Content.qml`, `launcher/services/Actions.qml` | Menú de sesión y acciones del launcher (`suspend`, `hibernate`, `suspendThenHibernate`). Un modo que logind no admite se muestra deshabilitado con el motivo. |
| `modules/BatteryMonitor.qml` | Batería crítica: avisa, reconsulta logind y a los 5 s hiberna si se puede; si no, suspende. La segunda notificación dice cuál de las dos ocurrió. |

## Keep-awake

Pausa las acciones de inactividad de Cortetsu (bloqueo, pantalla y suspensión).
No es un inhibidor de logind, así que una suspensión pedida por el usuario sigue
funcionando. Tampoco frena un `IdleAction=` de `logind.conf` (por defecto
`ignore`). Hyprland ignora los inhibidores de inactividad de superficies
layer-shell; por eso la versión anterior, un `IdleInhibitor` sobre un
`PanelWindow` invisible, no impedía nada.

- Barra inferior (StatusPill «Activo»), Utilidades, OSD y Ajustes › Energía.
- `SUPER + ALT + K` (`kbKeepAwake` en `variables.lua`).
- IPC: `qs ipc call keepAwake toggle|enable|disable|isEnabled`.

Las aplicaciones que inhiben la inactividad desde una ventana normal (vídeo,
reuniones) se respetan porque los monitores usan `respectInhibitors: true`.

## Política de inactividad (Ajustes › Energía › Reposo)

| Ajuste | Preferencia | Por defecto |
|---|---|---|
| Bloquear tras inactividad | entrada `idleAction: "lock"` de `idleTimeouts` | 15 min |
| Apagar la pantalla | entrada `idleAction: "dpms"` | ninguna (nunca) |
| Suspender | entrada `idleAction: "suspend"` | ninguna (nunca) |
| Suspender solo con batería | `idleSuspendOnBatteryOnly` | sí |
| Evitar reposo en pantalla completa | `idleInhibitWhenFullscreen` | sí |
| Evitar reposo con audio / cargando | `idleInhibitWhenAudio` / `idleInhibitWhenCharging` | sí / no |

Audio, carga y pantalla completa (en el monitor enfocado) retienen el apagado de
pantalla y la suspensión, nunca el bloqueo: dejar música sonando no deja la
sesión abierta. Solo keep-awake pausa el bloqueo.

La suspensión por inactividad nunca ocurre con una salida que no sea un panel
interno (`eDP`, `LVDS`, `DSI`), así que un escritorio o una salida virtual no
se suspenden solos. La tapa la gestiona logind (`HandleLidSwitch`), no Cortetsu.

`IdleMonitor.timeout` está en segundos. `idleTimeouts` guarda milisegundos y
`IdleMonitors` los divide entre 1000. Antes se pasaban sin convertir: los
900000 ms del bloqueo eran 900000 s (10 días) y el bloqueo automático nunca
ocurría.

## Este equipo

Solo hay zram como swap y ninguna configuración `resume=`, así que logind
responde `na` a hibernar y a suspend-then-hibernate. `SUPER + SHIFT + L`
suspende a RAM. Cuatro dedos hacia abajo abren el menú de sesión en lugar de
suspender, para que un gesto accidental, también jugando, no duerma el equipo.

## Migración y reversión

`install-cortetsu.sh` desactiva `cortetsu-keep-awake.service` y la renombra a
`cortetsu-keep-awake.service.retired` en `~/.config/systemd/user/`. Para
volver al comportamiento anterior:

```sh
mv ~/.config/systemd/user/cortetsu-keep-awake.service.retired ~/.config/systemd/user/cortetsu-keep-awake.service
systemctl --user daemon-reload
systemctl --user enable --now cortetsu-keep-awake.service
```

Apagar la pantalla y suspender no existen hasta que se eligen en Ajustes.
Borrar esas entradas de `idleTimeouts` en `~/.config/cortetsu/preferences.json`
las desactiva. La conversión de milisegundos no tiene interruptor: es la
corrección del bloqueo.

# Calendar, Google Calendar y Focus/Pomodoro

Cortetsu integra calendario mensual de solo lectura, agenda diaria y Pomodoro persistente. OAuth y HTTP viven en `cortetsu/bin/cortetsu-calendar`; QML consume JSON estructurado y ejecuta acciones explícitas del helper.

## Google Calendar: solo lectura

Scopes:

```text
https://www.googleapis.com/auth/calendar.events.readonly
https://www.googleapis.com/auth/calendar.calendarlist.readonly
```

No existe ruta de escritura de eventos, calendarios, recordatorios ni invitaciones.

## OAuth

1. Habilitar Google Calendar API.
2. Crear credenciales OAuth **Desktop application**.
3. Guardar el JSON en `~/.config/cortetsu/calendar-client.json` con modo `0600`.
4. Abrir Calendar o ejecutar `cortetsu-calendar sync --force`.

El flujo usa PKCE, `state` aleatorio, callback sólo en `127.0.0.1` y timeout global de cinco minutos. El refresh token vive en Secret Service bajo `cortetsu-google-calendar`; nunca se escribe en cache, configuración o logs. La migración v2 mueve de forma silenciosa el secreto anterior sólo cuando es necesario y lo elimina después de confirmar la nueva entrada.

## Sincronización

Se solicita al abrir desde Bottom Hub, shortcut o IPC. Un cache menor de 15 minutos se reutiliza; el refresco manual fuerza consulta nueva. Se conservan 62 días anteriores y 370 futuros, paginación, recurrencias expandidas, zona horaria IANA y eventos de varios días.

```text
$XDG_CONFIG_HOME/cortetsu/calendar-selection.json
$XDG_CACHE_HOME/cortetsu/calendar-events.json
```

## Arquitectura en el shell

| Pieza | Responsabilidad |
|---|---|
| `modules/calendar/CalendarService.qml` (singleton) | caché de eventos, selección de calendarios y el único proceso de sincronización; pide una sincronización cuando el Calendario se abre en cualquier pantalla |
| `modules/calendar/CalendarModel.js` | reglas de fecha puras: rejilla del mes (lunes primero), eventos por día en una pasada, fin exclusivo de los eventos de día completo |
| `modules/calendar/Content.qml`, `PomodoroCard.qml` | presentación; `SystemClock` por minutos solo con el panel abierto para que «hoy» cambie a medianoche |
| `modules/pomodoro/Pomodoro.qml` (singleton) | estado leído del archivo del helper, órdenes, el daemon y el aviso de fin de fase |
| `modules/pomodoro/PomodoroModel.js` | lo que se muestra: tiempo restante, progreso, botón principal y si un aviso es nuevo |
| `modules/dashboard/Today.qml`, `Focus.qml` | tarjetas del Dashboard sobre los mismos servicios |

Hay una instancia de cada servicio por shell. Antes, cada vista (dos por pantalla, contando una copia oculta en
la ventana de cajones) tenía su propia caché, su proceso de sincronización y su copia de la máquina de estados de
Pomodoro, y releía los archivos con `text()` tras `fileChanged` sin `reload()`, así que no veía los cambios.

## Focus/Pomodoro

```text
$XDG_STATE_HOME/cortetsu/pomodoro.json                 estado (schema 2, sin cambios de formato)
$XDG_STATE_HOME/cortetsu/pomodoro-notification.json    último aviso de fin de fase
```

Ciclo predeterminado:

```text
25 min FOCUS -> 5 min BREAK
cada 4 sesiones -> 15 min LONG_BREAK
BREAK/LONG_BREAK -> FOCUS
```

Contrato de `cortetsu-pomodoro`:

- `status|start|pause|resume|skip|reset` imprimen el estado en JSON; solo escriben el archivo si cambia.
- El helper es el único que calcula transiciones. Una fase termina en un instante de reloj de pared
  (`targetEndTimestamp`, segundos UTC), así que el tiempo sobrevive a reinicios del shell y a la suspensión, y un
  cambio de zona horaria no lo mueve. La fase siguiente empieza cuando se detecta el final (tras suspender, al
  despertar).
- Si el reloj retrocede, a una fase nunca le queda más que su duración completa. Si avanza, la fase termina antes:
  con reloj de pared no hay forma de distinguirlo de una suspensión.
- Cada fin de fase pasa por `settle()`, con el lock del estado: quien lo detecta primero (daemon u orden) guarda la
  fase nueva y escribe un único aviso. Antes solo el daemon avisaba y una orden en el instante del final lo perdía.
- `reset` reinicia el ciclo y conserva `focusMinutes`, `shortBreakMinutes`, `longBreakMinutes` y
  `sessionsBeforeLongBreak` (antes los borraba).
- Un estado en fase activa sin `targetEndTimestamp` se recupera como `IDLE`.
- `daemon`: un solo daemon por usuario (lock). Duerme sobre `CLOCK_BOOTTIME` en tramos de hasta 30 s hacia el
  final de la fase y sin despertar en reposo; las órdenes lo despiertan con `SIGUSR1`. `CLOCK_BOOTTIME` cuenta el
  tiempo suspendido, así que una fase que vence en `s2idle` se cierra al reanudar (con el reloj monótono anterior
  tardaba lo que quedara del tramo, hasta 30 s). Al despertar, si `~/.local/bin/cortetsu-pomodoro` apunta a otra
  generación de helpers, se reejecuta en ella con el mismo PID; `cortetsu install` lo despierta con
  `cortetsu-pomodoro wake`. Antes
  leía el archivo cada 0,5 s para siempre (en una sesión real: 118 827 despertares y 58 s de CPU en 16,5 h).
- Escrituras atómicas con `fsync`, modo `0600`.

El shell muestra un aviso por cada fin de fase escrito después de arrancar; uno anterior no se repite al recargar.

## Pruebas

```bash
cortetsu-calendar disconnect
bash cortetsu/tests/test-calendar-readonly.sh
python3 cortetsu/tests/test-calendar-credentials.py
python3 cortetsu/tests/test-calendar-polish.py
python3 cortetsu/tests/test-pomodoro.py                          # helper y daemon, reloj simulado, estado privado
python3 cortetsu/tests/test-calendar-pomodoro-services.py        # servicios reales en Quickshell, HOME privado
QT_QPA_PLATFORM=offscreen qmltestrunner -input cortetsu/tests/qml/calendar
QT_QPA_PLATFORM=offscreen qmltestrunner -input cortetsu/tests/qml/pomodoro
```

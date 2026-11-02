# Servicios del sistema simulados

`agent-realm simulate` da a un realm UPower, power-profiles-daemon, NetworkManager, BlueZ y PipeWire simulados y deterministas, para probar shells como Cortetsu sin tocar el hardware ni los servicios del anfitrión.

## Arquitectura

```
realm (bwrap + scope systemd del realm)
├── dbus-daemon privado ── $XDG_RUNTIME_DIR/system_bus_socket  ← DBUS_SYSTEM_BUS_ADDRESS del realm
│   ├── org.freedesktop.UPower                (UPower, dispositivos battery_BAT0, line_power_AC, DisplayDevice)
│   ├── org.freedesktop.UPower.PowerProfiles  (+ net.hadess.PowerProfiles)
│   ├── org.freedesktop.NetworkManager        (Wi-Fi, Ethernet, puntos de acceso, conexiones, activación)
│   ├── org.bluez                             (ObjectManager, hci0, dispositivos, Battery1)
│   └── org.cortetsu.AgentRealms.Simulator    (control: Apply, Set, Event, State, Reset)
└── pipewire privado ── $XDG_RUNTIME_DIR/pipewire-0
    ├── sumideros y fuentes null (sim_speakers, sim_headphones, sim_mic)
    ├── metadata "default" (dispositivo predeterminado)
    └── pw-cat con silencio cuando hay reproducción
```

- Todo corre **dentro del realm**: mismo bwrap, mismo PID namespace y un scope systemd registrado como app del realm. `agent-realm stop` lo recoge con el resto.
- El anfitrión no se conecta a esos sockets, que los procesos del realm podrían sustituir. Para consultar o cambiar el estado lanza `simulation/ctl.py` dentro del sandbox y lee su salida JSON, limitada a 1 MiB y validada.
- El realm no ve `/run/dbus` ni `/dev/snd` del anfitrión. El PipeWire privado no carga monitor ALSA y crea solo nodos null. Nada puede llegar a los altavoces, al Wi-Fi, al Bluetooth ni al perfil de energía reales.
- Bajo demanda: sin `simulate` no existe el bus privado y los clientes del realm fallan al conectar, igual que antes.

### Cómo se conectan los clientes (verificado, no supuesto)

| Cliente | Bus o socket | Prueba |
| --- | --- | --- |
| Quickshell (Qt `QDBusConnection::systemBus`) | `DBUS_SYSTEM_BUS_ADDRESS` | Cortetsu mostró los valores simulados |
| `busctl --system` (sd-bus), usado por `ConnectivityBluetooth.qml` | `DBUS_SYSTEM_BUS_ADDRESS` | `busctl` dentro del realm lista solo los servicios simulados |
| Coordinador Go `observedbus` | `DBUS_SYSTEM_BUS_ADDRESS`, si no `/run/dbus/...` | código: `observer.go`, `socket()` |
| Helper Rust de credenciales Wi-Fi (zbus) | `Connection::system()` | no ejercido en estas pruebas |
| Quickshell PipeWire | `$XDG_RUNTIME_DIR/pipewire-0` (socket nativo, no D-Bus) | volumen, mute y dispositivo predeterminado simulados en la UI |

Las interfaces y miembros salen del código de Quickshell 0.3.2 (`src/services/upower`, `src/network/nm`, `src/bluetooth`, `src/services/pipewire`, commit `4f508be`) y del uso de Cortetsu (`busctl` y `Process` en QML). Solo se implementa lo que esos clientes usan, con los nombres, rutas y tipos D-Bus reales.

## CLI

```sh
agent-realm simulate --list                                   # escenarios disponibles
agent-realm simulate codex --scenario battery-low             # inicia la simulación o cambia de escenario
agent-realm simulate codex --status                           # estado, grafo de audio en vivo y errores
agent-realm simulate codex --set upower.battery.percentage=12 --set 'upower.battery.state="discharging"'
agent-realm simulate codex --set network.wifi.connected=null  # desconecta el Wi-Fi
agent-realm simulate codex --event wifi-scan                  # también bt-discover, pipewire-restart
agent-realm simulate codex --reset                            # vuelve al estado inicial del escenario
agent-realm simulate codex --stop                             # cierra servicios, bus y PipeWire
```

**Inicia la simulación antes que el shell.** Quickshell 0.3.2 resuelve UPower, PowerProfiles y BlueZ una sola vez al arrancar (ver «Hallazgos»).

`--set` acepta `ruta=valor` en JSON (o texto plano). Cada cambio valida el estado completo y lo aplica emitiendo las señales que emitiría el daemon real:

| Transición | Señales |
| --- | --- |
| batería 50 % → 12 % | `PropertiesChanged` en DisplayDevice y battery_BAT0 |
| cargador conectado o desconectado | `PropertiesChanged` (`Online`, `OnBattery`, `State`) |
| batería retirada | `DeviceRemoved` |
| Wi-Fi conectado → desconectado | `Device.StateChanged` 100→30, `Connection.Active.StateChanged`, `PropertiesChanged` |
| escaneo (`wifi-scan` o `RequestScan`) | `AccessPointAdded`, `LastScan` |
| conexión fallida (`fail_connect`) | `Device.StateChanged` → 120 (FAILED, razón 7) → 30 |
| Bluetooth apagado → encendido | `PropertiesChanged` (`Powered`, `PowerState`) |
| descubrimiento (`bt-discover` o `StartDiscovery`) | `InterfacesAdded` |
| audio normal → mute | `Props` del nodo PipeWire |
| Balanced → Performance | `PropertiesChanged` (`ActiveProfile`) |
| servicio caído o recuperado | el nombre se libera o se toma (`NameOwnerChanged`) |

También funcionan los cambios que hace el propio cliente: `Properties.Set` de `ActiveProfile`, `Powered` o `WirelessEnabled`; `ActivateConnection`, `AddAndActivateConnection`, `Disconnect`, `Pair` y `Connect`; y el dispositivo de audio predeterminado elegido en la UI (se refleja de `default.configured.audio.*` a `default.audio.*`, el papel de WirePlumber).

## Escenarios

Archivos `scenarios/<nombre>.json` con `schema: 1`. Su `state` es parcial: se fusiona sobre un estado base completo y el resultado debe coincidir exactamente con el esquema de `simulation/scenario.py`. Se rechazan claves desconocidas, tipos incorrectos, rangos fuera de límite e incoherencias (un perfil activo que no existe, un SSID conectado que no es visible, direcciones repetidas). Las descripciones de nodos de audio no admiten comillas, llaves, corchetes ni `=`, porque viajan dentro de SPA-JSON.

| Escenario | Estado |
| --- | --- |
| `battery-low` | batería 12 %, sin cargador, Power Saver, Wi-Fi conectado, Bluetooth apagado |
| `charging` | 96 % cargando, Balanced, Wi-Fi conectado, audio disponible |
| `gaming` | cargador conectado, Performance activo, red conectada, mando Bluetooth conectado (`input-gaming`, 64 %) |
| `services-failing` | NetworkManager y UPower fuera del bus, PipeWire reiniciándose (vuelve a los 3 s), BlueZ devolviendo `org.bluez.Error.*` |
| `desktop` | sin batería, Ethernet conectado, sin adaptador Bluetooth, audio disponible |

Los estados de la especificación sin escenario propio se obtienen con `--set`: sin adaptador de red (`network.wifi.present=false`), Wi-Fi deshabilitado (`network.wireless_enabled=false`), perfil indisponible (`power_profiles.profiles`), cambio rechazado (`power_profiles.reject_changes=true`), error de emparejamiento (`bluetooth.fail_operations=true`), sin dispositivos de audio (`audio.sinks=[]`) y reproducción (`audio.playback=true`).

## MCP

`services_status` (observe) y `services_simulate` (control: `apply`, `set`, `event`, `reset`, `stop`) actúan sobre el realm del perfil, como el resto de herramientas.

## Hallazgos sobre Quickshell 0.3.2 y Cortetsu

Los produjo el simulador y se confirmaron leyendo el código:

1. **PipeWire ausente al arrancar el shell = sin audio hasta reiniciarlo.** `PwConnection` solo vigila la reaparición del socket si la conexión inicial falla y existe `QS_PIPEWIRE_IMMEDIATE_RECONNECT=1`. Si PipeWire cae con la conexión ya establecida, sí reconecta. Verificado: sin la variable, Quick Settings queda en «Volumen 0 %» aunque PipeWire vuelva; con ella, se recupera solo. Cortetsu lo aplica desde `fa4a07d` en `cortetsu-shell.service`; matriz completa en `evidence/cortetsu-phase4/phase-a/`.
2. **UPower, PowerProfiles y BlueZ no se reconectan.** Si el servicio falta al arrancar, Quickshell no lo vuelve a buscar. Si desaparece después, conserva los últimos valores. NetworkManager se recupera si cae en vivo (`QDBusServiceWatcher`), pero si falta al arrancar el shell, Quickshell elige el backend de red al iniciar y se queda sin él. Con el valor cambiado durante la caída, BlueZ y UPower conservan el valor anterior (el marcador del caso «tras recuperar» pasa por casualidad).
3. **Hardware Center no usa los servicios D-Bus para energía y red.** Su sonda nativa lee `/sys/class/power_supply` y ejecuta `iw dev <iface> link` e `ip addr`. Dentro del realm muestra la **batería real** y el **SSID real del anfitrión**, porque `/sys` se monta en solo lectura y el realm comparte el namespace de red. El perfil de energía sí viene del simulador. La captura `evidence/cortetsu-simulation/gaming-hardware-center.png` está redactada.

## Límites

- **GPU**: fuera del simulador D-Bus. `scripts/realm-gpu-scenario.py REALM ESCENARIO` (`--list` muestra los ocho) escribe un árbol sysfs y `nvidia-smi`/`lspci` falsos en el HOME del realm e imprime `CORTETSU_SYSFS_ROOT` y `PATH` para `CORTETSU_REALM_ENV`. No toca `/sys` ni dispositivos del kernel; la sonda marca la lectura como `simulated` y el Hardware Center muestra «Datos simulados». Capturas: `evidence/cortetsu-phase4/gpu/`.
- **Batería y red de Hardware Center**: el mismo mecanismo (`CORTETSU_SYSFS_ROOT`) cubriría la batería. El SSID requiere aislar el namespace de red del realm, que hoy se comparte a propósito para dar red a las apps.
- **zbus (helper de credenciales Wi-Fi)**: implementa los métodos `Settings.Connection` que usa, pero no se ejerció con Cortetsu.
- **El canal de control está en el bus privado**: las apps del realm pueden cambiar su propio mundo simulado. No alcanza al anfitrión ni a otros realms.
- **WirePlumber** no se ejecuta. Su único papel necesario (predeterminado configurado → predeterminado) lo replica el simulador. Rutas de dispositivos, perfiles ALSA y Bluetooth audio no existen en este grafo.

## Pruebas

| Prueba | Cubre |
| --- | --- |
| `tests/test_simulation.py` (10) | esquema y escenarios exigidos, inyección en asignaciones, UPower, PowerProfiles, NM y BlueZ sobre un `dbus-daemon` real con cliente Gio, salida no confiable del realm, `/run` y `/dev/snd` fuera del sandbox |
| `scripts/acceptance-simulation.sh` | realm real: bus privado, aislamiento, señales de cada transición, stream simulado ausente del PipeWire del anfitrión, `services-failing` con recuperación, limpieza y huella del anfitrión idéntica antes y después |
| `scripts/acceptance-simulation-ui.sh` | Cortetsu real en Quickshell, con OCR de Quick Settings: `battery-low`, transiciones, UI→servicio (mosaico Bluetooth), fallo al arrancar, recuperación en vivo de PipeWire y NM |

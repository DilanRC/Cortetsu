# Cortetsu Connectivity 2.0

La fuente editable es `cortetsu/` en este repositorio. `cortetsu/base/` aporta los componentes heredados; `build-runtime.sh` los copia a una generación y superpone `modules/`, `components/`, `services/` y `utils/`. El compositor migra los paneles. Nunca se corrige una generación sin corregir el checkout.

```text
Antes: barra/BottomHub → CortetsuNetwork → Networking
       Settings → CortetsuSettingsNetwork → nmcli
       Nexus heredado → Nmcli → nmcli
Ahora: Networking → ConnectivityWifi ─┐
       BlueZ/Bluetooth → ConnectivityBluetooth ─┤→ Connectivity → todas las superficies
       nmcli adaptador UUID/metadatos ─┘
       VPN existente → Connectivity.vpn
```

`Connectivity.qml` es la fachada única. Sus objetos Wi-Fi y Bluetooth son singletons. Las fachadas CortetsuNetwork/CortetsuSettingsNetwork/Nmcli conservan nombres de importación y delegan; no mantienen otro backend. PipeWire sigue en el servicio de audio existente: esta migración no necesita duplicarlo para dispositivos Bluetooth.

## Wi-Fi

Networking conserva identidad y reactividad de dispositivos y grupos WifiNetwork. Un grupo lógico no equivale a un AP físico. La API instalada agrupa redes; la tabla complementaria de AP conserva SSID, BSSID, interfaz, frecuencia, seguridad, señal y actividad. Mostrar BSSID no implica permitir fijar ese BSSID al conectar.

Los perfiles NetworkManager se identifican por UUID. Nombre, SSID, interfaz vinculada, autoconnect e IPv4 son campos separados. La conexión activa se comprueba con el UUID leído del dispositivo cuando se activa un perfil explícito. Una conexión a otro perfil no confirma la operación solicitada. Direcciones/gateway/DNS del inspector se muestran solo para el grupo conectado.

`ConnectivityNmAdapter.qml` serializa lecturas acotadas y las mutaciones que no expone la API nativa. Un único `nmcli monitor` dispara actualizaciones agrupadas; no hay sondeo periódico de perfiles. La recuperación del monitor tiene reintentos limitados. Procesos y operaciones tienen plazos y se cancelan al destruir el servicio. Los metadatos son snapshots; los objetos nativos siguen siendo la fuente de conexión.

Conectar/desconectar y scan usan la API nativa cuando es suficiente. Activación, olvido, autoconnect, IPv4 y red oculta usan UUID explícito. Crear una red oculta crea un perfil nuevo; nunca elimina otro por nombre. Para perfiles personales existentes, ConnectivitySecret.py recibe la contraseña por stdin, guarda el perfil con libnm TO_DISK y psk-flags=0, y comprueba settings y secreto antes de activar el UUID. No usa argv, archivos temporales ni logs de secretos. Una contraseña incorrecta puede guardarse, pero nunca confirma conexión: la autenticación real sigue siendo necesaria. Nuevas redes usan AddAndActivate nativo con flags persistentes por defecto. Los campos de contraseña se vacían al despachar y al cerrar. Un perfil creado se conserva si falla su activación. 802.1X requiere un perfil previamente configurado; no se simula un editor de certificados.

Cada operación conserva id, destino, inicio, estado, código, mensaje y posibilidad de reintento. Un proceso exitoso no basta: se exige estado nativo y/o lectura del perfil. Los callbacks de una operación antigua no pueden completar otra. Los errores de autenticación permanecen en contexto. Internet se representa separadamente de conexión: unknown/none/portal/limited/full.

## Bluetooth

Quickshell.Bluetooth aporta adaptadores y dispositivos nativos, conexión, pairing/cancelación, olvido, paired/bonded/trusted/blocked/wake y batería cuando BlueZ la ofrece. El adaptador seleccionado gobierna discovery; el contador conectado de barra/BottomHub considera todos los adaptadores.

Las operaciones se confirman con señales y estado BlueZ. Los setters nativos cachean anticipadamente su valor: power/trust/block/wake y propiedades de adaptador se verifican con una lectura D-Bus solo mientras la operación está pendiente. La UI conserva el valor confirmado. No hay sondeo en reposo. Cambiar adaptador durante una operación está deshabilitado; la desaparición del adaptador no puede confirmar un olvido.

La versión instalada no expone solicitudes Agent1 de PIN/passkey/confirmation ni errores de método como señales QML. Se usa su pairing existente, con progreso/cancelación/plazo; los flujos que necesitan autenticación interactiva requieren un agente del sistema. No se implementó un Agent1 especulativo. La UI explica esa limitación y no inventa diálogos. Cuando falta error nativo observable, se informa un plazo excedido; no se inventa HostDown o rechazo de autenticación.

## UI y vida de objetos

Barra, BottomHub, quick toggles, popups, OSD y Settings/Nexus leen Connectivity. Los toasts de conexión requieren confirmación. Settings y Nexus conservan sus layouts, categorías, controles y estilos originales. Los cambios de UI se limitan a fuentes de estado, acciones y limpieza de credenciales. Las páginas solicitan scan solo mientras son visibles y liberan ese propietario al salir. Cada vista usa un propietario de scan distinto; cerrar una no cancela otra aún abierta. El scan manual tiene duración acotada.

El backend Nmcli heredado de 1803 líneas queda como fachada mínima de compatibilidad, sin procesos ni eliminación por nombre. Las páginas heredadas conservan las rutas y los formularios originales del Nexus. VPN conserva sus proveedores/editor; su monitor duplicado se reemplaza por eventos del adaptador común. No quedan piezas antiguas necesarias como backend paralelo.

## Fallos y límites

Un timeout informa que no hubo confirmación; no garantiza que el daemon no complete posteriormente. El modelo nativo seguirá mostrando el resultado tardío. La lectura de metadatos puede fallar independientemente de la conexión; la UI muestra el error y permite actualizar. Recuperación física de daemon/suspensión, pairing interactivo y equipo ausente permanecen en la matriz de validación, sin bloquear la implementación independiente.

## Verificación y reversión

`build-runtime.sh` ejecuta pruebas existentes y las suites nuevas de policy/runtime y persistencia de credenciales. Los fixtures usan objetos o procesos falsos y no modifican perfiles ni radios reales. La matriz distingue fixtures, observación pasiva y pruebas físicas. La recarga instalada debe usar `cortetsu shell reload`, preservando el proceso de shell y las aplicaciones.

Antes de promover, guardar la ruta resuelta de current. Para revertir solo la shell, volver a apuntar current atómicamente a esa generación conservada y recargar. No usar rollback global de dotfiles para revertir únicamente conectividad. La evidencia de entrega incluye ruta anterior y comandos exactos.

El botón original de copiar contraseña crea una consulta efímera por UUID solo al pulsarlo. Destruye el proceso y su collector al terminar; el singleton conserva únicamente estado y error. Cancelar no modifica el portapapeles.

# Evidencia de Connectivity 2.0

Fecha: 2026-10-02. Rama de trabajo: `ascension/product-elevation`. Base auditada: `344a6e690406d7074fefac785f2bcb6e5cc207d1`. `.codebase-memory/` y `scripts/integration/` son preexistentes y se conservan sin incluirlos en commits.

## Entorno y evidencia inicial

La auditoría precedente confirmó Quickshell 0.3.1.r6.g0f9939c, Qt 6.11.2, Hyprland 0.56.2, NetworkManager 1.58.1, BlueZ 5.87, PipeWire 1.6.9 y kernel 7.2.8-1-cachyos. Sus pruebas preceden la migración: no se presentan como pruebas del código nuevo.

Interfaz Wi-Fi real: wlan0, conectada a la red doméstica por su perfil guardado (SSID y nombre de perfil coinciden, aunque el modelo los distingue). AP activo en 5180 MHz/5 GHz, anuncio WPA1/WPA2; la API nativa clasifica WPA2. Señal variable 60–61% durante la observación. IPv4 por DHCP con gateway y DNS del router; IPv6 link-local. Autoconnect activo. Conectividad full. Los identificadores del equipo (SSID, BSSID, UUID, direcciones) se omiten porque el repositorio es público. Los fixtures cubren nombres de perfil distintos del SSID y whitespace significativo.

Adaptador Bluetooth: hci0. Dispositivos conocidos: Gamepad y ZON, desconectados. En la auditoría conectar Gamepad produjo br-connection-create-socket/Host is down. No hay evidencia para atribuirlo a Cortetsu; necesita estar despierto para comparar conexión directa y desde UI.

Una sola pantalla activa: eDP-1, 1920×1080, escala 1, transform 0. Ethernet eno1 sin cable. No se reiniciaron NetworkManager, BlueZ ni el equipo. No se borraron perfiles reales ni se modificó su IPv4 en pruebas.

## Interpretación de la matriz

PASS_CONTROLLED significa fixture de política/backend o interacción QML aislada; no sustituye una prueba física. PASS_PHYSICAL_PRE_MIGRATION identifica pruebas de la fase de auditoría ya realizadas. PASS_PASSIVE identifica lecturas del equipo sin cambiar su conectividad. PENDING_PHYSICAL_VALIDATION significa que falta la ejecución física indicada, no que el caso esté probado.

| Caso Wi-Fi | Evidencia disponible | Validación física del código nuevo |
|---|---|---|
| Scan repetido | PASS_PHYSICAL_PRE_MIGRATION; scanner/lifetime QML PASS | PASS_PHYSICAL: backend nuevo, registro /tmp/cortetsu-connectivity-physical.log |
| Radio off/on | PASS_PHYSICAL_PRE_MIGRATION | PASS_PHYSICAL: backend nuevo, registro /tmp/cortetsu-connectivity-physical.log |
| Reconexión UUID | PASS_PHYSICAL_PRE_MIGRATION; identidad UUID fixture PASS | PASS_PHYSICAL: backend nuevo, registro /tmp/cortetsu-connectivity-physical.log |
| Red guardada | Fixture UUID/SSID distintos PASS_CONTROLLED | PENDING_PHYSICAL_VALIDATION de otra red |
| Credenciales correctas | PSK exclusivamente stdin PASS_CONTROLLED | PENDING_PHYSICAL_VALIDATION de red de prueba |
| Credenciales incorrectas | Normalización/auth-required PASS_CONTROLLED | PENDING_PHYSICAL_VALIDATION de red de prueba |
| Cambio entre redes | Destinos/identidad fixture PASS_CONTROLLED | PENDING_PHYSICAL_VALIDATION |
| Múltiples BSSID | APs de mismo SSID y distinta banda fixture PASS_CONTROLLED | PENDING_PHYSICAL_VALIDATION; no grupo físico duplicado en lectura inicial |
| Olvido | Inventario por UUID y confirmación PASS_CONTROLLED | PENDING_PHYSICAL_VALIDATION de perfil desechable |
| Autoconnect | Escritura+lectura por UUID PASS_CONTROLLED; real activo PASS_PASSIVE | PENDING_PHYSICAL_VALIDATION de perfil desechable |
| Limited → full | PASS_PHYSICAL_PRE_MIGRATION; enum/state policy PASS_CONTROLLED | PENDING_PHYSICAL_VALIDATION de transición provocada |
| Sin Internet / portal | Etiquetas/enum PASS_CONTROLLED | PENDING_PHYSICAL_VALIDATION de AP sin salida/portal |
| Ethernet + Wi-Fi | Modelo dispositivos y metadatos cable PASS_PASSIVE | PENDING_PHYSICAL_VALIDATION; falta cable |
| Red oculta | Creación+activación y stdin PASS_CONTROLLED | PENDING_PHYSICAL_VALIDATION de AP oculto |
| IPv4 DHCP/manual | Validación y lectura confirmada PASS_CONTROLLED | PENDING_PHYSICAL_VALIDATION de perfil desechable |
| NM recovery | Monitor/backoff/plazos inspeccionados y fixtures | PENDING_PHYSICAL_VALIDATION de reinicio deliberado |
| Suspend/resume | Lifetime y estado reactivo inspeccionados | PENDING_PHYSICAL_VALIDATION |

| Caso Bluetooth | Evidencia disponible | Validación física del código nuevo |
|---|---|---|
| Radio off/on | PASS_PHYSICAL_PRE_MIGRATION; readback/pending fixture PASS_CONTROLLED | PASS_PHYSICAL: backend nuevo, registro /tmp/cortetsu-connectivity-physical.log |
| Discovery | Owner múltiple y liberación de página PASS_CONTROLLED/Wayland | PASS_PHYSICAL: backend nuevo, registro /tmp/cortetsu-connectivity-physical.log |
| Connect/disconnect/reconnect | Confirmación nativa/single-flight/plazo PASS_CONTROLLED | PENDING_PHYSICAL_VALIDATION con Gamepad despierto |
| Pairing/cancel | API instalada y progreso/cancel fixture PASS_CONTROLLED | PENDING_PHYSICAL_VALIDATION de dispositivo de prueba |
| Pairing incorrecto/rechazado | Taxonomía policy PASS_CONTROLLED; método no expone error QML | PENDING_PHYSICAL_VALIDATION |
| PIN/passkey/confirmación | API instalada no expone Agent1 interactivo; UI lo explica | PENDING_PHYSICAL_VALIDATION con agente del sistema |
| Trust/block/wake | Valor confirmado retenido mientras pending/fallo PASS_CONTROLLED | PENDING_PHYSICAL_VALIDATION de dispositivo de prueba |
| Forget | Espera desaparición; adapter-removed no confirma éxito PASS_CONTROLLED | PENDING_PHYSICAL_VALIDATION de dispositivo de prueba |
| Batería | Propiedades API y presentación cuando disponible | PENDING_PHYSICAL_VALIDATION; equipos actuales no informan |
| Dispositivo desaparece | Política de pertenencia y fallo PASS_CONTROLLED | PENDING_PHYSICAL_VALIDATION |
| Dormido/fuera de alcance | Host is down observado antes de migración | PENDING_PHYSICAL_VALIDATION para comparación de capas |
| BlueZ recovery | Estado de adaptador y limpieza inspeccionados | PENDING_PHYSICAL_VALIDATION de reinicio deliberado |
| Suspend/resume | Lifetime y estado reactivo inspeccionados | PENDING_PHYSICAL_VALIDATION |
| Varios adaptadores | Modelo/selección/contador global y guard durante operación | PENDING_PHYSICAL_VALIDATION; un adaptador real |

| UI | Evidencia |
|---|---|
| Settings/Nexus original restaurado | Layout original conservado; siete páginas cargan en prueba Wayland |
| Mouse | Revalidación de controles originales en suite Wayland |
| Teclado | Revalidación Tab/Enter de controles originales en suite Wayland |
| Lifetime/scans | Cambio de categoría libera propietarios; prueba original Nexus cero scanowners |
| Barra/BottomHub/quick settings | Fachadas únicas y contratos PASS; ver registro de recarga efectiva |
| Popups/errores/toasts | Migrados a operación común; pruebas source/fixtures; ver registro de recarga |
| Multimonitor | Propietarios por instancia y estado por monitor inspeccionados; PENDING_PHYSICAL_VALIDATION |
| Escalado Wayland | PASS físico escala 1; PENDING_PHYSICAL_VALIDATION escala distinta |

## Suites nuevas

- `test-connectivity-wifi-policy.cjs`: escapes, whitespace, identidad de perfil/AP, confirmación UUID, errores y configuración IPv4.
- `test-connectivity-wifi-runtime.py`: backend QML real con nmcli falso aislado; inventario/olvido/autoconnect/IP, varios BSSID y contraseña por stdin. No toca perfiles del usuario.
- `test-connectivity-bluetooth.mjs`: 16 comprobaciones de política.
- `test-connectivity-bluetooth-runtime.py`: 17 comprobaciones del backend con objetos nativos falsos: confirmación, single-flight, dueños de scan, cancel, plazos, desaparición de adaptador y conservación de trust confirmado.
- `test-connectivity-ui-wayland.py`: opt-in visible, controles originales mouse/Tab/Enter/identidad/lifetime/scans, contra runtime construido. No conecta/desconecta dispositivos. Requiere una red ya conectada y perfiles existentes.

Las suites aisladas de backend y credenciales están integradas en build-runtime. La suite visible es opt-in para no abrir ventanas ni hacer discovery automáticamente en cualquier construcción.

## Problemas detectados y corregidos durante revisión

IDs QML repetidos, imports relativos inválidos después del aplanado, perfil equivocado por SSID, membresía de adaptador que podía confirmar un olvido, estado auth-required sin recuperación en popup, monitor VPN duplicado y toggles Bluetooth optimistas se corrigieron. El rediseño provisional fue retirado tras la corrección de alcance del usuario. La entrega conserva la interfaz original y adapta su comportamiento al backend común. Se corrigieron además tres fallos de controles compartidos expuestos por las páginas originales: id ausente, ventana nula y uso de splice sobre una lista QObject.

## Logs y medición

La construcción aislada completa final pasó todos los gates del repositorio: `/tmp/cortetsu-connectivity-build-final.log`. UI visible: `/tmp/cortetsu-connectivity-ui-acceptance.log`, resultado UI_WAYLAND_PASS 11. Los logs temporales de las sondas fallidas se conservan para diagnóstico, pero no representan la versión instalada.

Antes: PID 2719, ventana de 10.0007 s, CPU 7.2995% de un núcleo, RSS 350292 KiB, generación `20260930-034419-1073298`. El porcentaje de CPU de ps acumulado desde inicio no se compara con este muestreo. Después y recarga: añadir registro final solo tras medir.

## Reversión exacta de la shell

La generación inicial conservada es `/home/dilan/.local/share/cortetsu/builds/20260930-034419-1073298`. Para volver a ella sin resetear el checkout ni modificar dotfiles (comandos compatibles con fish):

```fish
ln -s /home/dilan/.local/share/cortetsu/builds/20260930-034419-1073298 /home/dilan/.config/quickshell/cortetsu/current.connectivity-rollback
mv -Tf /home/dilan/.config/quickshell/cortetsu/current.connectivity-rollback /home/dilan/.config/quickshell/cortetsu/current
cortetsu shell reload
```

Si el nombre temporal ya existe, inspeccionarlo antes; no sobrescribirlo a ciegas. Las generaciones se conservan, no se ejecutó GC. La reversión del código se hace con revert de los commits de esta tarea sobre esta rama, sin reset y sin tocar main.

## Persistencia y prueba física posterior

Los fixtures test-connectivity-secret.py usan libnm real para verificar que flags AGENT_OWNED/NOT_SAVED se eliminan, se preserva el resto del perfil y el readback incorrecto falla. test-connectivity-credential-flow.py comprueba que fallo, falta de comprobante y cancelación impiden activar el perfil. Los fixtures no modifican perfiles reales.

La prueba física del backend instalado realizó dos scans, Wi-Fi off/on, reconexión del UUID original, Bluetooth off/on y discovery; terminó con Internet full, radios encendidas y ningún propietario de scan/discovery. Resultado PHYSICAL_PASS en /tmp/cortetsu-connectivity-physical.log. No probó contraseñas de una segunda red ni conexión de Gamepad dormido.

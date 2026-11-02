# Seguridad del observador

`agent-realm observe` muestra el escritorio de un realm en un navegador. Este documento recoge qué protege, qué no y por qué.

## Arquitectura

```
navegador ──HTTP 127.0.0.1:<puerto>──► pasarela (solo observe) ──► captura en memoria (grim -)
                                              ▲
CLI agent-realm ──socket Unix 0600──► canal de control (status, launch, revoke, stop)
                 $XDG_RUNTIME_DIR/cortetsu-agent-realms/observers/<realm>/  (0700)
```

- Un proceso observador por realm (`flock` sobre `.lock`). Se inicia bajo demanda y termina cuando el realm se detiene, cambia de sesión o pasan 15 minutos sin visores (`--idle-timeout`).
- Las capturas viven solo en memoria: `grim` escribe a una tubería y la pasarela sirve rutas fijas (`/`, `/app.js`, `/api/session`, `/api/state`, `/api/frame`). No existe raíz de documentos, así que no hay rutas que resolver, symlinks que seguir ni archivos especiales que abrir.
- La captura ocurre solo cuando un visor autorizado pide un frame. Sin visores no se ejecuta `grim`.

## Autorización

1. `agent-realm observe <realm> --open` pide al canal de control un archivo de lanzamiento. El observador crea `launch-<aleatorio>.html` con `O_EXCL|O_NOFOLLOW` y permisos 0600. Contiene un ticket de un solo uso válido 60 s.
2. `xdg-open` recibe solo la ruta del archivo. El ticket nunca aparece en argv, en la salida de la CLI ni en logs. Esto importa porque `/proc` de este sistema se monta sin `hidepid` y cualquier usuario puede leer la línea de órdenes de otros procesos.
3. El archivo redirige a `http://127.0.0.1:<puerto>/#t=<ticket>`. El fragmento no se envía al servidor. La página lo lee, lo borra de la barra con `history.replaceState` y lo canjea por `POST /api/session`.
4. El token de sesión (256 bits) queda en una variable de JavaScript. No hay cookies ni `localStorage`. Cada petición lleva `Authorization: Bearer`.
5. Al canjear el ticket se borra el archivo de lanzamiento. Los no canjeados se borran al caducar.

Las sesiones caducan tras 30 minutos sin uso o 8 horas de vida, con un máximo de 8 simultáneas. El servidor guarda solo el SHA-256 de tickets y tokens.

| Acción | Efecto |
| --- | --- |
| `observe <realm> --revoke` | invalida todas las sesiones y los tickets pendientes |
| `observe <realm> --stop` | detiene el observador; el realm sigue activo |
| `agent-realm stop <realm>` | avisa al observador antes de parar; revoca y termina |
| reinicio del observador | los tokens anteriores dejan de valer (claves nuevas en memoria) |
| realm reiniciado con el mismo nombre | identidad de sesión distinta (scope + start time); el observador se cierra |

## Capacidades

| Capacidad | Permite | Quién la recibe |
| --- | --- | --- |
| `observe` | estado y frames | visor HTTP; herramientas MCP de lectura |
| `control` | entrada virtual, abrir/cerrar apps y ventanas | perfil MCP que lo declare |
| `admin` | iniciar y detener el realm | perfil MCP que lo declare |

La pasarela HTTP solo emite `observe` y no tiene rutas de control: `PUT`, `DELETE`, `PATCH` y `OPTIONS` devuelven 405, y cualquier otra ruta devuelve 404.

## Cabeceras y validaciones HTTP

- `Host` debe ser exactamente `127.0.0.1:<puerto>`; otro valor devuelve 421. Esto frena DNS rebinding.
- `Origin`, cuando existe, debe coincidir con el origen propio. `POST /api/session` lo exige. Las rutas `/api/*` rechazan `Sec-Fetch-Site: cross-site`.
- Sin cookies no hay credenciales ambientales y, por tanto, no hay CSRF. Tampoco hay fuga a otros servidores de `127.0.0.1`: las cookies no se aíslan por puerto y un proceso del realm puede escuchar en loopback.
- `Cache-Control: no-store`, CSP `default-src 'none'` con `script-src 'self'`, `frame-ancestors 'none'`, `nosniff`, `no-referrer`, CORP y COOP `same-origin`.
- El cuerpo admite como máximo 1 KiB y solo `application/json`. Cada conexión tiene un timeout de 10 s. Las peticiones malformadas reciben un JSON fijo, sin eco de la línea de petición. No se registra ninguna petición.

## Modelo de amenazas

| Amenaza | Estado | Motivo |
| --- | --- | --- |
| Apps del realm (comparten el namespace de red) | mitigada | alcanzan el puerto TCP, pero sin token reciben 401. El socket de control está fuera de sus mounts: `$XDG_RUNTIME_DIR` del anfitrión no se monta. Verificado en vivo desde dentro del realm (`evidence/observer-security/attacks-from-inside-realm.txt`) |
| Apps de otro realm | mitigada | mismo caso; además, tokens y tickets son por observador y por realm |
| Otros usuarios del sistema | mitigada | sin token reciben 401; el directorio de control es 0700; el ticket no pasa por argv |
| Páginas web maliciosas en el navegador del usuario | mitigada | Host y Origin validados, sin cookies y con CSP; no pueden leer respuestas entre orígenes |
| Symlinks, traversal, FIFOs o sockets falsos | mitigada | rutas fijas en memoria; directorios verificados con `lstat`; `.lock` y archivos de lanzamiento con `O_NOFOLLOW`; el socket de control se valida como socket propio |
| Metadatos manipulados desde el realm | mitigada | la identidad del realm sale de `control/session.json` (fuera del sandbox) y de systemd, nunca de `realm-report.json` |
| Sesiones o PIDs reutilizados | mitigada | la identidad combina scope systemd y start time; si cambia, el observador se cierra |
| Datos en directorios temporales | mitigada | no se escriben capturas en disco; el único archivo con secreto es el de lanzamiento (0600, efímero) |
| Procesos del anfitrión con el mismo UID | **no mitigable aquí** | pueden pedir tickets al canal de control, leer la memoria del observador o del navegador con ptrace y leer el perfil del navegador. El aislamiento frente al mismo UID exige otro usuario, un contenedor o un LSM |
| Extensiones del navegador con acceso a todas las URLs | no mitigada | pueden leer la página y el token en memoria; es un riesgo del navegador, no del protocolo |
| Historial del navegador | aceptada | puede guardar la URL con el fragmento `#t=`. El ticket ya es de un solo uso y caduca en 60 s |
| Denegación de servicio local (conexiones lentas) | parcial | timeout de 10 s y servidor con hilos; un proceso local puede abrir muchas conexiones. No afecta al realm |

## Pruebas

- `tests/test_observer.py`: 30 contratos con servidores HTTP y de control reales. Cubre acceso autorizado, falta de credencial, credenciales inválidas y caducadas, acceso entre realms, HTTP malformado, Origin, Host y Sec-Fetch, traversal, symlinks, FIFOs, realm detenido o reiniciado, frame de otra sesión, caída con socket huérfano, reinicio, revocación, limpieza de sockets y archivos, rechazo de otro UID y separación de capacidades.
- `scripts/acceptance-observer.sh`: lo mismo contra un realm real, incluido `kill -9` del observador y la parada del realm, comprobando procesos, sockets, scopes y foco del anfitrión.
- Navegador real: Chromium headless (el binario de Playwright en caché) abrió el archivo de lanzamiento, canjeó el ticket y mostró frames (`evidence/observer-security/browser-viewer-authorized.png`).

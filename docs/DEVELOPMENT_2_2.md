# Cortetsu 2.2: primera pasada de estabilidad

> Actualización de modernización del 2026-11-06: ver
> [`CORTETSU_2_2_MODERNIZATION_2026-11.md`](CORTETSU_2_2_MODERNIZATION_2026-11.md)
> para versiones instaladas, hallazgos, correcciones y gates posteriores.
> La evidencia de abajo conserva su fecha y checkout originales.

El despliegue del commit certificado `a46dd497665b7709bd25e1b402cebcc969afa50c`
en la sesión reiniciada se registró el 2026-11-06. La generación schema 2,
recarga suave, validación de superficies y muestreo de rendimiento están en
[`CORTETSU_2_2_LIVE_VALIDATION_2026-11-06.md`](CORTETSU_2_2_LIVE_VALIDATION_2026-11-06.md).
Las pruebas sin HDMI, suspensión/reanudación y una comparación pareada de PSS
siguen pendientes; el despliegue no se presenta como certificación física
completa.

2026-11-05. Base: `main` y `origin/main` en `5a679b6`, comprobado con
`git fetch origin`. Se conservaron las modificaciones locales de
`.codebase-memory/artifact.json` y `graph.db.zst`. No hay tag ni release.

## Bottom Hub

Su `PanelWindow` no declaraba namespace Wayland y recibía la identidad
implícita de Quickshell. Ahora publica `cortetsu-bottom-hub`. Se conserva la
animación global del compositor: no se añade una regla de animación. No cambia capa Top, máscara,
zona exclusiva, foco OnDemand ni estado por monitor. Esto permite identificar
y aplicar reglas a la superficie correcta sin depender del nombre del proceso.

`test-bottomhub-hover-close-race.py` comprueba capas reales: exactamente una
por cada monitor headless, uno a escala 1,25. El recorrido existente comprueba
hover, reentrada durante cierre, exclusividad entre monitores y conservación
del foco del cliente. `test-bottomhub-wayland-policy.py` añade fullscreen
real en un cliente anidado, identidad por monitor y GameMode
ACTIVE → INACTIVE restaurando siete opciones vivas de Hyprland. Primera ejecución falló más tarde en un IPC `inspect`
sin stderr; la segunda pasó todo el recorrido. No se atribuye ese fallo al
namespace ni se oculta con reintentos dentro del test.

## GPG: causa y corrección aislada

El fallo no era un timeout del shell: GnuPG recibía EOF antes del saludo
Assuan de `pinentry-gnome3` y devolvía `No pinentry`. `coredumpctl` registra
SIGSEGV en pinentry a las 19:43:45, 19:46:05 y 19:51:52. GDB reproduce el
crash sin GPG: iniciar pinentry con stdin cerrado sobre el bus privado basta.
El hilo `gdbus` cae en libgio mientras el hilo principal está en
`g_bus_get_sync()`, dentro de la consulta del screensaver.

Pinentry abre y cierra un prompt Gcr para comprobar disponibilidad, libera
la conexión compartida y la solicita otra vez para el screensaver. El parche
`scripts/dependencies/pinentry/pinentry-1.3.3-session-bus.patch` conserva una referencia
durante `main`: evita la destrucción entre ambos usuarios y la libera al
salir, conservando el resultado del bucle Assuan y el fallback curses.
La explicación coincide con el contrato de conexión compartida de
[GIO](https://gnome.pages.gitlab.gnome.org/gtk/gio/func.bus_get_sync.html).
No se modificó el prompter de Cortetsu ni se añadió una implementación Assuan.

Fuente: [tarball oficial pinentry 1.3.3](https://gnupg.org/ftp/gcrypt/pinentry/pinentry-1.3.3.tar.bz2),
SHA256 `c2970f16d6afb66ecddfca767d743936c86239bff936eed7fd7597a678414b63`.
Entorno: pinentry instalado 1.3.3-1.1, Gcr 3.41.2-2.1, GLib 2.90.1-1.1.
La fuente sin parche, compilada con la misma configuración que la parcheada,
falló en el arranque 5 bajo GDB, con el mismo stack. La parcheada pasó 200
arranques bajo GDB y la suite completa de prompter (crear/desbloquear keyring,
contraseña errónea, cancelar, fallback y firma GPG real). Sin GDB, 200 arranques
sin parche también pasaron: es una carrera, no una garantía de fallo en cada ronda.

Reproducción sin instalar paquetes ni cambiar `gpg-agent.conf` personal:

```bash
curl -fL https://gnupg.org/ftp/gcrypt/pinentry/pinentry-1.3.3.tar.bz2 -o /tmp/pinentry-1.3.3.tar.bz2
python3 scripts/dependencies/build-pinentry.py --archive /tmp/pinentry-1.3.3.tar.bz2 --out /tmp/cortetsu-pinentry-fixed
CORTETSU_TEST_PINENTRY=/tmp/cortetsu-pinentry-fixed ./scripts/cortetsu test
```

Requiere compilador C, make, patch, pkg-config y los headers de libassuan,
libgpg-error, libsecret, Gcr y ncurses. El builder verifica el hash antes de
extraer, rechaza sobrescribir la salida y solo entrega el binario pedido.
`CORTETSU_TEST_PINENTRY` elige un pinentry real para los tests; sin la variable
se sigue probando `/usr/bin/pinentry-gnome3`, sin skips ni retries. El test nuevo
comprueba 200 arranques sobre un bus privado y el de GPG mantiene firma y
contenido real del prompt. El log normal del agente acompaña cualquier fallo.

Al cerrar esta pasada, el paquete instalado aún no tenía el parche. La reparación
del paquete del sistema y su verificación posterior están registradas en
[`CORTETSU_2_3_VALIDATION_2026-11-08.md`](CORTETSU_2_3_VALIDATION_2026-11-08.md).

## Comparación y medidas

Versiones leídas: Hyprland 0.57.0, Quickshell 0.3.2 rev4f508be, Qt base
6.12.0-3/declarative 6.12.0-4.1, Rust 1.99.1 y Go 1.27.3.

Realm antes: `5a679b6`; después: snapshot de checkout `66d2e4e` (no es un
commit promovido en main). Ese candidato incluía una regla `fade` retirada
después para conservar la animación global. Ambas matrices: 155/155 comprobaciones, 80 capturas,
cero warnings sin clasificar. Los warnings clasificados son 145 antes y 146
después. Capturas en `/tmp/cortetsu22-realm-before` y
`/tmp/cortetsu22-realm-after`; son evidencia local, no assets del producto.
Se inspeccionó el escritorio oscuro con transparencia: mismas islas,
geometría y material; cambia el reloj. La matriz también cubre claro,
transparencia desactivada y movimiento reducido. El runtime final sin la
regla `fade`, snapshot `60968e7`, se recompuso y verificó aparte: compilación
QML e integridad PASS, IPC de red/Dashboard abre y cierra, capturas
`/tmp/cortetsu22-final-{desktop,network,dashboard}.png` y capas en
`/tmp/cortetsu22-final-layers.json`. Esta comprobación focal cubre el ajuste
final; no se presenta la matriz anterior como un build idéntico.

Muestreo simultáneo de 60 s en dos realms privados recién arrancados, mismos
1920×1080 y superficies cerradas. Se leen ticks y PSS de los procesos `qs` en
los scopes exactos desde `/proc`, con muestreo de PIDs por segundo:

| Medida | Antes | Después |
|---|---:|---:|
| CPU de qs en 60 s | 130 ms | 160 ms |
| PSS final de qs | 102382 KiB | 108652 KiB |
| Nuevos PIDs observados en el scope | 0 | 0 |

Las cifras corresponden al candidato `66d2e4e`, antes de retirar su regla
`fade`; no se repitió el minuto por ese ajuste de animación.
Son muestras únicas en runtimes aislados; no demuestran una mejora de
rendimiento ni una regresión atribuible al namespace. El muestreo de PIDs no
puede excluir procesos que duren menos de un segundo. No se midió latencia de
primer frame y no se propone una optimización basada en estas cifras.
La reducción de adapters Caelestia queda condicionada a un flujo y una
medición que justifiquen cada cambio; esta pasada no introduce abstracciones.

## Gates, límites y rollback

- PASS: regla de capas y recorrido anidado Bottom Hub con dos monitores.
- PASS: ambas matrices Realm, 155 comprobaciones cada una.
- PASS: Agent Realms, 142 tests, 10 skips del entorno.
- PASS: instalación en HOME temporal sin Python en PATH, dos generaciones
  schema2, integridad de assets/helpers, rollback de todas las capas y
  recuperación de instalación interrumpida.
- PASS: `CORTETSU_TEST_PINENTRY=/tmp/cortetsu-pinentry-repro ./scripts/cortetsu test`,
  incluyendo los ocho crates Rust, Go, QML y contratos. Clippy del crate
  desktop-runtime con `-D warnings`, Go con `-race` y `go vet` también pasan.
- PASS: ambas revisiones Thermos independientes, corrección/seguridad y
  mantenibilidad, sin bloqueantes.
- PASS: builder con tarball real; rechazo de hash incorrecto y preservación
  de salida preexistente.
- BLOCKED_EXTERNAL: pinentry instalado conserva la carrera; no se certifica
  el paquete del anfitrión por haber pasado con un binario aislado.
- SKIPPED_SAFETY: HDMI físico, suspensión, PAM, cambios energéticos y recarga
  de la sesión activa. La certificación física 2.1 no se da por cerrada.

Rollback del código: revertir los commits de esta pasada. No hay rollback
operativo pendiente: no se promovieron generaciones ni se instalaron paquetes.
Para adoptar el shell posteriormente hacen falta instalación y recarga
explícitas; esta pasada no las ejecuta contra la sesión personal.

Anti-slop: PASS en hechos y métricas con evidencia; PASS en conservación de
material y geometría en las capturas finales; PASS en foco/hover/multimonitor
en las pruebas anidadas. Colores, tipografía, assets y layout móvil nuevos:
N/A, no se introdujeron. No se certifican interacciones físicas no ejecutadas.

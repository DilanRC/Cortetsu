# Atajos y teclados: backend Rust

`cortetsu/keyboards/` es el backend de «Atajos y teclados»: inventario de
teclados, teclas declaradas con su estado y, en los PR siguientes, el editor
transaccional de atajos que sustituye a `cortetsu/bin/cortetsu-keybinds`
(Python). El binario se llama igual, `cortetsu-keybinds`, para conservar el
contrato de los comandos `list`, `set`, `delete`, `reset` y `add-app`.

Se ejecuta bajo demanda y termina. No hay daemon ni servicio: `watch` solo
vive mientras el editor lo mantiene abierto. No lee pulsaciones.

## Comandos (protocolo 2)

| Comando | Respuesta (`kind`) |
|---|---|
| `inventory` | Teclados conectados, sus interfaces y su nombre en Hyprland |
| `keys [--device ID]` | Cada tecla declarada con sus estados, y `spare` («Teclas por aprovechar») |
| `watch` | Una línea `inventory` al empezar (`event: "initial"`) y otra por cada cambio (`"changed"`) |

Cada respuesta es una línea JSON con `protocol: 2`, `kind` y `ok`. Un error
lleva `error.code` estable (`usage`, `unknown-device`, `watch-unavailable`) y
`error.message` en castellano. Los comandos heredados conservarán la forma de
la versión 1.

## Identidad de un teclado

- Las interfaces (`eventN`) se agrupan por su dispositivo USB, si no por su
  dispositivo HID, si no por el propio nodo. Las interfaces «Keyboard»,
  «Consumer Control» y «System Control» de un teclado USB son un teclado.
- `id` es estable entre arranques: bus, vendor, producto y puerto USB
  (`usb:1a2c:2124@pci0000:00/0000:00:14.0/usb1/1-2`). `eventN` cambia y solo
  se muestra para diagnóstico.
- `model` es lo mismo sin puerto: reconoce un teclado movido de puerto solo
  cuando ningún otro dispositivo comparte modelo.
- No se lee `uniq` (número de serie) ni se emite `phys`, que en un teclado
  Bluetooth (uhid) es la dirección del adaptador: el puerto distingue dos
  teclados iguales y los datos no identifican a la persona.
- Dos teclados USB idénticos tienen `id` distinto, pero Hyprland los llama
  `x` y `x-1` según el orden de conexión, que sysfs no reproduce. Entonces
  `hyprlandLinked: false`, `hyprlandName` queda vacío y `hyprlandCandidates`
  lista los dos nombres: un atajo por dispositivo no se construye sobre una
  suposición.
- `ambiguous: true` solo cuando dos teclados conectados tienen la misma
  identidad (dos Bluetooth del mismo modelo). Su `id` lleva `#1`, `#2`, válido
  mientras sigan los dos, y sus preferencias no se recuperan.
- Tipos: `internal`, `vendor-hotkeys` (HP WMI), `usb`, `bluetooth`,
  `virtual`, `system-buttons` (botón de encendido, Video Bus), `other`.
  Ratones y touchpads (solo declaran `BTN_*`) no aparecen.

## Estados de una tecla

Los estados se combinan; una tecla puede ser VERIFIED, ASSIGNED y RESERVED.

| Estado | Regla |
|---|---|
| DECLARED | El bitmap `capabilities/key` del controlador incluye el código |
| VERIFIED | La persona la pulsó en una prueba explícita (PR por dispositivo) |
| ASSIGNED | Un bind efectivo usa su keysym o `code:N`, sola; o es una tecla dedicada usada en una combinación |
| CANDIDATE | Tecla dedicada (multimedia, lanzamiento, programable, F13–F24, fabricante) con keysym, sin acción y no reservada |
| RESERVED | Escritura, modificadores, navegación, F1–F12, AltGr, sistema (encendido, brillo, radio), capa Fn, o un keysym de esas funciones |
| UNKNOWN | Sin clasificar, sin keysym, o KEY_FN_ESC hasta confirmar su comportamiento |

`confidence` dice cuánto sabemos de que la tecla existe físicamente:

- `declared`: solo el bitmap. `atkbd` declara KEY_MAIL en cualquier portátil.
- `model`: la base de datos de hardware de udev (`KEYBOARD_KEY_*` en
  `/run/udev/data`) la asigna para este modelo. En el HP Victus: calculadora,
  cámara, Fn+Esc, brillo.
- `verified`: pulsada en una prueba explícita.

La ausencia de un bind en Hyprland no prueba que una tecla esté libre en el
firmware o en otras aplicaciones; por eso «declared» se muestra siempre.

## Keysyms

`xkbcli compile-keymap` (libxkbcommon) compila la distribución efectiva de
cada teclado según `hyprctl devices` (layout, variant, options, model). El
código Linux N es el keycode XKB N + 8. Con reglas evdev, KEY_F13 produce
`XF86Tools` y KEY_F20 `XF86AudioMicMute`: un bind se escribe con el keysym
real, y F20 queda reservada porque compartiría acción con el micrófono.

## Conexión en caliente

`watch` lanza `setpriv --pdeathsig TERM -- udevadm monitor --udev
--subsystem-match=input`. El kernel termina `udevadm` cuando el helper muere,
incluso por SIGKILL. El helper termina cuando su padre desaparece o se cierra
su salida: escribe una línea vacía cada 5 s para notarlo, y quien lee ignora
las líneas vacías. Sin `setpriv` no arranca (`watch-unavailable`) antes que arriesgar
un huérfano. Un enchufado produce varios eventos: se agrupan 250 ms y, si
Hyprland aún no registró el teclado, se reintenta hasta 1,5 s.

## Dependencias

`serde` y `serde_json`. Se evaluó el crate `udev`: enlaza libudev y aporta un
monitor en proceso, pero todo lo que se lee está en sysfs y en
`/run/udev/data`, y el monitor externo con `--pdeathsig` no necesita `unsafe`
(`unsafe_code = "forbid"`). Herramientas usadas en tiempo de ejecución, todas
de paquetes base de Arch: `hyprctl`, `xkbcli` (libxkbcommon), `udevadm`
(systemd) y `setpriv` (util-linux). La tabla de códigos (`src/keycodes.rs`)
se genera con `tools/gen-keycodes.py` desde `linux/input-event-codes.h` y se
versiona para que la compilación no dependa de las cabeceras instaladas.

## Medidas (HP Victus, 2026-10-17, binario release)

| Medida | Valor |
|---|---|
| `inventory` | 15–35 ms (mediana 16 ms) |
| `keys` (incluye `hyprctl binds` y `xkbcli`) | 43–49 ms |
| `watch` en reposo | 3,0 MB RSS, 0 ticks de CPU en 10 s |
| Latencia de hotplug (fixture) | 305 ms, de ellos 250 ms de agrupación |
| Procesos tras matar `watch` con SIGKILL | ninguno |
| Binario | 617 KB |

## Pruebas

```bash
cd cortetsu/keyboards
cargo fmt --check
cargo clippy --all-targets --locked -- -D warnings
cargo test --locked
```

Las fixtures reproducen el HP Victus con sus bitmaps reales, un teclado USB
de tres interfaces, dos teclados idénticos, Bluetooth detrás de un adaptador
USB, un dispositivo virtual y la conexión/desconexión. `tests/watch.rs` prueba
el hotplug, que `udevadm` muere con el helper aunque se mate con SIGKILL, y
que cerrar la salida de `watch` lo termina.

## Pendiente físico (PENDING_PHYSICAL)

- Teclado USB externo real: verlo en `inventory` con sus interfaces agrupadas
  y su nombre de Hyprland, y conectarlo/desconectarlo con `watch` abierto.

# Atajos y teclados: backend Rust

`cortetsu/keyboards/` compila `cortetsu-keybinds`, el backend de «Atajos y
teclados»: inventario de teclados, teclas declaradas con su estado y el editor
transaccional de atajos. Sustituyó al helper Python del mismo nombre
(`cortetsu/bin/cortetsu-keybinds`, último commit 6e3fdaf) con el mismo
contrato de comandos; ver «Migración desde Python».

Se ejecuta bajo demanda y termina. No hay daemon ni servicio: `watch` solo
vive mientras el editor lo mantiene abierto. No lee pulsaciones.

## Comandos del editor (protocolo 1)

`list`, `set ID CHORD`, `delete ID`, `reset ID` y
`add-app APP_ID NAME COMMAND CHORD` responden `{"ok": …}` como el helper
Python: mismos campos, ids (`var:`, `user:`, `app:`, `edit:`, `fixed:` con el
mismo SHA-256), mensajes y códigos de salida. Capas, precedencia y reglas de
combinación: [KEYBINDS.md](KEYBINDS.md).

## Comandos de teclados (protocolo 2)

| Comando | Respuesta (`kind`) |
|---|---|
| `inventory` | Teclados conectados, sus interfaces y su nombre en Hyprland |
| `keys [--device ID]` | Cada tecla declarada con sus estados, y `spare` («Teclas por aprovechar») |
| `watch` | Una línea `inventory` al empezar (`event: "initial"`) y otra por cada cambio (`"changed"`) |
| `bindings` | La lista del editor con `version`, el resumen de la configuración leída |
| `preview set ID CHORD` / `preview add-app CHORD` | `before`, `after`, `valid`, `conflict`, `problem` y `version`, sin escribir nada |
| `capture begin MS` / `capture end` / `capture status` | Entra o sale del submapa `cortetsu-capture` (`active`, `submap`) |
| `probe begin DEVICE MS` / `probe status` / `probe end DEVICE` | La prueba de teclas: `active`, `hits`, `codes` (al empezar) y `verified` (al terminar) |

`scope ID only|except|all [NAME…]` es un comando de escritura del editor
(responde como los de protocolo 1 y admite `--expect`); ver «Atajos por
teclado».

Cada respuesta es una línea JSON con `protocol: 2`, `kind` y `ok`. Un error
lleva `error.code` estable (`usage`, `unknown-device`, `watch-unavailable`,
`not-linked`, `nothing-to-test`, `probe-unavailable`…) y
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
| VERIFIED | La persona la pulsó en la prueba de teclas («Probar teclas») |
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

En Hyprland anidado (configuración del repositorio, sysfs simulado):

| Medida | Valor |
|---|---|
| `bindings` | 3 ms |
| `keys` | 24–26 ms |
| `scope` (snapshot, escritura, recarga y verificación por `repl`) | 60–68 ms |
| `probe begin` / `status` / `end` | 32 / 10 / 18 ms |

## Escritura revisada

`--expect VERSION` delante de un comando de escritura (`set`, `delete`,
`reset`, `add-app`, `scope`) lo rechaza con `"stale": true` si la configuración cambió
desde la vista previa que mostró esa versión. La superficie aplica siempre con
la versión que el usuario revisó. Toda escritura toma antes un bloqueo
exclusivo (`keybinds.lock` junto al almacén), así que la comprobación y la
escritura no se intercalan con otro helper (`src/editor.rs`).

## Captura de atajos

Mientras se graba un atajo, Hyprland entra en el submapa `cortetsu-capture`
para que ningún bind global se dispare. Las salidas, en orden de seguridad:

1. la superficie llama a `capture end` al recibir el atajo, al cancelar, al
   cerrarse o perder el foco, y al destruirse;
2. un temporizador de Hyprland (`MS`, entre 1 y 60 s) sale solo si nadie lo
   hizo, y una captura nueva invalida el temporizador de la anterior;
3. recargar la configuración de Hyprland sale también: la recarga empieza un
   estado Lua nuevo, sin el temporizador, pero conserva el submapa, así que
   `keybinds.lua` sale de él al cargarse;
4. `SUPER + CTRL + ALT + SHIFT + Escape` sale a mano.

## Atajos por teclado

Un atajo que el editor guarda (`app:` y `edit:`) puede limitarse a unos
teclados. Los de la configuración base (`var:`, `user:`, `fixed:`) los pone
Lua que el editor no escribe: se cambian primero y la edición resultante sí
se limita.

- Almacén: `"devices": {"only": true|false, "names": [...]}` en el bind.
  `only` lo deja solo en esos teclados; `false`, en todos salvo esos. Sin el
  campo, en todos. Los nombres son los de `hyprctl devices`.
- Lua compilado: `device = { inclusive = …, list = { … } }`, que
  `hyprland.lua` pasa a `hl.bind` como la opción `device` de Hyprland 0.56.
  Guarda además cada objeto `HL.Keybind` en `_G.cortetsu_binds[id]`.
- `scope` solo acepta nombres que `hyprctl devices` lista ahora, salvo los que
  el atajo ya tenía: un teclado desenchufado no se pierde al editar. Rechaza
  los de dos teclados iguales (`x` y `x-1`): Hyprland los numera por orden de
  conexión y el ámbito acabaría en el otro tras reconectar.
- La verificación solo falla por un atajo sin limitar si Hyprland lo tiene en
  otros teclados; si no lo cargó, no bloquea los demás cambios.
- Conflictos: dos atajos chocan si algún teclado dispararía los dos. Dos
  listas `only` disjuntas no chocan; `only A` contra `except B` choca salvo
  que A esté dentro de B; todo lo demás choca (una lista `except` nunca se da
  por completa: se puede enchufar otro teclado). Así dos aplicaciones pueden
  compartir combinación en teclados distintos.
- Verificación: `hyprctl binds -j` no muestra el ámbito, así que tras recargar
  el helper pregunta por `repl` a `_G.cortetsu_binds` qué teclados tiene cada
  atajo y restaura el snapshot si alguno no coincide. Con un `hyprland.lua`
  anterior, que no guarda esa tabla, un atajo limitado se rechaza
  (`actualiza hyprland.lua`) en vez de quedar global sin aviso.
- `list` (protocolo 1) no cambia; `bindings` añade `scopable` y `devices`.
- La superficie muestra el ámbito con el nombre del teclado y marca
  «(desconectado)» el que no está. «Solo este» y «Todos salvo este» usan el
  teclado elegido a la izquierda; dos teclados idénticos que Hyprland no
  distingue (`hyprlandLinked: false`) no se pueden elegir.

## Prueba de teclas

La única vía a VERIFIED. `probe begin` liga cada tecla CANDIDATE del teclado,
por keycode (`code:N`) y solo en ese teclado, a una función Lua que anota la
pulsación y nada más (`cortetsu_probe_begin` en `hyprland/keybinds.lua`).
Las teclas probadas no tienen otra acción, así que no se pierde nada mientras
dura. `probe end` quita los binds y guarda los códigos pulsados por modelo de
teclado (`model`, sin puerto) en `~/.config/cortetsu/keyboards.json`; `keys`
los lee. Solo se guardan códigos que ese teclado declara.

Los binds se van al terminar, con el temporizador (`MS`, 1–120 s; lo pulsado
se conserva hasta `end`) o con una recarga, que empieza un estado Lua sin
ellos. Se quitan con `hl.unbind("code:N")`: en Hyprland 0.56.2,
`HL.Keybind:remove()` sobre un bind que ya se disparó cierra el compositor.
Mientras dura la prueba la superficie no permite grabar ni aplicar cambios, y
al cerrarse la termina.

## Sugerencias

Cada tecla CANDIDATE con un keysym conocido lleva `suggestion`
(`{category, label}`): una tabla fija de keysym a categoría freedesktop
(`XF86Calculator` → `Calculator`, `XF86Mail` → `Email`, `XF86Tools` →
`Settings`…). La superficie propone las aplicaciones instaladas de esa
categoría; elegir una abre la revisión normal, que hay que confirmar. Nunca
se aplica sola. Las teclas reservadas (OMEN abre Hardware Center, Copilot las
acciones rápidas) ni son CANDIDATE ni reciben sugerencia.

## Superficie «Atajos y teclados»

Superficie retenida propia (`modules/keyboards`, IPC `keyboards`, atajo global
`keyboards`), fuera de Hardware Center. Tres zonas: teclados conectados,
pestañas (Atajos, Teclas especiales, Por aprovechar) y el editor. El flujo de
edición es un reductor puro (`CaptureFlow.js`): reposo, grabando, revisión,
aplicando, verificado, y conflicto, fallo, cancelado o recuperando. Nada se
escribe sin «Confirmar y aplicar». `watch` solo corre con la superficie
abierta.

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

- `scripts/features/test-keybinds-preview.py`: vista previa y `--expect`.
- `scripts/features/test-keybinds-scope.py`: `scope`, conflictos entre
  ámbitos, restauración si Hyprland no tiene el ámbito, `--expect`.
- `scripts/integration/test-keyboards-scope.py` (Hyprland anidado, dos
  teclados virtuales): cada teclado dispara solo su atajo sobre la misma
  combinación, y `hyprland.lua` real informa los ámbitos.
- `scripts/integration/test-keyboards-probe.py` (Hyprland anidado, sysfs
  simulado): solo cuentan las pulsaciones del teclado probado, `end` las
  guarda como VERIFIED, y no queda ningún bind al terminar, con el
  temporizador ni tras recargar.
- `scripts/features/test-cortetsu-keyboards-devices-runtime.py`: la
  superficie con un helper simulado limita un atajo, prueba teclas, impide
  cambios durante la prueba, la termina al cerrarse y propone sin aplicar.
- `scripts/integration/test-keyboards-capture.py` (Hyprland anidado): el
  submapa retiene los binds, se suelta, el temporizador libera y un token
  viejo no corta una captura nueva.
- `scripts/features/test-cortetsu-keyboards-runtime.py`: la superficie real
  con un helper simulado recorre grabar, conflicto, aplicar, cancelar,
  cerrar, tiempo agotado y fallo de `capture begin`.
- `cortetsu/tests/qml/keyboards/`: reductor, modelo y lectura de teclas.

## Migración desde Python

- Equivalencia: `scripts/features/test-keybinds-equivalence.py` toma el
  helper Python de Git (6e3fdaf) y ejecuta con él y con el Rust las mismas 85
  operaciones en dos HOME idénticos, sobre la fixture de `test-keybinds.py` y
  sobre la configuración Lua real del repositorio. Exige respuestas, códigos
  de salida, `keybinds.json` y `cortetsu-keybinds.lua` iguales en cada paso.
  Corre en CI (con historial completo) y al construir una generación; en una
  copia sin ese commit la construcción la salta y lo dice.
- `test-keybinds.py`, `test-keybind-editor-runtime.py` (Hyprland anidado:
  reasignar, borrar, restablecer, reinicio, promoción y rollback de
  generación) y `test-hp-keys.py` corren contra el binario Rust. Las pruebas lo
  encuentran con `scripts/lib/keybinds_helper.py`, que lo recompila de forma
  incremental; `CORTETSU_KEYBINDS_HELPER` lo sustituye por otra orden.
- `keybinds.json`, `cortetsu-keybinds.lua`, los snapshots y su retención (20)
  no cambian de formato. Dos diferencias deliberadas, sin efecto en ningún
  archivo que Cortetsu instala:
  - Los snapshots nuevos se nombran en UTC (`AAAAMMDD-HHMMSS-micro`); los del
    Python usaban hora local. Siguen ordenándose por fecha.
  - En `variables.lua`, `--` dentro de una cadena ya no se toma por comentario.
  - En `hypr-user.lua`, `hl.dsp.exec_cmd([[a]] .. [[b]])` es una acción Lua
    (no editable); el Python lo leía como el comando `a]] .. [[b`.
  - Con un número de argumentos incorrecto responde JSON
    (`Argumentos incorrectos`, código 2) en vez del uso de argparse.
  - Los nombres de tecla solo aceptan ASCII; el Python aceptaba algunos
    caracteres Unicode equivalentes por `re.I`.
  - Las claves de los objetos JSON salen en orden alfabético; los valores son
    los mismos. Quien lee el JSON (QML) no depende del orden.
  - `hyprctl binds -j` se lee entrada a entrada: un campo nuevo o con otro tipo
    no invalida la lista.
- `install-cortetsu.sh` compila con `cargo build --release --locked` e instala
  el binario en `~/.local/bin/cortetsu-keybinds`. Abrir el editor no compila
  nada. El grupo `keyboards` de `packages/arch.toml` (rust, libxkbcommon,
  systemd) lo comprueba `cortetsu doctor`.
- Reversión: `git revert` del PR y `cortetsu install` reinstalan el helper
  Python; el almacén de ediciones es el mismo, así que no hay que migrar nada.

## Pendiente físico (PENDING_PHYSICAL)

- Teclado USB externo real: verlo en `inventory` con sus interfaces agrupadas
  y su nombre de Hyprland, y conectarlo/desconectarlo con `watch` abierto.
- Atajo limitado a ese teclado: que dispare en él y no en el integrado, y que
  siga limitado tras desconectarlo y volver a conectarlo (mismo nombre en
  Hyprland).
- «Probar teclas» en el teclado integrado: pulsar la calculadora y ver que
  pasa a «Comprobada»; comprobar que una tecla declarada que el portátil no
  tiene sigue sin comprobar.

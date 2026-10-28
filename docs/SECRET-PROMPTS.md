# Diálogos de llavero y GPG

Cortetsu abre su propio diálogo cuando gnome-keyring pide la contraseña de un
llavero (desbloquear o crear uno) y cuando GPG pide una frase de contraseña.
Los dos llegan por el mismo sitio: `org.gnome.keyring.SystemPrompter`, el
prompter del sistema de gcr.

- gnome-keyring 51.1 abre sus diálogos con `gcr_system_prompt_open`.
- GPG pide la frase a `pinentry`. En Wayland, `/usr/bin/pinentry` elige
  `pinentry-gnome3`, que está enlazado con `libgcr-base-3` y usa ese mismo
  prompter. Por eso no hace falta un `pinentry` propio ni tocar
  `gpg-agent.conf`.

## Piezas

| Archivo | Papel |
|---|---|
| `cortetsu/desktop-runtime-rs/src/prompter.rs` | `cortetsu-prompter`: ocupa el nombre D-Bus y habla el protocolo de gcr |
| `cortetsu/desktop-runtime-rs/src/sxaes.rs` | Intercambio cifrado `sx-aes-1` de gcr, lado prompter |
| `cortetsu/modules/SecretPromptHost.qml` | IPC `secretprompt`, cola de peticiones, socket y ventana de capa |
| `cortetsu/modules/prompt/SecretPrompt.qml` | El diálogo |
| `dotfiles/home/.local/share/dbus-1/services/org.gnome.keyring.SystemPrompter.service` | Sustituye al archivo de gcr en `/usr/share/dbus-1/services` |

## Recorrido de una contraseña

1. El cliente (gnome-keyring o pinentry-gnome3) llama a `BeginPrompting` en
   `org.gnome.keyring.SystemPrompter`. D-Bus activa `cortetsu-prompter` si no
   está en marcha.
2. Al arrancar, el helper comprueba con `qs ipc call secretprompt ping` que el
   shell responde. Si no responde en 3 s, se reemplaza por
   `/usr/lib/gcr-prompter` antes de ocupar el nombre (ver «Respaldo»).
3. Con cada `PerformPrompt`, el helper abre un socket `0600` en
   `$XDG_RUNTIME_DIR/cortetsu/` y llama a
   `qs ipc call secretprompt request <socket> <token>`. El shell se conecta.
4. Por el socket viaja una línea JSON por petición, con el título, el
   mensaje, la descripción, el aviso, la casilla opcional, `passwordNew` y las
   etiquetas de los botones. El shell responde con
   `{token, reply, password, choice}`. Una respuesta con otro token cuenta como
   cancelación.
5. El helper cifra la contraseña con la clave `sx-aes-1` que comparte con el
   cliente (Diffie-Hellman de 1536 bits del RFC 3526, HKDF-SHA256 y
   AES-128-CBC) y se la devuelve con `PromptReady`.
6. Tras una contraseña incorrecta, el cliente vuelve a preguntar por el mismo
   socket con un aviso. El diálogo sigue abierto, muestra el aviso en
   bermellón y devuelve el foco al campo.
7. `StopPrompting` cierra el socket, y con él el diálogo.

La contraseña solo pasa por el socket privado y, ya cifrada, por D-Bus. Nunca
pasa por `qs ipc`, por la línea de órdenes ni por un log.

## Comportamiento

- Un cliente a la vez; los demás esperan su turno, como `gcr-prompter` en modo
  único. El shell también encola las peticiones que le llegan.
- La ventana usa la capa `Overlay` con teclado exclusivo, en la pantalla
  enfocada al llegar la primera petición. Si se desconecta ese monitor, el
  diálogo pasa a la pantalla enfocada.
- Intro envía. Escape o Cancelar cancelan. Mientras el cliente comprueba la
  contraseña («Comprobando…») no hay petición que cancelar. Escape queda
  anotado: si el cliente vuelve a preguntar (contraseña incorrecta), la nueva
  petición se rechaza sin mostrarse; si la contraseña era buena, el diálogo se
  cierra igualmente.
- Desbloquear exige una contraseña no vacía. Un llavero nuevo pide la
  contraseña dos veces y no envía si no coinciden. Una contraseña vacía en un
  llavero nuevo sí se envía, y gnome-keyring pregunta entonces si guardar sin
  cifrar.
- Las preguntas de confirmación no tienen campo; Intro activa el botón
  principal.
- Si el cliente ofrece una casilla (por ejemplo «desbloquear automáticamente
  al iniciar sesión»), aparece como conmutador y su valor vuelve al cliente.
- Bajo el título se muestra quién pide la contraseña cuando el cliente lo
  dice: pinentry-gnome3 envía `[pid]@host (orden)`.
- Las etiquetas de gcr llegan con mnemónicos de GTK (`_OK`); el diálogo quita
  el guion bajo.
- El helper termina a los 10 s sin clientes. En reposo no queda ningún
  proceso.

## Respaldo

El helper se reemplaza por `/usr/lib/gcr-prompter` (paquete `gcr`, declarado
en `packages/arch.toml`) cuando el shell no responde al `ping` en 3 s. Es lo
que ocurre al iniciar sesión, antes de que arranque el shell, o con una
generación del shell sin el IPC `secretprompt`. Lo hace antes de ocupar el
nombre D-Bus y con el mismo pid, que es el que D-Bus espera.

Si el shell deja de responder después, en mitad de una petición, esa petición
se responde como cancelada. La siguiente activación del helper vuelve a
comprobar el shell.

El desbloqueo del llavero al iniciar sesión no usa ningún diálogo: lo hace
`pam_gnome_keyring` (`/etc/pam.d/sddm`) con la contraseña de inicio de sesión.

## Instalación

`cortetsu install` instala el archivo `.service` en
`~/.local/share/dbus-1/services/`. dbus-broker da prioridad a ese directorio
sobre `/usr/share/dbus-1/services/` cuando dos archivos declaran el mismo
nombre. Un `gcr-prompter` que ya esté en marcha conserva el nombre hasta que
termina, unos segundos después de su último diálogo.

## Verificación

- `cargo test --test prompter` (en `desktop-runtime-rs`), contra un
  gnome-keyring real en un bus privado y con un shell falso:
  - crea un llavero con `secret-tool store` (`passwordNew`);
  - desbloquea tras una contraseña incorrecta (llega el aviso);
  - una cancelación no revela el secreto;
  - `gpg --clearsign` con `pinentry-gnome3` en un `GNUPGHOME` temporal recibe
    la frase por el helper;
  - sin shell, el helper ejecuta el respaldo y no ocupa el nombre.

  Además se comprueba que el log de gnome-keyring no tiene avisos de gcr ni
  `GLib-CRITICAL`. Así se detectó que gcr envuelve dos veces cada propiedad en
  la dirección prompter→cliente; sin esa doble envoltura, gnome-keyring creía
  vacía cualquier contraseña nueva.
- `qmltestrunner -input cortetsu/tests/qml/prompt`: el diálogo, con las formas
  que envían gnome-keyring y pinentry-gnome3.
- `cortetsu/SecretPromptFixture.qml` (`cortetsu test`): el protocolo del
  socket contra el `SecretPromptHost` real, sin abrir ventana.
- `scripts/integration/test-secret-prompt.py`: el shell compuesto en un
  Hyprland anidado, con `cortetsu-prompter` y un gnome-keyring real en el bus
  privado de la sesión y teclado virtual. Se crea un llavero escribiendo la
  contraseña dos veces, se desbloquea tras una contraseña incorrecta (el
  diálogo sigue abierto con el aviso) y se cancela con Escape. Tras cada
  diálogo ninguna capa de Cortetsu conserva el teclado. Se ejecuta aparte de
  `cortetsu test`, en un escritorio libre:

  ```sh
  cargo build --release --manifest-path cortetsu/desktop-runtime-rs/Cargo.toml
  python3 scripts/integration/ws2_run.py --workspace 4 /tmp/ws.log -- \
      python3 scripts/integration/test-secret-prompt.py
  ```

`qs ipc call` sale con 0 aunque el shell no tenga el objetivo («Target not
found.»). Por eso el `ping` exige la respuesta `ok`, y no solo el código de
salida.

Quickshell 0.3.2 se cae si el manejador `onError` de un `Socket` pone
`connected = false`: `Socket::onSocketError` llama después a `deleteLater`
sobre un puntero nulo. Cuando el helper cierra el socket, el host solo limpia
su estado. El fixture cubre ese caso.

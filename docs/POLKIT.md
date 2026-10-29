# Agente polkit

Cortetsu es el agente de autenticación polkit de la sesión. Cuando una
aplicación pide privilegios (`pkexec`, montar discos, NetworkManager, systemd),
el shell abre un diálogo propio en la pantalla enfocada.

## Piezas

| Archivo | Papel |
|---|---|
| `cortetsu/modules/PolkitHost.qml` | `PolkitAgent` de Quickshell, ventana de capa y respaldo |
| `cortetsu/modules/polkit/PolkitDialog.qml` | Diálogo de un `AuthFlow`: mensaje, acción, usuario, campo y errores |
| `cortetsu/tests/qml/polkit/tst_PolkitDialog.qml` | Pruebas del diálogo con un `AuthFlow` falso |

## Comportamiento

- La pantalla se fija al empezar la petición; mover el puntero no traslada el diálogo.
- La ventana usa la capa `Overlay` con teclado exclusivo y espacio de nombres `cortetsu-polkit`.
- El diálogo muestra el `actionId` además del mensaje: el mensaje lo redacta la aplicación; el id dice qué se autoriza.
- Intro envía y vacía el campo. Escape o Cancelar cancelan la petición, también mientras el campo está desactivado. Una contraseña vacía no se envía.
- Si se desconecta el monitor de la petición, el diálogo pasa a la pantalla enfocada.
- polkit pide la contraseña alrededor de 1,5 s después de abrir el flujo. Hasta entonces el campo está desactivado; al llegar la petición recibe el foco.
- Tras una contraseña incorrecta, polkit vuelve a preguntar. El diálogo lo indica en bermellón y devuelve el foco al campo. Si PAM envía un mensaje propio (por ejemplo, el bloqueo de faillock), se muestra ese mensaje.
- Con varios usuarios administradores aparece «Cambiar usuario», que recorre las identidades.
- Con la sesión bloqueada, el diálogo queda debajo del Lock hasta desbloquear.

## Respaldo

polkit admite un solo agente por sesión. Si el shell no se registra en 5 s,
porque otro agente ocupa la sesión o el registro falla, arranca
`polkit-gnome-authentication-agent-1` una vez (`cortetsu:polkit-fallback` en el
inventario de arranque; `polkit-gnome` está declarado en `packages/arch.toml`). Si ya hay un agente, polkit-gnome falla al registrarse
y termina con código 1, así que no quedan procesos duplicados.

`execs.lua` ya no arranca polkit-gnome. En una sesión iniciada antes de este
cambio, polkit-gnome conserva el puesto hasta el siguiente inicio de sesión;
reiniciar solo el shell no basta.

## Verificación

- `qmltestrunner -input cortetsu/tests/qml/polkit`: 9 casos, dentro de `build-runtime.sh` y `build-regressions.sh`.
- Prueba real (2026-10-27): con polkit-gnome detenido, el agente se registró desde una unidad `systemd-run --user`. Recibió `org.freedesktop.policykit.exec` de `pkexec`. Al enviar una contraseña incorrecta, polkit devolvió `failed=true` y volvió a preguntar. Al cancelar, `pkexec` salió con 126.
- Con polkit-gnome activo, el registro falla con «An authentication agent already exists for the given subject». Es el caso que activa el respaldo.

Las pruebas con contraseñas incorrectas cuentan para `pam_faillock`. Con la
configuración por defecto (`deny=3`, `unlock_time=600`), tres fallos bloquean
la cuenta 10 minutos, también para `sudo` y para el Lock. No automatices
pruebas con contraseñas incorrectas en la sesión real.

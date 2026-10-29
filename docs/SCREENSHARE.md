# Compartir pantalla

xdg-desktop-portal-hyprland 1.4.1 lee `~/.config/hypr/xdph.conf`
(gestionado: `dotfiles/home/.config/hypr/xdph.conf`):

```
screencopy {
    custom_picker_binary = cortetsu-share-picker
    allow_token_by_default = true
}
```

Nombres verificados en el binario de xdph 1.4.1 (`screencopy:custom_picker_binary`,
`screencopy:allow_token_by_default`).

## Flujo

1. xdph ejecuta `cortetsu-share-picker` con `XDPH_WINDOW_SHARING_LIST`
   (`{handle}[HC>]{clase}[HT>]{título}[HE>]{dirección}[HA>]…`).
2. El helper (`desktop-runtime-rs/src/sharepicker.rs`) abre un socket 0600 en
   `$XDG_RUNTIME_DIR/cortetsu/` y llama a
   `qs -p ~/.config/quickshell/cortetsu/current ipc call screenshare request <socket> <token>`
   (plazo: 5 s).
3. `modules/screenshare/ScreenShare.qml` conecta, recibe
   `{"token", "windows": [...]}` y abre `ScreenSharePicker` en la pantalla enfocada.
4. La respuesta es una línea JSON (`screen`, `window`, `region` o `cancel`) con el
   token. El helper valida que nombre algo ofrecido y escribe
   `[SELECTION]<r>/screen:DP-1`, `window:<handle>` o `region:<salida>@x,y,w,h`.
5. Cancelar, un token distinto o 60 s sin respuesta: código ≠ 0 y sin salida.
   Sin shell (la llamada IPC falla, se cuelga o `qs` imprime `Target not found.`
   con código 0): `exec hyprland-share-picker`.

Chromium y Electron abren varias sesiones por cada compartición. La última
elección se guarda 15 s en `$XDG_RUNTIME_DIR/cortetsu/share-picker-last.json`
(0600; `CORTETSU_SHARE_PICKER_REUSE_MS` cambia el plazo) y responde a las
peticiones siguientes si lo que nombra sigue ofrecido. Cancelar la borra.
Límite conocido: xdph no dice al selector qué app pide, así que otra app que
pida dentro de esos 15 s recibe la misma elección sin preguntar.

«Recordar para esta app» (Alt+R) añade la marca `r`: xdph emite un token de
restauración y Chromium/Electron no vuelven a preguntar.

## Teclado

1–9 comparte el elemento N; flechas mueven; Enter comparte; Tab / Shift+Tab
cambian entre Pantallas, Ventanas y Región; Alt+R; Escape cancela.

## Pruebas

- `cargo test --test share_picker` (selección, cancelación, reserva, timeout, IPC colgada).
- `cortetsu/ScreenShareFixture.qml` (protocolo QML real con `SocketServer`).
- `scripts/features/test-cortetsu-screenshare-runtime.py` (teclado y estados;
  `CORTETSU_RENDER_DIR` guarda PNG).

## Pendiente físico

Latencia de apertura y token con Legcord/Discord, Chromium y OBS reales. La
región se envía en coordenadas lógicas relativas a la salida; falta comprobarla
en un monitor con escala ≠ 1.

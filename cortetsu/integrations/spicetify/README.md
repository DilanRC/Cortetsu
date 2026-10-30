# Letras de Spotify en el dashboard

`cortetsu-lyrics.js` es una extensión de spicetify que pide a Spotify la letra
de cada canción y se la pasa al shell por `127.0.0.1:47853`, donde escucha
`cortetsu-lyrics serve` (lo lanza el servicio `Lyrics` del shell). El puente
solo acepta peticiones con el origen de la página de Spotify.

Instalar:

```sh
ln -sf "$PWD/cortetsu-lyrics.js" ~/.config/spicetify/Extensions/
spicetify config extensions cortetsu-lyrics.js
spicetify apply
```

Sin la extensión, o con otro reproductor, el dashboard busca la letra en
lrclib.net (`cortetsu-lyrics lrclib`).

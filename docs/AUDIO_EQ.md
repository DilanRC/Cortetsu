# Ecualizador de 10 bandas (opcional)

Estado: `IMPLEMENTADO_SIN_VERIFICAR` (ola 3.0 del 2026-11-16). Nada de esto
se ha ejecutado todavía; ver [`QA_POSTERIOR.md`](roadmap/cortetsu-3.0/QA_POSTERIOR.md).

## Qué es

Un sumidero `filter-chain` de PipeWire con un preamplificador (el `mixer`
integrado, ganancia lineal) y diez filtros biquad (32 Hz a 16 kHz). Cortetsu no crea ese grafo ni toca la
configuración de PipeWire: solo ajusta las ganancias del nodo cuando existe.

| Pieza | Archivo |
| --- | --- |
| Grafo (opt-in) | `cortetsu/data/pipewire/cortetsu-eq.conf` |
| Dueño | `cortetsu/services/CortetsuEqualizer.qml` |
| Respuesta y margen | `cortetsu/services/EqResponse.js` (funciones puras) |
| Preferencias | `eqEnabled`, `eqGains` en `~/.config/cortetsu/preferences.json` |
| Interfaz | Ajustes → Sonido → Ecualizador (plegado) |

## Activarlo

```bash
mkdir -p ~/.config/pipewire/pipewire.conf.d
cp cortetsu/data/pipewire/cortetsu-eq.conf ~/.config/pipewire/pipewire.conf.d/
systemctl --user restart pipewire
```

Después, en Ajustes → Sonido → Salida, elegir «Ecualizador de Cortetsu».
El nodo reenvía el sonido a la salida predeterminada que había.

## Quitarlo

```bash
rm ~/.config/pipewire/pipewire.conf.d/cortetsu-eq.conf
systemctl --user restart pipewire
```

Las preferencias `eqEnabled` y `eqGains` se quedan y no hacen nada sin el nodo.

## Comportamiento

- Sin el nodo, el grupo dice cómo instalarlo y no dibuja controles.
- Cada cambio de curva, del interruptor o del nodo (un PipeWire reiniciado
  vuelve plano) reaplica la curva guardada con
  `pw-cli set-param <id> Props { params = [...] }`. Lista de argumentos, sin shell.
- Ganancias limitadas a ±12 dB y redondeadas a 1 dB.
- Protección contra la saturación: el preamplificador baja la señal lo que
  sube el punto más alto de la curva completa. Se calcula con las mismas
  fórmulas de los biquads de PipeWire 1.6.11 (`biquad.c`) en 241 frecuencias
  logarítmicas de 20 Hz a 20 kHz más el centro de cada banda. Dos bandas
  vecinas a una octava se solapan: +6 dB en 64 Hz y +6 dB en 125 Hz suben más
  de 6 dB entre ambas, y el cálculo anterior (la banda más alta) se quedaba
  corto.
- Ajustes → Sonido dibuja esa misma curva y, en gris, lo que sale del nodo
  tras el preamplificador.
- Apagar el ecualizador pone todo a 0 dB; el nodo sigue en la ruta, así que
  el sonido no cambia de dispositivo.
- Cortetsu no mata, reinicia ni lanza PipeWire, WirePlumber ni el nodo.

## El preamplificador: de `bq_highshelf` a 0 Hz al `mixer`

La primera versión usaba `bq_highshelf` con `Freq = 0` como ganancia de banda
ancha. Revisado contra el código de PipeWire 1.6.11 (la versión instalada):
`biquad_highshelf()` trata `frequency <= 0` como un caso especial y fija el
filtro a la ganancia constante A² = 10^(dB/20). La atenuación era correcta,
pero dependía de ese caso límite del código.

La segunda versión (`cortetsu.eq.graph = 2` en el nodo) usa el `mixer`
integrado con una entrada: `"Gain 1"` multiplica la señal, que es el uso
documentado del nodo. Como el `mixer` tiene ocho entradas, el grafo declara
`inputs` y `outputs`; sin ellos PipeWire expondría todas las entradas libres.

Un grafo de la primera versión sigue funcionando: el servicio lee la
propiedad del nodo y, si falta, envía el preamplificador en dB al filtro
antiguo. Ajustes avisa de que el archivo se puede actualizar.

## Riesgos sin verificar

- El `mixer` con `inputs`/`outputs` explícitos en un `filter-chain` estéreo
  (dos instancias del grafo): comprobar con `pw-dump` que el nodo tiene dos
  puertos de entrada y dos de salida, no dieciséis.
- `PwNode.properties` solo se llena con el nodo enlazado; el servicio lo
  enlaza con `PwObjectTracker` y no aplica nada hasta `node.ready`.
- `pw-cli set-param` sobre un `filter-chain` estéreo debe ajustar los dos
  canales con el mismo nombre de control.
- El nodo como salida predeterminada con el HDMI de la RTX 3050: posible
  activación de la dGPU al reproducir; medir en QA.

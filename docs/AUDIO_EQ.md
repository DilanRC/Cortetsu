# Ecualizador de 10 bandas (opcional)

Estado: `IMPLEMENTADO_SIN_VERIFICAR` (ola 3.0 del 2026-11-16). Nada de esto
se ha ejecutado todavía; ver [`QA_POSTERIOR.md`](roadmap/cortetsu-3.0/QA_POSTERIOR.md).

## Qué es

Un sumidero `filter-chain` de PipeWire con un preamplificador y diez filtros
biquad (32 Hz a 16 kHz). Cortetsu no crea ese grafo ni toca la
configuración de PipeWire: solo ajusta las ganancias del nodo cuando existe.

| Pieza | Archivo |
| --- | --- |
| Grafo (opt-in) | `cortetsu/data/pipewire/cortetsu-eq.conf` |
| Dueño | `cortetsu/services/CortetsuEqualizer.qml` |
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
  sube la banda más alta.
- Apagar el ecualizador pone todo a 0 dB; el nodo sigue en la ruta, así que
  el sonido no cambia de dispositivo.
- Cortetsu no mata, reinicia ni lanza PipeWire, WirePlumber ni el nodo.

## Riesgos sin verificar

- `bq_highshelf` con `Freq = 0` como ganancia de banda ancha: es el patrón de
  las configuraciones AutoEQ para PipeWire, pero no se ha medido aquí.
- `pw-cli set-param` sobre un `filter-chain` estéreo debe ajustar los dos
  canales con el mismo nombre de control.
- El nodo como salida predeterminada con el HDMI de la RTX 3050: posible
  activación de la dGPU al reproducir; medir en QA.

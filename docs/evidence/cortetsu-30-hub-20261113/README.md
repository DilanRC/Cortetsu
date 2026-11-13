# Hub multiposición (Cortetsu 3.0, fase 3)

2026-11-13. Hyprland 0.57.1 anidado en el WS 3 de
`eDP-1`, salida `HEADLESS-1` a 1280×720, render por software.

- `anchors.jpg`: el Hub en sus ocho anclajes con el popout de audio abierto
  por IPC (sin control de origen, así que va al extremo del borde). El aviso
  rojo es del Hyprland anidado, no de Cortetsu.
- `settings-hub-ink.png`: Ajustes → Personalización → Hub con el selector,
  tomada antes del último ajuste de proporciones de sus puntos.
- `test-hub-anchors.log`: resultado de `scripts/integration/test-hub-anchors.py`.

Lo que la prueba comprueba en cada anclaje: capa en su borde, zona reservada
solo en ese borde, popout dentro de la pantalla y sin pisar el Hub, popout
abierto por hover real y que se mantiene al cruzar hasta él, y clic real en
la campana donde el Hub dice que está.

No probado aquí: dos monitores físicos con anclajes distintos, escala 1.25,
modo juego y fullscreen con el Hub fuera del borde inferior, ni la sesión real.

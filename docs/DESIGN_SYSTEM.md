# Cortetsu visual system

La estética samurái de Cortetsu es contenida: precisión, contraste, espacio y materiales; no decoración temática literal.

## Lenguaje

- **sumi**: fondos casi negros y superficies carbón;
- **tetsu**: bordes y elevaciones como acero ennegrecido;
- **ai**: índigo para foco y acciones primarias;
- **shu**: bermellón reservado para estados importantes;
- **washi**: texto principal ligeramente cálido;
- **ma**: espacio negativo deliberado para reducir ruido visual.

## Fuente declarativa

`~/.config/cortetsu/ui.toml` es el contrato de producto. Vive dentro de las generaciones de dotfiles y define identidad, spacing, radios y presupuesto de motion. `core/theme.py` compila esos tokens a `modules/CortetsuDesign.js` y a las salidas nativas de Kitty/GTK/KDE.

La migración del shell es incremental: la lógica funcional puede seguir usando temporalmente servicios, tipografía e icon metrics del adapter Caelestia, pero las superficies propias deben dejar de depender de `Colours`/Material 3 a medida que pasan a Cortetsu.

## Primitives QML

`CortetsuSurface.qml` es la primera primitive visual nativa. Usa únicamente QtQuick y `CortetsuDesign.js` para definir:

- superficies sumi/tetsu;
- hover contenido;
- selección índigo;
- outline bermellón para estado activo/importante;
- radios y motion propios;
- estado pressed sin rebote ornamental.

`HubButton.qml` y `StatusPill.qml` ya consumen esta primitive y no leen `Colours` de Caelestia. Esto convierte controles compartidos del Bottom Hub en la primera capa de chrome inequívocamente Cortetsu sin duplicar lógica de interacción.

## Motion

- pressed: 70 ms, reducción mínima de escala;
- hover: 100 ms, escala máxima 1.04;
- cambios de estado: 100–160 ms;
- transiciones deliberadas: `motion.standard_ms` (180 ms) o `motion.deliberate_ms` (240 ms), según el peso de la superficie;
- popovers: entrada breve, sin rebote ornamental;
- animación infinita: sólo para estados activos que realmente lo justifican.

El objetivo no es añadir animación, sino eliminar latencia percibida sin mantener trabajo cuando la interfaz está quieta.

## Jerarquía

Una superficie debe mostrar primero el estado y la acción probable. Métricas avanzadas permanecen disponibles, pero no compiten con la información primaria.

Ejemplo Hardware:

```text
System health
CPU      17% · 52 C
GPU      11% · 59 C
Memory   8.2 / 32 GB

Advanced metrics ->
```

## Reglas

- una familia de radios, spacing y tipografía;
- ningún color hardcoded cuando existe token semántico;
- estados hover/focus/pressed consistentes;
- el bermellón comunica importancia, no decoración constante;
- el índigo mantiene foco/selección sin competir con contenido;
- iconografía funcional, no ornamental;
- el contenido manda sobre el chrome;
- overlays con exclusividad y foco predecibles;
- 144 Hz deben sentirse fluidos sin mantener trabajo continuo cuando la UI está quieta.

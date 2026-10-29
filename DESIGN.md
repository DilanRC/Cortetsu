---
name: Cortetsu
description: Shell personal forjado en sumi, tetsu y washi para Hyprland
colors:
  sumi: "#0B0D10"
  tetsu: "#171B21"
  surface-high: "#222831"
  surface-glass: "#1B2028"
  surface-glass-strong: "#202731"
  washi: "#E7E0D5"
  on-surface-muted: "#AAB1BA"
  muted: "#8A919B"
  outline-variant: "#505862"
  indigo: "#334E68"
  indicator: "#5F7FA0"
  primary-container: "#263E53"
  secondary: "#526D82"
  secondary-container: "#293B4A"
  vermillion: "#D64B32"
  success: "#7A9B83"
  warning: "#C49A62"
typography:
  body:
    fontFamily: "Rubik, sans-serif"
    fontSize: "13px"
    fontWeight: 400
  body-large:
    fontFamily: "Rubik, sans-serif"
    fontSize: "14px"
  label:
    fontFamily: "Rubik, sans-serif"
    fontSize: "12px"
    fontWeight: 500
  label-small:
    fontFamily: "Rubik, sans-serif"
    fontSize: "11px"
rounded:
  small: "8px"
  medium: "12px"
  large: "20px"
  surface: "28px"
  pill: "999px"
spacing:
  unit: "4px"
  compact: "8px"
  standard: "12px"
  comfortable: "16px"
  spacious: "24px"
  section: "32px"
components:
  button-primary:
    backgroundColor: "{colors.indigo}"
    textColor: "{colors.washi}"
    rounded: "{rounded.medium}"
    height: "40px"
  button:
    backgroundColor: "{colors.surface-glass-strong}"
    textColor: "{colors.washi}"
    rounded: "{rounded.medium}"
    height: "36px"
  list-row:
    textColor: "{colors.washi}"
    rounded: "{rounded.medium}"
    height: "52px"
  surface:
    backgroundColor: "{colors.surface-glass}"
    rounded: "{rounded.surface}"
  danger:
    backgroundColor: "{colors.vermillion}"
    textColor: "{colors.washi}"
---

# Design System: Cortetsu

Fuente normativa: `dotfiles/home/.config/cortetsu/ui.toml`, compilada a
`cortetsu/theme/CortetsuDesign.qml`. Este archivo describe esos tokens para
agentes; si discrepan, gana `ui.toml`. Las reglas de primitivos siguen en
`docs/CORTETSU_DESIGN_SYSTEM.md`. La verificación estática es
`scripts/verification/qml-design-lint.py`. Un hallazgo intencionado lleva
`// design-lint: allow <regla>: <motivo>` en su línea o en la anterior; sin
motivo no cuenta. Cada superficie rediseñada queda a cero en `--strict` dentro
de `scripts/verification/build-regressions.sh`.

## Overview

**Creative North Star: "Transformación bajo presión"** (el `identity.concept` de
`ui.toml`).

Acero ennegrecido sobre tinta: superficies oscuras con tinte frío, texto en papel
cálido, un índigo nocturno para lo que se toca y un bermellón que solo aparece
cuando algo pide atención. La estética samurái es de oficio, no de disfraz: corte
preciso, *ma* deliberado, nada decorativo que no cargue información.

Dilan prefiere expresividad (PRODUCT.md): las superficies tienen presencia por
material, profundidad y transiciones con intención. Lo que se usa decenas de veces
al día abre al instante; la expresividad se concentra en superficies ocasionales.

**Key Characteristics:**
- Neutrales siempre teñidos (sumi/tetsu fríos, washi cálido); nunca negro o gris puro.
- Un acento de interacción (índigo) y uno de peligro (bermellón).
- Densidad de herramienta: filas de 52 px, controles de 36 px, rejilla de 4 px.
- Movimiento corto, sin rebote, interrumpible.

## Colors

Paleta de tinta y acero con papel cálido; el color es escaso y siempre significa algo.

### Primary
- **Índigo nocturno** (#334E68): selección y acción primaria como relleno, con
  texto washi. Sobre tetsu no llega a 3:1, así que no se usa como indicador.
- **Índigo indicador** (#5F7FA0, `colorIndicator`): pistas, rellenos de control y
  contornos activos. Con un esquema dinámico, su primario se aclara hasta 3:1.

### Secondary
- **Acero azulado** (#526D82) y su contenedor (#293B4A): estados secundarios y chips.

### Tertiary
- **Bermellón** (#D64B32): peligro, error, grabación, atención.

### Neutral
- **Sumi** (#0B0D10): el vacío del escritorio y la base del scrim.
- **Tetsu** (#171B21): superficie base.
- **Tetsu alto** (#222831), **vidrio** (#1B2028), **vidrio fuerte** (#202731):
  capas de profundidad tonal.
- **Washi** (#E7E0D5): texto principal.
- **Washi apagado** (#AAB1BA) y **gris acero** (#8A919B): texto secundario y contornos.

### Named Rules
**La regla de las dos voces.** Índigo para interacción, bermellón para peligro.
Ningún otro color de marca compite con ellos.

**La regla del contraste calculado.** Todo texto llega a 4.5:1 sobre su superficie
y todo indicador a 3:1. `CortetsuDesign.readable()` corrige los roles de texto de
esquemas dinámicos; el linter comprueba los pares de tokens.

## Typography

**Body Font:** Rubik (con la sans-serif configurada como respaldo)
**Icon Font:** Material Symbols Rounded (obligatoria; otra familia convierte iconos en palabras)

**Character:** Rubik es redondeada y legible a 11–14 px; la jerarquía sale del
peso y del espacio, no de tamaños grandes.

### Hierarchy
- **Body** (400, 13 px): texto de filas y contenido.
- **Body Large** (14 px): títulos de fila y valores.
- **Label** (500, 12 px): etiquetas y botones.
- **Label Small** (11 px): metadatos.
- Los tamaños `display*` de `modules/CortetsuTypography.js` cubren lecturas
  destacadas de Dashboard y Focus.

## Layout

Rejilla de 4 px. Espaciados 8/12/16/24/32. Filas de 52 px, controles de 36 px
(40 px primarios), objetivo de clic mínimo 36 px. El BottomHub reserva 66 px
inferiores para que las tarjetas transitorias no lo tapen. Cada superficie se
prueba a escala 1.0, 1.5 y 2.0 y en dos monitores.

## Elevation & Depth

Profundidad tonal: sumi → tetsu → vidrio → vidrio fuerte. Las superficies
flotantes usan `overlayOpacity` 0.94 y el scrim no pasa de `scrimOpacity` 0.22
salvo en modales. Las sombras son semitransparentes y ambientales, nunca un borde
sólido como sustituto de elevación.

### Named Rules
**La regla de una sola superficie.** No se anida `CortetsuSurface` dentro de otra:
dentro de una superficie se separa con espacio, divisores finos o vidrio fuerte.

## Shapes

Radios 8 / 12 / 20 / 28 y píldora. Controles en 12, superficies grandes en 28
(par 14/22 en superficies medianas). Geometría firme; divisores de 1 px como cortes.

## Components

Primitivos en `cortetsu/components/`: `CortetsuButton`, `CortetsuToggle`,
`CortetsuSlider`, `CortetsuListRow`, `CortetsuChoiceCard`, `CortetsuActionTile`,
`CortetsuActionRow`, `CortetsuTab`, `CortetsuSectionHeader`, `CortetsuTooltip` y
`CortetsuPopupHost`. Todos tienen estados deshabilitado, hover, pulsado, foco
visible y seleccionado cuando aplica; se activan con Enter, Return o Space.
La pulsación escala solo el contenido pintado a `pressScale` en 120 ms, para que
el área de clic no cambie. El foco es un anillo washi de 2 px; el contorno en
reposo es una línea translúcida, el activo es índigo y solo el peligro es bermellón.
`CortetsuPopupHost` es el único dueño de Escape, clic fuera y foco.

## Motion

Tokens de `ui.toml [motion]`, leídos siempre desde `CortetsuDesign`:

| Elemento | Token | Duración |
|---|---|---|
| Pulsación (escala `pressScale` 0.97) | `motionFastMs` | 120 ms |
| Tooltip (entrada; retardo `tooltipDelayMs` 240 solo para el primero) | `motionTooltipMs` | 150 ms |
| Popover y menú, entrada / salida | `motionPopoverMs` / `motionPopoverExitMs` | 200 / 150 ms |
| Panel, entrada / salida | `motionPanelMs` / `motionPanelExitMs` | 320 / 240 ms |
| Drawer y BottomHub | `motionDrawerMs` | 400 ms |
| Cambios de contenido | `motionInstantMs` / `motionStandardMs` / `motionDeliberateMs` | 80 / 180 / 240 ms |

Curvas (`Easing.BezierSpline` + `easing.bezierCurve`):

- `easeOut` (0.23, 1, 0.32, 1): entradas y popovers. Es la curva por defecto de
  `Anim`, `CAnim` y `CortetsuAnim`.
- `easeInOut` (0.77, 0, 0.175, 1): la interfaz moviéndose en pantalla (tipos `Emphasized*`).
- `easeDrawer` (0.32, 0.72, 0, 1): drawers y BottomHub.

**Reducir movimiento** (Ajustes → Apariencia → Superficies) pone cada `motion*Ms`
a 0 y detiene los bucles decorativos; las opacidades y posiciones siguen
cambiando, solo que al instante. El retardo de los tooltips no es movimiento y se
mantiene. Las barras de carga infinitas no dependen de esos tokens.

Reglas que verifica el linter:

- sin rebote, elástico ni sobreimpulso;
- ease-in solo en salidas;
- la escala nunca parte de menos de 0.95;
- nada pasa de 300 ms salvo drawers (500 ms);
- se animan opacidad, escala y x/y; no `width`/`height`.

Reglas manuales (no decidibles estáticamente): una acción iniciada por teclado no
anima; las salidas son más rápidas que las entradas.

## Do's and Don'ts

- **Do** leer cada color, radio y duración de `CortetsuDesign`.
- **Do** dar a cada superficie estados de carga, error y vacío.
- **Do** probar con nombres largos, listas vacías y cifras enormes.
- **Don't** usar negro o gris puro, ni texto gris sobre fondo de color.
- **Don't** añadir un segundo acento de marca.
- **Don't** implementar Escape o foco fuera de `CortetsuPopupHost`.
- **Don't** editar `CortetsuDesign.qml` o `CortetsuDesignDefaults.js` a mano.

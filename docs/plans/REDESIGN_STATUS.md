# Estado del rediseño (rama `redesign/v2`)

Plan: rediseño QML y superficies nuevas. Worktree `~/Documentos/Cortetsu-redesign`.
Sin push, sin merge y sin instalar en la sesión real.

| Fase | Estado | Evidencia |
|---|---|---|
| 0.1 Skills Emil e Impeccable en `~/.claude/skills` | Hecho (antes de esta rama) | `ls ~/.claude/skills` |
| 0.2 `PRODUCT.md` y `DESIGN.md` | Hecho | raíz del repo |
| 0.3 `qml-design-lint.py` (informa, no bloquea) | Hecho | `scripts/features/test-qml-design-lint.py` |
| 1 Tokens de movimiento y primitivos | Pendiente | |
| 2.1 Selector de compartir pantalla | Pendiente | |
| 2.2 Agente polkit | Pendiente | |

## Línea base del linter (fase 0)

Reglas manuales, no estáticas: «una acción de teclado no anima» y «sin texto gris
sobre fondo de color».

```
qml-design-lint: 317 findings in 478 files
      2  motion-bounce  (bounce/elastic/overshoot easing)
      9  motion-ease-in  (ease-in curve (only valid on exits))
     28  motion-scale-from-zero  (scale starts below 0.95)
     37  motion-duration  (duration above 300 ms (500 ms for drawers))
     58  motion-layout-property  (animates width/height instead of opacity/scale/x/y)
     24  color-untinted-neutral  (pure black/grey/white without a washi/sumi tint)
      2  color-contrast  (token pair below WCAG AA)
     39  layout-nested-surface  (CortetsuSurface nested inside another CortetsuSurface)
      9  layout-small-target  (click target smaller than 36 px)
     24  token-literal-color  (colour literal outside CortetsuDesign)
     31  token-literal-radius  (radius literal outside CortetsuDesign)
     54  token-literal-duration  (duration literal outside CortetsuDesign)
by surface:
     80  base/modules/nexus
     31  base/modules/bar
     19  base/components/controls
     18  base/modules/dashboard
     16  base/components/containers
     16  base/modules/sidebar
     15  modules
     14  base/modules/lock
     12  base/modules/utilities
     11  modules/bar
      9  modules/clipboard
      8  base/components/filedialog
      7  components
      6  modules/overview
      5  modules/calendar
      5  modules/launcher
      5  modules/settings
      5  modules/utilities
      4  base/components/effects
      4  modules/background
      4  modules/hardware
      4  modules/notifications
      3  base/components/widgets
      2  base/modules/launcher
      2  base/modules/notifications
      2  modules/keyboards
      2  modules/osd
      2  services
      2  theme
      1  modules/display
      1  modules/lock
      1  modules/sidebar
      1  modules/wallpaper
```

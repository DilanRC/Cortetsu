# Settings: Bluetooth, Pantalla y correcciones visuales

Capturas del arnés aislado (`scripts/features/test-cortetsu-settings-runtime.py` y
`test-cortetsu-settings-visual.py`) en el commit `7e96db1a`, misma interfaz que
`73cf39db`. La línea base anterior es `docs/evidence/settings-pages-20261109/`
(commit `59ba7a53`).

La matriz completa (540 capturas: 30 páginas × Ink, Washi, Kurogane × seis
condiciones) ya no se guarda en Git: se genera bajo demanda con el workflow
**Settings visual matrix** (`workflow_dispatch`) y queda como artefacto. En cada
push, el workflow de QML sube las capturas de los escenarios interactivos
(`cortetsu-settings-qt-renders`).

## Antes y después

| Página | Antes | Después |
|---|---|---|
| Bluetooth | ![](../settings-pages-20261109/ink/bluetooth.png) | ![](bluetooth-ink.png) |
| Bluetooth (Washi) | ![](../settings-pages-20261109/washi/bluetooth.png) | ![](bluetooth-washi.png) |
| Pantalla | ![](../settings-pages-20261109/ink/display.png) | ![](display-ink.png) |
| Clima, estrecha | ![](../settings-pages-20261109/ink/narrow/weather.png) | ![](weather-narrow.png) |
| Colores | ![](../settings-pages-20261109/ink/colors.png) | ![](colors-ink.png) |
| Perfiles | ![](../settings-pages-20261109/ink/profiles.png) | ![](profiles-ink.png) |
| Fondo (Washi) | ![](../settings-pages-20261109/washi/background.png) | ![](background-washi.png) |

## Estados interactivos

| Escenario | Captura |
|---|---|
| Bluetooth: emparejando, con Cancelar | ![](bluetooth-pairing.png) |
| Bluetooth: bloquear pide confirmación | ![](bluetooth-confirm-block.png) |
| Bluetooth: estrecha (Kurogane) | ![](bluetooth-kurogane-narrow.png) |
| Pantalla: salida NVIDIA con nVibrant y VRR | ![](display-nvidia.png) |
| Pantalla: vista previa con cuenta atrás | ![](display-preview.png) |
| Pantalla: Washi con Aura claro | ![](display-washi-aura-light.png) |

## Qué se comprobó y cómo

Gate automático, en cada página de cada una de las 18 combinaciones:

- ningún control sale de la columna de la página;
- ningún grupo dentro de otro grupo;
- contraste WCAG 2.2 de los tokens efectivos: texto 4.5:1, contornos e
  indicadores 3:1.

Gate visual: inspección de las capturas de esta tabla a tamaño real y de las
540 en hojas de contactos por condición (escala reducida: detecta composición,
desbordes y contraste groseros, no diferencias de un píxel).

**Pendiente:** inspección individual a tamaño real de las 540 capturas, y el
contraste de pares compuestos con transparencia (alpha) sobre el fondo real.

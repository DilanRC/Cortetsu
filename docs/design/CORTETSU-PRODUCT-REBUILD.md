# Cortetsu Product Rebuild

This document records decisions made during the first-party product redesign.
It is intentionally short and grows with the implementation.

## Product direction

Cortetsu is a desktop shell with its own visual language and surface ownership.
Caelestia remains an implementation dependency only where an existing backend is
still required. It must not determine the final presentation.

## Visual foundation

- Palette: Sumi for the base, Tetsu for elevated surfaces, Washi for legibility,
  Indigo for interaction and selection, Vermillion only for meaningful danger or
  warning. Green is reserved for healthy, connected, or successful states.
- Spacing: `4 / 8 / 12 / 16 / 24 / 32` px. The `spacingSection` token is the
  32 px step used to separate groups.
- Radii: small `8`, medium `12`, large `20`, surface `28`, pill only for controls
  whose geometry is explicitly capsule-shaped.
- Hit targets: standard controls are 36 px; primary controls are 40 px. BottomHub
  actions must not fall below the standard target.
- Motion: fast `120 ms`, standard `180 ms`, emphasis `240 ms`, with OutCubic as
  the default easing. No ornamental bounce or indefinite animation.

## Brand mark

`cortetsu/assets/branding/cortetsu-mark.svg` is an original C/T monogram made
from two interlocking plates. It uses `currentColor`, so the same asset works
monochrome, on dark or light surfaces, and with Indigo without maintaining
separate raster variants. The diagonal cuts are structural, not decorative.

The mark is used selectively in product-entry surfaces such as Settings,
Dashboard, Lock, and About. It is not repeated in every popup.

## Delivery order

The redesign is delivered in product slices: design foundation, real state
providers, BottomHub system cluster, QSD, schemes, Settings, Dashboard, Lock,
then the remaining surfaces and legacy visual cleanup. QA artifacts from the
previous phase remain historical snapshots until the redesign is complete.

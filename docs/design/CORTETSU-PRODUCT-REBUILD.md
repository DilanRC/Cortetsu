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

## Brightness contract

Brightness is a capability, not a display-name assumption. Cortetsu discovers
the real `brightnessctl` device with the `backlight` class, reads its maximum
range from `/sys/class/backlight/<device>/max_brightness`, normalizes the raw
value against that range, writes a clamped raw value, and reads it back. A
monitor without a discovered backlight reports unsupported instead of showing
`0%`. The current machine exposes `amdgpu_bl2` with a `0..65535` range.

## Quick Settings Drawer

QSD is a dedicated first-party layer named `cortetsu-qsd`, separate from the
BottomHub and transient OSD. The host layer remains allocated so the first open
does not race layer allocation; only the drawer content is transient. Its visual contract is a 400 px right-side drawer
with a Cortetsu header, live audio and notification controls, real brightness
and volume sliders, and network/Bluetooth status. The state belongs to the
canonical per-screen state, while `SUPER + /` owns the shortcut. The drawer
uses the shared 120/180/240 ms motion scale and is excluded from the legacy
panel host's focus-grab cleanup so opening its own layer cannot immediately
close it.

## Delivery order

The redesign is delivered in product slices: design foundation, real state
providers, BottomHub system cluster, QSD, schemes, Settings, Dashboard, Lock,
then the remaining surfaces and legacy visual cleanup. QA artifacts from the
previous phase remain historical snapshots until the redesign is complete.

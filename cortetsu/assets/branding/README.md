# Cortetsu identity

Cortetsu uses an angular **open C** paired with a separate chamfered **T**. The geometry is intentionally direct and mechanical: the C reads as a protective frame while the T reads as the steel working element inside it.

## Product palette

- Sumi `#0B0D10` — deepest shell surfaces and light-background mark
- Tetsu `#171B21` — raised dark surfaces
- Washi `#E7E0D5` — primary mark/foreground on dark surfaces
- Indigo `#334E68` — primary product accent
- Steel blue `#526D82` — branding-only companion accent derived from Indigo
- Vermillion `#D64B32` — danger/error only; never decorative branding
- Success `#7A9B83` — semantic success only
- Warning `#C49A62` — semantic warning only

`cortetsu-mark.svg` is the canonical shell mark and is optimized for Cortetsu's dark Sumi/Tetsu surfaces. It has a transparent background so it works from BottomHub-scale icons through Lock and Dashboard treatments without carrying a foreign icon tile.

Use `cortetsu-mark-dark.svg` on dark surfaces, `cortetsu-mark-light.svg` on light surfaces, and the monochrome variants only where surrounding UI state should own all colour. `cortetsu-app-icon.svg` is the standalone rounded application tile. Horizontal lockups are intended for About/documentation-sized treatments rather than compact shell controls.

The brand never uses Vermillion or success green decoratively; those colours remain reserved for product state.

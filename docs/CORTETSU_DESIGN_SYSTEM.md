# Cortetsu visual system

Cortetsu uses a restrained iron-and-washi palette: `colorSumi` is the desktop
void, `colorTetsu` is the base surface, `colorWashi` is primary text, indigo
is the interaction accent, and vermillion is reserved for attention and danger.

## Surface rules

- Use `CortetsuSurface` for every owned card, popup and interactive container.
- Use `CortetsuPopupHost` for surfaces that need a scrim, focus, Escape and
  outside-click dismissal. A popup must not implement a second focus policy.
- Use `colorSurfaceGlass` for floating controls and
  `colorSurfaceGlassStrong` for tracks and nested controls.
- Keep scrim opacity at or below `scrimOpacity` unless the surface is modal.

## Component rules

`CortetsuButton`, `CortetsuToggle`, `CortetsuSlider`, `CortetsuListRow`,
`CortetsuChoiceCard`, `CortetsuActionTile` and `CortetsuSectionHeader` define
the shared interaction states. They expose signals instead of reaching into
services, so a popup can bind them to the existing first-party backend without
coupling presentation and capability.

Every interactive component has a disabled state, hover state, pressed state,
and a visible selected/active state where applicable. `CortetsuButton`,
`CortetsuListRow`, `CortetsuChoiceCard` and `CortetsuActionTile` also opt into
tab focus and activate with Enter, Return or Space. `CortetsuActionTile`
additionally supports a status-only mode through `clickable: false`, preserving
the same visual state contract without claiming an unavailable backend action.
Popup hosts still own Escape and outside-click dismissal.

## Density and motion

The base grid is four pixels. Rows are 52 px, ordinary controls are 36 px, and
large surfaces use the 14/22 px radius pair. Motion is short and OutCubic:
content changes use fast motion, surface entry uses panel motion, and no visual
state depends on animation completing.

# Cortetsu Evolving Mark

Cortetsu's approved identity is the **Evolving Mark**: one soul taking five
deliberate forms through transformation under pressure. The phases are Human,
Awakening, Monster, Ascended, and Cosmic. Their silhouettes are separate assets,
extracted from the approved monochrome reference board.

## Asset contract

- `cortetsu-mark-human.svg` — contained potential and the idle state.
- `cortetsu-mark-awakening.svg` — interaction intent and adaptation.
- `cortetsu-mark-monster.svg` — active launcher or pressed action.
- `cortetsu-mark-ascended.svg` — refined canonical static mark.
- `cortetsu-mark-cosmic.svg` — rare completed transformation pulse.

`cortetsu-mark-ascended.svg` is the canonical static mark for the application,
documentation, About, Settings, Lock, and other non-live contexts. The old
`cortetsu-mark.svg` filename remains only as a compatibility copy of Ascended;
new consumers must name the phase explicitly.

`CortetsuEvolvingMark.qml` owns the live crossfade. It has fixed geometry,
receives an explicit phase, and owns no input surface. Consumers decide the phase
from their own real state. Cosmic is never the default or an idle animation.

The source symbols are monochrome so they survive at compact sizes. The renderer
can apply a private brand accent or a controlled monochrome colour, but the mark
does not redefine Indigo interaction, Vermillion danger, or green success roles.

The extraction source is the approved monochrome board supplied with the branding
direction on 2026-09-09. The reproducible crop command is kept in
`scripts/features/extract-cortetsu-evolving-assets.sh`.

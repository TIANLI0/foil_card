# foil_card

Foil trading-card effects for Flutter. The card art and its foil are drawn by
**one fragment shader in one pass**; the foil reacts to a light you move with
a finger.

```dart
FoilTilt(
  child: FoilCard(
    image: NetworkImage(card.artUrl),
    mask: NetworkImage(card.foilMaskUrl), // optional: where the foil is
    style: FoilStyle.glitter,
    borderRadius: BorderRadius.circular(16),
  ),
)
```

> Status: prototype, not yet published.

## Patterns

| pattern | what it is |
|---|---|
| `sheen` | brushed metal: fine streaks and a soft warm glare |
| `rainbow` | diffraction stripes fixed to the card; the light slides their colours and a band through the light carries most of the strength |
| `glitter` | a field of tiny tilted mirrors, each lighting up only when its own tilt lines up with the light |
| `cosmos` | domain-warped clouds that drift and change colour with the light, plus crisp star flakes |

`FoilStyle` also takes `intensity`, `scale` (pattern density) and `seed`
(vary the pattern between cards sharing a style — derive it from a card id).

## Foil masks

Real foil cards are not foil all over: often only the frame, or only the
illustration, is printed on foil. Pass a `mask` image — **white is foil**,
black or transparent is plain art — stretched over the whole card, so author
it at the card's aspect ratio. `invertMask: true` swaps the two (a "reverse"
foil). Without a mask the whole card is foil.

The foil stays off until the mask has loaded, instead of flashing over the
whole card first.

## Light

`FoilCard` takes its light from, in order: its `light` parameter (a
`ValueListenable<Offset>`, card centre `(0, 0)`, corners `(±1, ±1)`), the
nearest `FoilLight` above it, or its `restLight`.

`FoilTilt` is the ready-made source: press anywhere on the card and that side
sinks away while the light jumps to the finger; drag to sweep it; release and
both spring back. The angle comes from *where* the pointer is, not how far it
moved, so `FoilTilt` uses a raw `Listener` and never enters the gesture arena:
it does not compete with taps or scrolling around it.

Nothing animates on its own. With no pointer on the card the foil paints once
and stays put — a grid of foil cards costs nothing while idle. When the
platform asks to reduce motion, `FoilTilt` steps aside and cards hold their
resting light.

## Why one pass

The usual way to build this effect — on the web, in CSS — stacks several
full-card layers with `color-dodge` / `overlay` / `soft-light` blend modes and
filters. Ported to Flutter literally, every one of those layers reads back
what is already on screen: Impeller has to copy the backdrop for each advanced
blend, and under a perspective transform that copy can come back blurred or
over-bright for a frame, so the card flashes when you press it.

`foil_card` passes the art to the shader as a sampler and computes every blend
from the art's own pixels. There are no backdrop reads, no `saveLayer` and no
advanced blend modes: the result is stable under any transform, and costs the
same in a grid as on its own. Patterns are procedural, so the package ships no
textures.

Where the shader cannot be loaded, the art is painted plainly.

## Example

```sh
cd example
flutter run
```

The example paints its own demo card and mask at startup, so it carries no
image assets either.

## Provenance

Written from scratch. The idea of pointer-driven foil cards is common; no code,
shader, texture or asset from any other project was used.

## License

MIT

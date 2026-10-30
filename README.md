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

## Finishes

`FoilStyle` comes with ready-made finishes modelled on real trading-card
foils. Where the foil sits on the card is the mask's job (see below); the
"usually printed on" column is how these finishes appear on real cards.

| finish | what it looks like | usually printed on |
|---|---|---|
| `plain` | no foil, only the lamination's glare | — |
| `reverseHolo` | metallic foil stamped with a repeating motif whose edges catch the light | everything but the art window |
| `holo` | vertical rainbow pillars sliding sideways with the light, fine scratches and glints | the art window |
| `cosmos` | drifting galaxy clouds dodged into the art, crisp stars | the art window |
| `glitter` | dense, bright, multicoloured glitter | the whole card |
| `crosshatch` | a criss-cross lattice of shimmering lines, each family sliding its own way | the whole card |
| `iridescent` | a broad metallic rainbow with an iridescent ripple under the light | the whole card |
| `diagonal` | diagonal rainbow bands in two layers travelling against each other | the whole card |
| `fullArt` | `diagonal` over finely grooved lines | the whole card |
| `altArt` | `diagonal` over a whorl of grooves | the whole card |
| `textured` | slow, broad colour under a strongly embossed cell texture | the whole card |
| `softFullArt` | a paler, softer `fullArt` | the whole card |
| `rainbowGlitter` | a pastel rainbow wash thick with glitter | the whole card |
| `gold` | gold leaf and gold glitter sharing the card, glitter layers sliding against each other | the whole card |
| `silver` | whites turned to silver foil, brightening back under the light | the background |
| `sheen` | brushed metal | anywhere |
| `rainbow` | a single diffraction band following the light | anywhere |

They are combinations of a `FoilPattern` (13 of them) and an optional
`FoilTexture` (`lines`, `swirl`, `mesh`) etched into the foil, plus
`intensity`, `scale` (pattern density), `seed` (vary the pattern between
cards sharing a finish — derive it from a card id), `textureStrength` and
`glare`. Build your own with the constructor or `copyWith`.

Every blend a finish needs — soft-light, colour-dodge, hard-light, lighten,
multiply, exclusion — is computed inside the shader from the art's own
pixels, so none of them costs a layer.

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

`FoilTilt` is the ready-made source: touch anywhere on the card and it turns
while the light jumps to the pointer; drag to sweep it; release and both
spring back. With `FoilTiltResponse.lift` (the default) the side under the
pointer rises toward the viewer, as if the card turned to look at it; with
`FoilTiltResponse.press` it sinks away, as if pressed. The angle comes from *where* the pointer is, not how far it
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

Written from scratch. The visual targets were set by looking at real foil
cards and at the rendered output of public web demos of foil effects; no
source code of those demos was read, and no code, shader, texture or asset
from any other project was used. All textures are procedural.

## License

MIT

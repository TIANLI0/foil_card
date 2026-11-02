# foil_card

Holographic foil and flash-card effects for any Flutter image: trading cards,
membership cards, illustrations, covers and photographs. Give it one complete
image; it adds a procedural foil material in a single fragment shader pass,
with no textures to ship and no separate art/text layers.

```dart
SizedBox(
  width: 300,
  child: FoilCard(
    image: AssetImage('assets/card.png'),
    style: FoilStyle.twinkle,      // silver flash-card stars
    interactive: true,             // touch / hover tilt
    motion: const FoilMotion(),    // and the device gyroscope
    borderRadius: BorderRadius.circular(16),
  ),
)
```

- One shader pass that samples the art itself: no backdrop reads, no
  `saveLayer`, no advanced blend modes, so it stays stable under perspective
  transforms and costs the same in a grid as on its own.
- Lit by touch, mouse hover or the gyroscope; nothing animates while idle.
- Any aspect ratio. With a loose axis the layout follows the image's own ratio
  once loaded; `aspectRatio` reserves space up front, `fit` controls cropping.

## Finishes

| Style | Look |
|---|---|
| `FoilStyle.holographic` (default) | Rainbow film with a moving reflective band |
| `FoilStyle.glossy` | Clear lamination without recoloring the artwork |
| `FoilStyle.satin` | Soft brushed metallic material |
| `FoilStyle.glitter` | Reflective flakes |
| `FoilStyle.pearl` | Soft pink/cyan nacre for light artwork |
| `FoilStyle.prism` | Independently reflecting triangular facets |
| `FoilStyle.radial` | Optical-disc color fans and concentric grooves |
| `FoilStyle.ripple` | Wavy contours with traveling reflective crests |
| `FoilStyle.confetti` | Coarse, scattered diamond foil fragments |
| `FoilStyle.starfield` | Flat silver star print swept by one reflection band |
| `FoilStyle.heartfield` | Transparent heart print with a soft cool reflection |
| `FoilStyle.lightBeams` | Clear film with narrow moving light streaks |
| `FoilStyle.aurora` | Translucent teal/violet interference ribbons |
| `FoilStyle.twinkle` | Flash-card silver stars, each glinting at its own angle |
| `FoilStyle.twinkleHearts` | The same with hearts |
| `FoilStyle.cosmos` | Colored clouds with fine glitter |
| `FoilStyle.gold` / `silver` | Warm gold / cool brushed silver |
| `FoilStyle.holo` | Moving vertical rainbow pillars |

Every preset is a starting point: `FoilStyle.prism.copyWith(scale: 1.3,
seed: 42)`. `intensity` sets the foil strength and `glare` the separate
lamination highlight (set both to 0 for the untouched image). `opacity` blends
the material layer with the art without touching image alpha.
`detailProtection` (0–1, default .75) holds reflections back at high-contrast
edges and dark ink, which keeps text on flattened cards readable; it is local
contrast protection, not text or subject segmentation. `seed` varies a pattern
between cards that share a style; derive it from a stable card id.

## Flash-card glitter

`twinkle` prints motifs (stars or hearts) on a staggered grid. Each motif has
its own angle, so turning the card hands the glint from one to the next
instead of sweeping a band over the whole field. Tune it through
`FoilStyle.glints`:

```dart
FoilStyle.twinkle.copyWith(
  glints: FoilGlitter.stars.copyWith(density: .6, size: .25),
)
```

| `FoilGlitter` | What it does |
|---|---|
| `motif` | `star` (four-point, with cross rays) or `heart` |
| `density` | Share of grid places that carry a motif |
| `size` | Motif size relative to the grid spacing |
| `sharpness` | Glint width: low lights many softly, high gives brief flashes |
| `flare` | Cross rays (stars) or halo (hearts) while lit |
| `dust` | Fine glitter between the motifs |
| `color` | 0 silver-white glints; higher adds holographic color |
| `hue`, `iridescence` | Where that color starts, and how far the angle moves it |
| `print` | Visibility of the unlit motifs' silver print |
| `frame` | Keep motifs off the face area of a portrait (upper middle) |

The presets are plain silver and keep clear of the face.

## Masks and relief

`mask` decides where the foil is printed: white is foil, black or transparent
is plain art (`maskChannel: FoilMaskChannel.alpha` reads alpha instead,
`invertMask` swaps them). It is stretched over the card, and the foil stays
off until it has loaded rather than flashing over everything first.
`foilRegion` limits the foil to a normalized rectangle. `foil` is an optional
card-aligned texture whose luminance adds a subtle relief.

## Touch

`interactive: true` installs a `FoilTilt`: hover and touch tilt the card in
perspective and move the light, with smoothing, a springy return and a fade
(`idleOpacity` sets the resting strength). `FoilTiltResponse.lift` raises the
pointed edge, `press` sinks it. The first pointer owns the interaction; the
listener stays out of the gesture arena, so scrolling and taps around the card
keep working. With reduced motion the card stays still. Compose your own with
`FoilTilt(child: FoilCard(...))`, or drive the light yourself with `light` or
an enclosing `FoilLight`.

Light positions are normalized: `(0, 0)` is the center, `(±1, ±1)` the
corners. The light comes from `FoilCard.light`, else `FoilLight`, else
`restLight`.

## Device motion

`FoilCard(motion: const FoilMotion())`, or `FoilTilt(motion: ...)`, moves the
light as the phone is turned. Turning an edge toward the viewer brings the
light toward it, as a touch with `FoilTiltResponse.lift` does. Only the light
moves: the card is not tilted on screen, since the screen already turns with
the device.

The gyroscope gives turn rates, not a pose, so turns are integrated and
recentered (`recenter`, default 3 s): the light answers each turn, then
settles, and whatever pose the phone comes to rest in becomes neutral. Rates
under `deadZone` are ignored and the light stops once it has caught up, so a
still phone costs no frames. The sensor is read at 30 Hz (`samplingPeriod`)
and the light is interpolated every frame. `range` (0.3 rad, about 17°) is the
turn that takes the light to the edge.

The gyroscope is read only while the card is laid out in portrait, the app is
in the foreground, animations are enabled and the route is visible; a touch
takes the light over and hands it back on release. Inject `rotationRates` in
tests.

This uses [sensors_plus](https://pub.dev/packages/sensors_plus). On iOS the
app's `Info.plist` must contain `NSMotionUsageDescription`.

## Example

```sh
cd example
flutter run
```

The example opens on single images (portrait illustration, landscape
membership card, square cover) with every finish and its controls; **材质实验**
opens a generated card with all presets.

## License

MIT

## 0.0.1

* Prototype: `FoilCard` (one-pass foil shader over card art, optional foil
  mask), `FoilTilt` (pointer-driven tilt and light), `FoilLight`, and four
  patterns — sheen, rainbow, glitter, cosmos.
* Finishes modelled on real trading-card foils: `plain`, `reverseHolo`,
  `holo`, `cosmos`, `glitter`, `crosshatch`, `iridescent`, `diagonal`,
  `fullArt`, `altArt`, `textured`, `softFullArt`, `rainbowGlitter`, `gold`,
  `silver` (9 new `FoilPattern`s, new `FoilTexture`, `textureStrength`,
  `glare`).
* `FoilTilt.response`: `lift` (default, pointer side rises) or `press`.

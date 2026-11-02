## 0.1.0

First public release.

* `FoilCard`: a procedural foil material over any image in one fragment
  shader pass, with no textures to ship. Any aspect ratio; masks, relief
  texture and foil region are optional.
* Finishes: holographic, glossy, satin, glitter, pearl, prism, radial, ripple,
  confetti, starfield, heartfield, light beams, aurora, cosmos, gold, silver,
  holo pillars and more, each tunable through `FoilStyle.copyWith`
  (intensity, scale, seed, glare, opacity, detail protection, texture).
* `FoilStyle.twinkle` / `twinkleHearts`: flash-card stars or hearts that each
  glint at their own angle, tuned through `FoilGlitter` (density, size,
  sharpness, flare, dust, color, hue, iridescence, print, and `frame` to keep
  them off the face of a portrait).
* `FoilTilt`: touch and hover tilt with smoothed light, springy return and
  fade, outside the gesture arena.
* `FoilMotion`: the light follows the device gyroscope — only the light moves,
  turns recenter, a still phone costs no frames, and it pauses in the
  background, in landscape and on hidden routes.

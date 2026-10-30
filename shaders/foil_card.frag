#version 460 core

// foil_card — one-pass foil shader.
//
// The card art is a sampler, not a backdrop: every blend below is computed
// here from the art's own pixels, so nothing ever reads what is already on
// screen. That is what keeps the effect stable under a perspective tilt and
// cheap enough for a grid of cards (no saveLayer, no advanced blend modes,
// no backdrop copies).
//
// Coordinate space used throughout: `s`, centred on the card, where the
// card's shorter side spans exactly 1.0. Patterns are authored in it so a
// flake or a stripe is the same physical size on every card shape.

#include <flutter/runtime_effect.glsl>

precision highp float;

uniform vec2 uSize;             // card size in logical pixels
uniform vec2 uLight;            // light position on the card: centre 0, corners ±1
uniform vec4 uArtXform;         // art uv = card uv * xy + zw (BoxFit, computed in Dart)
uniform float uPattern;         // FoilPattern index
uniform float uIntensity;       // 0 = plain art, 1 = designed strength
uniform float uScale;           // pattern density multiplier
uniform float uSeed;            // per-card variation
uniform float uMaskMode;        // 0 none, 1 mask, 2 inverted mask
uniform float uTexture;         // FoilTexture index
uniform float uTextureStrength; // etched texture strength
uniform float uGlare;           // lamination glare strength

uniform sampler2D uArt;
uniform sampler2D uMask;

out vec4 fragColor;

const float TAU = 6.28318530718;

// Blend modes a pattern can ask for.
const float SOFT_LIGHT = 0.0;
const float DODGE = 1.0;
const float HARD_LIGHT = 2.0;
const float LIGHTEN = 3.0;
const float MULTIPLY = 4.0;

// --- hashing & noise -------------------------------------------------------

// Sine-free hashes (fract/dot mixing, in the spirit of Dave Hoskins'
// "hash without sine"): stable across GPUs where sin() loses precision for
// large arguments.
float hash12(vec2 p) {
  vec3 q = fract(vec3(p.x, p.y, p.x) * vec3(0.1371, 0.1427, 0.1197));
  q += dot(q, q.yzx + 41.17);
  return fract((q.x + q.y) * q.z);
}

vec2 hash22(vec2 p) {
  vec3 q = fract(vec3(p.x, p.y, p.x) * vec3(0.1371, 0.1427, 0.1197));
  q += dot(q, q.yzx + 41.17);
  return fract((q.xx + q.yz) * q.zy);
}

float valueNoise(vec2 p) {
  vec2 i = floor(p);
  vec2 f = fract(p);
  vec2 u = f * f * (3.0 - 2.0 * f);
  float a = hash12(i);
  float b = hash12(i + vec2(1.0, 0.0));
  float c = hash12(i + vec2(0.0, 1.0));
  float d = hash12(i + vec2(1.0, 1.0));
  return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float fbm(vec2 p) {
  float sum = 0.0;
  float amp = 0.5;
  for (int i = 0; i < 4; i++) {
    sum += amp * valueNoise(p);
    p = p * 2.03 + vec2(17.1, 9.7);
    amp *= 0.5;
  }
  return sum;
}

// 1 on integers, 0 halfway between: a sharp periodic ridge once raised to a
// power.
float tri(float x) {
  return 1.0 - abs(fract(x) - 0.5) * 2.0;
}

// --- colour ----------------------------------------------------------------

// A smooth hue wheel; t wraps every 1.0.
vec3 spectrum(float t) {
  return 0.5 + 0.5 * cos(TAU * (t + vec3(0.0, 0.33, 0.67)));
}

vec3 pastel(float t) {
  return mix(spectrum(t), vec3(1.0), 0.45);
}

// W3C compositing formulas, evaluated against the art we already hold.
vec3 softLight(vec3 b, vec3 s) {
  vec3 d = mix(sqrt(b), ((16.0 * b - 12.0) * b + 4.0) * b, step(b, vec3(0.25)));
  vec3 dark = b - (1.0 - 2.0 * s) * b * (1.0 - b);
  vec3 light = b + (2.0 * s - 1.0) * (d - b);
  return mix(dark, light, step(vec3(0.5), s));
}

vec3 colorDodge(vec3 b, vec3 s) {
  return min(vec3(1.0), b / max(vec3(1.0) - s, vec3(0.001)));
}

vec3 hardLight(vec3 b, vec3 s) {
  return mix(2.0 * b * s, 1.0 - 2.0 * (1.0 - b) * (1.0 - s), step(vec3(0.5), s));
}

vec3 blendWith(float mode, vec3 b, vec3 s) {
  if (mode < 0.5) return softLight(b, s);
  if (mode < 1.5) return colorDodge(b, s);
  if (mode < 2.5) return hardLight(b, s);
  if (mode < 3.5) return max(b, s);
  return b * s;
}

// --- lighting ----------------------------------------------------------------

// A point light hovering above the card, a viewer straight above it. Each
// surface element (the whole card, or one glitter flake) lights up when its
// normal lines up with the half vector between the two.
vec3 halfVectorAt(vec2 at, vec3 lightPos) {
  vec3 l = normalize(lightPos - vec3(at, 0.0));
  return normalize(l + vec3(0.0, 0.0, 1.0));
}

// Glitter: a jittered grid of tiny tilted mirrors. Each flake catches the
// light only when its own random tilt matches the local half vector, so the
// sparkle field changes completely as the light moves, instead of a fixed
// set of dots fading in and out.
//   cell      flake spacing in `s` units
//   sharpness specular exponent: higher = fewer, crisper flakes
//   colour    0 = white flakes, 1 = fully hued
//   size      flake radius relative to its cell
vec3 flakes(vec2 s, vec3 lightPos, float cell, float sharpness, float colour,
            float size) {
  vec2 g = s / cell;
  vec2 base = floor(g);
  vec3 acc = vec3(0.0);
  for (int j = -1; j <= 1; j++) {
    for (int i = -1; i <= 1; i++) {
      vec2 id = base + vec2(float(i), float(j)) + uSeed * 31.0;
      vec2 centre = base + vec2(float(i), float(j)) + 0.15 + 0.7 * hash22(id);
      float radius = (0.22 + 0.3 * hash12(id * 1.7)) * size;
      float shape = 1.0 - smoothstep(radius * 0.35, radius, length(g - centre));
      if (shape <= 0.0) continue;
      vec2 tilt = (hash22(id * 3.1 + 7.0) - 0.5) * 1.1;
      vec3 n = normalize(vec3(tilt, 1.0));
      float spec = pow(max(dot(n, halfVectorAt(centre * cell, lightPos)), 0.0), sharpness);
      vec3 hue = mix(vec3(1.0), spectrum(hash12(id * 5.3)), colour);
      acc += shape * spec * hue;
    }
  }
  return acc;
}

// --- patterns ----------------------------------------------------------------
// Every pattern answers the same four things:
//   tint   the foil's own colour
//   amt    how much of it is blended into the art
//   mode   how it is blended (one of the constants above)
//   shine  light added on top (what the foil reflects back)

// Brushed metal: fine streaks across the card, lit by the glare.
void sheen(vec2 s, vec2 frag, vec2 spot, vec3 lightPos, float glare, float hot,
           out vec3 tint, out float amt, out float mode, out vec3 shine) {
  float streak = valueNoise(vec2(s.x * 3.0, s.y * 90.0 * uScale) + uSeed * 13.0);
  vec3 warm = vec3(1.0, 0.97, 0.92);
  tint = warm;
  amt = 0.1 + 0.25 * glare;
  mode = SOFT_LIGHT;
  shine = warm * (glare * 0.2 + hot * 0.3) * (0.85 + 0.3 * streak);
}

// Diffraction stripes fixed to the card; the light slides the colours along
// them, and a band through the light spot carries most of the strength.
void rainbow(vec2 s, vec2 frag, vec2 spot, vec3 lightPos, float glare, float hot,
             out vec3 tint, out float amt, out float mode, out vec3 shine) {
  vec2 dir = normalize(vec2(0.45, 0.89));
  // A slow wobble keeps the bands from looking ruler-straight. (A second
  // periodic grating was tried here: it reads as a cheap zigzag.)
  float wobble = valueNoise(s * 5.0 + uSeed * 3.0) - 0.5;
  float phase = dot(s, dir) * 6.5 * uScale + wobble * 0.35
              + dot(uLight, vec2(0.55, 0.35)) + uSeed;
  // Pulled toward mid grey: soft-light against grey is a no-op, so this is
  // how saturated the foil's own colour gets.
  vec3 col = mix(vec3(0.5), spectrum(phase), 0.85);
  float across = dot(s - spot, dir);
  float band = exp(-across * across / 0.035);
  tint = col;
  amt = 0.08 + 0.5 * band * (0.5 + 0.5 * glare);
  mode = SOFT_LIGHT;
  shine = spectrum(phase) * band * glare * 0.12 + vec3(hot * 0.15);
}

// Dense, bright, colourful glitter that lightens wherever a flake catches
// the light, over a faint pastel sheen.
void glitter(vec2 s, vec2 frag, vec2 spot, vec3 lightPos, float glare, float hot,
             out vec3 tint, out float amt, out float mode, out vec3 shine) {
  vec3 coarse = flakes(s, lightPos, 0.016 / uScale, 90.0, 0.7, 1.0);
  vec3 fine = flakes(s + 1.3, lightPos, 0.009 / uScale, 160.0, 0.4, 0.8);
  vec3 sparkle = coarse + fine * 0.7;
  vec3 wash = pastel(dot(s, vec2(0.3, 0.7)) * 1.5 + uLight.x * 0.3 + uSeed);
  tint = sparkle * 1.4 + wash * 0.3 * glare;
  amt = 1.0;
  mode = LIGHTEN;
  shine = sparkle * 0.6 * (0.4 + glare) + vec3(hot * 0.12);
}

// Drifting clouds whose colours shift with the light, dodged into the art
// with a rainbow running across them, plus crisp star flakes.
void cosmos(vec2 s, vec2 frag, vec2 spot, vec3 lightPos, float glare, float hot,
            out vec3 tint, out float amt, out float mode, out vec3 shine) {
  vec2 q = s * 2.4 * uScale + uSeed * 7.0;
  vec2 warp = vec2(
    fbm(q + vec2(0.0, uLight.x * 0.3)),
    fbm(q + vec2(5.2, 1.3) + uLight.y * 0.3)
  );
  float n = fbm(q + 1.8 * warp);
  vec3 nebula = 0.5 + 0.5 * cos(TAU * (n * 1.3 + dot(uLight, vec2(0.22, 0.14))
                                      + vec3(0.58, 0.70, 0.88)));
  vec3 bow = spectrum(dot(s, vec2(0.5, 0.85)) * 1.2 + dot(uLight, vec2(0.6, 0.4)) + uSeed);
  float cloud = smoothstep(0.35, 0.75, n);
  tint = mix(bow, nebula, 0.6) * (0.35 + 0.5 * cloud);
  amt = 0.5 + 0.4 * glare;
  mode = DODGE;
  // Stars are small and crisp; full-size flakes read as out-of-focus bokeh.
  vec3 stars = flakes(s + 3.7, lightPos, 0.035 / uScale, 260.0, 0.25, 0.45);
  // The gaps between clouds sink a little, which is what gives them depth.
  shine = stars * 1.6 + nebula * cloud * (0.06 + 0.12 * glare)
        - vec3(0.08) * (1.0 - cloud) * glare;
}

// No foil, only the lamination's glare.
void glareOnly(vec2 s, vec2 frag, vec2 spot, vec3 lightPos, float glare, float hot,
               out vec3 tint, out float amt, out float mode, out vec3 shine) {
  tint = vec3(0.5);
  amt = 0.0;
  mode = SOFT_LIGHT;
  shine = vec3(1.0, 0.98, 0.95) * (glare * 0.1 + hot * 0.12);
}

// Height of the repeating embossed motif: a diamond outline with a dot in
// the middle, on a brick-offset grid.
float motif(vec2 p, float cell) {
  vec2 g = p / cell;
  g.x += 0.5 * mod(floor(g.y), 2.0);
  vec2 local = fract(g) - 0.5;
  float diamond = abs(local.x) + abs(local.y);
  float ring = 1.0 - smoothstep(0.0, 0.06, abs(diamond - 0.3));
  float pip = 1.0 - smoothstep(0.07, 0.12, length(local));
  return max(ring, pip);
}

// Metallic foil stamped with a repeating motif whose edges catch the light
// on the side facing it and fall into shadow on the other.
void etched(vec2 s, vec2 frag, vec2 spot, vec3 lightPos, float glare, float hot,
            out vec3 tint, out float amt, out float mode, out vec3 shine) {
  float cell = 0.085 / uScale;
  vec2 toLight = normalize(spot - s + vec2(0.0001));
  float h0 = motif(s, cell);
  float h1 = motif(s + toLight * cell * 0.06, cell);
  float rim = clamp((h1 - h0) * 3.0, -1.0, 1.0);
  vec3 foil = mix(vec3(0.8, 0.82, 0.88),
                  pastel(dot(s, vec2(0.4, 0.9)) * 1.4 + uLight.x * 0.5 + uSeed), 0.35);
  tint = foil * 0.45;
  amt = 0.25 + 0.5 * glare;
  mode = DODGE;
  // The stamp stays faintly legible at rest, like embossing does.
  shine = vec3(rim) * (0.15 + 0.35 * glare) + foil * h0 * (0.06 + 0.2 * glare);
}

// Vertical rainbow pillars that slide sideways with the light, with fine
// vertical scratches and a scatter of tiny glints.
void beam(vec2 s, vec2 frag, vec2 spot, vec3 lightPos, float glare, float hot,
          out vec3 tint, out float amt, out float mode, out vec3 shine) {
  float scratch = valueNoise(vec2(s.x * 140.0 * uScale, s.y * 2.5 + uSeed));
  float phase = s.x * 9.0 * uScale + uLight.x * 1.4 + uSeed + scratch * 0.15;
  vec3 col = pastel(phase);
  float pillar = 0.55 + 0.45 * sin(TAU * (s.x * 4.0 * uScale + uLight.x * 0.6));
  float dx = s.x - spot.x;
  float near = exp(-dx * dx / 0.06);
  tint = col * 0.55;
  amt = (0.15 + 0.55 * near) * pillar;
  mode = DODGE;
  shine = col * near * glare * 0.12 * (0.6 + 0.8 * scratch)
        + flakes(s, lightPos, 0.02 / uScale, 220.0, 0.6, 0.5) * 0.8;
}

// Two families of fine diagonal lines crossing at right angles, each
// sliding its own way with the light; the crossings flare.
void crosshatch(vec2 s, vec2 frag, vec2 spot, vec3 lightPos, float glare, float hot,
                out vec3 tint, out float amt, out float mode, out vec3 shine) {
  float f = 11.0 * uScale;
  float a = pow(tri(dot(s, vec2(0.7071, 0.7071)) * f + dot(uLight, vec2(0.5, 0.5))), 6.0);
  float b = pow(tri(dot(s, vec2(0.7071, -0.7071)) * f + dot(uLight, vec2(0.5, -0.5))), 6.0);
  float lines = max(a, b);
  vec3 col = pastel(dot(s, vec2(0.3, 0.8)) * 1.5 + dot(uLight, vec2(0.4, 0.3)) + uSeed);
  tint = col * 0.6;
  amt = lines * (0.15 + 0.5 * glare);
  mode = DODGE;
  shine = vec3(0.9, 0.95, 1.0) * (lines * 0.12 + a * b * 0.3) * glare;
}

// A broad, slow metallic rainbow over the whole card, with an iridescent
// ripple shimmering out from under the light.
void iridescent(vec2 s, vec2 frag, vec2 spot, vec3 lightPos, float glare, float hot,
                out vec3 tint, out float amt, out float mode, out vec3 shine) {
  vec2 dir = normalize(vec2(0.8, 0.6));
  vec3 broad = spectrum(dot(s, dir) * 1.1 + dot(uLight, vec2(0.7, 0.5)) + uSeed);
  tint = mix(vec3(0.5), broad, 0.6) * 0.75;
  amt = 0.35 + 0.2 * glare;
  mode = DODGE;
  float d = length(s - spot);
  shine = (pastel(d * 4.0 - uLight.x * 0.5) - 0.5) * glare * 0.35 + vec3(hot * 0.15);
}

// Diagonal rainbow bands in two layers that travel in opposite directions as
// the light moves, over a faint film grain.
void diagonal(vec2 s, vec2 frag, vec2 spot, vec3 lightPos, float glare, float hot,
              out vec3 tint, out float amt, out float mode, out vec3 shine) {
  vec2 dir = vec2(0.7071, 0.7071);
  float along = dot(s, dir);
  float drift = dot(uLight, vec2(0.9, 0.6));
  vec3 col = (spectrum(along * 5.0 * uScale + drift + uSeed)
            + spectrum(along * 7.0 * uScale - drift + uSeed * 1.7)) * 0.5;
  float across = dot(s - spot, dir);
  float band = exp(-across * across / 0.06);
  float grain = hash12(floor(frag)) - 0.5;
  tint = clamp(col * 0.7 + grain * 0.08, 0.0, 1.0);
  amt = 0.15 + 0.45 * band;
  mode = DODGE;
  shine = col * band * glare * 0.1 + vec3(hot * 0.12);
}

// A pastel rainbow wash over the whole card, thick with glitter.
void rainbowGlitter(vec2 s, vec2 frag, vec2 spot, vec3 lightPos, float glare, float hot,
                    out vec3 tint, out float amt, out float mode, out vec3 shine) {
  vec2 dir = normalize(vec2(0.6, 0.8));
  tint = pastel(dot(s, dir) * 1.6 + dot(uLight, vec2(0.6, 0.3)) + uSeed);
  amt = 0.45 + 0.15 * glare;
  mode = HARD_LIGHT;
  vec3 sparkle = flakes(s, lightPos, 0.013 / uScale, 70.0, 0.35, 1.0)
               + flakes(s + 2.1, lightPos, 0.008 / uScale, 120.0, 0.2, 0.9) * 0.6;
  shine = sparkle * 1.3 + vec3(hot * 0.1);
}

// Gold leaf and gold glitter sharing the card: a soft diagonal boundary
// decides which one each area is, and two glitter layers slide against
// each other as the light moves.
void gold(vec2 s, vec2 frag, vec2 spot, vec3 lightPos, float glare, float hot,
          out vec3 tint, out float amt, out float mode, out vec3 shine) {
  vec3 dark = vec3(0.66, 0.48, 0.16);
  vec3 light = vec3(1.0, 0.9, 0.55);
  float leaf = smoothstep(-0.5, 0.5, dot(s, normalize(vec2(1.0, -0.6)))
                                     + valueNoise(s * 3.0 + uSeed) * 0.6 - 0.3);
  tint = mix(dark, light, glare);
  amt = (0.35 + 0.35 * glare) * (0.5 + 0.5 * leaf);
  mode = HARD_LIGHT;
  vec3 a = flakes(s + uLight * 0.04, lightPos, 0.014 / uScale, 80.0, 0.0, 1.0);
  vec3 b = flakes(s - uLight * 0.04 + 4.2, lightPos, 0.011 / uScale, 110.0, 0.0, 0.9);
  shine = (a + b) * light * 1.5 * (1.0 - 0.7 * leaf) + light * hot * 0.12;
}

// Silver foil: whites turn to brushed silver, brightening back under the
// light in soft rings.
void silver(vec2 s, vec2 frag, vec2 spot, vec3 lightPos, float glare, float hot,
            out vec3 tint, out float amt, out float mode, out vec3 shine) {
  float d = length(s - spot);
  float lift = clamp(glare * 1.2 + 0.15 * sin(d * 18.0 - uLight.x * 2.0), 0.0, 1.0);
  tint = mix(vec3(0.6, 0.62, 0.67), vec3(1.0), lift);
  amt = 0.55;
  mode = MULTIPLY;
  shine = pastel(d * 3.0 + uSeed) * glare * 0.08
        + flakes(s, lightPos, 0.02 / uScale, 200.0, 0.1, 0.6) * 0.8;
}

// --- etched texture ----------------------------------------------------------
// An optional surface texture pressed into the foil, independent of the
// pattern. 0 = none; otherwise how much etching there is at `s`, 0..1.

float etching(vec2 s) {
  if (uTexture < 0.5) return 0.0;
  if (uTexture < 1.5) {
    // Fine parallel lines.
    return smoothstep(0.75, 1.0, tri(dot(s, vec2(0.7071, 0.7071)) * 70.0 * uScale));
  }
  if (uTexture < 2.5) {
    // A whorl of grooves around an off-centre point.
    vec2 p = s - (vec2(0.18, -0.22) + (hash22(vec2(uSeed + 0.5)) - 0.5) * 0.3);
    float r = length(p);
    float a = atan(p.y, p.x);
    return smoothstep(0.7, 1.0, tri(r * 45.0 * uScale + a * 0.6));
  }
  // Hexagonal cells.
  vec2 g = s * 22.0 * uScale;
  vec2 r = vec2(1.0, 1.7320508);
  vec2 h = r * 0.5;
  vec2 a = mod(g, r) - h;
  vec2 b = mod(g - h, r) - h;
  vec2 q = abs(dot(a, a) < dot(b, b) ? a : b);
  float edge = max(dot(q, vec2(0.5, 0.8660254)), q.x);
  return smoothstep(0.42, 0.5, edge);
}

// --- main --------------------------------------------------------------------

void main() {
  vec2 frag = FlutterFragCoord().xy;
  vec2 uv = frag / uSize;
  float unit = min(uSize.x, uSize.y);
  vec2 s = (frag - 0.5 * uSize) / unit;
  vec2 spot = uLight * 0.5 * uSize / unit;

  vec4 art = texture(uArt, uv * uArtXform.xy + uArtXform.zw);
  if (art.a <= 0.0) {
    fragColor = vec4(0.0);
    return;
  }
  vec3 base = art.rgb / art.a; // samplers are premultiplied

  float mask = 1.0;
  if (uMaskMode > 0.5) {
    // White = foil. Premultiplied red works for both white-on-black and
    // white-on-transparent masks.
    mask = texture(uMask, uv).r;
    if (uMaskMode > 1.5) mask = 1.0 - mask;
  }

  float d = length(s - spot);
  float glare = exp(-d * d / 0.16);
  float hot = exp(-d * d / 0.01);
  vec3 lightPos = vec3(spot, 0.9);

  vec3 tint = vec3(0.5);
  float amt = 0.0;
  float mode = SOFT_LIGHT;
  vec3 shine = vec3(0.0);
  if (uPattern < 0.5) {
    sheen(s, frag, spot, lightPos, glare, hot, tint, amt, mode, shine);
  } else if (uPattern < 1.5) {
    rainbow(s, frag, spot, lightPos, glare, hot, tint, amt, mode, shine);
  } else if (uPattern < 2.5) {
    glitter(s, frag, spot, lightPos, glare, hot, tint, amt, mode, shine);
  } else if (uPattern < 3.5) {
    cosmos(s, frag, spot, lightPos, glare, hot, tint, amt, mode, shine);
  } else if (uPattern < 4.5) {
    glareOnly(s, frag, spot, lightPos, glare, hot, tint, amt, mode, shine);
  } else if (uPattern < 5.5) {
    etched(s, frag, spot, lightPos, glare, hot, tint, amt, mode, shine);
  } else if (uPattern < 6.5) {
    beam(s, frag, spot, lightPos, glare, hot, tint, amt, mode, shine);
  } else if (uPattern < 7.5) {
    crosshatch(s, frag, spot, lightPos, glare, hot, tint, amt, mode, shine);
  } else if (uPattern < 8.5) {
    iridescent(s, frag, spot, lightPos, glare, hot, tint, amt, mode, shine);
  } else if (uPattern < 9.5) {
    diagonal(s, frag, spot, lightPos, glare, hot, tint, amt, mode, shine);
  } else if (uPattern < 10.5) {
    rainbowGlitter(s, frag, spot, lightPos, glare, hot, tint, amt, mode, shine);
  } else if (uPattern < 11.5) {
    gold(s, frag, spot, lightPos, glare, hot, tint, amt, mode, shine);
  } else {
    silver(s, frag, spot, lightPos, glare, hot, tint, amt, mode, shine);
  }

  float k = mask * uIntensity;
  vec3 blended = blendWith(mode, base, clamp(tint, 0.0, 1.0));
  vec3 result = mix(base, blended, clamp(amt * k, 0.0, 1.0));
  result += shine * k;

  // Etching shows mostly where the light catches it, and shifts hue with
  // the angle. It is excluded into the foil (b + s - 2bs), so grooves read
  // as a change in the foil rather than as lines painted on top.
  float etch = etching(s);
  if (etch > 0.0) {
    vec3 groove = pastel(dot(s, vec2(0.6, 0.8)) * 2.0 + dot(uLight, vec2(0.8, 0.5)))
                * etch * 0.6;
    vec3 excluded = result + groove - 2.0 * result * groove;
    float vis = uTextureStrength * (0.12 + 0.88 * glare) * k;
    result = mix(result, excluded, clamp(vis, 0.0, 1.0));
  }

  // The lamination is glossy everywhere, foil or not.
  result += vec3(1.0, 0.98, 0.95) * (hot * 0.18 + glare * 0.04) * uGlare;

  fragColor = vec4(clamp(result, 0.0, 1.0) * art.a, art.a);
}

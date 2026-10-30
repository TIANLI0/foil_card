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

uniform vec2 uSize;       // card size in logical pixels
uniform vec2 uLight;      // light position on the card: centre 0, corners ±1
uniform vec4 uArtXform;   // art uv = card uv * xy + zw (BoxFit, computed in Dart)
uniform float uPattern;   // FoilPattern index
uniform float uIntensity; // 0 = plain art, 1 = designed strength
uniform float uScale;     // pattern density multiplier
uniform float uSeed;      // per-card variation
uniform float uMaskMode;  // 0 none, 1 mask, 2 inverted mask

uniform sampler2D uArt;
uniform sampler2D uMask;

out vec4 fragColor;

const float TAU = 6.28318530718;

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

// --- colour ----------------------------------------------------------------

// A smooth hue wheel; t wraps every 1.0.
vec3 spectrum(float t) {
  return 0.5 + 0.5 * cos(TAU * (t + vec3(0.0, 0.33, 0.67)));
}

// W3C compositing "soft-light", evaluated against the art we already hold.
vec3 softLight(vec3 b, vec3 s) {
  vec3 d = mix(sqrt(b), ((16.0 * b - 12.0) * b + 4.0) * b, step(b, vec3(0.25)));
  vec3 dark = b - (1.0 - 2.0 * s) * b * (1.0 - b);
  vec3 light = b + (2.0 * s - 1.0) * (d - b);
  return mix(dark, light, step(vec3(0.5), s));
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
// Each pattern answers two things:
//   tint/tintAmt  a colour soft-lit into the art (the foil's own colour)
//   shine         light added on top (what the foil reflects back)

void sheen(vec2 s, vec2 spot, float glare, float hot,
           out vec3 tint, out float tintAmt, out vec3 shine) {
  // Brushed metal: fine streaks across the card, lit by the glare.
  float streak = valueNoise(vec2(s.x * 3.0, s.y * 90.0 * uScale) + uSeed * 13.0);
  vec3 warm = vec3(1.0, 0.97, 0.92);
  tint = warm;
  tintAmt = 0.1 + 0.25 * glare;
  shine = warm * (glare * 0.2 + hot * 0.3) * (0.85 + 0.3 * streak);
}

void rainbow(vec2 s, vec2 spot, float glare, float hot,
             out vec3 tint, out float tintAmt, out vec3 shine) {
  // Diffraction stripes fixed to the card; the light slides the colours
  // along them, and a band through the light spot carries most of the
  // strength, so the rest of the art stays readable.
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
  tintAmt = 0.08 + 0.5 * band * (0.5 + 0.5 * glare);
  shine = spectrum(phase) * band * glare * 0.12 + vec3(hot * 0.15);
}

void glitter(vec2 s, vec3 lightPos, float glare, float hot,
             out vec3 tint, out float tintAmt, out vec3 shine) {
  vec3 sparkle = flakes(s, lightPos, 0.022 / uScale, 140.0, 0.55, 1.0);
  tint = spectrum(dot(s, vec2(0.3, 0.7)) * 1.5 + uLight.x * 0.3 + uSeed);
  tintAmt = 0.1 + 0.15 * glare;
  shine = sparkle * 1.5 + vec3(hot * 0.12);
}

void cosmos(vec2 s, vec3 lightPos, float glare, float hot,
            out vec3 tint, out float tintAmt, out vec3 shine) {
  // Domain-warped clouds; the light shifts both the warp and the palette,
  // so the nebula drifts and changes colour as the card turns.
  vec2 q = s * 2.4 * uScale + uSeed * 7.0;
  vec2 warp = vec2(
    fbm(q + vec2(0.0, uLight.x * 0.3)),
    fbm(q + vec2(5.2, 1.3) + uLight.y * 0.3)
  );
  float n = fbm(q + 1.8 * warp);
  vec3 col = 0.5 + 0.5 * cos(TAU * (n * 1.3 + dot(uLight, vec2(0.22, 0.14))
                                   + vec3(0.58, 0.70, 0.88)));
  float cloud = smoothstep(0.35, 0.75, n);
  tint = col;
  tintAmt = (0.5 + 0.4 * glare) * cloud;
  // Stars are small and crisp; full-size flakes read as out-of-focus bokeh.
  vec3 stars = flakes(s + 3.7, lightPos, 0.035 / uScale, 260.0, 0.25, 0.45);
  shine = stars * 1.6 + col * cloud * (0.1 + 0.25 * glare);
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
  float tintAmt = 0.0;
  vec3 shine = vec3(0.0);
  if (uPattern < 0.5) {
    sheen(s, spot, glare, hot, tint, tintAmt, shine);
  } else if (uPattern < 1.5) {
    rainbow(s, spot, glare, hot, tint, tintAmt, shine);
  } else if (uPattern < 2.5) {
    glitter(s, lightPos, glare, hot, tint, tintAmt, shine);
  } else {
    cosmos(s, lightPos, glare, hot, tint, tintAmt, shine);
  }

  float k = mask * uIntensity;
  vec3 result = mix(base, softLight(base, tint), clamp(tintAmt * k, 0.0, 1.0));
  result += shine * k;
  // The lamination is glossy everywhere, foil or not: a faint highlight
  // under the light keeps unmasked areas from reading as matte paper.
  result += vec3(1.0, 0.98, 0.95) * hot * 0.08 * uIntensity;

  fragColor = vec4(clamp(result, 0.0, 1.0) * art.a, art.a);
}

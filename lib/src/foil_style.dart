import 'package:flutter/foundation.dart';

/// The foil printed on the card.
///
/// The order is part of the shader contract (the index is passed as a
/// uniform); append new patterns, never reorder.
enum FoilPattern {
  /// Brushed metal: fine streaks and a soft warm glare.
  sheen,

  /// Diffraction stripes whose colours slide as the light moves.
  rainbow,

  /// Dense, bright, colourful glitter that lightens wherever a flake
  /// catches the light.
  glitter,

  /// Drifting coloured clouds with a scatter of star flakes.
  cosmos,

  /// No foil at all: only the lamination's glare.
  glare,

  /// Metallic foil stamped with a repeating motif whose edges catch the
  /// light.
  etched,

  /// Vertical rainbow pillars sliding sideways with the light.
  beam,

  /// Two families of fine diagonal lines crossing, each sliding its own way.
  crosshatch,

  /// A broad metallic rainbow with an iridescent shimmer under the light.
  iridescent,

  /// Diagonal rainbow bands in two layers travelling in opposite directions.
  diagonal,

  /// A pastel rainbow wash thick with glitter.
  rainbowGlitter,

  /// Gold leaf and gold glitter sharing the card.
  gold,

  /// Whites turned to silver foil, brightening back under the light.
  silver,

  /// Soft pink/cyan nacre.
  pearl,

  /// Triangular facets reflecting different colors as the light moves.
  prism,

  /// Concentric diffraction grooves, like the surface of a compact disc.
  radial,

  /// Undulating reflective contours.
  ripple,

  /// Large scattered angular foil pieces.
  confetti,

  /// Flat silver four-point foil print with a traveling reflection band.
  starfield,

  /// Translucent heart print revealed by a moving cool reflection.
  heartfield,

  /// Thin luminous streaks traveling over a clear film.
  lightBeams,

  /// Broad translucent teal/violet ribbons.
  aurora,

  /// Flash-card glitter: printed stars or hearts ([FoilGlitter]), each with
  /// its own angle, so different ones light up as the card turns rather than
  /// the whole field under one band (compare [starfield]).
  twinkle,
}

/// A surface texture pressed into the foil, on top of any [FoilPattern].
///
/// It shows mostly where the light catches it. The order is part of the
/// shader contract; append, never reorder.
enum FoilTexture {
  none,

  /// Fine parallel grooves.
  lines,

  /// A whorl of grooves around an off-centre point.
  swirl,

  /// Staggered embossed cells.
  mesh,
}

/// Shape printed by [FoilPattern.twinkle]. The order is part of the shader
/// contract; append, never reorder.
enum FoilGlitterMotif { star, heart }

/// Controls for [FoilPattern.twinkle]. Every other pattern ignores them.
///
/// Motifs (stars or hearts — only the shape differs) are printed on a
/// staggered grid and each glints at its own angle.
///
/// The color follows the viewing angle ([hue] plus the light position, scaled
/// by [iridescence]), with a small spread between motifs, so the visible ones
/// share a hue family instead of scattering random colors. How many motifs
/// there are is [density] here and the grid spacing [FoilStyle.scale];
/// [frame] keeps them out of the middle of the card, where a portrait's
/// subject usually is.
@immutable
class FoilGlitter {
  const FoilGlitter({
    this.motif = FoilGlitterMotif.star,
    this.density = .45,
    this.size = .2,
    this.sharpness = .4,
    this.flare = .85,
    this.dust = .18,
    this.color = 0,
    this.hue = 0,
    this.iridescence = .5,
    this.print = .2,
    this.frame = 0,
  })  : assert(density >= 0 && density <= 1),
        assert(size > 0 && size <= .45),
        assert(sharpness >= 0 && sharpness <= 1),
        assert(flare >= 0 && flare <= 1),
        assert(dust >= 0 && dust <= 1),
        assert(color >= 0 && color <= 1),
        assert(iridescence >= 0 && iridescence <= 1),
        assert(print >= 0 && print <= 1),
        assert(frame >= 0 && frame <= 1);

  /// Plain silver four-point stars with long thin rays, no color, few lit at
  /// a time, over sparse dust, kept off the face of a portrait.
  static const stars = FoilGlitter(frame: 1);

  /// The stars' twin with heart shapes: crisp silver hearts, each flashing at
  /// its own angle, kept off the face of a portrait.
  static const hearts = FoilGlitter(
    motif: FoilGlitterMotif.heart,
    // Denser than the stars: the face area is left empty, and quick glints
    // light fewer at a time.
    density: .6,
    size: .2,
    // Quick, clean flashes and no halo: a heart lingering half lit, or
    // haloed, reads as a blur rather than a printed shape.
    sharpness: .7,
    flare: 0,
    dust: 0,
    print: .1,
    frame: 1,
  );

  final FoilGlitterMotif motif;

  /// Share of grid places that carry a motif, 0–1.
  final double density;

  /// Motif radius as a share of the grid spacing, up to 0.45.
  final double size;

  /// How brief each glint is: 0 lights many motifs at once and softly, 1
  /// gives few, quick flashes.
  final double sharpness;

  /// Cross rays (stars) or halo (hearts) while a motif is lit, 0–1.
  final double flare;

  /// Fine glitter dust between the motifs, 0 (none) to 1.
  final double dust;

  /// 0 glints silver-white, 1 in full laser color.
  final double color;

  /// Where on the spectrum the glints start; any value, wraps at 1.
  final double hue;

  /// How far turning the card moves the color along the spectrum: 0 keeps
  /// [hue], 1 travels about one and a half rainbows from corner to corner.
  final double iridescence;

  /// How visible the motifs' silver print is when not lit, 0–1.
  final double print;

  /// How strictly motifs keep clear of where a portrait's face and head
  /// usually are (the upper middle of the card): 0 anywhere, 1 never there.
  final double frame;

  FoilGlitter copyWith({
    FoilGlitterMotif? motif,
    double? density,
    double? size,
    double? sharpness,
    double? flare,
    double? dust,
    double? color,
    double? hue,
    double? iridescence,
    double? print,
    double? frame,
  }) =>
      FoilGlitter(
        motif: motif ?? this.motif,
        density: density ?? this.density,
        size: size ?? this.size,
        sharpness: sharpness ?? this.sharpness,
        flare: flare ?? this.flare,
        dust: dust ?? this.dust,
        color: color ?? this.color,
        hue: hue ?? this.hue,
        iridescence: iridescence ?? this.iridescence,
        print: print ?? this.print,
        frame: frame ?? this.frame,
      );

  @override
  bool operator ==(Object other) =>
      other is FoilGlitter &&
      other.motif == motif &&
      other.density == density &&
      other.size == size &&
      other.sharpness == sharpness &&
      other.flare == flare &&
      other.dust == dust &&
      other.color == color &&
      other.hue == hue &&
      other.iridescence == iridescence &&
      other.print == print &&
      other.frame == frame;

  @override
  int get hashCode => Object.hash(motif, density, size, sharpness, flare, dust,
      color, hue, iridescence, print, frame);

  @override
  String toString() => 'FoilGlitter(${motif.name}, density: $density, '
      'size: $size, sharpness: $sharpness, flare: $flare, dust: $dust, '
      'color: $color, hue: $hue, iridescence: $iridescence, print: $print, '
      'frame: $frame)';
}

/// How the foil is applied.
///
/// The named constructors-as-constants below reproduce the finishes found on
/// real trading cards; combine them with a mask on [FoilCard] to decide
/// where on the card the foil sits (the art window, the frame, or all of
/// it).
@immutable
class FoilStyle {
  const FoilStyle({
    this.pattern = FoilPattern.rainbow,
    this.intensity = 1,
    this.scale = 1,
    this.seed = 0,
    this.texture = FoilTexture.none,
    this.textureStrength = 1,
    this.glare = 1,
    this.detailProtection = 0.75,
    this.opacity = 1,
    this.glints = FoilGlitter.stars,
  })  : assert(intensity >= 0, 'intensity must not be negative'),
        assert(scale > 0, 'scale must be positive'),
        assert(textureStrength >= 0, 'textureStrength must not be negative'),
        assert(glare >= 0, 'glare must not be negative'),
        assert(detailProtection >= 0 && detailProtection <= 1),
        assert(opacity >= 0 && opacity <= 1);

  /// A restrained holographic finish for a single flattened image.
  static const holographic = FoilStyle(
    pattern: FoilPattern.diagonal,
    intensity: .65,
    glare: .45,
  );

  /// Clear glossy lamination, preserving the original image colors.
  static const glossy = FoilStyle(pattern: FoilPattern.glare, glare: .6);

  /// A soft metallic finish for photographs, illustrations and membership cards.
  static const satin =
      FoilStyle(pattern: FoilPattern.sheen, intensity: .5, glare: .3);

  /// Subtle nacre, suited to light artwork and wedding/membership cards.
  static const pearl =
      FoilStyle(pattern: FoilPattern.pearl, intensity: .85, glare: .35);

  /// Broken triangular holographic facets.
  static const prism =
      FoilStyle(pattern: FoilPattern.prism, intensity: .9, glare: .3);

  /// Radial laser diffraction with concentric grooves.
  static const radial =
      FoilStyle(pattern: FoilPattern.radial, intensity: .85, glare: .35);

  /// Flowing, embossed water-like contours.
  static const ripple =
      FoilStyle(pattern: FoilPattern.ripple, intensity: .85, glare: .4);

  /// Coarse, individually reflective foil fragments.
  static const confetti =
      FoilStyle(pattern: FoilPattern.confetti, intensity: .9, glare: .3);

  /// Flat silver star print, revealed by a shared moving reflection band.
  static const starfield = FoilStyle(
      pattern: FoilPattern.starfield, intensity: .9, glare: .25, opacity: .62);

  /// Transparent hearts, with a single cool tint rather than random colors.
  static const heartfield = FoilStyle(
      pattern: FoilPattern.heartfield, intensity: .9, glare: .25, opacity: .6);

  /// Clear film with narrow, moving white/cyan light streaks.
  static const lightBeams = FoilStyle(
      pattern: FoilPattern.lightBeams, intensity: .9, glare: .2, opacity: .6);

  /// Transparent broad aurora ribbons, preserving the image underneath.
  static const aurora = FoilStyle(
      pattern: FoilPattern.aurora, intensity: .9, glare: .2, opacity: .55);

  /// Flash-card star glitter: every star glints at its own angle. A film
  /// effect, so dark ink is barely protected. Tune it through [glints].
  static const twinkle = FoilStyle(
      pattern: FoilPattern.twinkle,
      intensity: 1.35,
      scale: .85,
      glare: .15,
      detailProtection: .2);

  /// Flash-card hearts: [twinkle] with [FoilGlitter.hearts].
  static const twinkleHearts = FoilStyle(
      pattern: FoilPattern.twinkle,
      intensity: 1.35,
      scale: .85,
      glare: .15,
      detailProtection: .2,
      glints: FoilGlitter.hearts);

  /// A plain card: no foil, just the glare of the lamination.
  static const plain = FoilStyle(pattern: FoilPattern.glare);

  /// Brushed metal.
  static const sheen = FoilStyle(pattern: FoilPattern.sheen);

  /// A diffraction rainbow band that follows the light.
  static const rainbow = FoilStyle();

  /// Bright multicoloured glitter.
  static const glitter = FoilStyle(pattern: FoilPattern.glitter);

  /// Galaxy clouds and stars.
  static const cosmos = FoilStyle(pattern: FoilPattern.cosmos);

  /// The classic holo: vertical rainbow pillars. Usually printed on the art
  /// window only.
  static const holo = FoilStyle(pattern: FoilPattern.beam);

  /// Embossed metallic foil. Usually printed everywhere *except* the art
  /// window ("reverse holo"): pair it with an inverted mask.
  static const reverseHolo = FoilStyle(pattern: FoilPattern.etched);

  /// A criss-cross lattice of shimmering lines.
  static const crosshatch = FoilStyle(pattern: FoilPattern.crosshatch);

  /// A metallic rainbow with an iridescent shimmer.
  static const iridescent = FoilStyle(pattern: FoilPattern.iridescent);

  /// Diagonal rainbow bands travelling against each other.
  static const diagonal = FoilStyle(pattern: FoilPattern.diagonal);

  /// Diagonal bands over a finely grooved surface, for cards whose art
  /// covers the whole face.
  static const fullArt = FoilStyle(
    pattern: FoilPattern.diagonal,
    texture: FoilTexture.lines,
  );

  /// Like [fullArt] with a whorled texture.
  static const altArt = FoilStyle(
    pattern: FoilPattern.diagonal,
    texture: FoilTexture.swirl,
  );

  /// Broad, slow diagonal colour under a strongly embossed cell texture.
  static const textured = FoilStyle(
    pattern: FoilPattern.diagonal,
    intensity: 0.6,
    scale: 0.6,
    texture: FoilTexture.mesh,
    textureStrength: 1.4,
  );

  /// A softer, paler [fullArt].
  static const softFullArt = FoilStyle(
    pattern: FoilPattern.diagonal,
    intensity: 0.65,
    texture: FoilTexture.lines,
    textureStrength: 0.6,
  );

  /// Pastel rainbow with heavy glitter.
  static const rainbowGlitter = FoilStyle(pattern: FoilPattern.rainbowGlitter);

  /// Gold leaf and gold glitter.
  static const gold = FoilStyle(pattern: FoilPattern.gold);

  /// Silver foil.
  static const silver = FoilStyle(pattern: FoilPattern.silver);

  final FoilPattern pattern;

  /// Foil strength: 0 removes foil; 1 is the designed strength.
  /// Lamination [glare] is independent.
  final double intensity;

  /// Pattern density: above 1 packs more stripes / flakes / clouds into the
  /// same card.
  final double scale;

  /// Varies the pattern between cards that share a style, so a row of
  /// glitter cards does not sparkle in lockstep. Any value works; derive it
  /// from a stable card id.
  final double seed;

  final FoilTexture texture;

  /// How deep the [texture] reads.
  final double textureStrength;

  /// Strength of the lamination's glare, which covers the whole card
  /// whether or not it is foil.
  final double glare;

  /// Attenuate reflections around high-contrast image edges and very dark
  /// ink. 0 disables protection; 1 is strongest. This is local contrast
  /// protection, not text/subject segmentation.
  final double detailProtection;

  /// Material layer opacity, independent of [glare]. At 0 the foil
  /// disappears; at 1 the designed material is fully applied. Image alpha
  /// stays unchanged.
  final double opacity;

  /// Motif glitter controls; only [FoilPattern.twinkle] reads them. (Not
  /// named `glitter`: that is the [FoilStyle.glitter] preset.)
  final FoilGlitter glints;

  FoilStyle copyWith({
    FoilPattern? pattern,
    double? intensity,
    double? scale,
    double? seed,
    FoilTexture? texture,
    double? textureStrength,
    double? glare,
    double? detailProtection,
    double? opacity,
    FoilGlitter? glints,
  }) =>
      FoilStyle(
        pattern: pattern ?? this.pattern,
        intensity: intensity ?? this.intensity,
        scale: scale ?? this.scale,
        seed: seed ?? this.seed,
        texture: texture ?? this.texture,
        textureStrength: textureStrength ?? this.textureStrength,
        glare: glare ?? this.glare,
        detailProtection: detailProtection ?? this.detailProtection,
        opacity: opacity ?? this.opacity,
        glints: glints ?? this.glints,
      );

  @override
  bool operator ==(Object other) =>
      other is FoilStyle &&
      other.pattern == pattern &&
      other.intensity == intensity &&
      other.scale == scale &&
      other.seed == seed &&
      other.texture == texture &&
      other.textureStrength == textureStrength &&
      other.glare == glare &&
      other.detailProtection == detailProtection &&
      other.opacity == opacity &&
      other.glints == glints;

  @override
  int get hashCode => Object.hash(
        pattern,
        intensity,
        scale,
        seed,
        texture,
        textureStrength,
        glare,
        detailProtection,
        opacity,
        glints,
      );

  @override
  String toString() => 'FoilStyle(${pattern.name}, intensity: $intensity, '
      'scale: $scale, seed: $seed, texture: ${texture.name}, '
      'textureStrength: $textureStrength, glare: $glare, '
      'detailProtection: $detailProtection, opacity: $opacity, '
      'glints: $glints)';
}

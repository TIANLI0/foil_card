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

  /// Hexagonal cells.
  mesh,
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
  })  : assert(intensity >= 0, 'intensity must not be negative'),
        assert(scale > 0, 'scale must be positive'),
        assert(textureStrength >= 0, 'textureStrength must not be negative'),
        assert(glare >= 0, 'glare must not be negative');

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

  /// 0 shows the plain art; 1 is the designed strength.
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

  FoilStyle copyWith({
    FoilPattern? pattern,
    double? intensity,
    double? scale,
    double? seed,
    FoilTexture? texture,
    double? textureStrength,
    double? glare,
  }) =>
      FoilStyle(
        pattern: pattern ?? this.pattern,
        intensity: intensity ?? this.intensity,
        scale: scale ?? this.scale,
        seed: seed ?? this.seed,
        texture: texture ?? this.texture,
        textureStrength: textureStrength ?? this.textureStrength,
        glare: glare ?? this.glare,
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
      other.glare == glare;

  @override
  int get hashCode => Object.hash(
        pattern,
        intensity,
        scale,
        seed,
        texture,
        textureStrength,
        glare,
      );

  @override
  String toString() => 'FoilStyle(${pattern.name}, intensity: $intensity, '
      'scale: $scale, seed: $seed, texture: ${texture.name}, '
      'textureStrength: $textureStrength, glare: $glare)';
}

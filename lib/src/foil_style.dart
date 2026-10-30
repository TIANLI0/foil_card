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

  /// A field of tiny tilted mirrors, each catching the light at its own angle.
  glitter,

  /// Drifting coloured clouds with a scatter of star flakes.
  cosmos,
}

/// How a [FoilPattern] is applied.
@immutable
class FoilStyle {
  const FoilStyle({
    this.pattern = FoilPattern.rainbow,
    this.intensity = 1,
    this.scale = 1,
    this.seed = 0,
  })  : assert(intensity >= 0, 'intensity must not be negative'),
        assert(scale > 0, 'scale must be positive');

  static const sheen = FoilStyle(pattern: FoilPattern.sheen);
  static const rainbow = FoilStyle();
  static const glitter = FoilStyle(pattern: FoilPattern.glitter);
  static const cosmos = FoilStyle(pattern: FoilPattern.cosmos);

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

  FoilStyle copyWith({
    FoilPattern? pattern,
    double? intensity,
    double? scale,
    double? seed,
  }) =>
      FoilStyle(
        pattern: pattern ?? this.pattern,
        intensity: intensity ?? this.intensity,
        scale: scale ?? this.scale,
        seed: seed ?? this.seed,
      );

  @override
  bool operator ==(Object other) =>
      other is FoilStyle &&
      other.pattern == pattern &&
      other.intensity == intensity &&
      other.scale == scale &&
      other.seed == seed;

  @override
  int get hashCode => Object.hash(pattern, intensity, scale, seed);

  @override
  String toString() => 'FoilStyle(${pattern.name}, intensity: $intensity, '
      'scale: $scale, seed: $seed)';
}

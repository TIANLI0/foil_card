import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'foil_light.dart';
import 'foil_style.dart';

/// How an image determines foil coverage: by its brightness, or by its alpha
/// (for masks drawn as transparent cut-outs).
enum FoilMaskChannel { luminance, alpha }

/// Maps card uv to art uv for [fit], centred: `art = card * (x, y) + (z, w)`.
///
/// Pure so it can be pinned by tests; the shader receives the four numbers
/// as one vec4.
@visibleForTesting
(double, double, double, double) foilArtTransform(
  Size image,
  Size card,
  BoxFit fit,
) {
  final fitted = applyBoxFit(fit, image, card);
  final dst = Alignment.center.inscribe(fitted.destination, Offset.zero & card);
  final src = Alignment.center.inscribe(fitted.source, Offset.zero & image);
  final sx = src.width / dst.width;
  final sy = src.height / dst.height;
  return (
    card.width * sx / image.width,
    card.height * sy / image.height,
    (src.left - dst.left * sx) / image.width,
    (src.top - dst.top * sy) / image.height,
  );
}

/// A card whose art carries a foil that reacts to light.
///
/// The art and the foil are drawn by one fragment shader in one pass. The
/// shader reads the art from its own sampler instead of from the screen, so
/// the effect has no backdrop reads, no `saveLayer` and no advanced blend
/// modes: it stays stable under a perspective [Transform] (see [FoilTilt])
/// and costs the same in a grid as on its own.
///
/// Light comes from [light], else from the nearest [FoilLight] above (which
/// [FoilTilt] provides), else it rests at [restLight]. Nothing animates on
/// its own: with no pointer on the card the foil paints once and stays put.
///
/// Where the shader cannot be loaded the art is painted plainly.
class FoilCard extends StatefulWidget {
  const FoilCard({
    required this.image,
    this.style = FoilStyle.holographic,
    this.interactive = false,
    this.motion,
    this.idleOpacity = .5,
    this.aspectRatio,
    this.mask,
    this.maskChannel = FoilMaskChannel.luminance,
    this.foilRegion = const Rect.fromLTRB(0, 0, 1, 1),
    this.foil,
    this.invertMask = false,
    this.light,
    this.restLight = const Offset(-0.35, -0.45),
    this.fit = BoxFit.cover,
    this.borderRadius = BorderRadius.zero,
    this.filterQuality = FilterQuality.medium,
    this.semanticLabel,
    this.placeholder,
    this.child,
    super.key,
  })  : assert(aspectRatio == null ||
            (aspectRatio > 0 && aspectRatio < double.infinity)),
        assert(idleOpacity >= 0 && idleOpacity <= 1);

  /// The card art.
  final ImageProvider image;

  final FoilStyle style;

  /// Supplies hover/touch tilt automatically when no external light or
  /// enclosing FoilTilt is present.
  final bool interactive;

  /// Moves the light as the device is turned (see [FoilMotion]). Works with
  /// or without [interactive]; like it, ignored when the light comes from
  /// [light] or an enclosing [FoilLight], which then owns the light.
  final FoilMotion? motion;
  final double idleOpacity;

  /// Optional layout ratio. With one unconstrained axis, the image's own
  /// aspect ratio is used once loaded; bounded parent sizes remain respected.
  final double? aspectRatio;

  /// Where the foil is printed: white is foil, black (or transparent) is
  /// plain art. Stretched over the whole card, so author it at the card's
  /// aspect ratio. Without a mask the foil covers the whole card.
  ///
  /// The foil stays off until the mask has loaded rather than flashing over
  /// the whole card first.
  final ImageProvider? mask;
  final FoilMaskChannel maskChannel;

  /// Normalized card rectangle containing the foil.
  final Rect foilRegion;

  /// Optional card-aligned texture whose luminance adds a subtle relief to
  /// the foil. No texture is needed.
  final ImageProvider? foil;

  /// Prints the foil where the [mask] is black instead ("reverse holo").
  final bool invertMask;

  /// Light position on the card: centre (0, 0), corners (±1, ±1).
  final ValueListenable<Offset>? light;

  /// Where the light sits when no light source is attached.
  final Offset restLight;

  /// How the art is inscribed into the card.
  final BoxFit fit;

  final BorderRadius borderRadius;

  /// Sampling quality for the art and mask.
  final FilterQuality filterQuality;

  final String? semanticLabel;

  /// Shown until the art has loaded.
  final Widget? placeholder;

  /// Painted over the foil (names, stats, frame text...).
  final Widget? child;

  static Future<ui.FragmentProgram?>? _program;

  /// Loads the shader once for the whole app. Resolves to null when this
  /// platform cannot compile it; cards then paint the art plainly.
  static Future<ui.FragmentProgram?> _loadProgram() => _program ??= () async {
        try {
          // As a dependency the asset is namespaced under the package; in
          // this package's own tests it is a root asset.
          try {
            return await ui.FragmentProgram.fromAsset(
                'packages/foil_card/shaders/foil_surface.frag');
          } on Exception {
            return await ui.FragmentProgram.fromAsset(
                'shaders/foil_surface.frag');
          }
        } on Object catch (error, stack) {
          FlutterError.reportError(FlutterErrorDetails(
              exception: error,
              stack: stack,
              library: 'foil_card',
              context: ErrorDescription(
                  'loading the foil shader; cards will paint without foil')));
          return null;
        }
      }();

  /// Starts loading the shader ahead of the first card, so that card does
  /// not paint one frame without foil.
  static Future<void> precacheShader() async {
    await _loadProgram();
  }

  @override
  State<FoilCard> createState() => _FoilCardState();
}

class _FoilCardState extends State<FoilCard> {
  late final _ImageSlot _art = _ImageSlot(_changed);
  late final _ImageSlot _mask = _ImageSlot(_changed);
  late final _ImageSlot _foil = _ImageSlot(_changed);
  ui.FragmentShader? _shader;

  @override
  void initState() {
    super.initState();
    _loadShader();
  }

  Future<void> _loadShader() async {
    final program = await FoilCard._loadProgram();
    if (!mounted || program == null) return;
    setState(() {
      _shader?.dispose();
      _shader = program.fragmentShader();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolve();
  }

  @override
  void didUpdateWidget(FoilCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.image != widget.image ||
        oldWidget.mask != widget.mask ||
        oldWidget.foil != widget.foil) {
      _resolve();
    }
  }

  @override
  void dispose() {
    _art.dispose();
    _mask.dispose();
    _foil.dispose();
    _shader?.dispose();
    super.dispose();
  }

  void _resolve() {
    final config = createLocalImageConfiguration(context);
    _art.resolve(widget.image, config);
    _mask.resolve(widget.mask, config);
    _foil.resolve(widget.foil, config);
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    Widget card = Builder(builder: _buildCard);
    if ((widget.interactive || widget.motion != null) &&
        widget.light == null &&
        FoilLight.maybeOf(context) == null) {
      card = FoilTilt(
          idleOpacity: widget.idleOpacity,
          restLight: widget.restLight,
          motion: widget.motion,
          touch: widget.interactive,
          child: card);
    }
    return LayoutBuilder(builder: (context, constraints) {
      final art = _art.image;
      final ratio =
          widget.aspectRatio ?? (art == null ? 5 / 7 : art.width / art.height);
      if (!constraints.hasBoundedWidth && !constraints.hasBoundedHeight) {
        return SizedBox(
            width: art == null ? 300 : art.width / _art.scale,
            child: AspectRatio(aspectRatio: ratio, child: card));
      }
      if (widget.aspectRatio != null ||
          !constraints.hasTightWidth ||
          !constraints.hasTightHeight) {
        return AspectRatio(aspectRatio: ratio, child: card);
      }
      return card;
    });
  }

  Widget _buildCard(BuildContext context) {
    final art = _art.image;
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final light =
        reduceMotion ? null : widget.light ?? FoilLight.maybeOf(context);
    final activity = reduceMotion || widget.light != null
        ? null
        : FoilLight.activityOf(context);

    Widget face;
    if (art == null) {
      face = widget.placeholder ?? const SizedBox.expand();
    } else {
      final maskPending = widget.mask != null && _mask.image == null;
      face = RepaintBoundary(
        child: CustomPaint(
          painter: _FoilPainter(
            shader: _shader,
            pixelRatio: MediaQuery.maybeDevicePixelRatioOf(context) ?? 1,
            art: art,
            mask: _mask.image,
            foil: _foil.image,
            maskMode: widget.mask == null ? 0 : (widget.invertMask ? 2 : 1),
            maskChannel: widget.maskChannel,
            foilRegion: widget.foilRegion,
            style: maskPending
                ? widget.style.copyWith(intensity: 0)
                : widget.style,
            light: light,
            activity: activity,
            restLight: widget.restLight,
            fit: widget.fit,
            filterQuality: widget.filterQuality,
          ),
          child: const SizedBox.expand(),
        ),
      );
    }

    Widget card = widget.child == null
        ? face
        : Stack(fit: StackFit.expand, children: [face, widget.child!]);
    if (widget.borderRadius != BorderRadius.zero) {
      card = ClipRRect(borderRadius: widget.borderRadius, child: card);
    }
    if (widget.semanticLabel != null) {
      card = Semantics(image: true, label: widget.semanticLabel, child: card);
    }
    return card;
  }
}

class _FoilPainter extends CustomPainter {
  _FoilPainter({
    required this.shader,
    required this.pixelRatio,
    required this.art,
    required this.mask,
    required this.foil,
    required this.maskMode,
    required this.maskChannel,
    required this.foilRegion,
    required this.style,
    required this.light,
    required this.activity,
    required this.restLight,
    required this.fit,
    required this.filterQuality,
  }) : super(repaint: Listenable.merge([light, activity]));

  final ui.FragmentShader? shader;
  final double pixelRatio;
  final ui.Image art;
  final ui.Image? mask;
  final ui.Image? foil;
  final int maskMode;
  final FoilMaskChannel maskChannel;
  final Rect foilRegion;
  final FoilStyle style;
  final ValueListenable<Offset>? light;
  final ValueListenable<double>? activity;
  final Offset restLight;
  final BoxFit fit;
  final FilterQuality filterQuality;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final rect = Offset.zero & size;
    final shader = this.shader;
    if (shader == null) {
      paintImage(
        canvas: canvas,
        rect: rect,
        image: art,
        fit: fit,
        filterQuality: filterQuality,
      );
      return;
    }

    final (ax, ay, az, aw) = foilArtTransform(
      Size(art.width.toDouble(), art.height.toDouble()),
      size,
      fit,
    );
    final l = light?.value ?? restLight;
    var i = 0;
    final glints = style.glints;
    shader
      // Order must match the uniform declarations in foil_surface.frag.
      ..setFloat(i++, size.width)
      ..setFloat(i++, size.height)
      ..setFloat(i++, l.dx.isFinite ? l.dx.clamp(-1, 1).toDouble() : 0)
      ..setFloat(i++, l.dy.isFinite ? l.dy.clamp(-1, 1).toDouble() : 0)
      ..setFloat(i++, ax)
      ..setFloat(i++, ay)
      ..setFloat(i++, az)
      ..setFloat(i++, aw)
      ..setFloat(i++, style.pattern.index.toDouble())
      ..setFloat(i++, style.intensity)
      ..setFloat(i++, style.scale)
      ..setFloat(i++, style.seed)
      ..setFloat(i++, maskMode.toDouble())
      ..setFloat(i++, style.texture.index.toDouble())
      ..setFloat(i++, style.textureStrength)
      ..setFloat(i++, style.glare)
      ..setFloat(i++, activity?.value ?? 1)
      ..setFloat(i++, foil == null ? 0 : 1)
      ..setFloat(i++, pixelRatio)
      ..setFloat(i++, maskChannel.index.toDouble())
      ..setFloat(i++, foilRegion.left)
      ..setFloat(i++, foilRegion.top)
      ..setFloat(i++, foilRegion.right)
      ..setFloat(i++, foilRegion.bottom)
      ..setImageSampler(0, art, filterQuality: filterQuality)
      // An unused sampler still has to be bound; the art stands in.
      ..setImageSampler(1, mask ?? art, filterQuality: filterQuality)
      ..setImageSampler(2, foil ?? art, filterQuality: filterQuality)
      ..setFloat(i++, style.detailProtection)
      ..setFloat(i++, style.opacity)
      // uGlitterA, uGlitterB, uGlitterC.
      ..setFloat(i++, glints.density)
      ..setFloat(i++, glints.size)
      ..setFloat(i++, glints.sharpness)
      ..setFloat(i++, glints.flare)
      ..setFloat(i++, glints.dust)
      ..setFloat(i++, glints.color)
      ..setFloat(i++, glints.print)
      ..setFloat(i++, glints.hue)
      ..setFloat(i++, glints.motif.index.toDouble())
      ..setFloat(i++, glints.iridescence)
      ..setFloat(i++, glints.frame);
    canvas.drawRect(rect, Paint()..shader = shader);
  }

  @override
  bool shouldRepaint(_FoilPainter old) =>
      old.shader != shader ||
      old.pixelRatio != pixelRatio ||
      old.art != art ||
      old.mask != mask ||
      old.foil != foil ||
      old.maskMode != maskMode ||
      old.maskChannel != maskChannel ||
      old.foilRegion != foilRegion ||
      old.style != style ||
      old.light != light ||
      old.activity != activity ||
      old.restLight != restLight ||
      old.fit != fit ||
      old.filterQuality != filterQuality;
}

/// Resolves one [ImageProvider] and keeps its current frame.
class _ImageSlot {
  _ImageSlot(this.onChanged);

  final VoidCallback onChanged;
  ImageStream? _stream;
  ImageInfo? _info;
  late final ImageStreamListener _listener = ImageStreamListener(
    (info, _) => _set(info),
    onError: (error, stack) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'foil_card',
          context: ErrorDescription('resolving a foil card image'),
        ),
      );
    },
  );

  ui.Image? get image => _info?.image;
  double get scale => _info?.scale ?? 1;

  void resolve(ImageProvider? provider, ImageConfiguration config) {
    final next = provider?.resolve(config);
    if (next != null && _stream?.key == next.key) return;
    _stream?.removeListener(_listener);
    // Never keep a previous card's mask/relief while a new image is loading.
    // In particular a pending mask must suppress foil, not expose stale foil.
    if (_info != null) _set(null);
    _stream = next?..addListener(_listener);
  }

  void _set(ImageInfo? info) {
    _info?.dispose();
    _info = info;
    onChanged();
  }

  void dispose() {
    _stream?.removeListener(_listener);
    _info?.dispose();
    _info = null;
  }
}

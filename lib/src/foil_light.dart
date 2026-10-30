import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Where on a card a pointer is, as a light position: card centre (0, 0),
/// corners (±1, ±1), clamped to the card.
Offset foilPointAt(Offset local, Size size) => Offset(
      (local.dx / size.width * 2 - 1).clamp(-1.0, 1.0),
      (local.dy / size.height * 2 - 1).clamp(-1.0, 1.0),
    );

/// Publishes a light source to every `FoilCard` below it.
///
/// The light is a [ValueListenable] rather than a value so that moving the
/// light repaints the foil without rebuilding anything: dependants are only
/// notified when the listenable itself is swapped.
class FoilLight extends InheritedWidget {
  const FoilLight({required this.light, required super.child, super.key});

  /// Light position on the card: centre (0, 0), corners (±1, ±1).
  final ValueListenable<Offset> light;

  static ValueListenable<Offset>? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<FoilLight>()?.light;

  @override
  bool updateShouldNotify(FoilLight oldWidget) =>
      !identical(light, oldWidget.light);
}

/// Which way a card turns under the pointer.
enum FoilTiltResponse {
  /// The side under the pointer rises toward the viewer, as if the card
  /// were turned to look at the pointer. Natural for a mouse hovering.
  lift,

  /// The side under the pointer sinks away, as if pressed. Natural for a
  /// finger.
  press,
}

/// Tilts its child under the pointer and moves the foil light with it.
///
/// Touch anywhere on the card: that side turns (see [response]) and the
/// light jumps to the pointer; drag to sweep it; let go and both settle
/// back. The angle comes
/// from *where* the pointer is, not how far it moved, so the gesture needs no
/// drag recognizer: it never enters the gesture arena and never competes with
/// taps or scrolling around it. A scroll that starts on the card still
/// scrolls; the tilt simply follows the pointer meanwhile.
///
/// When the platform asks to reduce motion, the child is returned as is and
/// cards fall back to their resting light.
class FoilTilt extends StatefulWidget {
  const FoilTilt({
    required this.child,
    this.maxTilt = 0.22,
    this.restLight = const Offset(-0.35, -0.45),
    this.settleDuration = const Duration(milliseconds: 450),
    this.perspective = 0.0012,
    this.response = FoilTiltResponse.lift,
    super.key,
  });

  final Widget child;

  final FoilTiltResponse response;

  /// Rotation, in radians, with the finger on an edge.
  final double maxTilt;

  /// Where the light rests when nobody touches the card.
  final Offset restLight;

  /// How long the card takes to settle after release.
  final Duration settleDuration;

  /// Strength of the perspective (Matrix4 entry 3,2).
  final double perspective;

  @override
  State<FoilTilt> createState() => _FoilTiltState();
}

class _FoilTiltState extends State<FoilTilt>
    with SingleTickerProviderStateMixin {
  late final ValueNotifier<Offset> _light = ValueNotifier(widget.restLight);
  final ValueNotifier<Offset> _press = ValueNotifier(Offset.zero);
  late final AnimationController _settle = AnimationController(
    vsync: this,
    duration: widget.settleDuration,
  )..addListener(_onSettle);

  Offset _lightFrom = Offset.zero;
  Offset _pressFrom = Offset.zero;

  @override
  void didUpdateWidget(FoilTilt oldWidget) {
    super.didUpdateWidget(oldWidget);
    _settle.duration = widget.settleDuration;
    if (oldWidget.restLight != widget.restLight && !_settle.isAnimating) {
      if (_press.value == Offset.zero) _light.value = widget.restLight;
    }
  }

  @override
  void dispose() {
    _settle.dispose();
    _light.dispose();
    _press.dispose();
    super.dispose();
  }

  void _onSettle() {
    final t = _settle.value;
    // The tilt overshoots a little, like a card springing back; the light
    // just glides home.
    _press.value = Offset.lerp(
      _pressFrom,
      Offset.zero,
      Curves.easeOutBack.transform(t),
    )!;
    _light.value = Offset.lerp(
      _lightFrom,
      widget.restLight,
      Curves.easeOutCubic.transform(t),
    )!;
  }

  void _point(Offset local) {
    final size = context.size;
    if (size == null || size.isEmpty) return;
    _settle.stop();
    final p = foilPointAt(local, size);
    _press.value = p;
    _light.value = p;
  }

  void _release() {
    _pressFrom = _press.value;
    _lightFrom = _light.value;
    _settle.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      return widget.child;
    }
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (e) => _point(e.localPosition),
      onPointerMove: (e) => _point(e.localPosition),
      onPointerUp: (_) => _release(),
      onPointerCancel: (_) => _release(),
      child: ValueListenableBuilder<Offset>(
        valueListenable: _press,
        builder: (context, p, child) {
          // With a press, a positive x turns the right edge away from the
          // viewer and a positive y the bottom edge; a lift is the mirror.
          final a = widget.maxTilt *
              (widget.response == FoilTiltResponse.press ? 1 : -1);
          return Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..setEntry(3, 2, widget.perspective)
              ..rotateX(p.dy * a)
              ..rotateY(-p.dx * a),
            child: child,
          );
        },
        child: FoilLight(light: _light, child: widget.child),
      ),
    );
  }
}

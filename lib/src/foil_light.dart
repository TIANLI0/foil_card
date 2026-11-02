import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:sensors_plus/sensors_plus.dart';

/// Where on a card a pointer is, as a light position: card centre (0, 0),
/// corners (±1, ±1), clamped to the card.
Offset foilPointAt(Offset local, Size size) => size.isEmpty
    ? Offset.zero
    : Offset(
        (local.dx / size.width * 2 - 1).clamp(-1.0, 1.0),
        (local.dy / size.height * 2 - 1).clamp(-1.0, 1.0),
      );

/// Publishes a light source to every `FoilCard` below it.
///
/// The light is a [ValueListenable] rather than a value so that moving the
/// light repaints the foil without rebuilding anything: dependants are only
/// notified when the listenable itself is swapped.
class FoilLight extends InheritedWidget {
  const FoilLight(
      {required this.light, this.activity, required super.child, super.key});

  /// Light position on the card: centre (0, 0), corners (±1, ±1).
  final ValueListenable<Offset> light;

  /// Visibility of the reflection, from 0 (idle) to 1 (interacting).
  /// Omit to keep an externally controlled light always visible.
  final ValueListenable<double>? activity;

  static ValueListenable<double>? activityOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<FoilLight>()?.activity;

  static ValueListenable<Offset>? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<FoilLight>()?.light;

  @override
  bool updateShouldNotify(FoilLight oldWidget) =>
      !identical(light, oldWidget.light) ||
      !identical(activity, oldWidget.activity);
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

/// One gyroscope sample: how fast the device turns, in radians per second,
/// around its x axis (pointing right along the screen) and its y axis
/// (pointing up along the screen), and when it was measured.
typedef FoilRotationRate = ({double x, double y, Duration time});

/// Moves a card's light as the device is turned, read from the gyroscope.
///
/// Only the light moves. The card is not tilted on screen: the screen
/// already turns with the device, and turning the card on it as well would
/// double the motion.
///
/// A gyroscope reports how fast the device turns, not how it is held. The
/// turn is integrated and leaks back to zero with the time constant
/// [recenter]: the light answers each turn and then settles, and whatever
/// pose the device comes to rest in becomes the neutral one. So the resting
/// look does not depend on how someone happens to hold the phone, and sensor
/// drift cannot accumulate.
///
/// Nothing repaints while the device is still: rates within [deadZone] are
/// ignored and the light stops once it has caught up. The sensor is sampled
/// at [samplingPeriod] and the light is interpolated every frame, so motion
/// stays smooth on high refresh rate screens without sampling at that rate.
///
/// Turning an edge toward the viewer brings the light toward that edge, as a
/// touch does with [FoilTiltResponse.lift].
///
/// The gyroscope is only read while the card is laid out in portrait (device
/// axes are not remapped for landscape), the app is in the foreground,
/// animations are enabled, and the card's route is not hidden
/// ([TickerMode]). Where there is no gyroscope the light simply stays put.
///
/// On iOS the app's `Info.plist` must contain `NSMotionUsageDescription`;
/// sensors_plus requires it.
@immutable
class FoilMotion {
  const FoilMotion({
    this.range = .3,
    this.recenter = const Duration(seconds: 3),
    this.deadZone = .02,
    this.samplingPeriod = const Duration(milliseconds: 33),
    this.rotationRates,
  })  : assert(range > 0),
        assert(deadZone >= 0);

  /// Turn, in radians, that carries the light from its rest to an edge of
  /// the card. The default is about 17°.
  final double range;

  /// Time constant with which the pose the device is held in becomes the
  /// neutral one. [Duration.zero] keeps the first pose as neutral for good
  /// (sensor drift then accumulates).
  final Duration recenter;

  /// Rotation rate, in rad/s, below which the device counts as still.
  final double deadZone;

  /// How often the gyroscope is read.
  final Duration samplingPeriod;

  /// Rotation rates to follow instead of the device gyroscope, for tests and
  /// for apps that already own a motion stream.
  final Stream<FoilRotationRate>? rotationRates;

  Stream<FoilRotationRate> get _rates =>
      rotationRates ??
      gyroscopeEventStream(samplingPeriod: samplingPeriod).map((e) => (
            x: e.x,
            y: e.y,
            time: Duration(microseconds: e.timestamp.microsecondsSinceEpoch),
          ));

  @override
  bool operator ==(Object other) =>
      other is FoilMotion &&
      other.range == range &&
      other.recenter == recenter &&
      other.deadZone == deadZone &&
      other.samplingPeriod == samplingPeriod &&
      identical(other.rotationRates, rotationRates);

  @override
  int get hashCode => Object.hash(range, recenter, deadZone, samplingPeriod,
      identityHashCode(rotationRates));
}

/// Integrates [FoilMotion] rotation rates into an offset of the light.
///
/// Pure arithmetic, separated from [FoilTilt] so it can be tested sample by
/// sample.
@visibleForTesting
class FoilMotionIntegrator {
  FoilMotionIntegrator(this.motion);

  final FoilMotion motion;

  /// Longest gap integrated across. A longer one means the stream was paused
  /// or samples were dropped, and the rate before it says nothing about it.
  static const maxStep = Duration(milliseconds: 100);

  /// Below this the turn snaps to zero, so recentering ends instead of
  /// creeping toward zero forever (and repainting all the way).
  static const _snap = .004;

  Offset _turn = Offset.zero;
  Duration? _last;

  /// The light's offset from its rest, in card units: ±1 reaches an edge.
  /// Up to ±1.5 so that a turn beyond [FoilMotion.range] holds the light at
  /// the edge for a moment instead of bouncing straight back.
  Offset get offset => _turn / motion.range;

  void add(FoilRotationRate rate) {
    final last = _last;
    _last = rate.time;
    if (last == null) return;
    final micros = (rate.time - last).inMicroseconds;
    if (micros <= 0) return;
    final dt = math.min(micros, maxStep.inMicroseconds) / 1e6;
    final tau = motion.recenter.inMicroseconds / 1e6;
    final leak = tau > 0 ? math.exp(-dt / tau) : 1.0;
    final limit = motion.range * 1.5;
    final rx = _beyondDeadZone(rate.x);
    final ry = _beyondDeadZone(rate.y);
    // Turning about +y moves the right edge away from the viewer, so the
    // light goes left; turning about +x brings the top edge toward the viewer,
    // so the light goes up (screen y grows downward).
    final turn = Offset(
      (_turn.dx * leak - ry * dt).clamp(-limit, limit),
      (_turn.dy * leak - rx * dt).clamp(-limit, limit),
    );
    // Snap only while still: a slow turn adds less than the snap per sample
    // and would otherwise never get going.
    final still = rx == 0 && ry == 0;
    _turn = still && turn.distance / motion.range < _snap ? Offset.zero : turn;
  }

  /// The dead zone is subtracted rather than gated, so a turn starting from
  /// rest grows from zero instead of jumping by the dead zone's width.
  double _beyondDeadZone(double rate) {
    final excess = rate.abs() - motion.deadZone;
    return excess <= 0 ? 0 : excess * rate.sign;
  }

  void reset() {
    _turn = Offset.zero;
    _last = null;
  }
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
/// With [motion], turning the device moves the light as well (see
/// [FoilMotion]). A touch takes the light over while it lasts; on release
/// the light settles back to where the device's turn puts it.
///
/// When the platform asks to reduce motion, the child is returned as is and
/// cards fall back to their resting light.
class FoilTilt extends StatefulWidget {
  const FoilTilt({
    required this.child,
    this.maxTilt = 0.24933,
    this.restLight = const Offset(-0.35, -0.45),
    this.settleDuration = const Duration(milliseconds: 450),
    this.followDuration = const Duration(milliseconds: 90),
    this.perspective = 1 / 600,
    this.response = FoilTiltResponse.lift,
    this.idleOpacity = 0,
    this.motion,
    this.touch = true,
    super.key,
  })  : assert(idleOpacity >= 0 && idleOpacity <= 1),
        assert(maxTilt >= 0),
        assert(perspective >= 0);

  final Widget child;

  /// Follows the device's gyroscope as well as touch. Null: touch only.
  final FoilMotion? motion;

  /// Whether a touch or the mouse tilts the card and moves the light. Off,
  /// only [motion] moves the light and the card never tilts.
  final bool touch;

  final FoilTiltResponse response;

  /// Rotation, in radians, with the finger on an edge.
  final double maxTilt;

  /// Where the light rests when nobody touches the card.
  final Offset restLight;

  /// How long the card takes to settle after release.
  final Duration settleDuration;

  /// Smooths pointer movement before it reaches the tilt and the shader.
  /// Set to zero for direct tracking.
  final Duration followDuration;

  /// Strength of the perspective (Matrix4 entry 3,2).
  final double perspective;

  /// Reflections fade to this strength after release or mouse exit.
  /// Use 1 for an always-visible foil preview.
  final double idleOpacity;

  @override
  State<FoilTilt> createState() => _FoilTiltState();
}

class _FoilTiltState extends State<FoilTilt> with TickerProviderStateMixin {
  /// Time constant with which the light catches up with the device's turn.
  /// Samples arrive at ~30 Hz; this turns them into motion at frame rate.
  static const _driftTau = .06;

  /// Closer than this the light counts as caught up and stops repainting.
  static const _caughtUp = .002;

  late final ValueNotifier<Offset> _light = ValueNotifier(widget.restLight);
  final ValueNotifier<Offset> _press = ValueNotifier(Offset.zero);
  late final ValueNotifier<double> _activity =
      ValueNotifier(widget.idleOpacity);
  late final AnimationController _reveal = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 140),
    value: widget.idleOpacity,
  )..addListener(_syncActivity);

  /// Integrates the gyroscope while it is being read; null otherwise.
  FoilMotionIntegrator? _motion;
  StreamSubscription<FoilRotationRate>? _rates;

  /// A stream that failed (no gyroscope) is not retried for this widget.
  bool _motionFailed = false;
  bool _portrait = true;
  bool _visible = true;
  late final AppLifecycleListener _lifecycle;

  /// Moves the light toward the device's turn, frame by frame; stops once it
  /// has caught up, so a still device costs no frames.
  late final Ticker _drift = createTicker(_onDrift);
  Duration _driftLast = Duration.zero;
  late final AnimationController _settle = AnimationController(
    vsync: this,
    duration: widget.settleDuration,
  )..addListener(_onSettle);
  late final AnimationController _follow = AnimationController(
    vsync: this,
    duration: widget.followDuration,
  )..addListener(() {
      final t = Curves.easeOutCubic.transform(_follow.value);
      _press.value = Offset.lerp(_followPressFrom, _target, t)!;
      _light.value = Offset.lerp(_followLightFrom, _target, t)!;
    });

  Offset _lightFrom = Offset.zero;
  Offset _pressFrom = Offset.zero;
  Offset _followPressFrom = Offset.zero;
  Offset _followLightFrom = Offset.zero;
  Offset _target = Offset.zero;
  int? _pointer;
  bool _hovering = false;
  bool _engaged = false;
  bool _reducedMotion = false;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onStateChange: (_) => _syncMotion());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // A hidden route (offstage, behind another page) turns tickers off; the
    // gyroscope follows. `TickerMode.valuesOf` replaces this only from
    // Flutter 3.35, below this package's minimum.
    // ignore: deprecated_member_use
    _visible = TickerMode.of(context);
    _portrait =
        (MediaQuery.maybeOrientationOf(context) ?? Orientation.portrait) ==
            Orientation.portrait;
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduce != _reducedMotion) {
      _reducedMotion = reduce;
      _follow.stop();
      _settle.stop();
      _reveal.stop();
      _pointer = null;
      _hovering = false;
      _engaged = false;
      _press.value = Offset.zero;
      _light.value = widget.restLight;
      _reveal.value = widget.idleOpacity;
    }
    _syncMotion();
  }

  @override
  void didUpdateWidget(FoilTilt oldWidget) {
    super.didUpdateWidget(oldWidget);
    _settle.duration = widget.settleDuration;
    _follow.duration = widget.followDuration;
    if (oldWidget.motion != widget.motion) {
      _stopMotion();
      _motionFailed = false;
      _syncMotion();
    }
    if (oldWidget.idleOpacity != widget.idleOpacity &&
        _pointer == null &&
        !_hovering) {
      _reveal.animateTo(widget.idleOpacity);
    }
    if (oldWidget.restLight != widget.restLight && !_settle.isAnimating) {
      if (_pointer == null && !_hovering) _light.value = _ambient;
    }
  }

  @override
  void dispose() {
    _rates?.cancel();
    _lifecycle.dispose();
    _drift.dispose();
    _settle.dispose();
    _follow.dispose();
    _reveal.dispose();
    _activity.dispose();
    _light.dispose();
    _press.dispose();
    super.dispose();
  }

  /// Where the light rests when nothing touches the card: [FoilTilt.restLight]
  /// moved by the device's turn.
  Offset get _ambient {
    final offset = _motion?.offset ?? Offset.zero;
    return Offset(
      (widget.restLight.dx + offset.dx).clamp(-1.0, 1.0),
      (widget.restLight.dy + offset.dy).clamp(-1.0, 1.0),
    );
  }

  bool get _touchOwnsLight =>
      _pointer != null || _hovering || _settle.isAnimating;

  /// Reads the gyroscope exactly while it can show: motion requested, not
  /// failed, animations on, portrait, foreground, route visible.
  void _syncMotion() {
    if (!mounted) return;
    final motion = widget.motion;
    final lifecycle = SchedulerBinding.instance.lifecycleState;
    final wanted = motion != null &&
        !_motionFailed &&
        !_reducedMotion &&
        _portrait &&
        _visible &&
        (lifecycle == null || lifecycle == AppLifecycleState.resumed);
    if (!wanted) {
      _stopMotion();
      return;
    }
    if (_rates != null) return;
    _motion = FoilMotionIntegrator(motion);
    _rates = motion._rates.listen(
      _onRate,
      onError: (Object _) {
        _motionFailed = true;
        _stopMotion();
      },
      cancelOnError: true,
    );
  }

  /// Stops reading and lets the light drift back to its rest. The integrated
  /// turn is dropped: after a pause the device may be held quite differently.
  void _stopMotion() {
    _rates?.cancel();
    _rates = null;
    if (_motion == null) return;
    _motion = null;
    _driftToAmbient();
  }

  void _onRate(FoilRotationRate rate) {
    _motion?.add(rate);
    _driftToAmbient();
  }

  void _driftToAmbient() {
    if (_touchOwnsLight || _drift.isActive) return;
    if ((_light.value - _ambient).distance < _caughtUp) return;
    _driftLast = Duration.zero;
    _drift.start();
  }

  void _onDrift(Duration elapsed) {
    final dt = (elapsed - _driftLast).inMicroseconds / 1e6;
    _driftLast = elapsed;
    final target = _ambient;
    final next =
        Offset.lerp(_light.value, target, 1 - math.exp(-dt / _driftTau))!;
    if ((next - target).distance < _caughtUp) {
      _light.value = target;
      _drift.stop();
    } else {
      _light.value = next;
    }
    _syncActivity();
  }

  /// Touch shows the reflection through [_reveal]. With motion, turning the
  /// device shows it too, in proportion to how far the light has moved.
  void _syncActivity() {
    var activity = _reveal.value;
    if (_motion != null) {
      final idle = widget.idleOpacity;
      final moved =
          ((_light.value - widget.restLight).distance * 2).clamp(0.0, 1.0);
      activity = math.max(activity, idle + (1 - idle) * moved);
    }
    _activity.value = activity;
  }

  void _onSettle() {
    final t = _settle.value;
    // The tilt overshoots a little, like a card springing back; the light
    // just glides home, which with motion is wherever the device's turn
    // currently puts it.
    _press.value = Offset.lerp(
      _pressFrom,
      Offset.zero,
      Curves.easeOutBack.transform(t),
    )!;
    _light.value = Offset.lerp(
      _lightFrom,
      _ambient,
      Curves.easeOutCubic.transform(t),
    )!;
    _syncActivity();
  }

  void _point(Offset local) {
    final size = context.size;
    if (size == null || size.isEmpty) return;
    _drift.stop();
    _settle.stop();
    if (!_engaged) {
      _engaged = true;
      _reveal.animateTo(1,
          duration: const Duration(milliseconds: 140), curve: Curves.easeOut);
    }
    final p = foilPointAt(local, size);
    _target = p;
    _followPressFrom = _press.value;
    _followLightFrom = _light.value;
    _follow.forward(from: 0);
  }

  void _release() {
    _engaged = false;
    _follow.stop();
    _pressFrom = _press.value;
    _lightFrom = _light.value;
    _settle.forward(from: 0);
    _reveal.animateTo(widget.idleOpacity,
        duration: widget.settleDuration, curve: Curves.easeOutCubic);
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      return widget.child;
    }
    final lit =
        FoilLight(light: _light, activity: _activity, child: widget.child);
    if (!widget.touch) return lit;
    return MouseRegion(
      onEnter: (e) {
        _hovering = true;
        if (_pointer == null) _point(e.localPosition);
      },
      onHover: (e) {
        if (_pointer == null) _point(e.localPosition);
      },
      onExit: (_) {
        _hovering = false;
        if (_pointer == null) _release();
      },
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (e) {
          if (_pointer != null) return;
          _pointer = e.pointer;
          _point(e.localPosition);
        },
        onPointerMove: (e) {
          if (_pointer == e.pointer) _point(e.localPosition);
        },
        onPointerUp: (e) {
          if (_pointer != e.pointer) return;
          _pointer = null;
          if (e.kind == PointerDeviceKind.mouse && _hovering) {
            _point(e.localPosition);
          } else {
            _release();
          }
        },
        onPointerCancel: (e) {
          if (_pointer != e.pointer) return;
          _pointer = null;
          _release();
        },
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
                ..rotateY(-p.dx * a)
                ..rotateX(p.dy * a),
              child: child,
            );
          },
          child: lit,
        ),
      ),
    );
  }
}

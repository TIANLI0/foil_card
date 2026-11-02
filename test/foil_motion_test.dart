import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foil_card/foil_card.dart';

const _step = Duration(milliseconds: 33);

/// Feeds [count] samples of a constant rate, [_step] apart, from [from].
Duration _turn(
  void Function(FoilRotationRate) add, {
  required Duration from,
  required int count,
  double x = 0,
  double y = 0,
}) {
  var t = from;
  for (var i = 0; i < count; i++) {
    t += _step;
    add((x: x, y: y, time: t));
  }
  return t;
}

void main() {
  group('FoilMotionIntegrator', () {
    FoilMotionIntegrator integrator([FoilMotion motion = const FoilMotion()]) =>
        FoilMotionIntegrator(motion)..add((x: 0, y: 0, time: Duration.zero));

    test('turning an edge toward the viewer brings the light to it', () {
      // -y: the right edge comes toward the viewer.
      final right = integrator();
      _turn(right.add, from: Duration.zero, count: 10, y: -.5);
      expect(right.offset.dx, greaterThan(0));
      expect(right.offset.dy, 0);

      // -x: the bottom edge comes toward the viewer (screen y grows down).
      final down = integrator();
      _turn(down.add, from: Duration.zero, count: 10, x: -.5);
      expect(down.offset.dy, greaterThan(0));
      expect(down.offset.dx, 0);
    });

    test('a turn of [range] reaches the edge', () {
      const motion = FoilMotion(range: .3, recenter: Duration.zero);
      final m = integrator(motion);
      // 0.32 rad/s for ~1 s, minus the 0.02 dead zone = 0.3 rad.
      _turn(m.add, from: Duration.zero, count: 30, y: -.32);
      expect(m.offset.dx, closeTo(.99, .02));
    });

    test('recenters once the device is held still', () {
      final m = integrator();
      final t = _turn(m.add, from: Duration.zero, count: 10, y: -1);
      expect(m.offset.dx, greaterThan(.5));
      // Ten time constants of stillness.
      _turn(m.add, from: t, count: 910);
      expect(m.offset, Offset.zero);
    });

    test('ignores sensor noise inside the dead zone', () {
      final m = integrator();
      var t = Duration.zero;
      for (var i = 0; i < 300; i++) {
        t += _step;
        m.add((x: i.isEven ? .015 : -.015, y: .019, time: t));
      }
      expect(m.offset, Offset.zero);
    });

    test('a slow turn just past the dead zone still moves the light', () {
      final m = integrator(const FoilMotion(recenter: Duration.zero));
      _turn(m.add, from: Duration.zero, count: 60, y: -.03);
      expect(m.offset.dx, greaterThan(.03));
    });

    test('does not integrate across a gap in the stream', () {
      final m = integrator(const FoilMotion(recenter: Duration.zero));
      m.add((x: 0, y: -1, time: const Duration(seconds: 5)));
      final maxTurn = FoilMotionIntegrator.maxStep.inMicroseconds / 1e6 * .98;
      expect(m.offset.dx, closeTo(maxTurn / .3, 1e-9));
    });

    test('holds at most a little past the edge however far it turns', () {
      final m = integrator(const FoilMotion(recenter: Duration.zero));
      _turn(m.add, from: Duration.zero, count: 300, y: -3);
      expect(m.offset.dx, 1.5);
    });
  });

  group('FoilTilt with motion', () {
    late StreamController<FoilRotationRate> rates;
    late Duration clock;
    ValueListenable<Offset>? light;
    ValueListenable<double>? activity;

    setUp(() {
      rates = StreamController<FoilRotationRate>.broadcast(sync: true);
      clock = Duration.zero;
      light = null;
      activity = null;
    });
    tearDown(() => rates.close());

    void sample({double x = 0, double y = 0}) {
      clock += _step;
      rates.add((x: x, y: y, time: clock));
    }

    Widget probe() => Builder(builder: (context) {
          light = FoilLight.maybeOf(context);
          activity = FoilLight.activityOf(context);
          return const SizedBox(width: 200, height: 280);
        });

    Widget host({
      FoilMotion? motion,
      bool touch = true,
      Size size = const Size(400, 800),
      bool reduceMotion = false,
      bool tickers = true,
    }) =>
        MediaQuery(
          data: MediaQueryData(size: size, disableAnimations: reduceMotion),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: TickerMode(
              enabled: tickers,
              child: Center(
                child: FoilTilt(
                  restLight: Offset.zero,
                  idleOpacity: .4,
                  touch: touch,
                  motion: motion ??
                      FoilMotion(
                        rotationRates: rates.stream,
                        recenter: Duration.zero,
                      ),
                  child: probe(),
                ),
              ),
            ),
          ),
        );

    testWidgets('light and reflection follow the device turn', (tester) async {
      await tester.pumpWidget(host());
      expect(rates.hasListener, isTrue);
      sample();
      for (var i = 0; i < 10; i++) {
        sample(y: -.5);
      }
      await tester.pumpAndSettle();
      expect(light!.value.dx, greaterThan(.3));
      expect(activity!.value, greaterThan(.4));
    });

    testWidgets('costs no frames while the device is still', (tester) async {
      await tester.pumpWidget(host());
      sample();
      for (var i = 0; i < 10; i++) {
        sample(y: -.5);
      }
      await tester.pumpAndSettle();
      final settled = light!.value;
      for (var i = 0; i < 30; i++) {
        sample(x: .01, y: -.01); // noise inside the dead zone
      }
      expect(tester.binding.hasScheduledFrame, isFalse);
      expect(light!.value, settled);
    });

    testWidgets('a touch owns the light; release returns it to the turn',
        (tester) async {
      await tester.pumpWidget(host());
      sample();
      for (var i = 0; i < 10; i++) {
        sample(y: -.5);
      }
      await tester.pumpAndSettle();
      final turned = light!.value;

      final rect = tester.getRect(find.byType(FoilTilt));
      final gesture =
          await tester.startGesture(rect.topLeft + const Offset(2, 2));
      await tester.pumpAndSettle();
      for (var i = 0; i < 10; i++) {
        sample(y: .5); // turning back while touched
      }
      await tester.pumpAndSettle();
      expect(light!.value.dx, lessThan(-.9), reason: 'stays under the finger');

      await gesture.up();
      await tester.pumpAndSettle();
      // Released: back to the device's turn, which the touch-time samples
      // moved, not to the rest light.
      expect(light!.value.dx, lessThan(turned.dx));
      expect(light!.value.dx, isNot(closeTo(-1, .1)));
    });

    testWidgets('stops reading the gyroscope while hidden', (tester) async {
      await tester.pumpWidget(host());
      expect(rates.hasListener, isTrue);
      await tester.pumpWidget(host(tickers: false));
      expect(rates.hasListener, isFalse);
      await tester.pumpWidget(host());
      expect(rates.hasListener, isTrue);
    });

    testWidgets('does not read the gyroscope in landscape', (tester) async {
      await tester.pumpWidget(host(size: const Size(800, 400)));
      expect(rates.hasListener, isFalse);
    });

    testWidgets('does not read the gyroscope when motion is reduced',
        (tester) async {
      await tester.pumpWidget(host(reduceMotion: true));
      expect(rates.hasListener, isFalse);
    });

    testWidgets('stops reading on pause and drops the turn', (tester) async {
      await tester.pumpWidget(host());
      sample();
      for (var i = 0; i < 10; i++) {
        sample(y: -.5);
      }
      await tester.pumpAndSettle();
      expect(light!.value.dx, greaterThan(.3));

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      expect(rates.hasListener, isFalse);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      expect(rates.hasListener, isTrue);
      await tester.pumpAndSettle();
      expect(light!.value, Offset.zero);
    });

    testWidgets('a failing gyroscope leaves the light at rest', (tester) async {
      await tester.pumpWidget(host());
      rates.addError(StateError('no gyroscope'));
      await tester.pumpAndSettle();
      expect(rates.hasListener, isFalse);
      expect(light!.value, Offset.zero);
    });

    testWidgets('without touch, a press neither tilts nor moves the light',
        (tester) async {
      await tester.pumpWidget(host(touch: false));
      await tester.tapAt(
          tester.getRect(find.byType(FoilTilt)).topLeft + const Offset(2, 2));
      await tester.pumpAndSettle();
      expect(light!.value, Offset.zero);
      expect(find.byType(Transform), findsNothing);
    });
  });
}

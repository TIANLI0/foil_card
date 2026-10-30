import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foil_card/foil_card.dart';
import 'package:foil_card/src/foil_card.dart' show foilArtTransform;

// 1×1 opaque PNG.
final _pixel = MemoryImage(
  base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
  ),
);

void main() {
  group('foilArtTransform', () {
    test('cover crops the long side, centred', () {
      // 100×200 art on a 100×100 card: the middle half of the art shows.
      final (x, y, z, w) = foilArtTransform(
        const Size(100, 200),
        const Size(100, 100),
        BoxFit.cover,
      );
      expect(x, 1);
      expect(y, 0.5);
      expect(z, 0);
      expect(w, 0.25);
    });

    test('fill maps the card onto the whole art', () {
      final t = foilArtTransform(
        const Size(40, 90),
        const Size(63, 88),
        BoxFit.fill,
      );
      expect(t, (1.0, 1.0, 0.0, 0.0));
    });

    test('contain leaves the art uv outside 0..1 around it', () {
      // 100×50 art in a 100×100 card: art occupies the middle band.
      final (_, y, _, w) = foilArtTransform(
        const Size(100, 50),
        const Size(100, 100),
        BoxFit.contain,
      );
      expect(0.25 * y + w, closeTo(0, 1e-9));
      expect(0.75 * y + w, closeTo(1, 1e-9));
    });
  });

  test('foilPointAt maps centre to zero and clamps outside the card', () {
    const size = Size(200, 100);
    expect(foilPointAt(const Offset(100, 50), size), Offset.zero);
    expect(foilPointAt(const Offset(0, 100), size), const Offset(-1, 1));
    expect(foilPointAt(const Offset(500, -20), size), const Offset(1, -1));
  });

  test('FoilStyle has value equality', () {
    expect(FoilStyle.glitter, const FoilStyle(pattern: FoilPattern.glitter));
    expect(
      FoilStyle.rainbow.copyWith(seed: 3),
      isNot(FoilStyle.rainbow),
    );
    expect(
      FoilStyle.cosmos.copyWith(seed: 3).hashCode,
      FoilStyle.cosmos.copyWith(seed: 3).hashCode,
    );
  });

  group('FoilCard', () {
    testWidgets('shows the placeholder until the art loads, child on top', (
      tester,
    ) async {
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: SizedBox(
            width: 63,
            height: 88,
            child: FoilCard(
              image: _pixel,
              placeholder: const Text('loading'),
              child: const Text('name'),
            ),
          ),
        ),
      );
      expect(find.text('loading'), findsOneWidget);
      expect(find.text('name'), findsOneWidget);

      await tester.runAsync(
          () => precacheImage(_pixel, tester.element(find.byType(FoilCard))));
      await tester.pump();
      expect(find.text('loading'), findsNothing);
      expect(find.text('name'), findsOneWidget);
    });
  });

  group('FoilTilt', () {
    const rest = Offset(-0.4, -0.5);
    ValueListenable<Offset>? published;

    Widget harness() => Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: SizedBox(
              width: 200,
              height: 280,
              child: FoilTilt(
                restLight: rest,
                child: Builder(
                  builder: (context) {
                    published = FoilLight.maybeOf(context);
                    return const SizedBox.expand();
                  },
                ),
              ),
            ),
          ),
        );

    testWidgets('light follows the finger and settles back to rest', (
      tester,
    ) async {
      await tester.pumpWidget(harness());
      expect(published!.value, rest);

      final topLeft = tester.getTopLeft(find.byType(FoilTilt));
      final gesture = await tester.startGesture(
        topLeft + const Offset(150, 70),
      );
      expect(published!.value, const Offset(0.5, -0.5));

      await gesture.moveTo(topLeft + const Offset(100, 140));
      expect(published!.value, Offset.zero);

      await gesture.up();
      await tester.pumpAndSettle();
      expect(published!.value, rest);
    });

    for (final (response, nearer) in [
      (FoilTiltResponse.lift, true),
      (FoilTiltResponse.press, false),
    ]) {
      testWidgets(
          '${response.name}: the touched edge comes '
          '${nearer ? 'toward' : 'away from'} the viewer', (tester) async {
        const face = Key('face');
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: Center(
              child: SizedBox(
                width: 200,
                height: 280,
                child: FoilTilt(
                  response: response,
                  child: const SizedBox.expand(key: face),
                ),
              ),
            ),
          ),
        );
        final topLeft = tester.getTopLeft(find.byType(FoilTilt));
        final gesture =
            await tester.startGesture(topLeft + const Offset(195, 140));
        await tester.pump();

        // Perspective makes the nearer edge look longer.
        final box = tester.renderObject<RenderBox>(find.byKey(face));
        double edge(double x) => (box.localToGlobal(Offset(x, 280)) -
                box.localToGlobal(Offset(x, 0)))
            .distance;
        expect(edge(200) > edge(0), nearer);
        await gesture.up();
        await tester.pumpAndSettle();
      });
    }

    testWidgets('steps aside when the platform reduces motion', (
      tester,
    ) async {
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: harness(),
        ),
      );
      expect(published, isNull);
      expect(find.byType(Listener), findsNothing);
    });
  });
}

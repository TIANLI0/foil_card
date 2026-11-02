import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foil_card/foil_card.dart';

Future<MemoryImage> art({Color background = const Color(0xffaaaabb)}) async {
  final recorder = ui.PictureRecorder();
  final c = Canvas(recorder);
  c.drawRect(const Rect.fromLTWH(0, 0, 240, 120), Paint()..color = background);
  // Flattened black strokes and a transparent corner: no separate text layer.
  for (var x = 20.0; x < 120; x += 8) {
    c.drawRect(Rect.fromLTWH(x, 40, 3, 30), Paint()..color = Colors.black);
  }
  c.drawRect(const Rect.fromLTWH(220, 0, 20, 20),
      Paint()..blendMode = BlendMode.clear);
  final picture = recorder.endRecording();
  final image = await picture.toImage(240, 120);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  picture.dispose();
  return MemoryImage(bytes!.buffer.asUint8List());
}

void main() {
  testWidgets('single image infers layout and integrates pointer light',
      (tester) async {
    await tester.runAsync(FoilCard.precacheShader);
    final image = (await tester.runAsync(art))!;
    await tester.pumpWidget(Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
            child: SizedBox(
                width: 240,
                child: FoilCard(image: image, interactive: true)))));
    await tester.runAsync(
        () => precacheImage(image, tester.element(find.byType(FoilCard))));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(FoilCard)), const Size(240, 120));
    expect(find.byType(FoilTilt), findsOneWidget);
    final source = tester.widget<FoilLight>(find.byType(FoilLight));
    final rect = tester.getRect(find.byType(FoilCard));
    final drag =
        await tester.startGesture(rect.centerRight - const Offset(10, 0));
    await tester.pumpAndSettle();
    expect(source.light.value.dx, greaterThan(.7));
    await drag.up();
    await tester.pumpAndSettle();
    // An explicit source avoids installing an extra tilt controller.
    final external = ValueNotifier(Offset.zero);
    await tester.pumpWidget(Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
            child: SizedBox(
                width: 240,
                child: FoilCard(
                    image: image, interactive: true, light: external)))));
    await tester.pumpAndSettle();
    expect(find.byType(FoilTilt), findsNothing);
    await tester.pumpWidget(const SizedBox());
    external.dispose();
  });
  testWidgets('protection reduces edge changes and renders deterministically',
      (tester) async {
    final image = (await tester.runAsync(art))!;
    await tester.runAsync(FoilCard.precacheShader);
    const key = Key('surface');
    Future<Uint8List> render(FoilStyle style) async {
      await tester.pumpWidget(Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
              child: RepaintBoundary(
                  key: key,
                  child: SizedBox(
                      width: 240,
                      height: 120,
                      child: FoilCard(image: image, style: style))))));
      await tester.runAsync(
          () => precacheImage(image, tester.element(find.byType(FoilCard))));
      await tester.pumpAndSettle();
      return (await tester.runAsync(() async {
        final capture = await tester
            .renderObject<RenderRepaintBoundary>(find.byKey(key))
            .toImage();
        final data = await capture.toByteData();
        capture.dispose();
        return data!.buffer.asUint8List();
      }))!;
    }

    final plain =
        await render(FoilStyle.plain.copyWith(intensity: 0, glare: 0));
    final bare =
        await render(FoilStyle.holographic.copyWith(detailProtection: 0));
    final protected =
        await render(FoilStyle.holographic.copyWith(detailProtection: 1));
    int error(Uint8List data) {
      var total = 0;
      for (var y = 38; y < 72; y++) {
        for (var x = 18; x < 124; x++) {
          final i = (y * 240 + x) * 4;
          for (var channel = 0; channel < 3; channel++) {
            total += (data[i + channel] - plain[i + channel]).abs();
          }
        }
      }
      return total;
    }

    expect(error(bare), greaterThan(0));
    expect(error(protected), lessThan(error(bare)));
    expect(protected[(10 * 240 + 230) * 4 + 3], 0);
    final again =
        await render(FoilStyle.holographic.copyWith(detailProtection: 1));
    expect(again, orderedEquals(protected));
    expect(tester.takeException(), isNull);
  });

  testWidgets('new surface materials differ and respond to lighting',
      (tester) async {
    await tester.runAsync(FoilCard.precacheShader);
    final image = (await tester.runAsync(art))!;
    final light = ValueNotifier(const Offset(-.65, -.3));
    const key = Key('materials');
    Future<Uint8List> render(FoilStyle style, {ImageProvider? source}) async {
      await tester.pumpWidget(Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: RepaintBoundary(
            key: key,
            child: SizedBox(
              width: 240,
              height: 120,
              child:
                  FoilCard(image: source ?? image, style: style, light: light),
            ),
          ),
        ),
      ));
      await tester.runAsync(() => precacheImage(
          source ?? image, tester.element(find.byType(FoilCard))));
      await tester.pumpAndSettle();
      return (await tester.runAsync(() async {
        final capture = await tester
            .renderObject<RenderRepaintBoundary>(find.byKey(key))
            .toImage();
        final data = await capture.toByteData();
        capture.dispose();
        return data!.buffer.asUint8List();
      }))!;
    }

    double difference(Uint8List a, Uint8List b) {
      var sum = 0;
      for (var i = 0; i < a.length; i++) {
        if (i % 4 != 3) sum += (a[i] - b[i]).abs();
      }
      return sum / (240 * 120 * 3);
    }

    const styles = [
      FoilStyle.pearl,
      FoilStyle.prism,
      FoilStyle.radial,
      FoilStyle.ripple,
      FoilStyle.confetti,
      FoilStyle.starfield,
      FoilStyle.heartfield,
      FoilStyle.lightBeams,
      FoilStyle.aurora,
    ];
    final original = await render(FoilStyle.glossy.copyWith(glare: 0));
    final captures = <Uint8List>[];
    for (final style in styles) {
      light.value = const Offset(-.65, -.3);
      final left = await render(style);
      light.value = const Offset(.7, .45);
      final right = await render(style);
      expect(difference(left, right), greaterThan(.3),
          reason: '${style.pattern.name} must react to light');
      for (final prior in captures) {
        expect(difference(left, prior), greaterThan(.5),
            reason: '${style.pattern.name} must be a distinct material');
      }
      captures.add(left);
      expect(left[(10 * 240 + 230) * 4 + 3], 0);
      expect(await render(style.copyWith(intensity: 0, glare: 0)),
          orderedEquals(original));
      expect(await render(style.copyWith(opacity: 0, glare: 0)),
          orderedEquals(original));
    }
    final flakes = await render(FoilStyle.confetti);
    expect(
        difference(flakes,
            await render(FoilStyle.confetti.copyWith(scale: 1.8, seed: 7))),
        greaterThan(.5));
    // Silver must stay neutral, include dim/bright foil reflections, and leave
    // the unprinted background untouched rather than add a rainbow wash.
    final neutral = (await tester
        .runAsync(() => art(background: const Color(0xff999999))))!;
    final silver = await render(
        FoilStyle.starfield.copyWith(glare: 0, detailProtection: 0),
        source: neutral);
    var dark = 0, bright = 0, unchanged = 0, sampled = 0;
    for (var y = 0; y < 120; y++) {
      for (var x = 0; x < 215; x++) {
        // Ignore the black strokes, sampling both sides of the moving band.
        if (x >= 18 && x < 124 && y >= 38 && y < 72) continue;
        sampled++;
        final i = (y * 240 + x) * 4;
        expect((silver[i] - silver[i + 1]).abs(), lessThanOrEqualTo(1));
        expect((silver[i] - silver[i + 2]).abs(), lessThanOrEqualTo(1));
        if (silver[i] < 149) dark++;
        if (silver[i] > 158) bright++;
        if (silver[i] == 153) unchanged++;
      }
    }
    expect(dark, 0, reason: 'Off-angle foil must not leave opaque gray stamps');
    expect(bright, greaterThan(5), reason: 'Metal needs specular highlights');
    expect(unchanged, greaterThan(sampled * .85));
    // Layer opacity blends the complete material with the image, independently
    // of its strength. This preserves underlying contrast, including at peaks.
    for (final style in [
      FoilStyle.starfield,
      FoilStyle.heartfield,
      FoilStyle.lightBeams,
      FoilStyle.aurora
    ]) {
      final full = await render(style.copyWith(opacity: 1, glare: 0));
      final translucent = await render(style.copyWith(opacity: .4, glare: 0));
      for (var i = 0; i < full.length; i++) {
        if (i % 4 == 3) {
          expect(translucent[i], original[i]);
        } else {
          expect(translucent[i], closeTo(original[i] * .6 + full[i] * .4, 1.2),
              reason: '${style.pattern.name} must preserve the image below');
        }
      }
    }
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    light.dispose();
  });
}

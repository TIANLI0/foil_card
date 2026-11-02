import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foil_card/foil_card.dart';

const _w = 300;
const _h = 420;

Future<MemoryImage> _darkArt() async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawRect(
    Rect.fromLTWH(0, 0, _w.toDouble(), _h.toDouble()),
    Paint()..color = const Color(0xff1a1d2e),
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(_w, _h);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  picture.dispose();
  return MemoryImage(bytes!.buffer.asUint8List());
}

void main() {
  late MemoryImage image;
  late Uint8List plain;
  final light = ValueNotifier(Offset.zero);
  const key = Key('twinkle');

  Future<Uint8List> render(
      WidgetTester tester, FoilStyle style, Offset at) async {
    light.value = at;
    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: Center(
        child: RepaintBoundary(
          key: key,
          child: SizedBox(
            width: _w.toDouble(),
            height: _h.toDouble(),
            child: FoilCard(image: image, style: style, light: light),
          ),
        ),
      ),
    ));
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

  Future<void> setUpArt(WidgetTester tester) async {
    await tester.runAsync(FoilCard.precacheShader);
    image = (await tester.runAsync(_darkArt))!;
    plain = await render(
        tester, FoilStyle.twinkle.copyWith(intensity: 0), Offset.zero);
  }

  /// Pixels a glint brightened well past the faint silver print.
  Set<int> lit(Uint8List rgba) => {
        for (var i = 0; i < _w * _h; i++)
          if ((rgba[i * 4] - plain[i * 4]) +
                  (rgba[i * 4 + 1] - plain[i * 4 + 1]) +
                  (rgba[i * 4 + 2] - plain[i * 4 + 2]) >
              150)
            i,
      };

  int quadrant(int i) =>
      (i % _w < _w ~/ 2 ? 0 : 1) + (i ~/ _w < _h ~/ 2 ? 0 : 2);

  // How the glints spread is the point here, not where motifs are placed, so
  // the frame (which keeps the face area empty on purpose) is turned off.
  for (final (name, style) in [
    (
      'stars',
      FoilStyle.twinkle.copyWith(glints: FoilGlitter.stars.copyWith(frame: 0)),
    ),
    (
      'hearts',
      FoilStyle.twinkleHearts
          .copyWith(glints: FoilGlitter.hearts.copyWith(frame: 0)),
    ),
  ]) {
    testWidgets('$name light different motifs at different angles',
        (tester) async {
      await setUpArt(tester);
      final a = lit(await render(tester, style, const Offset(-.5, -.5)));
      final b = lit(await render(tester, style, const Offset(.5, .5)));

      expect(a.length, greaterThan(200), reason: 'some motifs catch light');
      expect(b.length, greaterThan(200));
      // Spread over the card, not gathered into one band.
      expect(a.map(quadrant).toSet().length, greaterThanOrEqualTo(3));
      // Turning the card hands the glints to other motifs.
      final shared = a.intersection(b).length;
      expect(
          shared / (a.length < b.length ? a.length : b.length), lessThan(.3));
    });
  }

  testWidgets('every glint control reaches the shader', (tester) async {
    await setUpArt(tester);
    const at = Offset(-.5, -.5);
    Future<Uint8List> with_(FoilGlitter glints) =>
        render(tester, FoilStyle.twinkle.copyWith(glints: glints), at);

    final none = lit(
        await with_(FoilGlitter.stars.copyWith(density: 0, dust: 0, print: 0)));
    expect(none, isEmpty, reason: 'density 0 and dust 0: nothing glints');

    final silverRgba =
        await with_(FoilGlitter.stars.copyWith(color: 0, dust: 0));
    final silver = lit(silverRgba);
    expect(silver, isNotEmpty);
    var maxSpread = 0;
    for (final i in silver) {
      final r = silverRgba[i * 4], g = silverRgba[i * 4 + 1];
      final b = silverRgba[i * 4 + 2];
      final spread = [r, g, b].reduce((x, y) => x > y ? x : y) -
          [r, g, b].reduce((x, y) => x < y ? x : y);
      if (spread > maxSpread) maxSpread = spread;
    }
    // The art underneath is a cool navy, so allow its tint through.
    expect(maxSpread, lessThan(40), reason: 'color 0 glints silver-white');

    final small = lit(await with_(FoilGlitter.stars.copyWith(size: .08)));
    final large = lit(await with_(FoilGlitter.stars.copyWith(size: .3)));
    expect(large.length, greaterThan(small.length * 2));

    // Iridescence moves the color with the angle: off the rest angle, 0 and 1
    // give clearly different glint colors.
    final still = await with_(
        FoilGlitter.stars.copyWith(dust: 0, color: 1, iridescence: 0));
    final shifting = await with_(
        FoilGlitter.stars.copyWith(dust: 0, color: 1, iridescence: 1));
    var colorShift = 0;
    for (final i in lit(still)) {
      for (var c = 0; c < 3; c++) {
        colorShift += (still[i * 4 + c] - shifting[i * 4 + c]).abs();
      }
    }
    expect(colorShift / lit(still).length, greaterThan(30));

    // Frame 1 keeps every motif off the face area (upper middle).
    final framed = lit(await with_(FoilGlitter.hearts.copyWith(frame: 1)));
    final face = framed.where((i) {
      final x = (i % _w) / _w - .5, y = (i ~/ _w) / _w - _h / _w / 2;
      final ex = x / .27, ey = (y + .33) / .33;
      return ex * ex + ey * ey < .7 * .7;
    });
    expect(face, isEmpty, reason: 'frame 1: nothing over the face');

    final stars = await with_(FoilGlitter.stars.copyWith(dust: 0));
    final hearts = await with_(
        FoilGlitter.stars.copyWith(dust: 0, motif: FoilGlitterMotif.heart));
    expect(lit(stars), isNot(equals(lit(hearts))));
  });
}

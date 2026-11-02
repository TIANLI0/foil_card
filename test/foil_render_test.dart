import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foil_card/foil_card.dart';

Future<MemoryImage> png(void Function(Canvas) draw) async {
  final recorder = ui.PictureRecorder();
  draw(Canvas(recorder));
  final picture = recorder.endRecording();
  final image = await picture.toImage(126, 176);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  picture.dispose();
  return MemoryImage(bytes!.buffer.asUint8List());
}

void main() {
  testWidgets(
      'shader preserves art, masks, transparency and moving reflections',
      (tester) async {
    final art = await tester.runAsync(() => png((c) {
          c.drawRect(const Rect.fromLTWH(0, 0, 126, 176),
              Paint()..color = const Color(0xff65717f));
          c.drawRect(const Rect.fromLTWH(50, 70, 26, 36),
              Paint()..color = const Color(0xff26303f));
        }));
    final mask = await tester.runAsync(() => png((c) {
          c.drawRect(const Rect.fromLTWH(0, 0, 126, 176),
              Paint()..color = Colors.black);
          c.drawRect(const Rect.fromLTWH(0, 0, 63, 176),
              Paint()..color = Colors.white);
        }));
    final relief = await tester.runAsync(() => png((c) {
          for (var x = 0; x < 126; x += 3) {
            c.drawRect(Rect.fromLTWH(x.toDouble(), 0, 2, 176),
                Paint()..color = Colors.white);
          }
        }));
    await tester.runAsync(FoilCard.precacheShader);
    const boundaryKey = Key('capture');
    final light = ValueNotifier(const Offset(-.7, -.5));
    final activity = ValueNotifier(1.0);

    Future<Uint8List> render(
        {FoilStyle style = FoilStyle.diagonal,
        ImageProvider? maskImage,
        ImageProvider? foil,
        FoilMaskChannel maskChannel = FoilMaskChannel.luminance,
        Rect foilRegion = const Rect.fromLTRB(0, 0, 1, 1),
        bool invert = false,
        BoxFit fit = BoxFit.cover,
        double height = 176}) async {
      await tester.pumpWidget(Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
              child: RepaintBoundary(
                  key: boundaryKey,
                  child: SizedBox(
                      width: 126,
                      height: height,
                      child: FoilLight(
                          light: light,
                          activity: activity,
                          child: FoilCard(
                              image: art!,
                              style: style,
                              mask: maskImage,
                              maskChannel: maskChannel,
                              foilRegion: foilRegion,
                              foil: foil,
                              invertMask: invert,
                              fit: fit)))))));
      final context = tester.element(find.byType(FoilCard));
      await tester.runAsync(() async {
        await precacheImage(art, context);
        if (maskImage != null) await precacheImage(maskImage, context);
        if (foil != null) await precacheImage(foil, context);
      });
      await tester.pumpAndSettle();
      return (await tester.runAsync(() async {
        final boundary =
            tester.renderObject<RenderRepaintBoundary>(find.byKey(boundaryKey));
        final image = await boundary.toImage();
        final data = await image.toByteData();
        image.dispose();
        return data!.buffer.asUint8List();
      }))!;
    }

    final plain = await render(style: FoilStyle.plain.copyWith(glare: 0));
    expect(plain.take(4), [101, 113, 127, 255]);
    final active = await render(style: FoilStyle.diagonal.copyWith(glare: 0));
    expect(active, isNot(orderedEquals(plain)));
    light.value = const Offset(.8, .6);
    final moved = await render(style: FoilStyle.diagonal.copyWith(glare: 0));
    expect(moved, isNot(orderedEquals(active)));
    activity.value = 0;
    expect(await render(), orderedEquals(plain));
    activity.value = 1;

    final masked = await render(
        maskImage: mask, style: FoilStyle.diagonal.copyWith(glare: 0));
    final inverted = await render(
        maskImage: mask,
        invert: true,
        style: FoilStyle.diagonal.copyWith(glare: 0));
    for (var y = 0; y < 176; y++) {
      for (var x = 0; x < 126; x++) {
        final i = (y * 126 + x) * 4;
        final unfoiled = x >= 63 ? masked : inverted;
        expect(unfoiled.sublist(i, i + 4), plain.sublist(i, i + 4));
      }
    }

    final alphaMasked = await render(
        maskImage: mask,
        maskChannel: FoilMaskChannel.alpha,
        style: FoilStyle.diagonal.copyWith(glare: 0));
    final rightPixel = (140 * 126 + 100) * 4;
    var changedOnBlack = 0;
    for (var y = 0; y < 176; y++) {
      for (var x = 63; x < 126; x++) {
        final i = (y * 126 + x) * 4;
        if (alphaMasked[i] != plain[i] ||
            alphaMasked[i + 1] != plain[i + 1] ||
            alphaMasked[i + 2] != plain[i + 2]) {
          changedOnBlack++;
        }
      }
    }
    expect(changedOnBlack, greaterThan(500));
    final clipped = await render(
        foilRegion: const Rect.fromLTRB(0, 0, .5, 1),
        style: FoilStyle.diagonal.copyWith(glare: 0));
    expect(clipped.sublist(rightPixel, rightPixel + 4),
        plain.sublist(rightPixel, rightPixel + 4));

    final textured = await render(foil: relief, style: FoilStyle.fullArt);
    expect(
        textured, isNot(orderedEquals(await render(style: FoilStyle.fullArt))));
    final contained = await render(fit: BoxFit.contain, height: 252);
    expect(contained[3], 0);
    expect(contained[((126 * 126) + 63) * 4 + 3], 255);
    for (final pattern in FoilPattern.values) {
      final pixels = await render(style: FoilStyle(pattern: pattern));
      expect(
          pixels.where((v) => v > 0 && v < 255).length, greaterThan(126 * 176));
    }
    await tester.pumpWidget(const SizedBox());
    light.dispose();
    activity.dispose();
  });
}

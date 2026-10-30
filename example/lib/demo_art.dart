import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Card art and foil mask for the demo, painted at startup so the example
/// ships no image assets.
class DemoArt {
  DemoArt._(this.art, this.mask);

  final MemoryImage art;

  /// White on the frame, black on the illustration window.
  final MemoryImage mask;

  static const size = Size(630, 880);
  static final _window = Rect.fromLTWH(40, 96, size.width - 80, 430);

  static Future<DemoArt> paint() async =>
      DemoArt._(await _png(_paintArt), await _png(_paintMask));

  static Future<MemoryImage> _png(void Function(Canvas) painter) async {
    final recorder = ui.PictureRecorder();
    painter(Canvas(recorder));
    final image = await recorder.endRecording().toImage(
      size.width.toInt(),
      size.height.toInt(),
    );
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return MemoryImage(bytes!.buffer.asUint8List());
  }

  static void _paintMask(Canvas canvas) {
    canvas
      ..drawRect(Offset.zero & size, Paint()..color = Colors.white)
      ..drawRRect(
        RRect.fromRectAndRadius(_window, const Radius.circular(10)),
        Paint()..color = Colors.black,
      );
  }

  static void _paintArt(Canvas canvas) {
    final card = Offset.zero & size;

    // Frame: a pale cool metal.
    canvas.drawRect(
      card,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFD9DEE8), Color(0xFFA9B3C6), Color(0xFFE4E7EE)],
        ).createShader(card),
    );

    _text(canvas, 'Dawn Keeper', const Offset(44, 30), 38, FontWeight.w800);
    _text(canvas, 'No. 001', Offset(size.width - 170, 40), 26, FontWeight.w600);

    // Illustration window: a dusk landscape.
    canvas
      ..save()
      ..clipRRect(RRect.fromRectAndRadius(_window, const Radius.circular(10)))
      ..drawRect(
        _window,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF1E1B4B),
              Color(0xFF7C3AED),
              Color(0xFFF472B6),
              Color(0xFFFBBF24),
            ],
            stops: [0, 0.4, 0.75, 1],
          ).createShader(_window),
      );
    final rng = math.Random(7);
    for (var i = 0; i < 40; i++) {
      canvas.drawCircle(
        Offset(
          _window.left + rng.nextDouble() * _window.width,
          _window.top + rng.nextDouble() * _window.height * 0.45,
        ),
        rng.nextDouble() * 1.8 + 0.6,
        Paint()
          ..color = Colors.white.withValues(
            alpha: 0.4 + rng.nextDouble() * 0.5,
          ),
      );
    }
    canvas.drawCircle(
      Offset(_window.center.dx + 60, _window.top + 300),
      70,
      Paint()..color = const Color(0xFFFFF1C1),
    );
    _ridge(canvas, 0.62, const Color(0xFF6D28D9), 3, 40);
    _ridge(canvas, 0.74, const Color(0xFF4C1D95), 5, 30);
    _ridge(canvas, 0.86, const Color(0xFF2E1065), 9, 22);
    canvas.restore();

    // Text box.
    final box = Rect.fromLTWH(40, _window.bottom + 28, size.width - 80, 250);
    canvas.drawRRect(
      RRect.fromRectAndRadius(box, const Radius.circular(10)),
      Paint()..color = const Color(0xFFF4F5F8),
    );
    _text(
      canvas,
      'Keeps watch over the first light.\nWhere it walks, the frost turns gold.',
      box.topLeft + const Offset(24, 24),
      24,
      FontWeight.w500,
      width: box.width - 48,
    );
    for (var i = 0; i < 3; i++) {
      final y = box.top + 140 + i * 30.0;
      canvas.drawLine(
        Offset(box.left + 24, y),
        Offset(box.right - 24, y),
        Paint()
          ..color = const Color(0xFFCBD0DB)
          ..strokeWidth = 2,
      );
    }
  }

  static void _ridge(
    Canvas canvas,
    double level,
    Color color,
    int seed,
    double amplitude,
  ) {
    final rng = math.Random(seed);
    final y = _window.top + _window.height * level;
    final path = Path()..moveTo(_window.left, _window.bottom);
    for (var x = 0.0; x <= _window.width; x += _window.width / 8) {
      path.lineTo(_window.left + x, y - rng.nextDouble() * amplitude * 2);
    }
    path
      ..lineTo(_window.right, _window.bottom)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  static void _text(
    Canvas canvas,
    String text,
    Offset at,
    double size,
    FontWeight weight, {
    double width = 560,
  }) {
    TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(
            color: const Color(0xFF1F2937),
            fontSize: size,
            fontWeight: weight,
            height: 1.3,
          ),
        ),
        textDirection: TextDirection.ltr,
      )
      ..layout(maxWidth: width)
      ..paint(canvas, at);
  }
}

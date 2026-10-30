import 'package:flutter/material.dart';
import 'package:foil_card/foil_card.dart';

import 'demo_art.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  FoilCard.precacheShader();
  runApp(const FoilDemoApp());
}

class FoilDemoApp extends StatelessWidget {
  const FoilDemoApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'foil_card',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      brightness: Brightness.dark,
      colorSchemeSeed: const Color(0xFF7C3AED),
      scaffoldBackgroundColor: const Color(0xFF111118),
    ),
    home: const FoilDemoPage(),
  );
}

enum _MaskMode { none, frame, window }

class FoilDemoPage extends StatefulWidget {
  const FoilDemoPage({super.key});

  @override
  State<FoilDemoPage> createState() => _FoilDemoPageState();
}

class _FoilDemoPageState extends State<FoilDemoPage> {
  late final Future<DemoArt> _art = DemoArt.paint();
  FoilPattern _pattern = FoilPattern.rainbow;
  _MaskMode _mask = _MaskMode.none;
  double _intensity = 1;

  static const _radius = BorderRadius.all(Radius.circular(18));

  Widget _card(DemoArt art, FoilStyle style, _MaskMode mask) => AspectRatio(
    aspectRatio: DemoArt.size.aspectRatio,
    child: FoilTilt(
      child: FoilCard(
        image: art.art,
        mask: mask == _MaskMode.none ? null : art.mask,
        invertMask: mask == _MaskMode.window,
        style: style,
        borderRadius: _radius,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: FutureBuilder<DemoArt>(
        future: _art,
        builder: (context, snapshot) {
          final art = snapshot.data;
          if (art == null) {
            return const Center(child: CircularProgressIndicator());
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 320),
                  child: _card(
                    art,
                    FoilStyle(pattern: _pattern, intensity: _intensity),
                    _mask,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              SegmentedButton<FoilPattern>(
                segments: [
                  for (final p in FoilPattern.values)
                    ButtonSegment(value: p, label: Text(p.name)),
                ],
                selected: {_pattern},
                showSelectedIcon: false,
                onSelectionChanged: (s) => setState(() => _pattern = s.first),
              ),
              const SizedBox(height: 12),
              SegmentedButton<_MaskMode>(
                segments: const [
                  ButtonSegment(
                    value: _MaskMode.none,
                    label: Text('whole card'),
                  ),
                  ButtonSegment(value: _MaskMode.frame, label: Text('frame')),
                  ButtonSegment(
                    value: _MaskMode.window,
                    label: Text('art window'),
                  ),
                ],
                selected: {_mask},
                showSelectedIcon: false,
                onSelectionChanged: (s) => setState(() => _mask = s.first),
              ),
              Row(
                children: [
                  const Text('intensity'),
                  Expanded(
                    child: Slider(
                      value: _intensity,
                      max: 1.5,
                      onChanged: (v) => setState(() => _intensity = v),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 16,
                crossAxisSpacing: 16,
                childAspectRatio: DemoArt.size.aspectRatio,
                children: [
                  for (final (i, p) in FoilPattern.values.indexed)
                    _card(
                      art,
                      FoilStyle(pattern: p, seed: i.toDouble()),
                      _MaskMode.window,
                    ),
                ],
              ),
            ],
          );
        },
      ),
    ),
  );
}

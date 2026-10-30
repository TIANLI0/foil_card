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

/// Where on the card the foil is printed.
enum Placement { whole, frame, window }

/// A finish as it appears on real cards: a style plus where it is printed.
typedef Finish = ({String name, FoilStyle style, Placement placement});

const finishes = <Finish>[
  (name: 'plain', style: FoilStyle.plain, placement: Placement.whole),
  (
    name: 'reverse holo',
    style: FoilStyle.reverseHolo,
    placement: Placement.frame,
  ),
  (name: 'holo', style: FoilStyle.holo, placement: Placement.window),
  (name: 'cosmos', style: FoilStyle.cosmos, placement: Placement.window),
  (name: 'glitter', style: FoilStyle.glitter, placement: Placement.whole),
  (name: 'crosshatch', style: FoilStyle.crosshatch, placement: Placement.whole),
  (name: 'iridescent', style: FoilStyle.iridescent, placement: Placement.whole),
  (name: 'diagonal', style: FoilStyle.diagonal, placement: Placement.whole),
  (name: 'full art', style: FoilStyle.fullArt, placement: Placement.whole),
  (name: 'alt art', style: FoilStyle.altArt, placement: Placement.whole),
  (name: 'textured', style: FoilStyle.textured, placement: Placement.whole),
  (
    name: 'soft full art',
    style: FoilStyle.softFullArt,
    placement: Placement.whole,
  ),
  (
    name: 'rainbow glitter',
    style: FoilStyle.rainbowGlitter,
    placement: Placement.whole,
  ),
  (name: 'gold', style: FoilStyle.gold, placement: Placement.whole),
  (name: 'silver', style: FoilStyle.silver, placement: Placement.frame),
  (name: 'sheen', style: FoilStyle.sheen, placement: Placement.window),
  (name: 'rainbow', style: FoilStyle.rainbow, placement: Placement.window),
];

class FoilDemoPage extends StatefulWidget {
  const FoilDemoPage({super.key});

  @override
  State<FoilDemoPage> createState() => _FoilDemoPageState();
}

class _FoilDemoPageState extends State<FoilDemoPage> {
  late final Future<DemoArt> _art = DemoArt.paint();
  Finish _finish = finishes[2];

  /// Overrides the finish's own placement while set.
  Placement? _placement;
  double _intensity = 1;
  FoilTiltResponse _response = FoilTiltResponse.lift;

  static const _radius = BorderRadius.all(Radius.circular(18));

  Widget _card(DemoArt art, FoilStyle style, Placement placement) =>
      AspectRatio(
        aspectRatio: DemoArt.size.aspectRatio,
        child: FoilTilt(
          response: _response,
          child: FoilCard(
            image: art.art,
            mask: placement == Placement.whole ? null : art.mask,
            invertMask: placement == Placement.window,
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
                  constraints: const BoxConstraints(maxWidth: 300),
                  child: _card(
                    art,
                    _finish.style.copyWith(
                      intensity: _finish.style.intensity * _intensity,
                    ),
                    _placement ?? _finish.placement,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final f in finishes)
                    ChoiceChip(
                      label: Text(f.name),
                      selected: f == _finish,
                      onSelected: (_) => setState(() {
                        _finish = f;
                        _placement = null;
                      }),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              SegmentedButton<Placement>(
                segments: const [
                  ButtonSegment(value: Placement.whole, label: Text('whole')),
                  ButtonSegment(value: Placement.frame, label: Text('frame')),
                  ButtonSegment(value: Placement.window, label: Text('window')),
                ],
                selected: {_placement ?? _finish.placement},
                showSelectedIcon: false,
                onSelectionChanged: (s) => setState(() => _placement = s.first),
              ),
              const SizedBox(height: 8),
              SegmentedButton<FoilTiltResponse>(
                segments: const [
                  ButtonSegment(
                    value: FoilTiltResponse.lift,
                    label: Text('tilt: lift'),
                  ),
                  ButtonSegment(
                    value: FoilTiltResponse.press,
                    label: Text('tilt: press'),
                  ),
                ],
                selected: {_response},
                showSelectedIcon: false,
                onSelectionChanged: (s) => setState(() => _response = s.first),
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
              const SizedBox(height: 8),
              GridView.count(
                crossAxisCount: 3,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: DemoArt.size.aspectRatio * 0.88,
                children: [
                  for (final (i, f) in finishes.indexed)
                    Column(
                      children: [
                        Expanded(
                          child: _card(
                            art,
                            f.style.copyWith(seed: i.toDouble()),
                            f.placement,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          f.name,
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      ],
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

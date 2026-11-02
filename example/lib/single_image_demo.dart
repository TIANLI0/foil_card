import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:foil_card/foil_card.dart';

import 'demo_art.dart';

typedef SingleImageSample = ({String name, ImageProvider image});

Future<List<SingleImageSample>> singleImageSamples() async {
  Future<MemoryImage> paint(Size size, void Function(Canvas, Rect) draw) async {
    final recorder = ui.PictureRecorder();
    draw(Canvas(recorder), Offset.zero & size);
    final picture = recorder.endRecording();
    final image = await picture.toImage(
      size.width.toInt(),
      size.height.toInt(),
    );
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    picture.dispose();
    return MemoryImage(bytes!.buffer.asUint8List());
  }

  void text(Canvas c, String value, Offset at, double size, Color color) {
    final p = TextPainter(
      text: TextSpan(
        text: value,
        style: TextStyle(
          fontFamily: 'sans-serif',
          fontSize: size,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    p.paint(c, at);
  }

  final landscape = await paint(const Size(660, 420), (c, r) {
    c.drawRect(
      r,
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0xff172945), Color(0xff364772)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ).createShader(r),
    );
    c.drawCircle(
      const Offset(540, 100),
      160,
      Paint()..color = const Color(0xff59678d),
    );
    c.drawCircle(
      const Offset(540, 100),
      115,
      Paint()..color = const Color(0xff253958),
    );
    text(c, 'ORBIT', const Offset(42, 36), 28, const Color(0xffe3d9bb));
    text(c, 'AURORA CLUB', const Offset(42, 174), 42, Colors.white);
    text(
      c,
      'MEMBERSHIP  /  0048  1026',
      const Offset(44, 332),
      19,
      const Color(0xffc4cede),
    );
  });
  final square = await paint(const Size(480, 480), (c, r) {
    c.drawRect(r, Paint()..color = const Color(0xffe7e1d7));
    c.drawCircle(
      const Offset(295, 185),
      140,
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0xffce7b52), Color(0xff6c4870)],
        ).createShader(r),
    );
    text(c, 'STILL', const Offset(32, 24), 64, const Color(0xff24242a));
    text(c, 'MOTION', const Offset(30, 328), 64, const Color(0xff24242a));
    text(
      c,
      'VOL. 04 / SOUND ARCHIVE',
      const Offset(34, 438),
      13,
      const Color(0xff49454a),
    );
  });
  final portrait = await DemoArt.paint();
  return [
    (name: '竖版插画', image: portrait.art),
    (name: '横版会员卡', image: landscape),
    (name: '方形封面', image: square),
  ];
}

class SingleImageDemoPage extends StatefulWidget {
  const SingleImageDemoPage({required this.openLab, super.key});
  final VoidCallback openLab;
  @override
  State<SingleImageDemoPage> createState() => _SingleImageDemoPageState();
}

class _SingleImageDemoPageState extends State<SingleImageDemoPage> {
  late final _samples = singleImageSamples();
  int _sample = 0, _finish = 0;
  double _strength = 1, _density = 1;
  double _opacity = FoilStyle.starfield.opacity;
  bool _protect = true, _original = false;
  static const _finishes = [
    (
      name: '银白星纹',
      description: '半透明平面星纹，银白高光带随角度扫过',
      style: FoilStyle.starfield,
    ),
    (
      name: '爱心透闪',
      description: '底图透过爱心，迎光时泛起柔和冷色反射',
      style: FoilStyle.heartfield,
    ),
    (
      name: '流光镭射',
      description: '透明覆膜上的细亮光带，随拖动滑过卡面',
      style: FoilStyle.lightBeams,
    ),
    (name: '极光薄膜', description: '半透明青紫光幕，保留图像纹理与细节', style: FoilStyle.aurora),
    (name: '全息', description: '斜向彩虹光带，适合大多数卡图', style: FoilStyle.holographic),
    (name: '亮膜', description: '透明覆膜，保留原图色彩', style: FoilStyle.glossy),
    (name: '柔缎', description: '柔和拉丝金属反光', style: FoilStyle.satin),
    (name: '闪粉', description: '细密彩色亮片随角度闪烁', style: FoilStyle.glitter),
    (name: '珠光', description: '柔和粉青偏色，适合浅色卡面', style: FoilStyle.pearl),
    (name: '棱镜', description: '三角切面呈现独立的彩色反射', style: FoilStyle.prism),
    (name: '镭射圆盘', description: '放射彩虹光扇与同心细纹', style: FoilStyle.radial),
    (name: '水波纹', description: '起伏波纹上的高光随光源游走', style: FoilStyle.ripple),
    (name: '碎箔', description: '大小分明的菱形箔片独立反光', style: FoilStyle.confetti),
    (name: '星云', description: '云雾色彩与细闪叠加', style: FoilStyle.cosmos),
    (name: '金箔', description: '温暖金色金属覆层', style: FoilStyle.gold),
    (name: '银箔', description: '冷色拉丝银面', style: FoilStyle.silver),
    (name: '光柱', description: '垂直彩虹条带随光线横向移动', style: FoilStyle.holo),
  ];

  Widget _finishChip(int i) {
    final finish = _finishes[i];
    return ChoiceChip(
      key: ValueKey('finish-${finish.style.pattern.name}'),
      label: Text(finish.name),
      selected: _finish == i,
      onSelected: (_) => setState(() {
        _finish = i;
        _opacity = finish.style.opacity;
      }),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('单图卡面'),
      actions: [
        TextButton(onPressed: widget.openLab, child: const Text('材质实验')),
      ],
    ),
    body: FutureBuilder<List<SingleImageSample>>(
      future: _samples,
      builder: (context, snapshot) {
        final samples = snapshot.data;
        if (samples == null) {
          return const Center(child: CircularProgressIndicator());
        }
        final finish = _finishes[_finish];
        final style = finish.style;
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text('一张完整图片即可使用，无需专用烫纹或遮罩。'),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                for (final (i, sample) in samples.indexed)
                  ChoiceChip(
                    label: Text(sample.name),
                    selected: _sample == i,
                    onSelected: (_) => setState(() => _sample = i),
                  ),
              ],
            ),
            const SizedBox(height: 24),
            Center(
              child: SizedBox(
                width: 300,
                child: FoilCard(
                  key: const Key('single-image-card'),
                  image: samples[_sample].image,
                  interactive: true,
                  idleOpacity: 1,
                  borderRadius: BorderRadius.circular(16),
                  style: style.copyWith(
                    intensity: _original ? 0 : style.intensity * _strength,
                    glare: _original ? 0 : style.glare * _strength,
                    scale: style.scale * _density,
                    opacity: _opacity,
                    detailProtection: _protect ? 0.85 : 0,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            const Text('在图片上横向拖动，观察反光'),
            const SizedBox(height: 12),
            const Text('通透闪卡 · 4 种'),
            Wrap(
              spacing: 8,
              children: [for (var i = 0; i < 4; i++) _finishChip(i)],
            ),
            const SizedBox(height: 8),
            Text(finish.description),
            Row(
              children: [
                const Text('通透度'),
                Expanded(
                  child: Slider(
                    key: const Key('foil-transparency'),
                    value: 1 - _opacity,
                    label: '${((1 - _opacity) * 100).round()}%',
                    onChanged: (v) => setState(() => _opacity = 1 - v),
                  ),
                ),
              ],
            ),
            const Text('通透度越高，原图保留越多；反光强度单独调节。'),
            const SizedBox(height: 12),
            Text('其他材质 · ${_finishes.length - 4} 种 · 左右滑动选择'),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (var i = 4; i < _finishes.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: _finishChip(i),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Text('反光强度'),
                Expanded(
                  child: Slider(
                    value: _strength,
                    max: 1.5,
                    onChanged: (v) => setState(() => _strength = v),
                  ),
                ),
              ],
            ),
            Row(
              children: [
                const Text('纹理密度'),
                Expanded(
                  child: Slider(
                    value: _density,
                    min: .5,
                    max: 2,
                    onChanged: style.pattern == FoilPattern.glare
                        ? null
                        : (v) => setState(() => _density = v),
                  ),
                ),
              ],
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('保护文字与细节'),
              subtitle: const Text('减弱深色笔画和高反差边缘的反光'),
              value: _protect,
              onChanged: (v) => setState(() => _protect = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('查看原图'),
              value: _original,
              onChanged: (v) => setState(() => _original = v),
            ),
          ],
        );
      },
    ),
  );
}

// Isolated visual/motion probe; never a product/release entrypoint.
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_shaders/flutter_shaders.dart';
import 'package:niran/core/widgets/brand_mark.dart';
import 'package:niran/core/widgets/live_liquid_glass.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  for (final asset in [
    'packages/liquid_glass_renderer/lib/assets/shaders/liquid_glass_geometry_blended.frag',
    'packages/liquid_glass_renderer/lib/assets/shaders/liquid_glass_final_render.frag',
  ]) {
    await ShaderBuilder.precacheShader(asset);
  }
  final frames = <FrameTiming>[];
  var reported = false;
  SchedulerBinding.instance.addTimingsCallback((batch) {
    frames.addAll(batch);
    if (reported || frames.length < 150) return;
    reported = true;
    final raster =
        frames
            .skip(30)
            .map((f) => f.rasterDuration.inMicroseconds / 1000)
            .toList()
          ..sort();
    final build =
        frames
            .skip(30)
            .map((f) => f.buildDuration.inMicroseconds / 1000)
            .toList()
          ..sort();
    final report = jsonEncode({
      'frames': frames.length,
      'firstRasterMs': frames.first.rasterDuration.inMicroseconds / 1000,
      'warmRasterP95Ms': raster[(raster.length * .95).floor()],
      'warmRasterMaxMs': raster.last,
      'warmBuildP95Ms': build[(build.length * .95).floor()],
    });
    debugPrint(report);
    if (args.isNotEmpty) File(args.first).writeAsStringSync(report);
  });
  runApp(
    const MaterialApp(debugShowCheckedModeBanner: false, home: MixedScene()),
  );
}

class MixedScene extends StatefulWidget {
  const MixedScene({super.key});
  @override
  State<MixedScene> createState() => _MixedSceneState();
}

class _MixedSceneState extends State<MixedScene>
    with SingleTickerProviderStateMixin {
  late final motion = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 4),
  )..repeat(reverse: true);
  @override
  void dispose() {
    motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xff252329),
    body: Column(
      children: [
        const Padding(
          padding: EdgeInsets.all(12),
          child: Text(
            'ISOLATED — real niraN lens / logo / tiny text / flags / saturated accents',
            style: TextStyle(color: Colors.white, fontSize: 18),
          ),
        ),
        for (final dark in [true, false])
          Expanded(
            child: Theme(
              data: dark ? ThemeData.dark() : ThemeData.light(),
              child: Builder(
                builder: (context) => DefaultTextStyle.merge(
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                  child: ColoredBox(
                    color: dark
                        ? const Color(0xff17151d)
                        : const Color(0xfff6f4fa),
                    child: LayoutBuilder(
                      builder: (context, bounds) => Stack(
                        children: [
                          Positioned(
                            left: 20,
                            top: 8,
                            child: Text(
                              '${dark ? 'DARK' : 'LIGHT'} · existing header sigma 18 · moving source',
                            ),
                          ),
                          Positioned(
                            left: 30,
                            right: 56,
                            top: 50,
                            child: AnimatedBuilder(
                              animation: motion,
                              builder: (context, child) => Transform.translate(
                                offset: Offset(
                                  motion.value * 24,
                                  motion.value * 10,
                                ),
                                child: child,
                              ),
                              child: const MixedSource(),
                            ),
                          ),
                          Positioned(
                            left: 20,
                            right: 20,
                            top: 38,
                            height: 104,
                            child: LiveLiquidSurface(
                              radius: 25,
                              blur: 18,
                              saturation: dark ? 1.20 : 1.25,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 24,
                                ),
                                child: Row(
                                  children: [
                                    const Text(
                                      'Servers (25)',
                                      style: TextStyle(
                                        fontSize: 23,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const Spacer(),
                                    const Icon(Icons.more_horiz, size: 30),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const Positioned(
                            left: 30,
                            top: 169,
                            child: Text(
                              'RAW comparison below — no Glass / no transform',
                            ),
                          ),
                          const Positioned(
                            left: 30,
                            right: 30,
                            top: 195,
                            child: MixedSource(),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    ),
  );
}

class MixedSource extends StatelessWidget {
  const MixedSource({super.key});
  @override
  Widget build(BuildContext context) => Row(
    children: [
      const BrandMark(size: 54),
      const SizedBox(width: 15),
      Container(
        width: 58,
        height: 38,
        color: const Color(0xff175cb1),
        child: Stack(
          children: [
            Positioned(
              top: 15,
              left: 0,
              right: 0,
              height: 8,
              child: Container(color: const Color(0xffffd73d)),
            ),
            Positioned(
              top: 0,
              bottom: 0,
              left: 18,
              width: 8,
              child: Container(color: const Color(0xffffd73d)),
            ),
          ],
        ),
      ),
      const SizedBox(width: 18),
      const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Arman · VLESS TCP TLS · 12:48 PM',
            style: TextStyle(fontSize: 16),
          ),
          Text(
            'متن کوچک پشت شیشه — subscription #12345',
            style: TextStyle(fontSize: 12),
          ),
        ],
      ),
      const Spacer(),
      const Text(
        '95 ms',
        style: TextStyle(
          color: Color(0xff00d078),
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
      ),
      const SizedBox(width: 16),
      Container(
        width: 44,
        height: 44,
        decoration: const BoxDecoration(
          color: Color(0xffab39e5),
          shape: BoxShape.circle,
        ),
      ),
      const SizedBox(width: 10),
      Container(
        width: 44,
        height: 44,
        decoration: const BoxDecoration(
          color: Color(0xffff8a00),
          shape: BoxShape.circle,
        ),
      ),
      const SizedBox(width: 12),
      const Text(
        'Failed',
        style: TextStyle(color: Color(0xffff405c), fontSize: 18),
      ),
    ],
  );
}

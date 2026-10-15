// Actual Windows GPU acceptance: transmission bends, curved specular light
// occupies the bevel, and the flat body is not replaced by an opaque frame.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:niran/core/widgets/live_liquid_glass.dart';
import 'package:niran/core/widgets/brand_mark.dart';

final scene = GlobalKey();
final panels = List.generate(6, (_) => GlobalKey());
Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  final clock = Stopwatch()..start();
  await prepareLiveGlass();
  runApp(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: RepaintBoundary(
          key: scene,
          child: Stack(
            children: [
              for (var i = 0; i < 6; i++)
                Positioned(
                  left: i.isEven ? 30 : 640,
                  top: 25 + (i ~/ 2) * 210,
                  width: 540,
                  height: 180,
                  child: Theme(
                    data: i.isEven ? ThemeData.dark() : ThemeData.light(),
                    child: Builder(
                      builder: (context) => Stack(
                        children: [
                          if (i < 2)
                            const Positioned.fill(
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [Colors.black, Colors.white],
                                  ),
                                ),
                              ),
                            )
                          else
                            Positioned.fill(
                              child: ColoredBox(
                                color: i.isEven
                                    ? const Color(0xff17151d)
                                    : const Color(0xfff7f6fc),
                                child: i < 4
                                    ? const SizedBox()
                                    : Stack(
                                        children: [
                                          const Positioned(
                                            left: 24,
                                            top: 62,
                                            child: BrandMark(size: 45),
                                          ),
                                          Positioned(
                                            left: 88,
                                            top: 60,
                                            width: 42,
                                            height: 36,
                                            child: ColoredBox(
                                              color: const Color(0xff176cc1),
                                              child: Stack(
                                                children: [
                                                  const Positioned(
                                                    left: 0,
                                                    right: 0,
                                                    top: 14,
                                                    height: 8,
                                                    child: ColoredBox(
                                                      color: Colors.yellow,
                                                    ),
                                                  ),
                                                  const Positioned(
                                                    left: 15,
                                                    top: 0,
                                                    bottom: 0,
                                                    width: 7,
                                                    child: ColoredBox(
                                                      color: Colors.yellow,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                          const Positioned(
                                            left: 160,
                                            top: 60,
                                            child: Text(
                                              'VLESS TCP · Small background',
                                              style: TextStyle(fontSize: 14),
                                            ),
                                          ),
                                          const Positioned(
                                            left: 180,
                                            top: 82,
                                            child: Text(
                                              'Large background text',
                                              style: TextStyle(fontSize: 22),
                                            ),
                                          ),
                                          const Positioned(
                                            right: 20,
                                            top: 72,
                                            child: Text(
                                              '95 ms',
                                              style: TextStyle(
                                                color: Colors.green,
                                                fontSize: 18,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                              ),
                            ),
                          Positioned(
                            left: 0,
                            right: 0,
                            top: 45,
                            height: 76,
                            child: SizedBox(
                              key: panels[i],
                              child: i < 4
                                  ? LiquidGlass.withOwnLayer(
                                      glassContainsChild: false,
                                      shape: const LiquidRoundedRectangle(
                                        borderRadius: 22,
                                      ),
                                      settings: LiquidGlassSettings(
                                        thickness: 18,
                                        blur: 6.5,
                                        refractiveIndex: 1.20,
                                        saturation: 1,
                                        chromaticAberration: 0,
                                        lightAngle: math.pi / 2,
                                        lightIntensity: i < 2
                                            ? 0
                                            : (i.isEven ? .38 : .55),
                                        ambientStrength: i < 2 ? 0 : .18,
                                        glassColor: Colors.transparent,
                                      ),
                                      child: const SizedBox.expand(),
                                    )
                                  : const LiveLiquidSurface(
                                      radius: 22,
                                      blur: 6.5,
                                      saturation: 1.15,
                                      child: Padding(
                                        padding: EdgeInsets.all(14),
                                        child: Text(
                                          'Servers (25)',
                                          style: TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
  );
  final timings = <ui.FrameTiming>[];
  WidgetsBinding.instance.addTimingsCallback(timings.addAll);
  for (var i = 0; i < 8; i++) {
    WidgetsBinding.instance.scheduleFrame();
    await WidgetsBinding.instance.endOfFrame;
  }
  final boundary =
      scene.currentContext!.findRenderObject() as RenderRepaintBoundary;
  final frame = await boundary.toImage(pixelRatio: 1);
  final bytes = (await frame.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  int pixel(int i, int x, int y, [int channel = 0]) {
    final origin = (panels[i].currentContext!.findRenderObject() as RenderBox)
        .localToGlobal(Offset.zero, ancestor: boundary);
    return bytes.getUint8(
      ((origin.dy.round() + y) * frame.width + origin.dx.round() + x) * 4 +
          channel,
    );
  }

  final checks = <Map<String, Object>>[];
  for (var i = 0; i < 2; i++) {
    final bends = [
      for (var y = 3; y <= 10; y++)
        pixel(i, 270, y) * 180 / 255 - (45 + y + .5),
    ];
    final bend = bends.reduce(math.max);
    final centerError = (pixel(i, 270, 38) - (45 + 38 + .5) * 255 / 180).abs();
    checks.add({
      'name': 'lens transmission ${i == 0 ? "dark" : "light"}',
      'maxBendPx': bend,
      'centerError': centerError,
      'pass': bend > 12 && centerError < 2,
    });
  }
  for (final i in [2, 3]) {
    final top = pixel(i, 270, 8);
    final bottom = pixel(i, 270, 67);
    final body = pixel(i, 270, 38);
    final base = i == 2 ? 23 : 247;
    final highlightSamples = [for (var y = 3; y < 17; y++) pixel(i, 270, y)];
    checks.add({
      'name': 'curved reflection ${i == 2 ? "dark" : "light"}',
      'top': top,
      'bottom': bottom,
      'body': body,
      'highlightSamples': highlightSamples,
      'pass':
          (top - bottom).abs() > 3 &&
          (body - base).abs() < 3 &&
          highlightSamples.every((value) => value < 255),
    });
  }
  final passed = checks.every((c) => c['pass'] == true);
  if (args.isNotEmpty) {
    final png = (await frame.toByteData(format: ui.ImageByteFormat.png))!;
    await File('${args.first}.png').writeAsBytes(png.buffer.asUint8List());
    await File(args.first).writeAsString(
      jsonEncode({
        'pass': passed,
        'checks': checks,
        'captureMs': clock.elapsedMilliseconds,
        'rasterMs': timings
            .map((t) => t.rasterDuration.inMicroseconds / 1000)
            .toList(),
      }),
    );
  }
  frame.dispose();
  exit(passed ? 0 : 1);
}

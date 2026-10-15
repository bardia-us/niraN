// Historical diagnostic for the bounded monotonic warp. It is NOT an
// acceptance test for the rounded Snell lens: a physical lens can reverse
// a background gradient continuously. Use verify_liquid_optics.dart to check
// transmission, curved reflection and highlight clipping of the current model.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:niran/core/widgets/live_liquid_glass.dart';
import 'package:niran/core/widgets/brand_mark.dart';

final scene = GlobalKey();
final panels = List.generate(4, (_) => GlobalKey());
Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  final clock = Stopwatch()..start();
  await prepareLiveGlass();
  final programMs = clock.elapsedMilliseconds;
  runApp(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: RepaintBoundary(
          key: scene,
          child: Stack(
            children: [
              for (var i = 0; i < 4; i++)
                Positioned(
                  left: i.isEven ? 30 : 640,
                  top: 40 + (i ~/ 2) * 220,
                  width: 540,
                  height: 180,
                  child: Theme(
                    data: i < 2 ? ThemeData.dark() : ThemeData.light(),
                    child: Builder(
                      builder: (context) => Stack(
                        children: [
                          if (i.isEven)
                            const Positioned.fill(
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [
                                      Color(0xff000000),
                                      Color(0xffffffff),
                                    ],
                                  ),
                                ),
                              ),
                            )
                          else
                            Positioned.fill(
                              child: ColoredBox(
                                color: i < 2
                                    ? const Color(0xff17151d)
                                    : const Color(0xfff7f6fc),
                                child: Stack(
                                  children: [
                                    const Positioned(
                                      left: 24,
                                      top: 68,
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
                                      left: 170,
                                      top: 68,
                                      child: Text(
                                        'VLESS TCP · Small background',
                                        style: TextStyle(fontSize: 14),
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
                              child: i.isEven
                                  ? LiquidGlass.withOwnLayer(
                                      glassContainsChild: false,
                                      shape: const LiquidRoundedRectangle(
                                        borderRadius: 22,
                                      ),
                                      settings: const LiquidGlassSettings(
                                        thickness: 18,
                                        blur: 6.5,
                                        refractiveIndex: 1.20,
                                        saturation: 1,
                                        chromaticAberration: 0,
                                        lightIntensity: 0,
                                        ambientStrength: 0,
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
  final frameMs = <int>[];
  for (var i = 0; i < 8; i++) {
    WidgetsBinding.instance.scheduleFrame();
    await WidgetsBinding.instance.endOfFrame;
    frameMs.add(clock.elapsedMilliseconds);
  }
  final boundary =
      scene.currentContext!.findRenderObject() as RenderRepaintBoundary;
  final beforeCaptureMs = clock.elapsedMilliseconds;
  final frame = await boundary.toImage(pixelRatio: 1);
  final bytes = (await frame.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  final checks = <Map<String, Object>>[];
  for (final i in [0, 2]) {
    final origin = (panels[i].currentContext!.findRenderObject() as RenderBox)
        .localToGlobal(Offset.zero, ancestor: boundary);
    final values = <int>[];
    for (var y = 3; y < 73; y++) {
      values.add(
        bytes.getUint8(
          ((origin.dy.round() + y) * frame.width + origin.dx.round() + 270) * 4,
        ),
      );
    }
    var reversed = 0;
    var worst = 0;
    for (var y = 1; y < values.length; y++) {
      final delta = values[y] - values[y - 1];
      if (delta < -1) reversed++;
      if (delta < worst) worst = delta;
    }
    checks.add({
      'theme': i == 0 ? 'dark' : 'light',
      'reversedSteps': reversed,
      'worstDelta': worst,
      'samples': values,
      'pass': reversed == 0,
    });
  }
  if (args.isNotEmpty) {
    final png = (await frame.toByteData(format: ui.ImageByteFormat.png))!;
    await File('${args.first}.png').writeAsBytes(png.buffer.asUint8List());
    await File(args.first).writeAsString(
      jsonEncode({
        'pass': checks.every((c) => c['pass'] == true),
        'programLoadMs': programMs,
        'frameMs': frameMs,
        'beforeCaptureMs': beforeCaptureMs,
        'captureMs': clock.elapsedMilliseconds,
        'checks': checks,
        'rasterMs': timings
            .map((t) => t.rasterDuration.inMicroseconds / 1000)
            .toList(),
      }),
    );
  }
  frame.dispose();
  exit(checks.every((c) => c['pass'] == true) ? 0 : 1);
}

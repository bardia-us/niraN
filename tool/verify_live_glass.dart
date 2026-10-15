// GPU regression probe only. Never use this as the product entrypoint.
// Run in an isolated Windows runner; no backend, account, tray or proxy.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_shaders/flutter_shaders.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';

final _scene = GlobalKey();
final _panels = [GlobalKey(), GlobalKey()];

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  for (final asset in [
    'packages/liquid_glass_renderer/lib/assets/shaders/liquid_glass_geometry_blended.frag',
    'packages/liquid_glass_renderer/lib/assets/shaders/liquid_glass_final_render.frag',
  ]) {
    await ShaderBuilder.precacheShader(asset);
  }
  runApp(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: RepaintBoundary(
          key: _scene,
          child: Stack(
            children: [
              const Positioned.fill(
                child: ColoredBox(color: Color(0xff204bd5)),
              ),
              for (var i = 0; i < 2; i++)
                Positioned(
                  left: 45 + i * 480,
                  top: 140 + i * 110,
                  width: 420,
                  height: 88,
                  child: SizedBox(
                    key: _panels[i],
                    child: LiquidGlass.withOwnLayer(
                      glassContainsChild: false,
                      shape: LiquidRoundedRectangle(borderRadius: 25),
                      settings: LiquidGlassSettings(
                        thickness: 18,
                        blur: 9,
                        refractiveIndex: 1.2,
                        saturation: 1.15,
                        chromaticAberration: .002,
                        lightIntensity: i == 0 ? .38 : .55,
                        ambientStrength: .18,
                        glassColor: const Color(0x06ffffff),
                      ),
                      child: const Center(
                        child: Text(
                          'SHARP foreground · Servers (25)',
                          style: TextStyle(color: Colors.white, fontSize: 18),
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
  );
  for (var i = 0; i < 5; i++) {
    WidgetsBinding.instance.scheduleFrame();
    await WidgetsBinding.instance.endOfFrame;
  }
  final boundary =
      _scene.currentContext!.findRenderObject() as RenderRepaintBoundary;
  final image = await boundary.toImage(pixelRatio: 1);
  final bytes = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  final results = <Map<String, Object>>[];
  for (var i = 0; i < _panels.length; i++) {
    final box = _panels[i].currentContext!.findRenderObject() as RenderBox;
    for (final y in [5.0, 20.0, 68.0, 83.0]) {
      final point = box.localToGlobal(Offset(300, y), ancestor: boundary);
      final index = (point.dy.round() * image.width + point.dx.round()) * 4;
      final rgba = List.generate(4, (c) => bytes.getUint8(index + c));
      results.add({
        'panel': i,
        'y': y,
        'rgba': rgba,
        'pass': rgba[2] >= 100 && rgba[2] > rgba[0] + 30 && rgba[3] == 255,
      });
    }
  }
  image.dispose();
  final passed = results.every((r) => r['pass'] == true);
  final report = jsonEncode({'pass': passed, 'samples': results});
  debugPrint(report);
  if (args.isNotEmpty) await File(args.first).writeAsString(report);
  exit(passed ? 0 : 1);
}

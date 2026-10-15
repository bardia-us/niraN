// Disposable shader attribution probe. No application backend or user data.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

Future<void> main(List<String> arguments) async {
  final stage = arguments.contains('render') ? 'render' : 'geometry';
  final clock = Stopwatch()..start();
  final log = File(
    '${File(Platform.resolvedExecutable).parent.path}/stage-$stage.jsonl',
  );
  void record(String phase) => log.writeAsStringSync(
    '${jsonEncode({'stage': stage, 'phase': phase, 'us': clock.elapsedMicroseconds})}\n',
    mode: FileMode.append,
    flush: true,
  );
  PaintingBinding.shaderWarmUp = null;
  final binding = WidgetsFlutterBinding.ensureInitialized();
  record('dart_main');
  runApp(
    const MaterialApp(
      home: Scaffold(
        body: Center(child: Text('Isolated shader timing — no API or Xray')),
      ),
    ),
  );
  Timer(const Duration(seconds: 35), () {
    record('timeout');
    exit(2);
  });
  await binding.waitUntilFirstFrameRasterized;
  record('plain_raster');
  try {
    final key = stage == 'geometry'
        ? 'liquid_glass_geometry_blended.frag'
        : 'liquid_glass_render.frag';
    record('program_start');
    final program = await ui.FragmentProgram.fromAsset(
      'packages/liquid_glass_widgets/shaders/$key',
    );
    record('program_loaded');
    final shader = program.fragmentShader();
    final textures = <ui.Image>[];
    final values = List<double>.filled(stage == 'geometry' ? 121 : 46, 0);
    if (stage == 'geometry') {
      values[0] = 256;
      values[1] = 96;
      values[2] = 1.21;
      values[4] = 40;
      values[6] = 1;
      values[7] = 1;
      final shape = <double>[3, 128, 48, 240, 80, 26, 26];
      values.setRange(8, 15, shape);
      values[120] = 1;
    } else {
      values[0] = 256;
      values[1] = 96;
      values[4] = 256;
      values[5] = 96;
      values[10] = 1.21;
      values[11] = .002;
      values[12] = 40;
      values[13] = 1;
      values[14] = .18;
      values[15] = .2;
      values[16] = 1;
      values[17] = .7071;
      values[18] = -.7071;
      values[29] = .3;
      values[30] = 1 / 3;
      values[33] = 1;
      values[37] = .55;
      values[38] = 1.3;
      for (final color in [const Color(0xFF3080D0), const Color(0xFF808040)]) {
        final recorder = ui.PictureRecorder();
        Canvas(recorder).drawColor(color, BlendMode.src);
        final picture = recorder.endRecording();
        textures.add(await picture.toImage(256, 96));
        picture.dispose();
      }
      shader.setImageSampler(0, textures[0]);
      shader.setImageSampler(1, textures[1]);
    }
    for (var index = 0; index < values.length; index++) {
      shader.setFloat(index, values[index]);
    }
    record('raster_start');
    final recorder = ui.PictureRecorder();
    Canvas(
      recorder,
    ).drawRect(const Rect.fromLTWH(0, 0, 256, 96), Paint()..shader = shader);
    final picture = recorder.endRecording();
    final image = await picture.toImage(256, 96);
    await image.toByteData();
    record('raster_complete');
    image.dispose();
    picture.dispose();
    shader.dispose();
    for (final image in textures) {
      image.dispose();
    }
    exit(0);
  } catch (_) {
    record('probe_error');
    exit(1);
  }
}

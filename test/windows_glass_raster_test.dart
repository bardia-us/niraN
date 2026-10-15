import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/widgets/shared/lightweight_liquid_glass.dart';
import 'package:niran/core/widgets/glass_surface.dart';

void main() {
  testWidgets('independent surfaces own independent mutable shader uniforms', (
    tester,
  ) async {
    await tester.runAsync(LightweightLiquidGlass.preWarm);
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 120,
                  height: 80,
                  child: GlassSurface(child: SizedBox.expand()),
                ),
                SizedBox(
                  width: 48,
                  height: 48,
                  child: GlassSurface(radius: 24, child: SizedBox.expand()),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // Deliberate renderer-level regression: sharing the immutable program is
    // safe, sharing mutable per-surface size/shape/colour uniforms is not.
    final shaders = tester.allRenderObjects
        .where(
          (render) =>
              render.runtimeType.toString() == '_RenderLightweightGlass',
        )
        .map((render) => (render as dynamic).shader as ui.FragmentShader?)
        .toList();
    expect(shaders, hasLength(2));
    expect(shaders.every((shader) => shader != null), isTrue);
    expect(identical(shaders.first, shaders.last), isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  for (final ratio in [1.0, 1.25, 1.5, 2.0]) {
    testWidgets('glass rim is translation invariant at desktop DPR $ratio', (
      tester,
    ) async {
      tester.view.devicePixelRatio = ratio;
      tester.view.physicalSize = Size(640 * ratio, 200 * ratio);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.runAsync(LightweightLiquidGlass.preWarm);
      final key = GlobalKey();
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: ThemeData(brightness: Brightness.dark),
            home: Align(
              alignment: Alignment.topLeft,
              child: RepaintBoundary(
                key: key,
                child: SizedBox(
                  width: 640,
                  height: 200,
                  child: ColoredBox(
                    color: const Color(0xff202020),
                    child: Stack(
                      children: [
                        for (final left in [20.0, 310.0])
                          Positioned(
                            left: left,
                            top: 35,
                            width: 120,
                            height: 100,
                            child: const GlassSurface(
                              radius: 28,
                              child: SizedBox.expand(),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final data = await tester.runAsync(() async {
        final image =
            await (key.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary)
                .toImage(pixelRatio: ratio);
        final bytes = await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        );
        final width = image.width;
        image.dispose();
        return (bytes: bytes!, width: width);
      });
      var totalDifference = 0;
      var count = 0;
      for (var y = 0; y < (100 * ratio).round(); y++) {
        for (var x = 0; x < (120 * ratio).round(); x++) {
          final row = (35 * ratio).round() + y;
          final first = (row * data!.width + (20 * ratio).round() + x) * 4;
          final second = (row * data.width + (310 * ratio).round() + x) * 4;
          totalDifference +=
              (data.bytes.getUint8(first) - data.bytes.getUint8(second)).abs();
          count++;
        }
      }
      expect(
        totalDifference / count,
        lessThan(1.5),
        reason: 'Position/DPI must not change the same glass silhouette',
      );
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('glass SDF matches its clip after a desktop canvas scale', (
    tester,
  ) async {
    await tester.runAsync(LightweightLiquidGlass.preWarm);
    final key = GlobalKey();
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: ThemeData(brightness: Brightness.dark),
          home: Align(
            alignment: Alignment.topLeft,
            child: RepaintBoundary(
              key: key,
              child: SizedBox(
                width: 640,
                height: 220,
                child: ColoredBox(
                  color: const Color(0xff202020),
                  child: Stack(
                    children: [
                      const Positioned(
                        left: 20,
                        top: 30,
                        width: 120,
                        height: 100,
                        child: GlassSurface(
                          radius: 28,
                          child: SizedBox.expand(),
                        ),
                      ),
                      Positioned(
                        left: 310,
                        top: 30,
                        width: 120,
                        height: 100,
                        child: Transform.scale(
                          scale: 1.25,
                          alignment: Alignment.topLeft,
                          child: const GlassSurface(
                            radius: 28,
                            child: SizedBox.expand(),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final data = await tester.runAsync(() async {
      final image =
          await (key.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary)
              .toImage();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      final width = image.width;
      image.dispose();
      return (bytes: bytes!, width: width);
    });
    int red(int x, int y) => data!.bytes.getUint8((y * data.width + x) * 4);
    var error = 0.0;
    var samples = 0;
    // Sample just inside the left/right straight rims, far from corners.
    for (var y = 34; y < 65; y++) {
      // Exclude the subpixel AA boundary: scaling changes pixel coverage there.
      for (final x in [2, 3, 4, 115, 116]) {
        error +=
            (red(20 + x, 30 + y) -
                    red(310 + (x * 1.25).round(), 30 + (y * 1.25).round()))
                .abs();
        samples++;
      }
    }
    expect(
      error / samples,
      lessThan(8),
      reason: 'FittedBox/DPI transforms must not shift or break the glass rim',
    );
  });

  testWidgets(
    'standard glass shader emits valid premultiplied alpha at its rim',
    (tester) async {
      final invalid = await tester.runAsync(() async {
        final program = await ui.FragmentProgram.fromAsset(
          'packages/liquid_glass_widgets/shaders/lightweight_glass.frag',
        );
        final shader = program.fragmentShader();
        final values = <double>[
          96, 64, 0, 0, // size, local origin
          1, 1, 1, 31 / 255, // reference dark tint
          40, 0, 1, .7, // thickness, light direction/intensity
          .2, 1.4, 1.26, 0, // ambient, saturation, refraction, dispersion
          22, 1, 1, 0, // radius, scale, glow
          0, 0, 1, .15, // density, weight, sharpness, backdrop luma
          0, 0, 0, 0, 0, 0, 1, 1, // corner and texture fallback
          .035, 0, 0, // absorption, Fresnel, body mode
        ];
        for (var i = 0; i < values.length; i++) {
          shader.setFloat(i, values[i]);
        }
        shader.setImageSampler(0, LightweightLiquidGlass.dummyImage);
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);
        canvas.drawRect(
          const Rect.fromLTWH(0, 0, 96, 64),
          Paint()..shader = shader,
        );
        final picture = recorder.endRecording();
        final image = await picture.toImage(96, 64);
        final bytes = (await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!;
        var invalidPixels = 0;
        for (var i = 0; i < bytes.lengthInBytes; i += 4) {
          final alpha = bytes.getUint8(i + 3);
          if (bytes.getUint8(i) > alpha + 1 ||
              bytes.getUint8(i + 1) > alpha + 1 ||
              bytes.getUint8(i + 2) > alpha + 1) {
            invalidPixels++;
          }
        }
        image.dispose();
        picture.dispose();
        shader.dispose();
        return invalidPixels;
      });
      expect(
        invalid,
        0,
        reason:
            'Flutter requires RGB <= alpha for transparent shader output; rim lighting must not violate compositing',
      );
    },
  );
}

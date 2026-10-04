import 'dart:ui' as ui;
import 'dart:typed_data';
import 'package:flutter/painting.dart';

/// Compile the existing Skia glass draw operations during startup, not during
/// the first popup animation. No user content is captured or cached.
class WindowsGlassShaderWarmUp extends ShaderWarmUp {
  const WindowsGlassShaderWarmUp();
  // Match the real chrome/dialog/menu kernels, not only the old 22px filter.
  static const filterSigmas = [4.0, 16.0, 18.0, 22.0, 24.0, 30.0];

  @override
  ui.Size get size => const ui.Size(256, 256);

  @override
  Future<void> execute() async {
    // This legacy Skia warmup captures 24 full-viewport scenes. Impeller has
    // its own shader pipeline; these captures delay startup without preparing
    // the live optical program and must not gate the first product frame.
    if (ui.ImageFilter.isShaderFilterSupported) return;
    try {
      await _prepare();
    } on Object {
      // An optimization must not fail startup on an unavailable GPU/context.
      // The normal live renderer remains the fallback; no cached pixels.
    }
  }

  Future<void> _prepare() async {
    await super.execute();
    // Canvas image filters alone do not compile Skia's backdrop sampling path.
    // Exercise that actual scene-layer operation too, including scaled/identity
    // popup transforms. These tiny synthetic GPU images are immediately freed.
    final views = ui.PlatformDispatcher.instance.views;
    final view = views.isEmpty ? null : views.first;
    final reportedSize = view?.physicalSize;
    final viewport =
        reportedSize != null &&
            !reportedSize.isEmpty &&
            reportedSize.width.isFinite &&
            reportedSize.height.isFinite
        ? ui.Size(
            reportedSize.width.clamp(1, 3840),
            reportedSize.height.clamp(1, 2160),
          )
        : const ui.Size(1024, 768);
    final pixelRatio = view?.devicePixelRatio ?? 1.0;
    final rect = ui.Offset.zero & viewport;
    const panel = ui.Rect.fromLTWH(0, 0, 264, 260);
    final round = ui.RRect.fromRectAndRadius(
      panel.deflate(.7),
      const ui.Radius.circular(18),
    );
    for (final dark in [true, false]) {
      final backgroundRecorder = ui.PictureRecorder();
      final backgroundCanvas = ui.Canvas(backgroundRecorder);
      backgroundCanvas.drawRect(
        rect,
        ui.Paint()
          ..color = dark
              ? const ui.Color(0xFF10111A)
              : const ui.Color(0xFFF8F8FC),
      );
      backgroundCanvas.drawCircle(
        const ui.Offset(60, 90),
        30,
        ui.Paint()..color = const ui.Color(0xFF2196F3),
      );
      final background = backgroundRecorder.endRecording();
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      final path = ui.Path()..addRRect(round);
      canvas.drawPath(
        path,
        ui.Paint()
          ..color = const ui.Color(0x06FFFFFF)
          ..blendMode = dark ? ui.BlendMode.screen : ui.BlendMode.multiply,
      );
      canvas.drawPath(
        path,
        ui.Paint()
          ..color = const ui.Color(0x30FFFFFF)
          ..style = ui.PaintingStyle.stroke
          ..strokeWidth = 1,
      );
      final content = recorder.endRecording();
      try {
        for (final sigma in filterSigmas) {
          for (final scale in [.96, 1.0]) {
            final deviceScale = scale * pixelRatio;
            final builder = ui.SceneBuilder()
              ..addPicture(ui.Offset.zero, background);
            builder.pushTransform(
              Float64List.fromList([
                deviceScale,
                0,
                0,
                0,
                0,
                deviceScale,
                0,
                0,
                0,
                0,
                1,
                0,
                96 * pixelRatio,
                96 * pixelRatio,
                0,
                1,
              ]),
            );
            builder.pushClipRRect(round);
            builder.pushBackdropFilter(_filter(sigma));
            builder.addPicture(ui.Offset.zero, content);
            builder.pop();
            builder.pop();
            builder.pop();
            final scene = builder.build();
            try {
              final image = await scene.toImage(
                viewport.width.ceil(),
                viewport.height.ceil(),
              );
              image.dispose();
            } finally {
              scene.dispose();
            }
          }
        }
      } finally {
        background.dispose();
        content.dispose();
      }
    }
  }

  ui.ImageFilter _filter(double sigma) => ui.ImageFilter.compose(
    inner: const ui.ColorFilter.matrix([
      1.22432,
      -.18784,
      -.03648,
      0,
      0,
      -.09568,
      1.13216,
      -.03648,
      0,
      0,
      -.09568,
      -.18784,
      1.28352,
      0,
      0,
      0,
      0,
      0,
      1,
      0,
    ]),
    outer: ui.ImageFilter.blur(
      sigmaX: sigma,
      sigmaY: sigma,
      tileMode: ui.TileMode.mirror,
    ),
  );

  @override
  Future<void> warmUpOnCanvas(ui.Canvas canvas) async {
    const rect = ui.Rect.fromLTWH(0, 0, 256, 256);
    final round = ui.RRect.fromRectAndRadius(
      rect.deflate(8),
      const ui.Radius.circular(18),
    );
    for (final dark in [true, false]) {
      canvas.drawRect(
        rect,
        ui.Paint()
          ..color = dark
              ? const ui.Color(0xFF10111A)
              : const ui.Color(0xFFF8F8FC),
      );
      canvas.drawCircle(
        const ui.Offset(60, 90),
        30,
        ui.Paint()..color = const ui.Color(0xFF2196F3),
      );
      canvas.drawRRect(
        round,
        ui.Paint()
          ..color = const ui.Color(0x40000000)
          ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 20),
      );
      canvas.save();
      canvas.clipRRect(round);
      // Saturation values are uniforms; compile the same composed filter used
      // by GlassSurface, including its mirror-tiled Gaussian passes.
      for (final sigma in filterSigmas) {
        canvas.saveLayer(
          rect,
          ui.Paint()
            ..imageFilter = ui.ImageFilter.compose(
              inner: const ui.ColorFilter.matrix([
                1.22432,
                -.18784,
                -.03648,
                0,
                0,
                -.09568,
                1.13216,
                -.03648,
                0,
                0,
                -.09568,
                -.18784,
                1.28352,
                0,
                0,
                0,
                0,
                0,
                1,
                0,
              ]),
              outer: ui.ImageFilter.blur(
                sigmaX: sigma,
                sigmaY: sigma,
                tileMode: ui.TileMode.mirror,
              ),
            ),
        );
        canvas.drawRRect(round, ui.Paint()..color = const ui.Color(0xFF625BD2));
        canvas.restore();
      }
      canvas.drawRRect(
        round,
        ui.Paint()
          ..color = const ui.Color(0x06FFFFFF)
          ..blendMode = dark ? ui.BlendMode.screen : ui.BlendMode.multiply,
      );
      canvas.drawRRect(
        round,
        ui.Paint()
          ..color = const ui.Color(0x30FFFFFF)
          ..style = ui.PaintingStyle.stroke
          ..strokeWidth = 1,
      );
      canvas.restore();
    }
  }
}

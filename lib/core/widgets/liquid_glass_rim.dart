import 'dart:ui' as ui;

import 'package:flutter/material.dart';

Future<ui.FragmentProgram?>? _program;
ui.FragmentProgram? _loadedProgram;

/// Warmed alongside the modal lens, before the product screen is revealed.
/// Shader compilation failure keeps a thin safe rim; never gates access/UI.
Future<ui.FragmentProgram?> warmLiquidGlassRim() =>
    _program ??= ui.FragmentProgram.fromAsset('shaders/desktop_glass_rim.frag')
        .then<ui.FragmentProgram?>((value) => _loadedProgram = value)
        .catchError((Object _) => null);

/// Same normal-lit bevel as the snapshot lens, but without live pixel capture.
/// Each surface owns its mutable shader; no frame loop or per-paint allocation.
class LiquidGlassRim extends StatefulWidget {
  const LiquidGlassRim({required this.radius, this.strength = .9, super.key});
  final double radius;
  final double strength;

  @override
  State<LiquidGlassRim> createState() => _LiquidGlassRimState();
}

class _LiquidGlassRimState extends State<LiquidGlassRim> {
  ui.FragmentShader? _shader;

  @override
  void initState() {
    super.initState();
    final program = _loadedProgram;
    if (program != null) {
      _shader = program.fragmentShader();
    } else {
      warmLiquidGlassRim().then((program) {
        if (!mounted || program == null) return;
        setState(() => _shader = program.fragmentShader());
      });
    }
  }

  @override
  void dispose() {
    _shader?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: CustomPaint(
      painter: _RimPainter(_shader, widget.radius, widget.strength),
    ),
  );
}

class _RimPainter extends CustomPainter {
  const _RimPainter(this.shader, this.radius, this.strength);
  final ui.FragmentShader? shader;
  final double radius;
  final double strength;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final shader = this.shader;
    if (shader == null) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          (Offset.zero & size).deflate(.5),
          Radius.circular(radius.clamp(0, size.shortestSide / 2)),
        ),
        Paint()
          ..color = Colors.white.withValues(alpha: .16)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
      return;
    }
    shader.setFloat(0, size.width);
    shader.setFloat(1, size.height);
    shader.setFloat(2, radius.clamp(0, size.shortestSide / 2));
    shader.setFloat(3, strength.clamp(0, 1));
    canvas.drawRect(Offset.zero & size, Paint()..shader = shader);
  }

  @override
  bool shouldRepaint(_RimPainter oldDelegate) =>
      shader != oldDelegate.shader ||
      radius != oldDelegate.radius ||
      strength != oldDelegate.strength;
}

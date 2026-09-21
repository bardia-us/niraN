import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/vpn/app_controller.dart';

/// Windows-compatible counterpart of niraNG's Liquid Glass surface.
///
/// The fragment shader used on Android/Impeller is not supported by Flutter's
/// Windows Skia renderer. This keeps the same visual recipe using one live
/// backdrop pass, luminance-preserving saturation, a light tint and specular
/// edge/depth painting. Performance mode deliberately remains opaque.
class GlassSurface extends ConsumerWidget {
  const GlassSurface({
    required this.child,
    super.key,
    this.padding,
    this.radius = 16,
    this.blur = 9,
    this.overlayColor,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final double radius;
  final double blur;
  final Color? overlayColor;

  static List<double> _saturationMatrix(double saturation) {
    const lumR = .299;
    const lumG = .587;
    const lumB = .114;
    final inverse = 1 - saturation;
    return [
      lumR * inverse + saturation,
      lumG * inverse,
      lumB * inverse,
      0,
      0,
      lumR * inverse,
      lumG * inverse + saturation,
      lumB * inverse,
      0,
      0,
      lumR * inverse,
      lumG * inverse,
      lumB * inverse + saturation,
      0,
      0,
      0,
      0,
      0,
      1,
      0,
    ];
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final reducedEffects = ref.watch(performanceModeProvider);
    final borderRadius = BorderRadius.circular(radius);
    final content = Padding(padding: padding ?? EdgeInsets.zero, child: child);

    if (reducedEffects) {
      final opaqueSurface = overlayColor == null
          ? scheme.surfaceContainerHigh
          : Color.alphaBlend(overlayColor!, scheme.surfaceContainerHigh);
      return DecoratedBox(
        decoration: BoxDecoration(
          color: opaqueSurface,
          border: Border.all(color: scheme.outlineVariant),
          borderRadius: borderRadius,
        ),
        child: content,
      );
    }

    final saturation = dark ? 1.48 : 1.38;
    final filter = ImageFilter.compose(
      inner: ColorFilter.matrix(_saturationMatrix(saturation)),
      outer: ImageFilter.blur(
        sigmaX: blur,
        sigmaY: blur,
        tileMode: TileMode.mirror,
      ),
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: dark ? .32 : .10),
            blurRadius: 22,
            spreadRadius: -5,
            offset: const Offset(0, 9),
          ),
          BoxShadow(
            color: Colors.white.withValues(alpha: dark ? .025 : .24),
            blurRadius: 7,
            spreadRadius: -4,
            offset: const Offset(-2, -2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: borderRadius,
        child: Stack(
          fit: StackFit.passthrough,
          children: [
            Positioned.fill(
              child: BackdropFilter(
                filter: filter,
                blendMode: BlendMode.srcOver,
                child: ColoredBox(
                  color: dark
                      ? Colors.white.withValues(alpha: .018)
                      : Colors.black.withValues(alpha: .012),
                ),
              ),
            ),
            if (overlayColor case final color?)
              Positioned.fill(child: ColoredBox(color: color)),
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _LiquidGlassFramePainter(dark: dark, radius: radius),
                ),
              ),
            ),
            content,
          ],
        ),
      ),
    );
  }
}

class _LiquidGlassFramePainter extends CustomPainter {
  const _LiquidGlassFramePainter({required this.dark, required this.radius});

  final bool dark;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final rect = Offset.zero & size;
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          rect.deflate(.7),
          Radius.circular(math.max(0, radius - .7)),
        ),
      );
    final square = Rect.fromCircle(
      center: rect.center,
      radius: size.longestSide / 2,
    );
    final edge = LinearGradient(
      begin: const Alignment(-.75, -.75),
      end: const Alignment(.75, .75),
      colors: [
        Colors.white.withValues(alpha: dark ? .72 : .92),
        Colors.white.withValues(alpha: dark ? .22 : .48),
        Colors.white.withValues(alpha: dark ? .08 : .20),
        Colors.black.withValues(alpha: dark ? .42 : .13),
      ],
      stops: const [0, .34, .67, 1],
    ).createShader(square);

    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.15
        ..shader = edge
        ..blendMode = BlendMode.hardLight,
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.2
        ..shader = edge
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.7)
        ..blendMode = BlendMode.overlay,
    );
  }

  @override
  bool shouldRepaint(covariant _LiquidGlassFramePainter oldDelegate) =>
      dark != oldDelegate.dark || radius != oldDelegate.radius;
}

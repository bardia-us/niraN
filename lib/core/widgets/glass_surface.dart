import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/vpn/app_controller.dart';

enum GlassSurfaceStyle { liquid, flat }

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
    this.blur = 18,
    this.overlayColor,
    this.style = GlassSurfaceStyle.liquid,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final double radius;
  final double blur;
  final Color? overlayColor;
  final GlassSurfaceStyle style;

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

    if (style == GlassSurfaceStyle.flat) {
      return _FlatGlassSurface(
        borderRadius: borderRadius,
        blur: blur,
        dark: dark,
        scheme: scheme,
        overlayColor: overlayColor,
        child: content,
      );
    }

    // This is the Windows/Skia equivalent used by the approved Glass Test
    // Lab. Keep detail destruction and colour transmission independent: blur
    // removes glyph detail while the luminance-preserving saturation keeps
    // flags, latency colours and accents present inside the glass.
    const saturation = 1.25;
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
            color: Colors.black.withValues(alpha: dark ? .26 : .08),
            blurRadius: 20,
            spreadRadius: -6,
            offset: const Offset(0, 8),
          ),
          BoxShadow(
            color: Colors.white.withValues(alpha: dark ? .02 : .16),
            blurRadius: 6,
            spreadRadius: -4,
            offset: const Offset(-1, -1),
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
                blendMode: BlendMode.srcATop,
                child: const SizedBox.expand(),
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

class _FlatGlassSurface extends StatelessWidget {
  const _FlatGlassSurface({
    required this.borderRadius,
    required this.blur,
    required this.dark,
    required this.scheme,
    required this.overlayColor,
    required this.child,
  });

  final BorderRadius borderRadius;
  final double blur;
  final bool dark;
  final ColorScheme scheme;
  final Color? overlayColor;
  final Widget child;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: borderRadius,
    child: BackdropFilter(
      filter: ImageFilter.blur(
        sigmaX: blur.clamp(0, 4),
        sigmaY: blur.clamp(0, 4),
        tileMode: TileMode.mirror,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Color.alphaBlend(
            overlayColor ?? Colors.transparent,
            scheme.surface.withValues(alpha: dark ? .54 : .66),
          ),
          border: Border.all(
            color: scheme.outlineVariant.withValues(alpha: dark ? .34 : .48),
            width: .8,
          ),
          borderRadius: borderRadius,
        ),
        child: child,
      ),
    ),
  );
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
    final glassColor = dark
        ? Colors.white.withValues(alpha: .025)
        : Colors.black.withValues(alpha: .015);
    canvas.drawPath(
      path,
      Paint()
        ..color = glassColor
        ..blendMode = dark ? BlendMode.screen : BlendMode.multiply
        ..style = PaintingStyle.fill,
    );
    final lightIntensity = dark ? .72 : .95;
    final ambientStrength = dark ? .20 : .34;
    final alpha = Curves.easeOut.transform(lightIntensity);
    final color = Colors.white.withValues(alpha: alpha);
    const lightAngle = 1.8;
    final x = math.cos(lightAngle);
    final y = math.sin(lightAngle);
    final lightCoverage = .3 + (.5 - .3) * lightIntensity;
    final alignmentWithShortestSide = (size.aspectRatio < 1 ? y : x).abs();
    final aspectAdjustment = 1 - 1 / size.aspectRatio;
    final gradientScale = aspectAdjustment * (1 - alignmentWithShortestSide);
    final inset = .5 * gradientScale.clamp(0, 1);
    final secondInset =
        lightCoverage + (.5 - lightCoverage) * gradientScale.clamp(0, 1);
    final edge = LinearGradient(
      begin: Alignment(x, y),
      end: Alignment(-x, -y),
      colors: [
        color,
        color.withValues(alpha: ambientStrength),
        color.withValues(alpha: ambientStrength),
        color,
      ],
      stops: [inset, secondInset, 1 - secondInset, 1 - inset],
    ).createShader(square);

    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1 + lightIntensity
        ..shader = edge
        ..blendMode = BlendMode.hardLight,
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..shader = edge
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, .5)
        ..blendMode = BlendMode.overlay,
    );
  }

  @override
  bool shouldRepaint(covariant _LiquidGlassFramePainter oldDelegate) =>
      dark != oldDelegate.dark || radius != oldDelegate.radius;
}

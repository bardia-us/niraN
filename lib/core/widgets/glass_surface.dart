import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/vpn/app_controller.dart';
import 'snapshot_glass.dart';
import 'live_liquid_glass.dart';

enum GlassSurfaceStyle { liquid, flat }

/// Windows-compatible counterpart of niraNG's Liquid Glass surface.
///
/// Opted-in surfaces use live image-filter shaders when the Windows renderer
/// supports them. Unsupported renderers keep the prepared snapshot/frosted
/// fallback; flat config rows never receive the 3D lens.
class GlassSurface extends ConsumerWidget {
  const GlassSurface({
    required this.child,
    super.key,
    this.padding,
    this.radius = 16,
    this.blur = 16,
    this.saturation = 1.25,
    this.overlayColor,
    this.style = GlassSurfaceStyle.liquid,
    this.liveLiquid = false,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final double radius;
  final double blur;
  final double saturation;
  final Color? overlayColor;
  final GlassSurfaceStyle style;
  final bool liveLiquid;

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

    if (liveLiquid && liveGlassReady) {
      return LiveLiquidSurface(
        radius: radius,
        blur: blur,
        saturation: saturation,
        overlayColor: overlayColor,
        child: content,
      );
    }

    // This is the Windows/Skia equivalent used by the approved Glass Test
    // Lab. Keep detail destruction and colour transmission independent: blur
    // removes glyph detail while the luminance-preserving saturation keeps
    // flags, latency colours and accents present inside the glass.
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
              child: SnapshotGlassBackdrop(
                radius: radius,
                blur: blur,
                saturation: saturation,
                fallback: BackdropFilter.grouped(
                  filter: filter,
                  // srcOver is the only BackdropFilter blend mode guaranteed
                  // across Flutter renderers. srcATop preserves the destination
                  // alpha and allowed the sharp backdrop to dominate on Windows,
                  // making higher sigma values appear to do nothing.
                  blendMode: BlendMode.srcOver,
                  child: const SizedBox.expand(),
                ),
              ),
            ),
            Positioned.fill(
              child: ColoredBox(
                color: scheme.surface.withValues(alpha: dark ? .48 : .44),
              ),
            ),
            if (overlayColor case final color?)
              Positioned.fill(child: ColoredBox(color: color)),
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _LiquidGlassFramePainter(
                    dark: dark,
                    radius: radius,
                    edgeColor: scheme.outline.withValues(
                      alpha: dark ? .32 : .26,
                    ),
                  ),
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
    // Tonal content cards are not navigation glass. A filter per server row
    // multiplies GPU passes with list length without adding useful depth.
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
  );
}

class _LiquidGlassFramePainter extends CustomPainter {
  const _LiquidGlassFramePainter({
    required this.dark,
    required this.radius,
    required this.edgeColor,
  });

  final bool dark;
  final double radius;
  final Color edgeColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final rect = Offset.zero & size;
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          rect.deflate(.7),
          Radius.circular((radius - .7).clamp(0, double.infinity)),
        ),
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
    // A single quiet perimeter keeps the glass readable and consistent.
    // Directional rim gradients made large Windows surfaces look layered.
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = edgeColor,
    );
  }

  @override
  bool shouldRepaint(covariant _LiquidGlassFramePainter oldDelegate) =>
      dark != oldDelegate.dark ||
      radius != oldDelegate.radius ||
      edgeColor != oldDelegate.edgeColor;
}

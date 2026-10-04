import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'shader_preparation.dart';

// Exact recipe approved in glass_test_lab_windows. Do not add a second rim or
// a tinted gradient over the optics. The two themes use upstream's own presets.
const messagesLiquidBlur = 2.4;
const messagesLiquidSaturation = 1.4;

LiquidGlassSettings niranLiquidSettings(Brightness brightness) =>
    (brightness == Brightness.dark
            ? LiquidGlassSettings.ios27Dark
            : LiquidGlassSettings.ios27Light)
        .copyWith(blur: messagesLiquidBlur);

final _preparation = ShaderPreparation(_prepare);
bool get liveGlassReady =>
    _preparation.ready && ui.ImageFilter.isShaderFilterSupported;
Future<bool> prepareLiveGlass() => _preparation.prepare();

Future<bool> _prepare() async {
  if (!ui.ImageFilter.isShaderFilterSupported) return false;
  try {
    await LiquidGlassWidgets.initialize(
      warmUpMode: GlassWarmUpMode.always,
      enablePerformanceMonitor: false,
    );
    // The pinned upstream loader reports failures through FlutterError and may
    // complete normally. Check the exact programs the renderer will use, not
    // merely whether initialize() returned. No per-menu retry of a bad shader.
    return LiquidGlassWidgets.premiumShadersReady;
  } on Object {
    return false; // Shader failure must not prevent startup or opaque fallback.
  }
}

class LiveLiquidSurface extends StatelessWidget {
  const LiveLiquidSurface({
    required this.child,
    required this.radius,
    required this.blur,
    required this.saturation,
    this.overlayColor,
    super.key,
  });
  final Widget child;
  // Retain the surface API for existing consumers/fallback; premium optics use
  // one authoritative theme recipe, not the old renderer's per-widget knobs.
  final double radius, blur, saturation;
  final Color? overlayColor;

  @override
  Widget build(BuildContext context) => AdaptiveGlass(
    quality: GlassQuality.premium,
    allowElevation: false,
    settings: niranLiquidSettings(Theme.of(context).brightness),
    shape: LiquidRoundedRectangle(borderRadius: radius),
    child: RepaintBoundary(child: child),
  );
}

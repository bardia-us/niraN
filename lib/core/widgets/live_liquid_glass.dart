import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'shader_preparation.dart';

// Clear Lens approved in glass_test_lab_windows on 2026-10-13.
// Keep the backdrop's colour; only the optics and blur change it.
const messagesLiquidBlur = 4.5;
const messagesLiquidSaturation = 1.0;

LiquidGlassSettings niranLiquidSettings(Brightness brightness) =>
    (brightness == Brightness.dark
            ? LiquidGlassSettings.ios27Dark
            : LiquidGlassSettings.ios27Light)
        .copyWith(
          bodyMode: GlassBodyMode.clear,
          glassColor: const Color(0x00000000),
          saturation: messagesLiquidSaturation,
          frost: 0,
          blur: messagesLiquidBlur,
          blurWeight: 1,
          thickness: 40,
          rimLight: 1.3,
          rimShade: .55,
          edgeAbsorption: 0,
          // widgets 1.12 added this term; the approved 1.8 lab lens has none.
          bodyShade: 0,
          lightIntensity: .18,
          fresnelStrength: .3,
        );

final _preparation = ShaderPreparation(_prepare);
bool get liveGlassReady =>
    _preparation.ready && ui.ImageFilter.isShaderFilterSupported;
Future<bool> prepareLiveGlass() => _preparation.prepare();

Future<bool> _prepare() async {
  try {
    await LiquidGlassWidgets.initialize(
      warmUpMode: ui.ImageFilter.isShaderFilterSupported
          ? GlassWarmUpMode.always
          : GlassWarmUpMode.auto,
      enablePerformanceMonitor: false,
    );
    // The pinned upstream loader reports failures through FlutterError and may
    // complete normally. Check the exact programs the renderer will use, not
    // merely whether initialize() returned. No per-menu retry of a bad shader.
    return ui.ImageFilter.isShaderFilterSupported &&
        LiquidGlassWidgets.premiumShadersReady;
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
    this.quality = GlassQuality.premium,
    super.key,
  });
  final Widget child;
  // Retain the surface API for existing consumers/fallback; premium optics use
  // one authoritative theme recipe, not the old renderer's per-widget knobs.
  final double radius, blur, saturation;
  final Color? overlayColor;
  final GlassQuality quality;

  @override
  Widget build(BuildContext context) {
    final standard = quality == GlassQuality.standard;
    final recipe = niranLiquidSettings(Theme.of(context).brightness);
    final material = AdaptiveGlass(
      quality: quality,
      allowElevation: false,
      settings: standard
          ? recipe.copyWith(
              blur: 0,
              frost: 0,
              saturation: 1,
              // Use upstream's Premium -> Standard thickness calibration.
              // A 40px premium lens is not a 40px Skia hairline bevel.
              thickness: recipe.thickness * .4,
              fresnelStrength: .6,
            )
          : recipe,
      shape: LiquidRoundedRectangle(borderRadius: radius),
      child: RepaintBoundary(
        child: overlayColor == null
            ? child
            : Stack(
                fit: StackFit.passthrough,
                children: [
                  Positioned.fill(
                    child: IgnorePointer(
                      child: ColoredBox(color: overlayColor!),
                    ),
                  ),
                  child,
                ],
              ),
      ),
    );
    if (!standard) return material;
    // Windows/Skia cannot use ImageFilter.shader. Own the Gaussian pass here:
    // it is present before async shader loading and honours Home's blur group.
    // The upstream material draws optics only, not a second backdrop filter.
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter.grouped(
        filter: ui.ImageFilter.compose(
          outer: ui.ColorFilter.matrix(_saturationMatrix(saturation)),
          inner: ui.ImageFilter.blur(
            sigmaX: blur.clamp(8, 18),
            sigmaY: blur.clamp(8, 18),
          ),
        ),
        blendMode: ui.BlendMode.srcOver,
        child: material,
      ),
    );
  }

  static List<double> _saturationMatrix(double saturation) {
    const r = .299, g = .587, b = .114;
    final inverse = 1 - saturation;
    return [
      r * inverse + saturation,
      g * inverse,
      b * inverse,
      0,
      0,
      r * inverse,
      g * inverse + saturation,
      b * inverse,
      0,
      0,
      r * inverse,
      g * inverse,
      b * inverse + saturation,
      0,
      0,
      0,
      0,
      0,
      1,
      0,
    ];
  }
}

import 'package:flutter/rendering.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';

/// Exact lens evaluation is valid for one sharp-foreground rounded rectangle.
/// Shared, rotated, sheared and refracted-child geometry retains the general
/// renderer. Uniform popup scaling is supported without changing paths mid-open.
double? singleLensRadius({
  required LiquidShape shape,
  required bool glassContainsChild,
  required int shapeCount,
  required Matrix4 transform,
  required double devicePixelRatio,
}) {
  if (shapeCount != 1 || glassContainsChild || shape is! LiquidRoundedRectangle)
    return null;
  final m = transform.storage;
  final scale = m[0];
  if (!scale.isFinite ||
      scale <= 0 ||
      !devicePixelRatio.isFinite ||
      devicePixelRatio <= 0 ||
      (m[5] - scale).abs() > 1e-6 ||
      [1, 2, 3, 4, 6, 7, 8, 9, 11].any((i) => m[i].abs() > 1e-6) ||
      (m[10] - 1).abs() > 1e-6 ||
      (m[15] - 1).abs() > 1e-6) return null;
  return shape.borderRadius * scale * devicePixelRatio;
}

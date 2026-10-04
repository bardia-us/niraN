import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/src/rendering/single_lens_geometry.dart';

void main() {
  double? radius(
    Matrix4 transform, {
    int count = 1,
    bool contains = false,
    LiquidShape shape = const LiquidRoundedRectangle(borderRadius: 22),
  }) => singleLensRadius(
    shape: shape,
    glassContainsChild: contains,
    shapeCount: count,
    transform: transform,
    devicePixelRatio: 2,
  );
  test(
    'translated and scaled popup keeps exact lens throughout its animation',
    () {
      expect(radius(Matrix4.translationValues(60, 120, 0)), 44);
      expect(
        radius(
          Matrix4.translationValues(60, 120, 0)..scaleByDouble(.96, .96, 1, 1),
        ),
        closeTo(42.24, 1e-9),
      );
    },
  );
  test(
    'incompatible geometry cannot silently render as a single rectangle',
    () {
      expect(radius(Matrix4.identity(), count: 2), isNull);
      expect(radius(Matrix4.identity(), contains: true), isNull);
      expect(radius(Matrix4.identity(), shape: const LiquidOval()), isNull);
      expect(radius(Matrix4.rotationZ(.1)), isNull);
      expect(radius(Matrix4.identity()..scaleByDouble(.96, .8, 1, 1)), isNull);
      expect(radius(Matrix4.identity()..setEntry(3, 2, .001)), isNull);
    },
  );
}

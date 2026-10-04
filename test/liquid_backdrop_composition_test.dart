import 'dart:ui';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/src/rendering/liquid_backdrop_filter.dart';

void main() {
  final optical = ImageFilter.matrix(
    Float64List.fromList([1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]),
  );

  test(
    'optical filter consumes requested blurred backdrop, not sharp input',
    () {
      expect(
        composeLiquidBackdrop(optical, 9),
        ImageFilter.compose(
          outer: optical,
          inner: ImageFilter.blur(
            sigmaX: 9,
            sigmaY: 9,
            tileMode: TileMode.mirror,
          ),
        ),
      );
      expect(composeLiquidBackdrop(optical, 9), isNot(optical));
    },
  );

  test('zero frost does not add an unnecessary blur pass', () {
    expect(composeLiquidBackdrop(optical, 0), same(optical));
  });
}

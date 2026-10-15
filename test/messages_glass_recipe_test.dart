import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:niran/core/widgets/live_liquid_glass.dart';

void main() {
  for (final dark in [true, false]) {
    testWidgets('Approved sandbox optics in ${dark ? 'Dark' : 'Light'}', (
      tester,
    ) async {
      late Widget surface;
      await tester.pumpWidget(
        MaterialApp(
          theme: dark ? ThemeData.dark() : ThemeData.light(),
          home: Builder(
            builder: (context) {
              surface = const LiveLiquidSurface(
                radius: 22,
                blur: messagesLiquidBlur,
                saturation: messagesLiquidSaturation,
                child: SizedBox(),
              ).build(context);
              return const SizedBox();
            },
          ),
        ),
      );
      expect(surface, isA<AdaptiveGlass>());
      final renderer = surface as AdaptiveGlass;
      expect(renderer.settings.blur, 4.5);
      expect(renderer.settings.thickness, 40);
      expect(renderer.settings.rimLight, 1.3);
      expect(renderer.settings.refractiveIndex, 1.24);
      expect(renderer.settings.lensModel, GlassLensModel.paraxial);
      expect(renderer.settings.bodyMode, GlassBodyMode.clear);
      expect(renderer.settings.glassColor.a, 0);
      expect(renderer.settings.frost, 0);
      expect(renderer.settings.saturation, 1);
      expect(
        renderer.settings.bodyShade,
        0,
        reason: 'The approved lab lens does not darken its interior',
      );
      expect(renderer.quality, GlassQuality.premium);
      expect(renderer.allowElevation, isFalse);
      expect(renderer.child, isA<RepaintBoundary>());
    });
  }
}

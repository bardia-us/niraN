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
      final preset = dark
          ? LiquidGlassSettings.ios27Dark
          : LiquidGlassSettings.ios27Light;
      expect(renderer.settings, preset.copyWith(blur: 2.4));
      expect(renderer.quality, GlassQuality.premium);
      expect(renderer.allowElevation, isFalse);
      expect(renderer.child, isA<RepaintBoundary>());
    });
  }
}

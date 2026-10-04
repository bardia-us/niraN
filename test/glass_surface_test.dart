import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niran/core/widgets/glass_surface.dart';

void main() {
  testWidgets('flat content panels do not allocate a live backdrop per row', (
    tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: GlassSurface(
              style: GlassSurfaceStyle.flat,
              child: Text('Row'),
            ),
          ),
        ),
      ),
    );
    expect(find.byType(BackdropFilter), findsNothing);
  });
  for (final brightness in Brightness.values) {
    testWidgets('glass has a legible material tint on $brightness', (
      tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: ThemeData(brightness: brightness),
            home: const Scaffold(
              body: SizedBox(
                width: 240,
                height: 120,
                child: GlassSurface(child: Text('foreground')),
              ),
            ),
          ),
        ),
      );
      final tints = tester.widgetList<ColoredBox>(
        find.descendant(
          of: find.byType(GlassSurface),
          matching: find.byType(ColoredBox),
        ),
      );
      expect(
        tints.any((box) => box.color.a >= .25 && box.color.a < .9),
        isTrue,
        reason:
            'Without a material tint the control disappears on a plain backdrop',
      );
    });
  }

  testWidgets('liquid glass composites its filtered backdrop with srcOver', (
    tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                Text('sharp backdrop'),
                SizedBox(
                  width: 240,
                  height: 120,
                  child: GlassSurface(child: Text('foreground')),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    final filter = tester.widget<BackdropFilter>(find.byType(BackdropFilter));
    expect(filter.blendMode, BlendMode.srcOver);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niran/core/widgets/glass_surface.dart';

void main() {
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

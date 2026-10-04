import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niran/core/widgets/interactive_depth.dart';

void main() {
  for (final enabled in [true, false]) {
    testWidgets(
      '${enabled ? 'idle action' : 'disabled row'} keeps text on translation-only raster path',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: InteractiveDepth(
                  enabled: enabled,
                  child: const SizedBox(
                    width: 240,
                    height: 56,
                    child: Center(child: Text('Set System Proxy • VLESS TCP')),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final paragraph = tester.renderObject<RenderParagraph>(
          find.text('Set System Proxy • VLESS TCP'),
        );
        final transform = paragraph.getTransformTo(null);
        // Non-zero perspective selects the engine's unsnapped glyph path even
        // when this two-dimensional control is not moving or tilted.
        expect(transform.entry(3, 0), 0);
        expect(transform.entry(3, 1), 0);
        expect(transform.entry(3, 2), 0);
        expect(transform.entry(3, 3), 1);
        expect(transform.entry(0, 0), 1);
        expect(transform.entry(1, 1), 1);
      },
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niran/core/widgets/settings_group.dart';

void main() {
  testWidgets('settings sections have one rounded tonal frame, no live blur', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SettingsGroup(title: 'Appearance', children: [Text('Body')]),
        ),
      ),
    );
    final tile = tester.widget<ExpansionTile>(find.byType(ExpansionTile));
    expect(tile.shape, isA<RoundedRectangleBorder>());
    expect(tile.collapsedShape, tile.shape);
    expect(find.byType(BackdropFilter), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'settings expansion reuses the painted body while its height changes',
    (tester) async {
      final controller = ExpansibleController();
      var paints = 0;
      final input = TextEditingController(text: 'retained');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SettingsGroup(
              title: 'Updates',
              controller: controller,
              children: [
                CustomPaint(
                  painter: _CountingPainter(() => paints++),
                  child: SizedBox(
                    height: 180,
                    child: TextField(controller: input),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      controller.expand();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 30));
      final firstPaints = paints;
      expect(firstPaints, greaterThan(0));
      await tester.pump(const Duration(milliseconds: 30));
      await tester.pump(const Duration(milliseconds: 30));
      expect(
        paints,
        firstPaints,
        reason:
            'Static settings contents must not repaint for each expansion tick',
      );
      await tester.pumpAndSettle();
      controller.collapse();
      await tester.pumpAndSettle();
      controller.expand();
      await tester.pumpAndSettle();
      expect(input.text, 'retained');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
      input.dispose();
    },
  );
}

class _CountingPainter extends CustomPainter {
  _CountingPainter(this.onPaint);
  final VoidCallback onPaint;
  @override
  void paint(Canvas canvas, Size size) {
    onPaint();
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.blue);
  }

  @override
  bool shouldRepaint(_CountingPainter old) => false;
}

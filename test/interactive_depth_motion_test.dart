import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niran/core/widgets/interactive_depth.dart';

Future<void> _mount(
  WidgetTester tester, {
  required VoidCallback onPressed,
  bool reducedMotion = false,
  bool reducedEffects = false,
}) => tester.pumpWidget(
  MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: reducedMotion),
      child: Scaffold(
        body: Center(
          child: InteractiveDepth(
            tiltEnabled: false,
            reducedEffects: reducedEffects,
            child: SizedBox(
              width: 180,
              height: 60,
              child: TextButton(onPressed: onPressed, child: const Text('Run')),
            ),
          ),
        ),
      ),
    ),
  ),
);

void main() {
  testWidgets('held control follows small pointer movement before pan slop', (
    tester,
  ) async {
    await _mount(tester, onPressed: () {});
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(TextButton)),
    );
    await gesture.moveBy(const Offset(8, 3));
    await tester.pumpAndSettle();
    final matrix = tester
        .widget<AnimatedContainer>(find.byType(AnimatedContainer))
        .transform!;
    expect(matrix.getTranslation().x, closeTo(.96, .001));
    expect(matrix.getTranslation().y, closeTo(.36, .001));
    await gesture.cancel();
    await tester.pumpAndSettle();
  });

  testWidgets('drag translates and stretches together within bounds', (
    tester,
  ) async {
    await _mount(tester, onPressed: () {});
    final button = find.byType(TextButton);
    final center = tester.getCenter(button);
    final gesture = await tester.startGesture(
      center,
      kind: PointerDeviceKind.mouse,
    );
    await gesture.moveBy(const Offset(30, 10));
    await tester.pumpAndSettle();
    var matrix = tester
        .widget<AnimatedContainer>(find.byType(AnimatedContainer))
        .transform!;
    expect(matrix.getTranslation().x, closeTo(3.6, .001));
    expect(matrix.getTranslation().y, closeTo(1.2, .001));
    expect(matrix.entry(0, 0), greaterThan(matrix.entry(1, 1)));
    expect(tester.getCenter(button).dx, closeTo(center.dx + 3.6, .01));
    expect(tester.getCenter(button).dy, closeTo(center.dy + 1.2, .01));
    await gesture.moveBy(const Offset(900, -600));
    await tester.pumpAndSettle();
    matrix = tester
        .widget<AnimatedContainer>(find.byType(AnimatedContainer))
        .transform!;
    expect(matrix.getTranslation().x, 5);
    expect(matrix.getTranslation().y, -4);
    expect(tester.getRect(button).width, lessThan(205));
    expect(tester.getRect(button).height, lessThan(80));
    await gesture.cancel();
    await tester.pumpAndSettle();
  });

  testWidgets('release returns softly without invoking the dragged action', (
    tester,
  ) async {
    var clicks = 0;
    await _mount(tester, onPressed: () => clicks++);
    final button = find.byType(TextButton);
    final resting = tester.getRect(button);
    final gesture = await tester.startGesture(resting.center);
    await gesture.moveBy(const Offset(45, 15));
    await tester.pumpAndSettle();
    await gesture.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    final returning = tester.getCenter(button).dx - resting.center.dx;
    expect(returning, greaterThan(0));
    expect(returning, lessThan(5));
    expect(clicks, 0);
    await tester.pumpAndSettle();
    expect(tester.getRect(button), resting);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(clicks, 1);
  });

  testWidgets('cancel restores translated geometry and the next action', (
    tester,
  ) async {
    var clicks = 0;
    await _mount(tester, onPressed: () => clicks++);
    final button = find.byType(TextButton);
    final resting = tester.getRect(button);
    final gesture = await tester.startGesture(resting.center);
    await gesture.moveBy(const Offset(-35, 48));
    await tester.pumpAndSettle();
    expect(tester.getCenter(button).dy, closeTo(resting.center.dy + 4, .01));
    await gesture.cancel();
    await tester.pumpAndSettle();
    expect(tester.getRect(button), resting);
    expect(clicks, 0);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(clicks, 1);
  });

  for (final performance in [false, true]) {
    testWidgets('reduced ${performance ? 'effects' : 'motion'} preserves tap', (
      tester,
    ) async {
      var clicks = 0;
      await _mount(
        tester,
        onPressed: () => clicks++,
        reducedMotion: !performance,
        reducedEffects: performance,
      );
      expect(find.byType(AnimatedContainer), findsNothing);
      await tester.tap(find.byType(TextButton));
      expect(clicks, 1);
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(TextButton)),
      );
      await gesture.moveBy(const Offset(50, 10));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(clicks, 1);
    });
  }
}

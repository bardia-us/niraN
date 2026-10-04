import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niran/core/desktop_feedback.dart';
import 'package:niran/core/widgets/glass_menu.dart';
import 'package:niran/core/widgets/glass_surface.dart';
import 'package:niran/core/widgets/interactive_depth.dart';

Future<void> mountControl(
  WidgetTester tester, {
  required VoidCallback onPressed,
  bool pressEnabled = true,
  bool reducedMotion = false,
  Size size = const Size(180, 60),
}) => tester.pumpWidget(
  MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: reducedMotion),
      child: Scaffold(
        body: Center(
          child: InteractiveDepth(
            pressEnabled: pressEnabled,
            tiltEnabled: false,
            child: SizedBox.fromSize(
              size: size,
              child: TextButton(
                onPressed: onPressed,
                child: const Text('Action'),
              ),
            ),
          ),
        ),
      ),
    ),
  ),
);

void main() {
  testWidgets('drag translates and deforms with bounded dimensions', (
    tester,
  ) async {
    var clicks = 0;
    await mountControl(tester, onPressed: () => clicks++);
    final control = find.byType(TextButton);
    final centre = tester.getCenter(control);
    final gesture = await tester.startGesture(centre);
    await gesture.moveBy(const Offset(55, 8));
    await tester.pumpAndSettle();
    final deformed = tester.getRect(control);
    final matrix = tester
        .widget<AnimatedContainer>(find.byType(AnimatedContainer))
        .transform!;
    expect(deformed.center.dx, closeTo(centre.dx + 5, .01));
    expect(deformed.center.dy, closeTo(centre.dy + .96, .01));
    expect(matrix.getTranslation().x, 5);
    expect(matrix.getTranslation().y, closeTo(.96, .001));
    expect(matrix.entry(0, 0), greaterThan(matrix.entry(1, 1)));
    expect(deformed.width, inInclusiveRange(175, 196));
    expect(deformed.height, inInclusiveRange(52, 65));
    await gesture.moveBy(const Offset(800, 400));
    await tester.pumpAndSettle();
    final far = tester.getRect(control);
    expect(far.center.dx, closeTo(centre.dx + 5, .01));
    expect(far.center.dy, closeTo(centre.dy + 4, .01));
    expect(far.width, lessThan(205));
    expect(far.height, lessThan(80));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(clicks, 0);
    expect(tester.getSize(control), const Size(180, 60));
    expect(tester.getRect(control).size, const Size(180, 60));
    await tester.tap(control);
    await tester.pumpAndSettle();
    expect(clicks, 1);
  });

  testWidgets(
    'cancelled vertical drag restores geometry and permits next tap',
    (tester) async {
      var clicks = 0;
      await mountControl(tester, onPressed: () => clicks++);
      final control = find.byType(TextButton);
      final resting = tester.getRect(control);
      final gesture = await tester.startGesture(resting.center);
      await gesture.moveBy(const Offset(0, 42));
      await tester.pumpAndSettle();
      final matrix = tester
          .widget<AnimatedContainer>(find.byType(AnimatedContainer))
          .transform!;
      expect(matrix.entry(1, 1), greaterThan(matrix.entry(0, 0)));
      await gesture.cancel();
      await tester.pumpAndSettle();
      expect(tester.getRect(control), resting);
      expect(clicks, 0);
      await tester.tap(control);
      expect(clicks, 1);
    },
  );

  testWidgets(
    'press-disabled wrapper leaves the child drag recognizer active',
    (tester) async {
      var distance = 0.0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: InteractiveDepth(
                pressEnabled: false,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanUpdate: (event) => distance += event.delta.distance,
                  child: const SizedBox(width: 160, height: 60),
                ),
              ),
            ),
          ),
        ),
      );
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(InteractiveDepth)),
      );
      await gesture.moveBy(const Offset(30, 0));
      await gesture.moveBy(const Offset(25, 0));
      await gesture.up();
      expect(distance, greaterThan(0));
    },
  );

  testWidgets('OS reduced motion removes transforms while preserving action', (
    tester,
  ) async {
    var clicks = 0;
    await mountControl(tester, onPressed: () => clicks++, reducedMotion: true);
    expect(find.byType(AnimatedContainer), findsNothing);
    await tester.tap(find.text('Action'));
    expect(clicks, 1);
  });

  test('soft pop has gentle gain, smooth edges and unclipped PCM', () {
    final bytes = DesktopFeedback.softCue();
    final data = ByteData.sublistView(bytes);
    final length = (bytes.length - 44) ~/ 2;
    final samples = List.generate(
      length,
      (i) => data.getInt16(44 + i * 2, Endian.little),
    );
    final peak = samples.map((v) => v.abs()).reduce(math.max);
    final rms = math.sqrt(
      samples.fold<double>(0, (sum, v) => sum + v * v) / length,
    );
    expect(peak, inInclusiveRange(1500, 5500));
    expect(rms, inInclusiveRange(200, 1500));
    expect(samples.first, 0);
    expect(samples.last, 0);
    expect(samples.take(8).map((v) => v.abs()).reduce(math.max), lessThan(200));
    expect(
      samples.skip(length - 80).map((v) => v.abs()).reduce(math.max),
      lessThan(200),
    );
    expect(samples.every((v) => v.abs() < 32767), isTrue);
  });

  for (final brightness in Brightness.values) {
    testWidgets(
      'glass on $brightness diffuses small detail but transmits broad colour',
      (tester) async {
        const boundaryKey = ValueKey('glass pixels');
        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              theme: ThemeData(brightness: brightness),
              home: Scaffold(
                body: Center(
                  child: RepaintBoundary(
                    key: boundaryKey,
                    child: SizedBox(
                      width: 520,
                      height: 300,
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: CustomPaint(painter: _StripedBackdrop()),
                          ),
                          const Positioned(
                            left: 60,
                            top: 60,
                            width: 400,
                            height: 160,
                            child: GlassSurface(child: Text('Menu foreground')),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(boundaryKey),
        );
        final pixels = await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 1);
          final bytes = await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          );
          image.dispose();
          return bytes!;
        });
        int red(int x) => pixels!.getUint8((170 * 520 + x) * 4);
        expect(
          (red(150) - red(152)).abs(),
          lessThan(8),
          reason:
              'Fine background detail must not remain sharp through navigation glass',
        );
        expect(
          red(150) - red(370),
          greaterThan(60),
          reason: 'A fog-heavy tint suppresses the broad backdrop colours',
        );
      },
    );
    testWidgets(
      'menu on $brightness keeps diffusion without a fog-heavy tint',
      (tester) async {
        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              theme: ThemeData(brightness: brightness),
              home: Scaffold(
                body: Builder(
                  builder: (context) => TextButton(
                    onPressed: () => showGlassMenu<int>(
                      context: context,
                      position: const Offset(300, 200),
                      items: const [
                        GlassMenuItem(
                          value: 1,
                          icon: Icons.edit,
                          label: 'Edit',
                        ),
                      ],
                    ),
                    child: const Text('Open'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        final glass = tester.widget<GlassSurface>(find.byType(GlassSurface));
        expect(glass.blur, inInclusiveRange(12, 18));
        final tints = tester.widgetList<ColoredBox>(
          find.descendant(
            of: find.byType(GlassSurface),
            matching: find.byType(ColoredBox),
          ),
        );
        final tint = tints.where((box) => box.color.a > .1).single;
        expect(tint.color.a, inInclusiveRange(.35, .52));
        final filter = find.byType(BackdropFilter);
        expect(filter, findsOneWidget);
        expect(
          find.ancestor(of: filter, matching: find.byType(Opacity)),
          findsNothing,
        );
        expect(
          find.ancestor(of: filter, matching: find.byType(FadeTransition)),
          findsNothing,
        );
      },
    );
  }
}

class _StripedBackdrop extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    for (var x = 0.0; x < size.width; x += 2) {
      final bright = (x ~/ 2).isEven;
      final dominant = bright ? 210 : 190;
      final other = bright ? 60 : 40;
      canvas.drawRect(
        Rect.fromLTWH(x, 0, 2, size.height),
        Paint()
          ..color = x < size.width / 2
              ? Color.fromARGB(255, dominant, other, other)
              : Color.fromARGB(255, other, other, dominant),
      );
    }
  }

  @override
  bool shouldRepaint(_StripedBackdrop oldDelegate) => false;
}

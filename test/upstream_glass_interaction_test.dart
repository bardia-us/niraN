import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart' as glass;
import 'package:liquid_glass_widgets/widgets/shared/glass_focus_region.dart';
import 'package:niran/core/widgets/glass_menu.dart';
import 'package:niran/features/vpn/app_controller.dart';

void main() {
  testWidgets(
    'physical hover follows enable changes without pointer movement',
    (tester) async {
      final enabled = ValueNotifier(true);
      final hovered = ValueNotifier(false);
      addTearDown(enabled.dispose);
      addTearDown(hovered.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: ValueListenableBuilder<bool>(
              valueListenable: enabled,
              builder: (context, active, _) => GlassFocusRegion(
                enabled: active,
                isHoveredNotifier: hovered,
                child: const SizedBox(width: 100, height: 100),
              ),
            ),
          ),
        ),
      );
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: const Offset(1, 1));
      await mouse.moveTo(const Offset(400, 300));
      await tester.pump();
      expect(hovered.value, isTrue);
      enabled.value = false;
      await tester.pump();
      expect(hovered.value, isFalse);
      enabled.value = true;
      await tester.pump();
      expect(hovered.value, isTrue);
      await mouse.moveTo(const Offset(1, 1));
      await tester.pump();
      expect(hovered.value, isFalse);
      await mouse.removePointer();
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    },
  );

  Future<void> mount(
    WidgetTester tester,
    ValueChanged<int> select, {
    bool reduced = false,
    bool performance = false,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [performanceModeProvider.overrideWithValue(performance)],
        child: MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(
              size: const Size(800, 600),
              disableAnimations: reduced,
            ),
            child: Scaffold(
              body: Column(
                children: [
                  TextButton(
                    onPressed: () => select(-1),
                    child: const Text('Before menu'),
                  ),
                  Align(
                    alignment: Alignment.topRight,
                    child: GlassActionMenu<int>(
                      tooltip: 'Actions',
                      onSelected: select,
                      items: const [
                        GlassMenuItem(
                          value: 1,
                          icon: Icons.edit,
                          label: 'Edit config',
                        ),
                        GlassMenuItem(
                          value: 2,
                          icon: Icons.delete,
                          label: 'Delete config',
                          destructive: true,
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: () => select(-2),
                    child: const Text('After menu'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('anchored upstream morph selects once and closes without dim', (
    tester,
  ) async {
    final selected = <int>[];
    await mount(tester, selected.add);
    final menu = tester.widget<glass.GlassMenu>(find.byType(glass.GlassMenu));
    expect(menu.morphFromZero, isFalse);
    expect(menu.autoAdjustToScreen, isTrue);
    expect(
      menu.quality,
      glass.GlassQuality.minimal,
      reason: 'No prepared native shader must use a shader-free fallback',
    );
    await tester.tap(find.byTooltip('Actions'));
    await tester.pumpAndSettle();
    expect(find.text('Edit config'), findsOneWidget);
    expect(
      tester
          .widgetList<ModalBarrier>(find.byType(ModalBarrier))
          .every((barrier) => (barrier.color?.a ?? 0) == 0),
      isTrue,
    );
    final rect = tester.getRect(find.text('Edit config'));
    expect(rect.right, lessThanOrEqualTo(800));
    await tester.tap(find.text('Edit config'));
    await tester.pumpAndSettle();
    expect(selected, [1]);
    expect(find.text('Edit config'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('short action menus do not move when the wheel scrolls', (
    tester,
  ) async {
    await mount(tester, (_) {});
    await tester.tap(find.byTooltip('Actions'));
    await tester.pumpAndSettle();
    final before = tester.getTopLeft(find.text('Edit config'));
    tester.binding.handlePointerEvent(
      PointerScrollEvent(
        position: tester.getCenter(find.text('Edit config')),
        scrollDelta: const Offset(0, 200),
        kind: PointerDeviceKind.mouse,
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('Edit config')), before);
    expect(tester.takeException(), isNull);
  });

  testWidgets('menu hover remains visible while the mouse is stationary', (
    tester,
  ) async {
    final oldStrategy = FocusManager.instance.highlightStrategy;
    addTearDown(() => FocusManager.instance.highlightStrategy = oldStrategy);
    FocusManager.instance.highlightStrategy =
        FocusHighlightStrategy.alwaysTraditional;
    await mount(tester, (_) {});
    await tester.tap(find.byTooltip('Actions'));
    await tester.pumpAndSettle();
    final item = find.byWidgetPredicate(
      (w) => w is glass.GlassMenuItem && w.title == 'Edit config',
    );
    double paintedHighlight() {
      final decorations = tester.widgetList<DecoratedBox>(
        find.descendant(of: item, matching: find.byType(DecoratedBox)),
      );
      return decorations
          .map((box) => (box.decoration as BoxDecoration).color?.a ?? 0)
          .fold(0.0, (a, b) => a > b ? a : b);
    }

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(10, 500));
    await mouse.moveTo(tester.getCenter(find.text('Edit config')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 160));
    expect(paintedHighlight(), greaterThan(0));
    FocusManager.instance.highlightStrategy =
        FocusHighlightStrategy.alwaysTouch;
    for (final interval in [40, 120, 300, 1000]) {
      await tester.pump(Duration(milliseconds: interval));
      expect(
        paintedHighlight(),
        greaterThan(0),
        reason: 'Hover faded while pointer stayed on the item',
      );
    }
    await mouse.moveTo(const Offset(10, 500));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 160));
    expect(paintedHighlight(), 0);
    await mouse.moveTo(tester.getCenter(find.text('Edit config')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(paintedHighlight(), greaterThan(0));
    await mouse.moveTo(const Offset(10, 500));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(paintedHighlight(), 0);
    await mouse.removePointer();
    expect(tester.takeException(), isNull);
  });

  testWidgets('Escape dismisses without selecting and menu can reopen', (
    tester,
  ) async {
    final selected = <int>[];
    await mount(tester, selected.add);
    await tester.tap(find.byTooltip('Actions'));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Edit config'), findsNothing);
    expect(selected, isEmpty);
    await tester.tap(find.byTooltip('Actions'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(20, 550));
    await tester.pumpAndSettle();
    expect(find.text('Edit config'), findsNothing);
    expect(selected, isEmpty);
    expect(tester.takeException(), isNull);
  });

  for (final performance in [true, false]) {
    testWidgets(
      'reduced motion and performance=$performance remain functional',
      (tester) async {
        final selected = <int>[];
        await mount(
          tester,
          selected.add,
          reduced: true,
          performance: performance,
        );
        await tester.tap(find.byTooltip('Actions'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Delete config'));
        await tester.pumpAndSettle();
        expect(selected, [2]);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('Escape restores actionable trigger focus for Enter/Space', (
    tester,
  ) async {
    await mount(tester, (_) {});
    await tester.tap(find.byTooltip('Actions'));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.text('Edit config'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    expect(find.text('Edit config'), findsOneWidget);
  });

  testWidgets('Tab stays in an open menu and escapes normally after dismiss', (
    tester,
  ) async {
    final selected = <int>[];
    await mount(tester, selected.add);
    await tester.tap(find.byTooltip('Actions'));
    await tester.pumpAndSettle();
    for (var index = 0; index < 12; index++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(
        FocusManager.instance.primaryFocus?.context
            ?.findAncestorWidgetOfExactType<GlassActionMenu<int>>(),
        isNotNull,
      );
    }
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Edit config'), findsNothing);
    expect(selected, isEmpty);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(
      FocusManager.instance.primaryFocus?.context
          ?.findAncestorWidgetOfExactType<GlassActionMenu<int>>(),
      isNull,
    );
  });
}

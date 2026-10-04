import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niran/features/vpn/app_controller.dart';
import 'package:niran/features/vpn/home_layout.dart';
import 'package:niran/main.dart';
import 'home_canvas_test.dart' show CanvasController;

void main() {
  testWidgets('standard desktop connection content keeps readable scale', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appControllerProvider.overrideWith(() => CanvasController()),
        ],
        child: const NirangApp(),
      ),
    );
    await tester.pumpAndSettle();
    final emblem = tester.getRect(
      find.byKey(const Key('home-connection-emblem')),
    );
    expect(emblem.width, greaterThanOrEqualTo(42));
    expect(tester.takeException(), isNull);
  });

  test('connection controls cannot be moved to the outer Home bottom', () {
    expect(HomeLayout.defaults().move('tun', 0, 80), isNull);
  });

  testWidgets(
    'controls remain inside the full connection card and TUN is a switch',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = CanvasController();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [appControllerProvider.overrideWith(() => controller)],
          child: const NirangApp(),
        ),
      );
      await tester.pumpAndSettle();
      final card = find.byKey(const Key('home-connection'));
      for (final id in ['systemProxy', 'clearProxy', 'tun', 'restart']) {
        expect(
          find.descendant(of: card, matching: find.byKey(Key('home-tile-$id'))),
          findsOneWidget,
        );
      }
      expect(
        find.descendant(of: card, matching: find.byType(Switch)),
        findsOneWidget,
      );
      final outer = tester.getRect(find.byKey(const Key('home-tile-status')));
      final inner = tester.getRect(card);
      expect((outer.width - inner.width).abs(), lessThan(1));
      expect((outer.height - inner.height).abs(), lessThan(1));
      await tester.tap(find.byKey(const Key('customize-home')));
      await tester.pump(const Duration(milliseconds: 260));
      final reset = find.byKey(const Key('reset-home-layout'));
      expect(reset, findsOneWidget);
      expect(
        tester.widget<IconButton>(reset).color,
        Theme.of(tester.element(reset)).colorScheme.error,
      );
      expect(controller.operationCalls, 0);
    },
  );
}

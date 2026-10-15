import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/gestures.dart';
import 'package:niran/main.dart';
import 'package:niran/core/widgets/navigation_dock.dart';
import 'package:niran/core/platform/native_models.dart';
import 'package:niran/features/vpn/app_controller.dart';
import 'package:niran/features/vpn/home_canvas.dart';
import 'home_canvas_test.dart' show CanvasController;

void main() {
  testWidgets('horizontal dock accommodates enlarged text', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: NavigationDock(
                destinations: const [
                  NavigationDestination(icon: Icon(Icons.home), label: 'Home'),
                ],
                selectedIndex: 0,
                onSelected: (_) {},
                vertical: false,
              ),
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
  });
  testWidgets('floating bottom dock leaves Home controls accessible', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1152, 720);
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
    await controller.updateSettings({'navigationPosition': 'bottom'});
    await tester.pumpAndSettle();
    final last = tester.getRect(find.byKey(const Key('home-tile-logs')));
    final dock = tester.getRect(find.byKey(const Key('navigation-dock')));
    expect(last.bottom, lessThanOrEqualTo(dock.top));
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'selected navigation remains stretchable without triggering another tab',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
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
      final home = find.descendant(
        of: find.byKey(const Key('navigation-tab-0')),
        matching: find.text('Home'),
      );
      final resting = tester.getCenter(home);
      final drag = await tester.startGesture(
        resting,
        kind: PointerDeviceKind.mouse,
      );
      await drag.moveBy(const Offset(30, 10));
      await tester.pumpAndSettle();
      expect(tester.getCenter(home).dx, greaterThan(resting.dx));
      await drag.up();
      await tester.pumpAndSettle();
      expect(tester.getCenter(home), resting);
      expect(find.text('Connection status'), findsOneWidget);
    },
  );
  for (final position in ['left', 'right', 'bottom']) {
    testWidgets(
      'Home edit saves $position navigation without changing the network',
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
        await tester.tap(find.byKey(const Key('customize-home')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        await tester.tap(find.byKey(const Key('navigation-placement')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        await tester.tap(
          find.text(switch (position) {
            'left' => 'Left',
            'right' => 'Right',
            _ => 'Bottom',
          }),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(controller.saves, 0);
        final preview = tester.getRect(
          find.byKey(const Key('navigation-dock')),
        );
        expect(preview.height > preview.width, position != 'bottom');
        if (position == 'right') expect(preview.left, greaterThan(1100));
        expect(find.byKey(const Key('save-home-layout')), findsOneWidget);
        await tester.tap(find.byKey(const Key('save-home-layout')));
        await tester.pumpAndSettle();
        expect(
          controller.state.value!.settings.resolvedNavigationPosition,
          position,
        );
        expect(controller.operationCalls, 0);
        expect(find.byKey(const Key('navigation-dock')), findsOneWidget);
        final dock = tester.getRect(find.byKey(const Key('navigation-dock')));
        expect(
          dock.height > dock.width,
          position == 'left' || position == 'right',
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets('navigation preview cancels without saving or losing the draft', (
    tester,
  ) async {
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
    final original = tester.getRect(find.byKey(const Key('navigation-dock')));
    await tester.tap(find.byKey(const Key('customize-home')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.drag(
      find.byKey(const Key('resize-home-logs')),
      const Offset(0, -10),
    );
    await tester.pump();
    final canvas = find.byWidgetPredicate(
      (w) => w is HomeCanvas && !w.controlsOnly,
    );
    final draft = tester.widget<HomeCanvas>(canvas).layout.encode();
    expect(draft, isNot(controller.state.value!.settings.homeLayout));
    await tester.tap(find.byKey(const Key('navigation-placement')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Top'), findsNothing);
    await tester.tap(find.text('Bottom'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      tester.getRect(find.byKey(const Key('navigation-dock'))).width,
      greaterThan(500),
    );
    expect(tester.widget<HomeCanvas>(canvas).layout.encode(), draft);
    await tester.tap(find.byKey(const Key('cancel-home-edit')));
    await tester.pumpAndSettle();
    expect(tester.getRect(find.byKey(const Key('navigation-dock'))), original);
    expect(controller.saves, 0);
  });
  for (final connected in [false, true]) {
    testWidgets(
      'bottom Home connection fits without internal scroll ($connected)',
      (tester) async {
        tester.view.physicalSize = const Size(1152, 720);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final controller = CanvasController(
          connection: ConnectionInfo(
            state: connected ? 'connected' : 'disconnected',
          ),
        );
        await tester.pumpWidget(
          ProviderScope(
            overrides: [appControllerProvider.overrideWith(() => controller)],
            child: const NirangApp(),
          ),
        );
        await tester.pumpAndSettle();
        await controller.updateSettings({'navigationPosition': 'bottom'});
        await tester.pumpAndSettle();
        final card = find.byKey(const Key('home-connection'));
        expect(
          find.descendant(of: card, matching: find.byType(Scrollable)),
          findsNothing,
        );
        final metrics = find.descendant(
          of: card,
          matching: find.text('Public IP'),
        );
        expect(
          tester.getRect(metrics).bottom,
          lessThan(tester.getRect(card).bottom - 12),
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
  test('retired top placement resolves to bottom', () {
    expect(
      const NativeSettings(
        navigationPosition: 'top',
      ).resolvedNavigationPosition,
      'bottom',
    );
  });
  test('legacy navigation side is preserved until explicitly edited', () {
    expect(
      NativeSettings.fromMap({'sidebarRight': true}).resolvedNavigationPosition,
      'right',
    );
    expect(const NativeSettings().resolvedNavigationPosition, 'left');
    expect(
      const NativeSettings().withUpdates({
        'navigationPosition': 'bottom',
      }).resolvedNavigationPosition,
      'bottom',
    );
  });
  testWidgets('navigation does not shift when Settings opens', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
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
    final nav = find.byKey(const Key('navigation-dock'));
    final home = find.descendant(of: nav, matching: find.text('Home'));
    final before = tester.getTopLeft(home);
    await tester.tap(find.descendant(of: nav, matching: find.text('Settings')));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(home), before);
    expect(tester.takeException(), isNull);
  });
}

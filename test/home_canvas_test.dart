import 'package:flutter/material.dart';
import 'dart:ui' show PointerDeviceKind;
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niran/core/platform/native_models.dart';
import 'package:niran/features/vpn/app_controller.dart';
import 'package:niran/main.dart';
import 'package:niran/features/settings/settings_screen.dart';
import 'home_refinement_test.dart' show HomeController;

class CanvasController extends HomeController {
  CanvasController({super.language, super.connection});
  @override
  Future<AppSnapshot> build() async => (await super.build()).copyWith(
    logs: List.generate(
      30,
      (i) => LogEntry(
        DateTime(2026, 10, 1, 12, 0, i),
        'info',
        'Recorded event $i',
      ),
    ),
  );
}

void main() {
  Future<void> mount(
    WidgetTester tester,
    CanvasController controller, {
    Size size = const Size(1280, 900),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith(() => controller)],
        child: const NirangApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> edit(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('customize-home')));
    await tester.pump(const Duration(milliseconds: 250));
  }

  Future<void> drag(WidgetTester tester, String source, String target) async {
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(Key('home-tile-$source'))),
      kind: PointerDeviceKind.mouse,
    );
    await gesture.moveTo(
      tester.getCenter(find.byKey(Key('home-tile-$target'))),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await gesture.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 220));
  }

  testWidgets(
    'mouse drag swaps independent Proxy/TUN cards without executing actions',
    (tester) async {
      final controller = CanvasController();
      await mount(tester, controller);
      await edit(tester);
      final before = tester.getRect(
        find.byKey(const Key('home-tile-systemProxy')),
      );
      final destination = tester.getRect(
        find.byKey(const Key('home-tile-tun')),
      );
      await drag(tester, 'systemProxy', 'tun');
      expect(
        tester.getRect(find.byKey(const Key('home-tile-systemProxy'))).left,
        closeTo(destination.left, 2),
      );
      expect(
        tester.getRect(find.byKey(const Key('home-tile-tun'))).left,
        closeTo(before.left, 2),
      );
      expect(controller.operationCalls, 0);
      await tester.tap(find.byKey(const Key('save-home-layout')));
      await tester.pumpAndSettle();
      expect(controller.saves, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'stationary edit cards share their backdrop but a dragged card does not',
    (tester) async {
      await mount(tester, CanvasController());
      await edit(tester);
      final board = find.byKey(const Key('home-control-canvas'));
      final filters = find.descendant(
        of: board,
        matching: find.byType(BackdropFilter),
      );
      final keys = tester
          .renderObjectList<RenderBackdropFilter>(filters)
          .map((filter) => filter.backdropKey)
          .toSet();
      expect(keys.length, 1);
      expect(keys.single, isNotNull);
      final actionRect = tester.getRect(
        find.byKey(const Key('home-tile-clearProxy')),
      );
      expect(
        actionRect.width,
        lessThan(200),
        reason: 'Home actions must not fill a quarter of a desktop page',
      );
      final tileDecorations = tester.widgetList<DecoratedBox>(
        find.descendant(
          of: find.byKey(const Key('home-tile-clearProxy')),
          matching: find.byType(DecoratedBox),
        ),
      );
      expect(
        tileDecorations.where(
          (box) =>
              box.decoration is BoxDecoration &&
              (box.decoration as BoxDecoration).border?.top.color ==
                  Theme.of(
                    tester.element(board),
                  ).colorScheme.primary.withValues(alpha: .55),
        ),
        isEmpty,
      );
      final close = find.byKey(const Key('remove-home-logs'));
      final closeDecoration =
          tester
                  .widget<DecoratedBox>(
                    find
                        .ancestor(
                          of: close,
                          matching: find.byType(DecoratedBox),
                        )
                        .first,
                  )
                  .decoration
              as BoxDecoration;
      expect(closeDecoration.shape, BoxShape.circle);
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const Key('home-tile-clearProxy'))),
        kind: PointerDeviceKind.mouse,
      );
      await gesture.moveBy(const Offset(30, 0));
      await tester.pump(const Duration(milliseconds: 50));
      final movingKeys = tester
          .renderObjectList<RenderBackdropFilter>(filters)
          .map((filter) => filter.backdropKey)
          .toSet();
      expect(
        movingKeys.length,
        2,
        reason: 'Overlapping drag preview must not reuse another card blur',
      );
      await gesture.cancel();
      await tester.pump(const Duration(milliseconds: 100));
    },
  );

  testWidgets(
    'subscription and traffic move independently and Cancel restores placements',
    (tester) async {
      final controller = CanvasController();
      await mount(tester, controller);
      final initial = tester.getRect(
        find.byKey(const Key('home-tile-subscription')),
      );
      final traffic = tester.getRect(
        find.byKey(const Key('home-tile-traffic')),
      );
      await edit(tester);
      // No left/right toggles: a regular mouse drag owns the whole card.
      expect(find.byKey(const Key('usage-side-left')), findsNothing);
      await drag(tester, 'subscription', 'traffic');
      expect(
        tester.getRect(find.byKey(const Key('home-tile-subscription'))).top,
        greaterThan(initial.top),
      );
      expect(
        tester.getRect(find.byKey(const Key('home-tile-traffic'))).top,
        lessThan(traffic.top),
      );
      await tester.tap(find.byKey(const Key('cancel-home-edit')));
      await tester.pumpAndSettle();
      expect(
        tester.getRect(find.byKey(const Key('home-tile-subscription'))),
        initial,
      );
      expect(controller.saves, 0);
    },
  );

  testWidgets(
    'logs are multi-line, removable by edit X and restorable from Settings',
    (tester) async {
      final controller = CanvasController();
      await mount(tester, controller);
      expect(find.byKey(const Key('home-log-scroll')), findsOneWidget);
      expect(
        find.textContaining('Recorded event 0', findRichText: true),
        findsOneWidget,
      );
      expect(
        find.textContaining('Recorded event 29', findRichText: true),
        findsOneWidget,
      );
      await edit(tester);
      expect(find.byType(SwitchListTile), findsNothing);
      await tester.tap(find.byKey(const Key('remove-home-logs')));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byKey(const Key('home-tile-logs')), findsNothing);
      await tester.tap(find.byKey(const Key('save-home-layout')));
      await tester.pumpAndSettle();
      expect(
        controller.state.asData!.value.settings.showRecentLogsOnHome,
        isFalse,
      );
      await tester.tap(find.text('Settings').last);
      await tester.pumpAndSettle();
      final settingsScroll = find
          .descendant(
            of: find.byType(SettingsScreen),
            matching: find.byType(Scrollable),
          )
          .first;
      await tester.scrollUntilVisible(
        find.text('APPEARANCE'),
        400,
        scrollable: settingsScroll,
      );
      await tester.tap(find.text('APPEARANCE'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Show recent logs on Home'),
        400,
        scrollable: settingsScroll,
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Show recent logs on Home'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Show recent logs on Home'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Home').last);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('home-tile-logs')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'logs exchange with status, resize inside bounds, restart is separate',
    (tester) async {
      final controller = CanvasController();
      await mount(tester, controller);
      await edit(tester);
      final status = tester.getRect(find.byKey(const Key('home-tile-status')));
      await drag(tester, 'logs', 'status');
      final logRect = tester.getRect(find.byKey(const Key('home-tile-logs')));
      expect(logRect.top, closeTo(status.top, 2));
      final resize = await tester.startGesture(
        tester.getCenter(find.byKey(const Key('resize-home-logs'))),
      );
      await resize.moveBy(const Offset(-70, -30));
      await resize.up();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 220));
      expect(
        tester.getSize(find.byKey(const Key('home-tile-logs'))).width,
        lessThan(logRect.width),
      );
      expect(find.byKey(const Key('home-tile-restart')), findsOneWidget);
      final board = tester.getRect(find.byKey(const Key('home-canvas')));
      expect(
        board.contains(
          tester.getBottomRight(find.byKey(const Key('home-tile-logs'))),
        ),
        isTrue,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('minimum Persian Home never overflows and has no outer scroll', (
    tester,
  ) async {
    await mount(
      tester,
      CanvasController(
        language: 'fa',
        connection: const ConnectionInfo(state: 'connected'),
      ),
      size: const Size(800, 600),
    );
    await edit(tester);
    final canvas = tester.getRect(find.byKey(const Key('home-canvas')));
    for (final id in [
      'status',
      'subscription',
      'traffic',
      'logs',
      'systemProxy',
      'clearProxy',
      'tun',
      'restart',
    ]) {
      final tile = tester.getRect(find.byKey(Key('home-tile-$id')));
      expect(tile.left, greaterThanOrEqualTo(canvas.left));
      expect(tile.bottom, lessThanOrEqualTo(canvas.bottom));
    }
    expect(tester.takeException(), isNull);
  });
}

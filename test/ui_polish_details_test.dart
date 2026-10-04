import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niran/core/widgets/niran_toast.dart';
import 'package:niran/core/widgets/simple_frosted_surface.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:niran/features/vpn/app_controller.dart';
import 'package:niran/main.dart';

import 'home_canvas_test.dart' show CanvasController;

import 'package:niran/core/registration/device_registration.dart';
import 'package:niran/features/registration/registration_bootstrap.dart';
import 'package:niran/features/logs/logs_screen.dart';
import 'package:niran/core/platform/native_models.dart';

import 'ui_polish_test.dart' as harness;

void main() {
  tearDown(clearDeviceAccessBlocked);
  testWidgets(
    'subscription success toast follows multi-phase refresh completion',
    (tester) async {
      final controller = PolishingController();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [appControllerProvider.overrideWith(() => controller)],
          child: const NirangApp(),
        ),
      );
      await tester.pumpAndSettle();
      controller.beginRefresh();
      await tester.pump();
      controller.receiveSubscription();
      await tester.pump();
      expect(find.text('Subscription updated'), findsNothing);
      controller.finishRefresh();
      await tester.pumpAndSettle();
      expect(find.text('Subscription updated'), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
    },
  );
  testWidgets(
    'a final log batch received while pointer is held appears on release',
    (tester) async {
      final controller = PolishingController();
      await harness.mount(tester, const LogsScreen(), controller: controller);
      final viewport = tester.getRect(find.byType(ListView));
      final mouse = await tester.startGesture(
        viewport.bottomRight - const Offset(8, 8),
        kind: PointerDeviceKind.mouse,
      );
      controller.appendLog();
      await tester.pump();
      expect(find.text('Final arrived log'), findsNothing);
      await mouse.up();
      await tester.pumpAndSettle();
      expect(find.text('Final arrived log'), findsOneWidget);
    },
  );

  testWidgets(
    'access verification and graphics overlap without exposing Home',
    (tester) async {
      final remote = PendingAccess();
      final graphics = Completer<void>();
      await tester.pumpWidget(
        NiranRegistrationBootstrap(
          coordinator: remote,
          graphicsReady: graphics.future,
          child: const MaterialApp(home: Text('HOME_READY')),
        ),
      );
      await tester.pump();
      expect(remote.statusStarted, isTrue);
      expect(find.text('niraN'), findsOneWidget);
      expect(find.text('HOME_READY'), findsNothing);
      remote.status.complete();
      await tester.pump();
      expect(find.text('HOME_READY'), findsNothing);
      graphics.complete();
      await tester.pumpAndSettle();
      expect(find.text('HOME_READY'), findsOneWidget);
    },
  );

  testWidgets('a blocked response does not wait for graphics or expose Home', (
    tester,
  ) async {
    final remote = PendingAccess();
    final graphics = Completer<void>();
    await tester.pumpWidget(
      NiranRegistrationBootstrap(
        coordinator: remote,
        graphicsReady: graphics.future,
        child: const MaterialApp(home: Text('HOME_READY')),
      ),
    );
    await tester.pump();
    remote.status.completeError(
      const DeviceAccessException('blocked_by_administrator', 'Blocked'),
    );
    await tester.pumpAndSettle();
    expect(find.text('Access blocked'), findsOneWidget);
    expect(find.text('HOME_READY'), findsNothing);
    graphics.complete();
  });

  testWidgets(
    'operation toast is compact, undimmed and disappears automatically',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showNiranToast(context, 'TCP Ping: 45 ms'),
                child: const Text('Show'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Show'));
      await tester.pumpAndSettle();
      expect(find.text('TCP Ping: 45 ms'), findsOneWidget);
      expect(
        tester.getSize(find.byType(SimpleFrostedSurface)).width,
        lessThan(500),
      );
      expect(
        tester
            .widgetList<ModalBarrier>(find.byType(ModalBarrier))
            .every((barrier) => (barrier.color?.a ?? 0) == 0),
        isTrue,
      );
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(find.text('TCP Ping: 45 ms'), findsNothing);
    },
  );

  testWidgets('Logs copies the manually highlighted word from right click', (
    tester,
  ) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await harness.mount(tester, const LogsScreen());
    final text = find.text('Recorded event 29');
    final paragraph = tester.renderObject<RenderParagraph>(
      find.descendant(of: text, matching: find.byType(RichText)),
    );
    final box = paragraph
        .getBoxesForSelection(
          const TextSelection(baseOffset: 9, extentOffset: 14),
        )
        .single
        .toRect();
    final start = paragraph.localToGlobal(Offset(box.left + .2, box.center.dy));
    final end = paragraph.localToGlobal(Offset(box.right - .2, box.center.dy));
    final mouse = await tester.startGesture(
      start,
      kind: PointerDeviceKind.mouse,
    );
    await mouse.moveTo(end);
    await mouse.up();
    await tester.pumpAndSettle();
    final secondary = await tester.startGesture(
      (start + end) / 2,
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await secondary.up();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Copy').last);
    await tester.pumpAndSettle();
    expect(copied, 'event');
    expect(tester.takeException(), isNull);
  });
}

class PolishingController extends CanvasController {
  void beginRefresh() => state = AsyncData(
    state.asData!.value.copyWith(
      isRefreshing: true,
      clearSubscriptionError: true,
    ),
  );
  void receiveSubscription() =>
      state = AsyncData(state.asData!.value.copyWith(lastUpdated: 200));
  void finishRefresh() =>
      state = AsyncData(state.asData!.value.copyWith(isRefreshing: false));
  void appendLog() => state = AsyncData(
    state.asData!.value.copyWith(
      logs: [
        ...state.asData!.value.logs,
        LogEntry(DateTime(2026, 10, 4), 'info', 'Final arrived log'),
      ],
    ),
  );
}

class PendingAccess
    implements DeviceRegistrationCoordinator, RemoteAccessController {
  final status = Completer<void>();
  bool statusStarted = false;
  @override
  Future<bool> initialize() async => true;
  @override
  Future<void> requireAllowed() {
    statusStarted = true;
    return status.future;
  }

  @override
  Future<void> accept() async {}
  @override
  Future<void> exitApplication() async {}
  @override
  Future<RemoteSubscription> fetchSubscription() async =>
      const RemoteSubscription([], null);
}

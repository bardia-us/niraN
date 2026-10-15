import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niran/core/registration/device_registration.dart';
import 'package:niran/features/registration/registration_bootstrap.dart';

void main() {
  testWidgets(
    'a startup with no graphics work does not await a GPU acknowledgement',
    (tester) async {
      final coordinator = _PendingAccess();
      final raster = Completer<void>();
      await tester.pumpWidget(
        NiranRegistrationBootstrap(
          coordinator: coordinator,
          firstFrameRasterized: raster.future,
          child: const MaterialApp(home: Text('HOME_READY')),
        ),
      );
      coordinator.registration.complete(true);
      coordinator.access.complete();
      await tester.pump();
      await tester.pump();
      expect(find.text('HOME_READY'), findsOneWidget);
      raster.complete();
      await tester.pumpAndSettle();
    },
  );
  testWidgets(
    'missing raster acknowledgement skips optional work without trapping authorized UI',
    (tester) async {
      final coordinator = _PendingAccess();
      final raster = Completer<void>();
      var graphicsStarted = false;
      await tester.pumpWidget(
        NiranRegistrationBootstrap(
          coordinator: coordinator,
          firstFrameRasterized: raster.future,
          prepareGraphics: () async {
            graphicsStarted = true;
          },
          child: const MaterialApp(home: Text('HOME_READY')),
        ),
      );
      coordinator.registration.complete(true);
      coordinator.access.complete();
      await tester.pump();
      await tester.pump(const Duration(seconds: 3));
      await tester.pump();
      expect(graphicsStarted, false);
      expect(find.text('HOME_READY'), findsOneWidget);
      raster.complete();
      await tester.pumpAndSettle();
      expect(graphicsStarted, false);
    },
  );
  testWidgets(
    'optional graphics waits for renderer presentation, not layout alone',
    (tester) async {
      final coordinator = _PendingAccess();
      final presented = Completer<void>();
      var graphicsStarted = false;
      await tester.pumpWidget(
        NiranRegistrationBootstrap(
          coordinator: coordinator,
          firstFrameRasterized: presented.future,
          prepareGraphics: () async {
            graphicsStarted = true;
          },
          child: const MaterialApp(home: Text('HOME_READY')),
        ),
      );
      coordinator.registration.complete(true);
      coordinator.access.complete();
      await tester.pump();
      expect(graphicsStarted, isFalse);
      expect(find.text('HOME_READY'), findsNothing);
      presented.complete();
      await tester.pumpAndSettle();
      expect(graphicsStarted, isTrue);
      expect(find.text('HOME_READY'), findsOneWidget);
    },
  );
  tearDown(clearDeviceAccessBlocked);

  testWidgets('initial loading follows the Persian system locale', (
    tester,
  ) async {
    tester.platformDispatcher.localesTestValue = const [Locale('fa')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    final coordinator = _PendingAccess();
    await tester.pumpWidget(
      NiranRegistrationBootstrap(
        coordinator: coordinator,
        child: const MaterialApp(home: Text('HOME_READY')),
      ),
    );
    await tester.pump();
    expect(find.text('آماده‌سازی دستگاه…'), findsOneWidget);
    coordinator.registration.complete(false);
    await tester.pumpAndSettle();
  });

  testWidgets('hung optional graphics cannot trap authorized startup', (
    tester,
  ) async {
    final coordinator = _PendingAccess();
    final graphics = Completer<void>();
    await tester.pumpWidget(
      NiranRegistrationBootstrap(
        coordinator: coordinator,
        prepareGraphics: () => graphics.future,
        child: const MaterialApp(home: Text('HOME_READY')),
      ),
    );
    coordinator.registration.complete(true);
    coordinator.access.complete();
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
    expect(find.text('HOME_READY'), findsOneWidget);
    graphics.complete();
    await tester.pumpAndSettle();
  });

  // Starting preparation in initState before the branded screen is laid out
  // recreates the startup hitch and must fail this test.
  testWidgets('optional graphics start after the loading frame is painted', (
    tester,
  ) async {
    final coordinator = _PendingAccess();
    final graphics = Completer<void>();
    var paintedLoadingBeforeGraphics = false;
    await tester.pumpWidget(
      NiranRegistrationBootstrap(
        coordinator: coordinator,
        prepareGraphics: () {
          final progress = find.byType(LinearProgressIndicator);
          if (progress.evaluate().isNotEmpty) {
            final renderObject = tester.renderObject(progress);
            paintedLoadingBeforeGraphics = !renderObject.debugNeedsPaint;
          }
          return graphics.future;
        },
        child: const MaterialApp(home: Text('HOME_READY')),
      ),
    );
    expect(paintedLoadingBeforeGraphics, isTrue);
    coordinator.registration.complete(true);
    coordinator.access.complete();
    graphics.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('optional graphics failure falls back after authorized access', (
    tester,
  ) async {
    final coordinator = _PendingAccess();
    await tester.pumpWidget(
      NiranRegistrationBootstrap(
        coordinator: coordinator,
        prepareGraphics: () async => throw StateError('GPU unavailable'),
        child: const MaterialApp(home: Text('HOME_READY')),
      ),
    );
    expect(find.text('HOME_READY'), findsNothing);
    coordinator.registration.complete(true);
    await tester.pump();
    expect(find.text('HOME_READY'), findsNothing);
    coordinator.access.complete();
    await tester.pumpAndSettle();
    expect(find.text('HOME_READY'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('blocked access wins while optional graphics are pending', (
    tester,
  ) async {
    final coordinator = _PendingAccess();
    final graphics = Completer<void>();
    await tester.pumpWidget(
      NiranRegistrationBootstrap(
        coordinator: coordinator,
        prepareGraphics: () => graphics.future,
        child: const MaterialApp(home: Text('HOME_READY')),
      ),
    );
    coordinator.registration.complete(true);
    await tester.pump();
    coordinator.access.completeError(
      const DeviceAccessException('blocked_by_administrator', 'Blocked'),
    );
    await tester.pumpAndSettle();
    expect(find.text('Access blocked'), findsOneWidget);
    expect(find.text('HOME_READY'), findsNothing);
    graphics.complete();
    await tester.pumpAndSettle();
    expect(find.text('HOME_READY'), findsNothing);
  });

  // Returning a generic spinner instead of the real pending stage should fail
  // this test; completing registration must not expose Home before access.
  testWidgets(
    'loading reports device then access work while Home stays gated',
    (tester) async {
      final coordinator = _PendingAccess();
      await tester.pumpWidget(
        NiranRegistrationBootstrap(
          coordinator: coordinator,
          child: const MaterialApp(home: Text('HOME_READY')),
        ),
      );
      expect(find.text('Preparing device…'), findsOneWidget);
      expect(find.text('HOME_READY'), findsNothing);
      coordinator.registration.complete(true);
      await tester.pump();
      expect(find.text('Checking access…'), findsOneWidget);
      expect(find.text('HOME_READY'), findsNothing);
      await tester.pump(const Duration(seconds: 4));
      expect(
        find.text('Waiting for the access check. Please stay connected.'),
        findsOneWidget,
      );
      coordinator.access.complete();
      await tester.pumpAndSettle();
      expect(find.text('HOME_READY'), findsOneWidget);
    },
  );

  // Removing the graphics gate or adding a minimum loading duration should
  // fail: the label describes actual work and Home appears as soon as it ends.
  testWidgets('graphics loading ends immediately when real preparation ends', (
    tester,
  ) async {
    final coordinator = _PendingAccess();
    final graphics = Completer<void>();
    await tester.pumpWidget(
      NiranRegistrationBootstrap(
        coordinator: coordinator,
        graphicsReady: graphics.future,
        child: const MaterialApp(home: Text('HOME_READY')),
      ),
    );
    coordinator.registration.complete(true);
    coordinator.access.complete();
    await tester.pump();
    expect(find.text('Preparing interface…'), findsOneWidget);
    expect(find.text('HOME_READY'), findsNothing);
    graphics.complete();
    await tester.pump();
    await tester.pump();
    expect(find.text('HOME_READY'), findsOneWidget);
  });
}

class _PendingAccess
    implements DeviceRegistrationCoordinator, RemoteAccessController {
  final registration = Completer<bool>();
  final access = Completer<void>();

  @override
  Future<bool> initialize() => registration.future;
  @override
  Future<void> requireAllowed() => access.future;
  @override
  Future<void> accept() async {}
  @override
  Future<void> exitApplication() async {}
  @override
  Future<RemoteSubscription> fetchSubscription() async =>
      const RemoteSubscription([], null);
}

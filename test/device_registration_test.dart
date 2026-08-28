import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niran/core/registration/device_registration.dart';
import 'package:niran/features/registration/registration_bootstrap.dart';

void main() {
  test(
    'registration is consent-gated and persists a random installation id',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'niran-registration-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final info = _FakeInfoProvider();
      final transport = _RecordingTransport();
      final service = DeviceRegistrationService(
        infoProvider: info,
        transport: transport,
        dataDirectory: directory,
        clock: () => DateTime.utc(2026, 8, 28, 12),
      );

      expect(await service.initialize(), isFalse);
      expect(info.reads, 0);
      expect(transport.payloads, isEmpty);

      await service.accept();
      await _waitFor(() => transport.payloads.isNotEmpty);
      final payload = transport.payloads.single;
      expect(payload.keys.toSet(), {
        'schema_version',
        'installation_id',
        'device_name',
        'windows_username',
        'windows_version',
        'app_version',
        'first_seen',
        'last_seen',
      });
      expect(
        payload['installation_id'],
        matches(
          RegExp(
            r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
          ),
        ),
      );

      final local =
          jsonDecode(
                await File(
                  '${directory.path}${Platform.pathSeparator}device-registration.json',
                ).readAsString(),
              )
              as Map<String, dynamic>;
      expect(local['consent_accepted'], isTrue);
      expect(local['consent_version'], 2);
      expect(local['installation_id'], payload['installation_id']);
      expect(local['schema_version'], 2);
      expect(local['device_name'], 'DATA');
      expect(local['windows_username'], 'Bardia Behrad');
      expect(local.containsKey('device_model'), isFalse);
      expect(local.containsKey('username'), isFalse);
      expect(local.containsKey('hostname'), isFalse);

      final second = DeviceRegistrationService(
        infoProvider: info,
        transport: transport,
        dataDirectory: directory,
        clock: () => DateTime.utc(2026, 8, 29, 12),
      );
      expect(await second.initialize(), isTrue);
      await _waitFor(() => transport.payloads.length == 2);
      expect(
        transport.payloads.last['installation_id'],
        payload['installation_id'],
      );
    },
  );

  test(
    'previous consent is not reused for newly disclosed identity fields',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'niran-old-consent-',
      );
      addTearDown(() => directory.delete(recursive: true));
      await File(
        '${directory.path}${Platform.pathSeparator}device-registration.json',
      ).writeAsString(
        jsonEncode({
          'schema_version': 1,
          'consent_accepted': true,
          'installation_id': '12345678-1234-4123-8123-123456789abc',
          'first_seen': '2026-08-28T12:00:00.000Z',
        }),
      );
      final info = _FakeInfoProvider();
      final transport = _RecordingTransport();
      final service = DeviceRegistrationService(
        infoProvider: info,
        transport: transport,
        dataDirectory: directory,
      );

      expect(await service.initialize(), isFalse);
      expect(info.reads, 0);
      expect(transport.payloads, isEmpty);
    },
  );

  testWidgets('Home child is not built until registration is accepted', (
    tester,
  ) async {
    final coordinator = _FakeCoordinator();
    await tester.pumpWidget(
      NiranRegistrationBootstrap(
        coordinator: coordinator,
        child: const MaterialApp(home: Text('HOME_READY')),
      ),
    );
    await tester.pump();

    expect(find.text('HOME_READY'), findsNothing);
    expect(find.text('Accept & Continue'), findsOneWidget);
    expect(find.textContaining('does not collect'), findsOneWidget);

    await tester.ensureVisible(find.text('Accept & Continue'));
    await tester.tap(find.text('Accept & Continue'));
    await tester.pumpAndSettle();
    expect(coordinator.accepts, 1);
    expect(find.text('HOME_READY'), findsOneWidget);
  });
}

Future<void> _waitFor(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 2));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('Timed out waiting for registration sync');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

final class _FakeInfoProvider implements DeviceRegistrationInfoProvider {
  int reads = 0;

  @override
  Future<DeviceRegistrationInfo> read() async {
    reads++;
    return const DeviceRegistrationInfo(
      deviceName: 'DATA',
      windowsUsername: 'Bardia Behrad',
      windowsVersion: 'Windows 11 24H2 (build 26100.1)',
      appVersion: '0.3.0',
    );
  }

  @override
  Future<void> exitApplication() async {}
}

final class _RecordingTransport implements DeviceRegistrationTransport {
  final List<Map<String, Object?>> payloads = [];

  @override
  Future<void> send(Map<String, Object?> payload) async {
    payloads.add(Map<String, Object?>.from(payload));
  }
}

final class _FakeCoordinator implements DeviceRegistrationCoordinator {
  int accepts = 0;

  @override
  Future<bool> initialize() async => false;

  @override
  Future<void> accept() async => accepts++;

  @override
  Future<void> exitApplication() async {}
}

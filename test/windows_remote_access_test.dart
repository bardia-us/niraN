import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:niran/core/registration/device_registration.dart';
import 'package:niran/platform/windows/windows_remote_access.dart';

void main() {
  test('publisher system id is one-way and stable across reinstall', () async {
    final firstDirectory = await Directory.systemTemp.createTemp(
      'niran-access-a-',
    );
    final secondDirectory = await Directory.systemTemp.createTemp(
      'niran-access-b-',
    );
    addTearDown(() async {
      await firstDirectory.delete(recursive: true);
      await secondDirectory.delete(recursive: true);
    });
    final firstTransport = _RegistryTransport();
    final secondTransport = _RegistryTransport();
    final first = WindowsRemoteAccessService(
      infoProvider: const _InfoProvider(),
      transport: firstTransport,
      dataDirectory: firstDirectory,
    );
    final second = WindowsRemoteAccessService(
      infoProvider: const _InfoProvider(),
      transport: secondTransport,
      dataDirectory: secondDirectory,
    );

    await first.accept();
    await second.accept();

    final firstPayload = firstTransport.payloads.single;
    final secondPayload = secondTransport.payloads.single;
    expect(firstPayload['schema_version'], 5);
    expect(firstPayload['platform'], 'windows');
    expect(firstPayload['app_name'], 'niraN');
    expect(firstPayload['device_key'], secondPayload['device_key']);
    expect(
      firstPayload['installation_id'],
      isNot(secondPayload['installation_id']),
    );
    expect('${firstPayload['device_key']}', hasLength(64));
    expect(
      jsonEncode(firstPayload),
      isNot(contains(_InfoProvider.rawSystemId)),
    );

    final local = await File(
      '${firstDirectory.path}${Platform.pathSeparator}device-registration.json',
    ).readAsString();
    expect(local, isNot(contains(_InfoProvider.rawSystemId)));
  });

  test('subscription access is authenticated and block persists', () async {
    final directory = await Directory.systemTemp.createTemp(
      'niran-access-block-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final transport = _RegistryTransport();
    final service = WindowsRemoteAccessService(
      infoProvider: const _InfoProvider(),
      transport: transport,
      dataDirectory: directory,
    );
    await service.accept();

    final subscription = await service.fetchSubscription();
    expect(utf8.decode(subscription.bytes), startsWith('vless://'));
    expect(subscription.usageHeader, contains('total='));
    expect(transport.tokens.last, _RegistryTransport.token);

    transport.blocked = true;
    await expectLater(
      service.requireAllowed(),
      throwsA(
        isA<DeviceAccessException>().having(
          (error) => error.reason,
          'reason',
          'blocked_by_administrator',
        ),
      ),
    );

    final callsAfterBlock = transport.payloads.length;
    final restarted = WindowsRemoteAccessService(
      infoProvider: const _InfoProvider(),
      transport: transport,
      dataDirectory: directory,
    );
    await expectLater(
      restarted.initialize(),
      throwsA(isA<DeviceAccessException>()),
    );
    expect(transport.payloads, hasLength(callsAfterBlock + 1));

    transport.blocked = false;
    expect(await restarted.initialize(), isTrue);
    expect(transport.payloads.last['action'], 'status');
  });
}

final class _InfoProvider implements DeviceRegistrationInfoProvider {
  const _InfoProvider();

  static const rawSystemId = '0123456789abcdef0123456789abcdef';

  @override
  Future<DeviceRegistrationInfo> read() async => const DeviceRegistrationInfo(
    deviceName: 'DESKTOP-TEST',
    windowsUsername: 'Test User',
    windowsVersion: 'Windows 11 24H2',
    appVersion: '0.3.1',
    systemId: rawSystemId,
    systemIdSource: 'tpm',
  );

  @override
  Future<void> exitApplication() async {}
}

final class _RegistryTransport implements WindowsRegistryTransport {
  static const token = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';
  final List<Map<String, Object?>> payloads = [];
  final List<String?> tokens = [];
  bool blocked = false;

  @override
  Future<RegistryResponse> send(
    Map<String, Object?> payload, {
    String? token,
    int maximumBytes = 8192,
  }) async {
    payloads.add(Map<String, Object?>.from(payload));
    tokens.add(token);
    if (blocked) {
      return const RegistryResponse(
        statusCode: 403,
        bytes: [],
        json: {
          'ok': false,
          'allowed': false,
          'blocked': true,
          'minimum_version': '0.3.1',
          'update_required': false,
          'reason': 'blocked_by_administrator',
        },
        usageHeader: null,
      );
    }
    if (payload['action'] == 'subscription') {
      return RegistryResponse(
        statusCode: 200,
        bytes: utf8.encode(
          'vless://00000000-0000-4000-8000-000000000001@example.com:443?security=tls&type=ws#Test',
        ),
        json: null,
        usageHeader: 'upload=1; download=2; total=100',
      );
    }
    return const RegistryResponse(
      statusCode: 200,
      bytes: [],
      json: {
        'ok': true,
        'allowed': true,
        'blocked': false,
        'minimum_version': '0.3.1',
        'update_required': false,
        'reason': 'allowed',
        'access_token': _RegistryTransport.token,
      },
      usageHeader: null,
    );
  }
}

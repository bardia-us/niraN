import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niran/core/registration/device_registration.dart';
import 'package:niran/platform/windows/windows_native_host.dart';
import 'package:niran/platform/windows/windows_platform_backend.dart';
import 'package:niran/platform/windows/windows_server_record.dart';
import 'package:niran/platform/windows/windows_traffic.dart';

void main() {
  test('cancel during listener readiness releases ping ownership', () async {
    final dir = await _seed(2);
    var started = false;
    final gate = Completer<void>();
    final backend = _backend(
      dir,
      readiness: (_) {
        started = true;
        return gate.future;
      },
    );
    await backend.initialize();
    final operation = backend.pingAll();
    await _until(() => started);
    await backend.cancelPing();
    await operation.timeout(const Duration(milliseconds: 500));
    gate.complete();
    await backend.disconnect();
    await dir.delete(recursive: true);
  });
  test(
    'queued ping workers each receive their timeout instead of sharing one batch deadline',
    () async {
      final dir = await _seed(24);
      final backend = _backend(
        dir,
        probe: (_) async {
          await Future<void>.delayed(const Duration(milliseconds: 850));
          return 42;
        },
      );
      await backend.initialize();
      await backend.updateSettings({
        'realPingConcurrency': 4,
        'realDelayTimeoutSeconds': 3,
      });
      await backend.pingAll();
      final servers = ((await backend.initialize())['servers'] as List)
          .cast<Map>();
      expect(servers.where((s) => s['status'] == 'success'), hasLength(24));
      await backend.disconnect();
      await dir.delete(recursive: true);
    },
  );
  test(
    'disconnect captures a final short-session sample before stopping the Core',
    () async {
      final dir = await _seed(1);
      var queries = 0;
      final backend = WindowsPlatformBackend(
        host: _Host(),
        dataDirectory: dir,
        remoteAccess: _Access(),
        autoStartCore: false,
        proxyReadinessProbe: (_) async {},
        localPortPreflight: (_) async {},
        trafficCounterQuery: () async {
          queries++;
          return TrafficCounters(
            queries == 1 ? 10 : 20,
            queries == 1 ? 30 : 70,
          );
        },
      );
      await backend.initialize();
      await backend.connect('s0');
      await backend.disconnect();
      final traffic = (await backend.initialize())['traffic'] as Map;
      expect(traffic['lifetimeUpload'], 20);
      expect(traffic['lifetimeDownload'], 70);
      expect(traffic['available'], isFalse);
      final restored = _backend(dir);
      expect(
        ((await restored.initialize())['traffic'] as Map)['lifetimeDownload'],
        70,
      );
      await restored.disconnect();
      await dir.delete(recursive: true);
    },
  );
  test(
    'bulk ping marks all queued rows and replaces a completed worker without a group barrier',
    () async {
      final dir = await _seed(32);
      final probes = <Completer<int>>[];
      final backend = _backend(
        dir,
        probe: (_) {
          final pending = Completer<int>();
          probes.add(pending);
          return pending.future;
        },
      );
      final events = <Map>[];
      final sub = backend.events.listen(events.add);
      await backend.initialize();
      final operation = backend.pingAll();
      await _until(() => probes.length == 16);
      expect(
        events
            .where(
              (e) =>
                  e['type'] == 'serverPing' &&
                  (e['data'] as Map)['status'] == 'testing',
            )
            .map((e) => (e['data'] as Map)['id'])
            .toSet(),
        hasLength(32),
      );
      probes.first.complete(42);
      await _until(() => probes.length > 16);
      expect(probes.length, 17);
      await backend.cancelPing();
      // Cancel must finish the owning operation while old probes are unresolved.
      await operation.timeout(const Duration(milliseconds: 500));
      for (final probe in probes.where((p) => !p.isCompleted)) {
        probe.complete(1);
      }
      await operation;
      final statuses = ((await backend.initialize())['servers'] as List)
          .cast<Map>();
      expect(statuses.where((s) => s['status'] == 'testing'), isEmpty);
      expect(statuses.where((s) => s['status'] == 'success'), hasLength(1));
      await sub.cancel();
      await backend.disconnect();
      await dir.delete(recursive: true);
    },
  );

  test(
    'completed ping results restore after shutdown and subscription refresh invalidates them',
    () async {
      final dir = await _seed(2);
      final backend = _backend(dir);
      await backend.initialize();
      await backend.pingAll();
      await backend.disconnect();
      final restored = _backend(dir);
      final initial = await restored.initialize();
      expect(
        (initial['servers'] as List).cast<Map>().map((s) => s['ping']),
        everyElement(42),
      );
      expect(
        (initial['servers'] as List).cast<Map>().map((s) => s['status']),
        everyElement('success'),
      );
      await restored.refreshSubscription();
      final refreshed = ((await restored.initialize())['servers'] as List)
          .cast<Map>();
      expect(refreshed, isNotEmpty);
      expect(refreshed.map((s) => s['ping']), everyElement(isNull));
      expect(refreshed.map((s) => s['status']), everyElement('idle'));
      await restored.disconnect();
      await dir.delete(recursive: true);
    },
  );

  test(
    'Home slots are validated and persisted without restarting a Core',
    () async {
      final dir = await _seed(1);
      final backend = _backend(dir);
      await backend.initialize();
      await backend.updateSettings({
        'homeUsageSide': 'left',
        'homeControlOrder': 'tun,systemProxy,clearProxy',
      });
      final restored = _backend(dir);
      final settings = (await restored.initialize())['settings'] as Map;
      expect(settings['homeUsageSide'], 'left');
      expect(settings['homeControlOrder'], 'tun,systemProxy,clearProxy');
      await expectLater(
        backend.updateSettings({'homeUsageSide': 'offscreen'}),
        throwsA(isA<PlatformException>()),
      );
      await expectLater(
        backend.updateSettings({'homeControlOrder': 'tun,tun,clearProxy'}),
        throwsA(isA<PlatformException>()),
      );
      await backend.disconnect();
      await restored.disconnect();
      await dir.delete(recursive: true);
    },
  );
}

WindowsPlatformBackend _backend(
  Directory dir, {
  Future<int> Function(int)? probe,
  Future<void> Function(int)? readiness,
}) => WindowsPlatformBackend(
  host: _Host(),
  dataDirectory: dir,
  autoStartCore: false,
  remoteAccess: _Access(),
  proxyReadinessProbe: readiness ?? (_) async {},
  realDelayProbe: probe ?? (_) async => 42,
);

Future<Directory> _seed(int count) async {
  final dir = await Directory.systemTemp.createTemp('niran-bulk-');
  await File('${dir.path}/subscription-cache.json').writeAsString(
    jsonEncode({
      'servers': [
        for (var i = 0; i < count; i++)
          WindowsServerRecord(
            id: 's$i',
            name: 's$i',
            country: 'DE',
            protocol: 'vless',
            address: 'example.invalid',
            port: 443,
            credential: '00000000-0000-4000-8000-000000000001',
            transport: 'tcp',
            security: 'tls',
            parameters: const {},
          ).toPrivateJson(),
      ],
      'usage': {},
      'lastUpdated': 1,
    }),
  );
  await File('${dir.path}/state.json').writeAsString(
    jsonEncode({
      'settings': {
        'routingMode': 'global',
        'ipCheckUrl': '',
        'realPingConcurrency': 16,
      },
      'selectedId': 's0',
    }),
  );
  return dir;
}

Future<void> _until(bool Function() condition) async {
  for (var i = 0; i < 250; i++) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  expect(condition(), isTrue, reason: 'Probe workers did not progress');
}

final class _Access implements RemoteAccessController {
  @override
  Future<void> requireAllowed() async {}
  @override
  Future<RemoteSubscription> fetchSubscription() async => RemoteSubscription(
    utf8.encode(
      'vless://00000000-0000-4000-8000-000000000001@example.invalid:443?security=tls&type=tcp#refreshed',
    ),
    null,
  );
}

final class _Host implements WindowsNativeHostApi {
  @override
  Future<Map<dynamic, dynamic>> getBuildConfig() async => {
    'expectedCoreVersion': '26.3.27',
  };
  @override
  Future<String> getXrayVersion() async => '26.3.27';
  @override
  Future<String> getSingBoxVersion() async => '1.14.0';
  @override
  Future<bool> recoverSystemProxy() async => false;
  @override
  Future<String> getSystemProxyState(int port) async => 'clear';
  @override
  Future<String> protectData(String text) async =>
      base64Encode(utf8.encode(text));
  @override
  Future<String> unprotectData(String text) async =>
      utf8.decode(base64Decode(text));
  @override
  Future<List<String>> drainXrayLogs() async => [];
  @override
  Future<List<String>> drainSingBoxLogs() async => [];
  @override
  Future<List<String>> drainTunFrontendLogs() async => [];
  @override
  dynamic noSuchMethod(Invocation invocation) => Future<void>.value();
}

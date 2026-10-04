import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niran/core/registration/device_registration.dart';
import 'package:niran/features/vpn/home_layout.dart';
import 'package:niran/platform/windows/windows_native_host.dart';
import 'package:niran/platform/windows/windows_platform_backend.dart';

void main() {
  test(
    'layout and sound choice persist atomically with unrelated settings',
    () async {
      final dir = await _seed({'localSocksPort': 12345, 'themeMode': 'dark'});
      addTearDown(() => dir.delete(recursive: true));
      final host = _Host();
      final backend = _backend(dir, host: host);
      await backend.initialize();
      final encoded = HomeLayout.defaults().move('status', 0, 36)!.encode();
      final updated = await backend.updateSettings({
        'homeLayout': encoded,
        'soundStyle': 'classic',
        'soundEffects': false,
      });
      expect(updated['homeLayout'], encoded);
      expect(updated['soundStyle'], 'classic');
      expect(updated['soundEffects'], isFalse);
      expect(updated['localSocksPort'], 12345);
      expect(updated['themeMode'], 'dark');
      expect(host.coreStarts, 0);
      final restored = _backend(dir);
      final settings = (await restored.initialize())['settings'] as Map;
      expect(settings['homeLayout'], encoded);
      expect(settings['soundStyle'], 'classic');
      expect(settings['soundEffects'], isFalse);
      await backend.disconnect();
      await restored.disconnect();
    },
  );

  test(
    'invalid canvas and sound updates leave the persisted draft untouched',
    () async {
      final dir = await _seed({});
      addTearDown(() => dir.delete(recursive: true));
      final backend = _backend(dir);
      await backend.initialize();
      final encoded = HomeLayout.defaults().encode();
      await backend.updateSettings({'homeLayout': encoded});
      final original = await File('${dir.path}/state.json').readAsString();
      final overlap = jsonDecode(encoded) as Map;
      ((overlap['placements'] as Map)['logs'] as Map)['y'] = 0;
      for (final values in <Map<String, Object?>>[
        {'homeLayout': '{'},
        {'homeLayout': jsonEncode(overlap)},
        {'homeLayout': 123},
        {'soundStyle': 'unknown'},
        {'soundStyle': null},
      ]) {
        await expectLater(
          backend.updateSettings(values),
          throwsA(isA<PlatformException>()),
        );
        expect(await File('${dir.path}/state.json').readAsString(), original);
      }
      await backend.disconnect();
    },
  );

  test(
    'damaged new fields recover without losing other cached preferences',
    () async {
      final dir = await _seed({
        'homeLayout': '{',
        'soundStyle': 'broken',
        'soundEffects': false,
        'localSocksPort': 12345,
        'themeMode': 'dark',
      });
      addTearDown(() => dir.delete(recursive: true));
      final backend = _backend(dir);
      final settings = (await backend.initialize())['settings'] as Map;
      expect(settings['homeLayout'], '');
      expect(settings['soundStyle'], 'notification');
      expect(settings['soundEffects'], isFalse);
      expect(settings['themeMode'], 'dark');
      expect(settings['localSocksPort'], 12345);
      await backend.updateSettings({'accentColor': 'blue'});
      await backend.disconnect();
    },
  );

  test(
    'hidden logs may share space but cannot be enabled over a card',
    () async {
      final dir = await _seed({});
      addTearDown(() => dir.delete(recursive: true));
      final backend = _backend(dir);
      await backend.initialize();
      final layout = HomeLayout.defaults()
          .resize('logs', 32, 18)!
          .move('subscription', 0, 88, logsVisible: false)!;
      await backend.updateSettings({
        'homeLayout': layout.encode(),
        'showRecentLogsOnHome': false,
      });
      await expectLater(
        backend.updateSettings({'showRecentLogsOnHome': true}),
        throwsA(isA<PlatformException>()),
      );
      final restored = layout.restoreLogs()!;
      await backend.updateSettings({
        'homeLayout': restored.encode(),
        'showRecentLogsOnHome': true,
      });
      await backend.disconnect();
    },
  );
}

WindowsPlatformBackend _backend(Directory dir, {_Host? host}) =>
    WindowsPlatformBackend(
      host: host ?? _Host(),
      dataDirectory: dir,
      autoStartCore: false,
      remoteAccess: _Access(),
    );

Future<Directory> _seed(Map<String, Object?> settings) async {
  final dir = await Directory.systemTemp.createTemp('niran-home-layout-');
  await File('${dir.path}/state.json').writeAsString(
    jsonEncode({
      'settings': {'ipCheckUrl': '', 'autoUpdate': false, ...settings},
    }),
  );
  return dir;
}

final class _Access implements RemoteAccessController {
  @override
  Future<void> requireAllowed() async {}
  @override
  Future<RemoteSubscription> fetchSubscription() async =>
      RemoteSubscription(const [], null);
}

final class _Host implements WindowsNativeHostApi {
  int coreStarts = 0;
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
  Future<List<String>> drainXrayLogs() async => [];
  @override
  Future<List<String>> drainSingBoxLogs() async => [];
  @override
  Future<List<String>> drainTunFrontendLogs() async => [];
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #startXray ||
        invocation.memberName == #startSingBox) {
      coreStarts++;
    }
    return Future<void>.value();
  }
}

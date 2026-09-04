import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niran/platform/windows/windows_native_host.dart';
import 'package:niran/platform/windows/windows_platform_backend.dart';
import 'package:niran/platform/windows/windows_real_delay.dart';
import 'package:niran/platform/windows/windows_server_record.dart';
import 'package:niran/platform/windows/windows_subscription_parser.dart';
import 'package:niran/platform/windows/windows_xray_config_builder.dart';
import 'package:niran/core/registration/device_registration.dart';
import 'package:niran/platform/windows/windows_auto_start.dart';

void main() {
  const parser = WindowsSubscriptionParser();
  const builder = WindowsXrayConfigBuilder();

  test(
    'portable auto-start is applied and persisted only when changed',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'niran-autostart-',
      );
      final autoStart = _FakeAutoStartController();
      try {
        final backend = WindowsPlatformBackend(
          remoteAccess: _AllowedRemoteAccess(),
          autoStartController: autoStart,
          autoStartCore: false,
          host: _FakeWindowsHost(),
          dataDirectory: directory,
        );
        await backend.initialize();
        final enabled = await backend.updateSettings({
          'startWithWindows': true,
        });
        expect(autoStart.values, [true]);
        expect(enabled['startWithWindows'], isTrue);
        await backend.updateSettings({'startWithWindows': true});
        expect(autoStart.values, [true]);
        final disabled = await backend.updateSettings({
          'startWithWindows': false,
        });
        expect(autoStart.values, [true, false]);
        expect(disabled['startWithWindows'], isFalse);
        final persisted =
            jsonDecode(
                  await File('${directory.path}\\state.json').readAsString(),
                )
                as Map;
        expect((persisted['settings'] as Map)['startWithWindows'], isFalse);
      } finally {
        await directory.delete(recursive: true);
      }
    },
  );

  test('Windows subscription parser supports VLESS, Trojan, and VMess', () {
    const vless =
        'vless://00000000-0000-4000-8000-000000000001@example.com:443'
        '?type=ws&security=tls&host=cdn.example.com&path=%2Fws#Germany';
    const trojan =
        'trojan://password@example.net:443?type=tcp&security=tls#France';
    final vmessPayload = base64Url.encode(
      utf8.encode(
        jsonEncode({
          'v': '2',
          'ps': 'Netherlands',
          'add': 'vmess.example.org',
          'port': '443',
          'id': '00000000-0000-4000-8000-000000000002',
          'aid': '0',
          'scy': 'auto',
          'net': 'ws',
          'type': 'none',
          'host': 'cdn.example.org',
          'path': '/ray',
          'tls': 'tls',
          'sni': 'cdn.example.org',
        }),
      ),
    );

    final servers = parser.parse('$vless\n$trojan\nvmess://$vmessPayload');

    expect(servers, hasLength(3));
    expect(servers.map((server) => server.protocol), {
      'vless',
      'trojan',
      'vmess',
    });
    expect(servers.first.country, 'DE');
    expect(servers.first.parameters['path'], '/ws');
    expect(servers[2].parameters['headerType'], 'none');
  });

  test('Patt-compatible TLS parameters survive import and export', () {
    const finalMask =
        '{"tcp":[{"type":"fragment","settings":{"packets":"tlshello","length":"1-1","delay":"1-2"}}]}';
    final link =
        'vless://00000000-0000-4000-8000-000000000001@104.16.0.1:443'
        '?security=tls&type=ws&host=cdn.example.com&sni=origin.example.com'
        '&path=%2Fedge%3Fed%3D2560&alpn=http%2F1.1&allowInsecure=1'
        '&fp=unsafe&cs=${Uri.encodeQueryComponent('TLS_AES_128_GCM_SHA256:TLS_AES_256_GCM_SHA384')}'
        '&fm=${Uri.encodeQueryComponent(finalMask)}&future=first&future=value%2Bkept#%F0%9F%87%B3%F0%9F%87%B1%20CDN';

    final server = parser.parse(link).single;
    expect(server.country, 'NL');
    expect(server.security, 'tls');
    expect(server.transport, 'ws');
    expect(server.parameters['host'], 'cdn.example.com');
    expect(server.parameters['sni'], 'origin.example.com');
    expect(server.parameters['path'], '/edge?ed=2560');
    expect(server.parameters['allowInsecure'], '1');
    expect(server.parameters['fp'], 'unsafe');
    expect(server.parameters['cs'], contains('TLS_AES_128_GCM_SHA256'));
    expect(server.parameters['fm'], finalMask);
    expect(server.parameters['future'], 'value+kept');

    final exported = parser.exportShareLink(server);
    expect(RegExp(r'(?:\?|&)future=').allMatches(exported), hasLength(2));
    final reparsed = parser.parse(exported).single;
    for (final key in [
      'security',
      'type',
      'host',
      'sni',
      'path',
      'alpn',
      'allowInsecure',
      'fp',
      'cs',
      'fm',
      'future',
    ]) {
      expect(reparsed.parameters[key], server.parameters[key], reason: key);
    }
  });

  test('CDN TLS fields are mapped field-for-field to Xray JSON', () {
    const finalMask = {
      'tcp': [
        {
          'type': 'fragment',
          'settings': {'packets': 'tlshello', 'length': '1-1', 'delay': '1-2'},
        },
      ],
    };
    final server = WindowsServerRecord(
      id: 'cdn',
      name: 'CDN',
      country: 'NL',
      protocol: 'vless',
      address: '104.16.0.1',
      port: 443,
      credential: '00000000-0000-4000-8000-000000000001',
      transport: 'ws',
      security: 'tls',
      parameters: {
        'security': 'tls',
        'type': 'ws',
        'host': 'cdn.example.com',
        'sni': 'origin.example.com',
        'path': '/edge?ed=2560',
        'alpn': 'http/1.1',
        'fp': 'unsafe',
        'cs': 'TLS_AES_128_GCM_SHA256:TLS_AES_256_GCM_SHA384',
        'fm': jsonEncode(finalMask),
        'allowInsecure': '1',
      },
    );
    final config =
        jsonDecode(builder.build(server: server, settings: _settings()))
            as Map<String, dynamic>;
    final stream =
        (config['outbounds'] as List).first['streamSettings']
            as Map<String, dynamic>;
    expect(stream['network'], 'ws');
    expect(stream['security'], 'tls');
    expect(stream['wsSettings']['host'], 'cdn.example.com');
    expect(stream['wsSettings']['path'], '/edge?ed=2560');
    expect(stream['tlsSettings']['serverName'], 'origin.example.com');
    expect(stream['tlsSettings']['alpn'], ['http/1.1']);
    expect(stream['tlsSettings']['fingerprint'], 'unsafe');
    expect(stream['tlsSettings'], isNot(contains('allowInsecure')));
    expect(
      stream['tlsSettings']['cipherSuites'],
      'TLS_AES_128_GCM_SHA256:TLS_AES_256_GCM_SHA384',
    );
    expect(stream['finalmask'], finalMask);
  });

  test('unsafe is rejected explicitly for incompatible Reality transport', () {
    final server = WindowsServerRecord(
      id: 'reality',
      name: 'Reality',
      country: 'NL',
      protocol: 'vless',
      address: 'example.com',
      port: 443,
      credential: '00000000-0000-4000-8000-000000000001',
      transport: 'xhttp',
      security: 'reality',
      parameters: const {'sni': 'example.com', 'fp': 'unsafe'},
    );
    expect(
      () => builder.build(server: server, settings: _settings()),
      throwsFormatException,
    );
  });

  test('Windows Xray config is proxy-only and keeps required local ports', () {
    final server = WindowsServerRecord(
      id: 'server',
      name: 'Server',
      country: 'DE',
      protocol: 'vless',
      address: 'example.com',
      port: 443,
      credential: '00000000-0000-4000-8000-000000000001',
      transport: 'ws',
      security: 'tls',
      parameters: const {
        'path': '/ws',
        'host': 'cdn.example.com',
        'sni': 'cdn.example.com',
        'fp': 'chrome',
      },
    );

    final config =
        jsonDecode(builder.build(server: server, settings: _settings()))
            as Map<String, dynamic>;
    final inbounds = config['inbounds'] as List<dynamic>;

    expect(
      inbounds.map((item) => item['protocol']),
      containsAll(['socks', 'http']),
    );
    expect(inbounds.map((item) => item['port']), containsAll([10808, 10809]));
    expect(inbounds.map((item) => item['protocol']), isNot(contains('tun')));
    expect((config['outbounds'] as List).first['protocol'], 'vless');
  });

  test('Windows Xray TUN config is independent from System Proxy', () {
    final server = WindowsServerRecord(
      id: 'server',
      name: 'Server',
      country: 'DE',
      protocol: 'vless',
      address: 'example.com',
      port: 443,
      credential: '00000000-0000-4000-8000-000000000001',
      transport: 'tcp',
      security: 'tls',
      parameters: const {'sni': 'example.com'},
    );
    final config =
        jsonDecode(
              builder.build(
                server: server,
                settings: {..._settings(), 'tunEnabled': true},
              ),
            )
            as Map<String, dynamic>;
    final inbounds = config['inbounds'] as List<dynamic>;
    expect(inbounds, hasLength(3));
    final tun = inbounds.singleWhere((item) => item['protocol'] == 'tun');
    expect(tun['settings']['autoOutboundsInterface'], 'auto');
    expect(tun['settings']['autoSystemRoutingTable'], contains('0.0.0.0/0'));
    expect(
      inbounds.map((item) => item['protocol']),
      containsAll(['socks', 'http']),
    );
  });

  test(
    'Real Delay config isolates every server behind its own local proxy',
    () {
      final servers = [
        WindowsServerRecord(
          id: 'first',
          name: 'First',
          country: 'DE',
          protocol: 'vless',
          address: 'one.example.com',
          port: 443,
          credential: '00000000-0000-4000-8000-000000000001',
          transport: 'tcp',
          security: 'tls',
          parameters: const {'sni': 'one.example.com'},
        ),
        WindowsServerRecord(
          id: 'second',
          name: 'Second',
          country: 'NL',
          protocol: 'trojan',
          address: 'two.example.com',
          port: 443,
          credential: 'password',
          transport: 'tcp',
          security: 'tls',
          parameters: const {'sni': 'two.example.com'},
        ),
      ];

      final config =
          jsonDecode(
                builder.buildSpeedtest(
                  servers: servers,
                  settings: _settings(),
                  socksPorts: const [21001, 21002],
                  httpPorts: const [22001, 22002],
                ),
              )
              as Map<String, dynamic>;
      final inbounds = config['inbounds'] as List<dynamic>;
      final outbounds = config['outbounds'] as List<dynamic>;
      final rules =
          (config['routing'] as Map<String, dynamic>)['rules'] as List<dynamic>;

      expect(inbounds.map((item) => item['port']), [
        21001,
        22001,
        21002,
        22002,
      ]);
      expect(outbounds.map((item) => item['tag']), [
        'test-out-0',
        'test-out-1',
      ]);
      expect(rules[0]['inboundTag'], ['test-in-0', 'test-in-0-http']);
      expect(rules[0]['outboundTag'], 'test-out-0');
      expect(rules[1]['inboundTag'], ['test-in-1', 'test-in-1-http']);
      expect(rules[1]['outboundTag'], 'test-out-1');
    },
  );

  test('Real Delay records the faster of two SOCKS transfers', () async {
    late List<String> capturedArguments;
    final delay = await measureWindowsRealDelay(
      target: Uri.parse('https://real-delay.test/generate_204'),
      socksPort: 21080,
      timeout: const Duration(seconds: 9),
      commandRunner: (arguments, timeout) async {
        capturedArguments = arguments;
        return (exitCode: 0, stdout: '0.180000\n0.025400\n');
      },
    );

    expect(delay, 25);
    expect(
      capturedArguments,
      containsAllInOrder(['--socks5-hostname', '127.0.0.1:21080']),
    );
    expect(
      capturedArguments.where(
        (value) => value == 'https://real-delay.test/generate_204',
      ),
      hasLength(2),
    );
  });

  test('Real Delay returns -1 for a failed proxied request', () async {
    expect(
      await measureWindowsRealDelay(
        target: Uri.parse('https://real-delay.test/generate_204'),
        socksPort: 21080,
        timeout: const Duration(seconds: 2),
        commandRunner: (_, _) async => (exitCode: 28, stdout: ''),
      ),
      -1,
    );
  });

  test(
    'Desktop initialization restores the selected Core and proxy policy',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'niraN-auto-core-test-',
      );
      final host = _FakeWindowsHost();
      late WindowsPlatformBackend backend;
      try {
        await _seedConnectableServer(directory);
        backend = WindowsPlatformBackend(
          remoteAccess: _AllowedRemoteAccess(),
          localPortPreflight: (_) async {},
          host: host,
          dataDirectory: directory,
          proxyReadinessProbe: (port) async => host.calls.add('ready:$port'),
        );

        final bootstrap = await backend.initialize();

        expect(host.calls, ['start', 'ready:10809', 'enable:10809']);
        expect(bootstrap['connection'], containsPair('state', 'connected'));
      } finally {
        await backend.disconnect();
        await directory.delete(recursive: true);
      }
    },
  );

  test('Windows backend initializes through the platform contract', () async {
    final directory = await Directory.systemTemp.createTemp(
      'niraN-backend-test-',
    );
    try {
      final backend = WindowsPlatformBackend(
        remoteAccess: _AllowedRemoteAccess(),
        autoStartCore: false,
        localPortPreflight: (_) async {},
        host: _FakeWindowsHost(),
        dataDirectory: directory,
      );
      final bootstrap = await backend.initialize();

      expect(bootstrap['appVersion'], '0.1.0');
      expect(bootstrap['coreVersion'], 'v26.7.28');
      expect(bootstrap['subscriptionConfigured'], isTrue);
      expect((bootstrap['settings'] as Map)['connectionMode'], 'proxy');
    } finally {
      await directory.delete(recursive: true);
    }
  });

  test('Windows connection owns System Proxy in a safe order', () async {
    final directory = await Directory.systemTemp.createTemp(
      'niraN-lifecycle-test-',
    );
    final host = _FakeWindowsHost();
    late WindowsPlatformBackend backend;
    try {
      await _seedConnectableServer(directory);
      backend = WindowsPlatformBackend(
        remoteAccess: _AllowedRemoteAccess(),
        autoStartCore: false,
        localPortPreflight: (_) async {},
        host: host,
        dataDirectory: directory,
        proxyReadinessProbe: (port) async => host.calls.add('ready:$port'),
      );
      await backend.initialize();
      host.calls.clear();

      await backend.connect('server');
      expect(host.calls, ['start', 'ready:10809', 'enable:10809']);

      await backend.disconnect();
      expect(host.calls, [
        'start',
        'ready:10809',
        'enable:10809',
        'disable',
        'stop',
      ]);
      expect(
        (await backend.initialize())['connection'],
        containsPair('state', 'disconnected'),
      );
    } finally {
      await directory.delete(recursive: true);
    }
  });

  test('server block is enforced again before Connect', () async {
    final directory = await Directory.systemTemp.createTemp(
      'niraN-blocked-connect-test-',
    );
    final host = _FakeWindowsHost();
    final access = _AllowedRemoteAccess();
    try {
      await _seedConnectableServer(directory);
      final backend = WindowsPlatformBackend(
        remoteAccess: access,
        autoStartCore: false,
        localPortPreflight: (_) async {},
        host: host,
        dataDirectory: directory,
      );
      await backend.initialize();
      access.failure = const DeviceAccessException(
        'blocked_by_administrator',
        'This Windows device has been blocked by the administrator',
      );

      await expectLater(
        backend.connect('server'),
        throwsA(isA<DeviceAccessException>()),
      );
      expect(host.calls, isNot(contains('start')));
      expect(access.checks, 2);
    } finally {
      await directory.delete(recursive: true);
    }
  });

  test(
    'block discovered during refresh stops Core and emits access gate',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'niraN-blocked-refresh-test-',
      );
      final host = _FakeWindowsHost();
      final access = _AllowedRemoteAccess();
      final events = <Map<dynamic, dynamic>>[];
      try {
        await _seedConnectableServer(directory);
        final backend = WindowsPlatformBackend(
          remoteAccess: access,
          autoStartCore: false,
          localPortPreflight: (_) async {},
          host: host,
          dataDirectory: directory,
          proxyReadinessProbe: (_) async {},
        );
        await backend.initialize();
        final subscription = backend.events.listen(events.add);
        addTearDown(subscription.cancel);
        await backend.connect('server');
        host.calls.clear();
        access.failure = const DeviceAccessException(
          'blocked_by_administrator',
          'This Windows device has been blocked by the administrator',
        );

        await expectLater(
          backend.refreshSubscription(),
          throwsA(isA<DeviceAccessException>()),
        );
        expect(host.calls, containsAllInOrder(['disable', 'stop']));
        expect(events.any((event) => event['type'] == 'accessBlocked'), isTrue);
        expect(
          (await backend.initialize())['connection'],
          containsPair('state', 'disconnected'),
        );
      } finally {
        await directory.delete(recursive: true);
      }
    },
  );

  test('Windows TUN lifecycle never changes System Proxy', () async {
    final directory = await Directory.systemTemp.createTemp(
      'niraN-tun-lifecycle-test-',
    );
    final host = _FakeWindowsHost();
    try {
      await _seedConnectableServer(directory);
      final backend = WindowsPlatformBackend(
        remoteAccess: _AllowedRemoteAccess(),
        autoStartCore: false,
        localPortPreflight: (_) async {},
        host: host,
        dataDirectory: directory,
        proxyReadinessProbe: (port) async => host.calls.add('ready:$port'),
      );
      await backend.initialize();
      await backend.updateSettings({
        'tunEnabled': true,
        'systemProxyEnabled': false,
      });
      host.calls.clear();

      await backend.connect('server');
      expect(host.calls, ['start:tun', 'ready:10809']);

      await backend.disconnect();
      expect(host.calls, ['start:tun', 'ready:10809', 'disable', 'stop']);
    } finally {
      await directory.delete(recursive: true);
    }
  });

  test('Clear System Proxy leaves Xray and local proxies running', () async {
    final directory = await Directory.systemTemp.createTemp(
      'niraN-clear-proxy-test-',
    );
    final host = _FakeWindowsHost();
    late WindowsPlatformBackend backend;
    try {
      await _seedConnectableServer(directory);
      backend = WindowsPlatformBackend(
        remoteAccess: _AllowedRemoteAccess(),
        autoStartCore: false,
        localPortPreflight: (_) async {},
        host: host,
        dataDirectory: directory,
        proxyReadinessProbe: (port) async => host.calls.add('ready:$port'),
      );
      await backend.initialize();
      host.calls.clear();
      await backend.connect('server');

      await backend.clearSystemProxy();
      expect(host.running, isTrue);
      expect(host.calls.last, 'clear');
      expect(host.calls, isNot(contains('stop')));

      await backend.setSystemProxy();
      expect(host.running, isTrue);
      expect(host.calls.sublist(host.calls.length - 2), [
        'ready:10809',
        'enable:10809',
      ]);
    } finally {
      await backend.disconnect();
      await directory.delete(recursive: true);
    }
  });

  test('TUN prerequisite failure preserves running Core and proxy', () async {
    final directory = await Directory.systemTemp.createTemp(
      'niraN-tun-preflight-test-',
    );
    final host = _FakeWindowsHost();
    try {
      await _seedConnectableServer(directory);
      final backend = WindowsPlatformBackend(
        remoteAccess: _AllowedRemoteAccess(),
        autoStartCore: false,
        localPortPreflight: (_) async {},
        host: host,
        dataDirectory: directory,
        proxyReadinessProbe: (port) async => host.calls.add('ready:$port'),
      );
      await backend.initialize();
      await backend.connect('server');
      host.calls.clear();
      host.tunValidationFailure = PlatformException(
        code: 'tun_privilege',
        message: 'TUN mode requires administrator privileges.',
      );

      await expectLater(
        backend.updateSettings({'tunEnabled': true}),
        throwsA(isA<PlatformException>()),
      );

      expect(host.calls, ['validateTun']);
      expect(host.running, isTrue);
      expect(
        (await backend.initialize())['connection'],
        containsPair('state', 'connected'),
      );
      expect(
        (await backend.initialize())['settings'],
        containsPair('tunEnabled', false),
      );
      await backend.disconnect();
    } finally {
      await directory.delete(recursive: true);
    }
  });

  test('System Proxy enable failure restores proxy and stops Xray', () async {
    final directory = await Directory.systemTemp.createTemp(
      'niraN-enable-failure-test-',
    );
    final host = _FakeWindowsHost()
      ..enableFailure = PlatformException(
        code: 'proxy',
        message: 'enable failed',
      );
    try {
      await _seedConnectableServer(directory);
      final backend = WindowsPlatformBackend(
        remoteAccess: _AllowedRemoteAccess(),
        autoStartCore: false,
        localPortPreflight: (_) async {},
        host: host,
        dataDirectory: directory,
        proxyReadinessProbe: (port) async => host.calls.add('ready:$port'),
      );
      await backend.initialize();
      host.calls.clear();

      await expectLater(backend.connect('server'), throwsA(isA<Object>()));
      expect(host.calls, [
        'start',
        'ready:10809',
        'enable:10809',
        'disable',
        'stop',
      ]);
      expect(
        (await backend.initialize())['connection'],
        containsPair('state', 'error'),
      );
    } finally {
      await directory.delete(recursive: true);
    }
  });

  test('Xray crash reports error even when proxy restore fails', () async {
    final directory = await Directory.systemTemp.createTemp(
      'niraN-crash-test-',
    );
    final host = _FakeWindowsHost();
    try {
      await _seedConnectableServer(directory);
      final backend = WindowsPlatformBackend(
        remoteAccess: _AllowedRemoteAccess(),
        autoStartCore: false,
        localPortPreflight: (_) async {},
        host: host,
        dataDirectory: directory,
        proxyReadinessProbe: (_) async {},
      );
      await backend.initialize();
      await backend.connect('server');
      host
        ..running = false
        ..disableFailure = PlatformException(
          code: 'proxy',
          message: 'restore failed',
        );

      await Future<void>.delayed(const Duration(milliseconds: 1150));
      final connection =
          (await backend.initialize())['connection'] as Map<dynamic, dynamic>;
      expect(connection['state'], 'error');
      expect('${connection['error']}', contains('proxy restore failed'));

      host.disableFailure = null;
      await backend.disconnect();
    } finally {
      await directory.delete(recursive: true);
    }
  });

  test('official bundled Xray accepts a generated Windows config', () async {
    final xray = File('windows/xray/bin/xray-v26.7.28.exe');
    if (!await xray.exists()) return;
    final directory = await Directory.systemTemp.createTemp('niraN-xray-test-');
    final config = File('${directory.path}\\config.json');
    try {
      await config.writeAsString(
        builder.build(
          server: WindowsServerRecord(
            id: 'server',
            name: 'Server',
            country: 'DE',
            protocol: 'vless',
            address: 'example.com',
            port: 443,
            credential: '00000000-0000-4000-8000-000000000001',
            transport: 'ws',
            security: 'tls',
            parameters: const {
              'host': 'cdn.example.com',
              'sni': 'example.com',
              'path': '/edge?ed=2560',
              'alpn': 'http/1.1',
              'fp': 'unsafe',
              'cs': 'TLS_AES_128_GCM_SHA256:TLS_AES_256_GCM_SHA384',
              'fm':
                  '{"tcp":[{"type":"fragment","settings":{"packets":"tlshello","length":"1-1","delay":"1-2"}}]}',
            },
          ),
          settings: _settings(),
        ),
      );
      final result = await Process.run(xray.absolute.path, [
        'run',
        '-test',
        '-c',
        config.path,
      ]);
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    } finally {
      await directory.delete(recursive: true);
    }
  });
}

Map<String, Object?> _settings() => {
  'connectionMode': 'proxy',
  'systemProxyEnabled': true,
  'tunEnabled': false,
  'routingMode': 'global',
  'enableLocalDns': true,
  'enableFakeDns': false,
  'remoteDns': 'https://dns.google/dns-query',
  'localSocksPort': 10808,
  'localHttpPort': 10809,
  'vpnDns': '1.1.1.1',
  'vpnInterfaceAddress': '10.10.14.1/30',
  'vpnMtu': 1500,
  'domainStrategy': 'AsIs',
  'sniffingEnabled': true,
  'routeOnly': false,
  'enableIpv6': true,
  'preferIpv6': false,
};

Future<void> _seedConnectableServer(Directory directory) async {
  final server = WindowsServerRecord(
    id: 'server',
    name: 'Server',
    country: 'DE',
    protocol: 'vless',
    address: 'example.com',
    port: 443,
    credential: '00000000-0000-4000-8000-000000000001',
    transport: 'tcp',
    security: 'tls',
    parameters: const {'sni': 'example.com'},
  );
  await File('${directory.path}\\subscription-cache.json').writeAsString(
    jsonEncode({
      'servers': [server.toPrivateJson()],
      'usage': <String, Object?>{},
      'lastUpdated': DateTime.now().millisecondsSinceEpoch,
    }),
  );
  await File('${directory.path}\\state.json').writeAsString(
    jsonEncode({
      'selectedId': server.id,
      'hiddenIds': <String>[],
      'settings': {'routingMode': 'global', 'ipCheckUrl': ''},
      'openCount': 0,
    }),
  );
}

final class _FakeWindowsHost implements WindowsNativeHostApi {
  final List<String> calls = [];
  bool running = false;
  Object? enableFailure;
  Object? disableFailure;
  Object? tunValidationFailure;
  String proxyState = 'niran';

  @override
  Future<Map<dynamic, dynamic>> getBuildConfig() async => {
    'subscriptionUrl': '',
    'telegramUrl': '',
    'telegramContact': '',
    'appVersion': '0.1.0',
  };

  @override
  Future<Map<dynamic, dynamic>> getDeviceRegistrationInfo() async => const {};

  @override
  Future<void> exitApplication() async {}

  @override
  Future<void> validateTunPrerequisites() async {
    calls.add('validateTun');
    if (tunValidationFailure case final failure?) throw failure;
  }

  @override
  Future<String> getXrayVersion() async => 'v26.7.28';

  @override
  Future<bool> recoverSystemProxy() async => false;

  @override
  Future<List<String>> drainXrayLogs() async => const [];

  @override
  Future<Map<dynamic, dynamic>> getXrayStatus() async => {
    'running': running,
    if (!running) 'exitCode': 23,
  };

  @override
  Future<void> disableSystemProxy() async {
    calls.add('disable');
    if (disableFailure case final failure?) throw failure;
    proxyState = 'clear';
  }

  @override
  Future<void> clearSystemProxy() async {
    calls.add('clear');
    proxyState = 'clear';
  }

  @override
  Future<void> enableSystemProxy(int httpPort) async {
    calls.add('enable:$httpPort');
    if (enableFailure case final failure?) throw failure;
    proxyState = 'niran';
  }

  @override
  Future<String> getSystemProxyState(int httpPort) async => proxyState;

  @override
  Future<void> openExternalUrl(String url) async {}

  @override
  Future<void> startXray(String configPath, {required bool tunMode}) async {
    calls.add(tunMode ? 'start:tun' : 'start');
    running = true;
  }

  @override
  Future<void> stopXray() async {
    calls.add('stop');
    running = false;
  }

  @override
  Future<void> startSpeedtestXray(String configPath) async {
    calls.add('startSpeedtest');
  }

  @override
  Future<void> stopSpeedtestXray() async {
    calls.add('stopSpeedtest');
  }
}

final class _AllowedRemoteAccess implements RemoteAccessController {
  int checks = 0;
  DeviceAccessException? failure;

  @override
  Future<void> requireAllowed() async {
    checks++;
    if (failure case final error?) throw error;
  }

  @override
  Future<RemoteSubscription> fetchSubscription() async {
    await requireAllowed();
    return const RemoteSubscription([], null);
  }
}

final class _FakeAutoStartController implements AutoStartController {
  final List<bool> values = [];

  @override
  Future<void> setEnabled(bool enabled) async => values.add(enabled);
}

import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:niran/platform/windows/windows_core_selection.dart';
import 'package:niran/platform/windows/windows_server_record.dart';
import 'package:niran/platform/windows/windows_sing_box_proxy_config_builder.dart';

void main() {
  const builder = WindowsSingBoxProxyConfigBuilder();
  WindowsServerRecord fixture(
    String protocol, {
    String transport = 'tcp',
    Map<String, String> parameters = const {},
  }) => WindowsServerRecord(
    id: 'fixture',
    name: 'Synthetic fixture',
    country: '',
    protocol: protocol,
    address: 'example.com',
    port: 443,
    credential: ['vless', 'vmess'].contains(protocol)
        ? '00000000-0000-4000-8000-000000000001'
        : 'synthetic-password',
    transport: protocol == 'hysteria2' ? 'hysteria' : transport,
    security: ['shadowsocks', 'socks'].contains(protocol) ? 'none' : 'tls',
    parameters: {'method': 'aes-128-gcm', ...parameters},
  );
  test('Xray default and sing-box mapping are independent of TUN', () {
    expect(
      WindowsCoreSelection.forProtocol({'tunEnabled': true}, 'vless'),
      WindowsProxyCore.xray,
    );
    expect(
      WindowsCoreSelection.forProtocol({
        'tunEnabled': false,
        'coreByProtocol': {'vless': 'sing-box'},
      }, 'vless'),
      WindowsProxyCore.singBox,
    );
    expect(
      () => WindowsCoreSelection.validateMapping({'vless': 'unknown'}),
      throwsFormatException,
    );
  });
  test('rejects Xray-only profile features instead of dropping them', () {
    for (final parameters in [
      {'fm': '{}'},
      {'extra': '{}'},
      {'fp': 'unsafe'},
      {'pqv': 'key'},
    ]) {
      expect(
        () => builder.build(
          server: fixture('vless', parameters: parameters),
          settings: const {'routingMode': 'global'},
        ),
        throwsFormatException,
      );
    }
    expect(
      () => builder.build(
        server: fixture('vless', transport: 'xhttp'),
        settings: const {'routingMode': 'global'},
      ),
      throwsFormatException,
    );
    expect(
      () => builder.build(
        server: fixture('vless'),
        settings: const {'routingMode': 'global', 'muxEnabled': true},
      ),
      throwsFormatException,
    );
  });
  test(
    'WS headers, TLS and credentials survive conversion; proxy has no TUN',
    () {
      final root =
          jsonDecode(
                builder.build(
                  server: fixture(
                    'vless',
                    transport: 'ws',
                    parameters: {
                      'host': 'cdn.example.com',
                      'sni': 'origin.example.com',
                      'path': '/ws',
                    },
                  ),
                  settings: const {'routingMode': 'global'},
                ),
              )
              as Map;
      expect((root['inbounds'] as List).cast<Map>().map((r) => r['type']), [
        'socks',
        'http',
      ]);
      final outbound = (root['outbounds'] as List).first as Map;
      expect((outbound['tls'] as Map)['server_name'], 'origin.example.com');
      expect(
        ((outbound['transport'] as Map)['headers'] as Map)['Host'],
        'cdn.example.com',
      );
      expect(outbound['uuid'], '00000000-0000-4000-8000-000000000001');
    },
  );
  test('does not silently discard transports and early-data options', () {
    for (final profile in [
      fixture('shadowsocks', transport: 'ws'),
      fixture('trojan', parameters: {'flow': 'xtls-rprx-vision'}),
      fixture('vless', transport: 'ws', parameters: {'ed': '2048'}),
    ]) {
      expect(
        () => builder.build(
          server: profile,
          settings: const {'routingMode': 'global'},
        ),
        throwsFormatException,
      );
    }
  });
  test(
    'bundled sing-box accepts all supported protocol and transport configs',
    () async {
      if (!Platform.isWindows) return;
      final directory = await Directory.systemTemp.createTemp(
        'niran-singbox-check-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final executable = File(
        'windows/sing-box/bin/sing-box-v1.14.0.exe',
      ).absolute;
      expect(await executable.exists(), isTrue);
      final examples = [
        for (final protocol in WindowsCoreSelection.protocols)
          fixture(protocol),
        fixture('vless', transport: 'ws'),
        fixture('trojan', transport: 'grpc'),
        fixture('vmess', transport: 'httpupgrade'),
      ];
      for (var i = 0; i < examples.length; i++) {
        final file = File('${directory.path}/fixture-$i.json');
        await file.writeAsString(
          builder.build(
            server: examples[i],
            settings: const {'routingMode': 'global'},
          ),
        );
        final result = await Process.run(executable.path, [
          'check',
          '-c',
          file.path,
        ], workingDirectory: executable.parent.path);
        expect(
          result.exitCode,
          0,
          reason:
              '${examples[i].protocol}/${examples[i].transport}: ${result.stderr}',
        );
      }
      final speedtest = File('${directory.path}/speedtest.json');
      await speedtest.writeAsString(
        builder.buildSpeedtest(
          servers: [fixture('vless'), fixture('trojan')],
          settings: const {},
          socksPorts: [20808, 20810],
          httpPorts: [20809, 20811],
        ),
      );
      final result = await Process.run(executable.path, [
        'check',
        '-c',
        speedtest.path,
      ], workingDirectory: executable.parent.path);
      expect(result.exitCode, 0, reason: '${result.stderr}');
    },
  );
}

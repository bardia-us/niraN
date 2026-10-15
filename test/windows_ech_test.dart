import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:niran/platform/windows/windows_subscription_parser.dart';
import 'package:niran/platform/windows/windows_xray_config_builder.dart';
import 'package:niran/platform/windows/windows_core_selection.dart';
import 'package:niran/platform/windows/windows_sing_box_proxy_config_builder.dart';

void main() {
  test('VMess ECH survives JSON import while older links remain unchanged', () {
    final parser = const WindowsSubscriptionParser();
    for (final withEch in [false, true]) {
      final link =
          'vmess://${base64Encode(utf8.encode(jsonEncode({'v': '2', 'ps': 'Probe', 'add': 'example.com', 'port': '443', 'id': '00000000-0000-4000-8000-000000000001', 'net': 'ws', 'tls': 'tls', 'fp': 'chrome', if (withEch) 'echConfigList': 'AF7+DQ=='})))}';
      final server = parser.parse(link).single;
      final config = jsonDecode(
        const WindowsXrayConfigBuilder().build(
          server: server,
          settings: {'routingMode': 'global'},
        ),
      );
      final tls =
          config['outbounds'][0]['streamSettings']['tlsSettings'] as Map;
      expect(tls.containsKey('echConfigList'), withEch);
      if (withEch) expect(tls['echConfigList'], 'AF7+DQ==');
      expect(tls['fingerprint'], 'chrome');
    }
  });
  for (final value in ['AF7+DQ==', 'example.com+udp://1.1.1.1']) {
    test('raw ECH plus survives share-link parsing: $value', () {
      final server = const WindowsSubscriptionParser()
          .parse(
            'vless://00000000-0000-4000-8000-000000000001@example.com:443?security=tls&ech=$value#Probe',
          )
          .single;
      expect(server.parameters['ech'], value);
    });
  }
  test('sing-box rejects ECH instead of silently ignoring it', () {
    final server = const WindowsSubscriptionParser()
        .parse(
          'vless://00000000-0000-4000-8000-000000000001@example.com:443?security=tls&ech=udp%3A%2F%2F1.1.1.1#Probe',
        )
        .single;
    expect(
      WindowsCoreSelection.singBoxUnsupportedReason(server, {}),
      isNotNull,
    );
  });
  test('sing-box local routing also honors explicit proxy selection', () {
    final server = const WindowsSubscriptionParser()
        .parse(
          'vless://00000000-0000-4000-8000-000000000001@example.com:443?security=tls#Probe',
        )
        .single;
    final config = jsonDecode(
      const WindowsSingBoxProxyConfigBuilder().build(
        server: server,
        settings: {'routingMode': 'global', 'localBypassMode': 'proxy'},
      ),
    );
    final localRule = (config['route']['rules'] as List).firstWhere(
      (rule) => (rule['domain'] as List?)?.contains('localhost') == true,
    );
    expect(localRule['outbound'], 'proxy');
    expect(
      (config['dns']['rules'] as List).where(
        (rule) => rule['server'] == 'local-dns',
      ),
      isEmpty,
    );
  });
  test(
    'local proxy selection outranks Iran bypass and does not resolve local names on the host',
    () {
      final server = const WindowsSubscriptionParser()
          .parse(
            'vless://00000000-0000-4000-8000-000000000001@example.com:443?security=tls#Probe',
          )
          .single;
      final config = jsonDecode(
        const WindowsXrayConfigBuilder().build(
          server: server,
          settings: {'routingMode': 'bypassIran', 'localBypassMode': 'proxy'},
          iranCidrs: ['5.160.0.0/16'],
        ),
      );
      final rules = config['routing']['rules'] as List;
      expect(
        rules.firstWhere(
          (rule) =>
              (rule['domain'] as List?)?.contains('full:localhost') == true,
        )['outboundTag'],
        'proxy',
      );
      expect(
        (config['dns']['servers'] as List).whereType<Map>().any(
          (server) => server['address'] == 'localhost',
        ),
        isFalse,
      );
    },
  );
  test('internal DNS queries have explicit proxy routing', () {
    final server = const WindowsSubscriptionParser()
        .parse(
          'vless://00000000-0000-4000-8000-000000000001@example.com:443?security=tls#Probe',
        )
        .single;
    final config = jsonDecode(
      const WindowsXrayConfigBuilder().build(
        server: server,
        settings: {'routingMode': 'global'},
      ),
    );
    expect(config['dns']['tag'], 'remote-dns');
    expect(config['routing']['rules'][0]['inboundTag'], ['remote-dns']);
    expect(config['routing']['rules'][0]['outboundTag'], 'proxy');
  });
  for (final key in ['ech', 'echConfigList']) {
    for (final value in [
      'udp://1.1.1.1',
      'example.com+udp://1.1.1.1',
      'AF7+DQ==',
    ]) {
      test('$key survives parser and TLS output: $value', () {
        final server = const WindowsSubscriptionParser()
            .parse(
              'vless://00000000-0000-4000-8000-000000000001@example.com:443'
              '?security=tls&type=ws&fp=chrome&alpn=h2&$key=${Uri.encodeQueryComponent(value)}#Probe',
            )
            .single;
        final config = jsonDecode(
          const WindowsXrayConfigBuilder().build(
            server: server,
            settings: {'routingMode': 'global'},
          ),
        );
        final tls = config['outbounds'][0]['streamSettings']['tlsSettings'];
        expect(tls['echConfigList'], value);
        expect(tls['fingerprint'], 'chrome');
        expect(tls['alpn'], ['h2']);
      });
    }
  }
}

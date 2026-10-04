import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:niran/platform/windows/windows_subscription_parser.dart';
import 'package:niran/platform/windows/windows_xray_config_builder.dart';
import 'package:niran/platform/windows/windows_sing_box_tun_config_builder.dart';

void main() {
  final server = const WindowsSubscriptionParser()
      .parse(
        'vless://00000000-0000-4000-8000-000000000001@example.com:443?security=tls&type=tcp#Test',
      )
      .single;
  for (final mode in ['global', 'bypassIran', 'custom']) {
    test('Xray $mode always bypasses local before QUIC/DNS rules', () {
      final root =
          jsonDecode(
                const WindowsXrayConfigBuilder().build(
                  server: server,
                  settings: {'routingMode': mode, 'blockQuic': true},
                  iranCidrs: const ['2.144.0.0/14'],
                ),
              )
              as Map;
      final rules = ((root['routing'] as Map)['rules'] as List).cast<Map>();
      final local = rules.indexWhere(
        (r) => (r['ip'] as List?)?.contains('192.168.0.0/16') == true,
      );
      expect(local, greaterThanOrEqualTo(0));
      expect(rules[local]['outboundTag'], 'direct');
      expect(
        (rules[local]['ip'] as List),
        containsAll([
          '127.0.0.0/8',
          '10.0.0.0/8',
          '100.64.0.0/10',
          'fe80::/10',
        ]),
      );
      final blocked = rules.indexWhere((r) => r['outboundTag'] == 'blocked');
      expect(local, lessThan(blocked));
      final dns = ((root['dns'] as Map)['servers'] as List).whereType<Map>();
      expect(
        dns.any(
          (r) =>
              r['address'] == 'localhost' &&
              r['finalQuery'] == true &&
              (r['domains'] as List?)?.contains('domain:local') == true,
        ),
        isTrue,
      );
    });
    test(
      'sing-box TUN $mode always bypasses LAN and resolves local with system DNS',
      () {
        final root =
            jsonDecode(
                  const WindowsSingBoxTunConfigBuilder().build(
                    settings: {'routingMode': mode},
                    xraySocksPort: 10808,
                    iranCidrs: const ['2.144.0.0/14'],
                    protectedProcessPaths: const [],
                  ),
                )
                as Map;
        final rules = ((root['route'] as Map)['rules'] as List).cast<Map>();
        expect(
          rules.indexWhere(
            (r) => (r['ip_cidr'] as List?)?.contains('192.168.0.0/16') == true,
          ),
          lessThan(rules.indexWhere((r) => r['action'] == 'hijack-dns')),
        );
        expect(
          rules.any(
            (r) =>
                (r['domain_suffix'] as List?)?.contains('.local') == true &&
                r['outbound'] == 'direct',
          ),
          isTrue,
        );
        expect(
          rules.any(
            (r) =>
                (r['ip_cidr'] as List?)?.contains('100.64.0.0/10') == true &&
                r['outbound'] == 'direct',
          ),
          isTrue,
        );
        final dns = root['dns'] as Map;
        expect(
          (dns['servers'] as List).cast<Map>().any(
            (r) => r['tag'] == 'local-dns' && r['type'] == 'local',
          ),
          isTrue,
        );
        expect(
          (dns['rules'] as List).cast<Map>().any(
            (r) =>
                (r['domain_suffix'] as List?)?.contains('.local') == true &&
                r['server'] == 'local-dns',
          ),
          isTrue,
        );
      },
    );
  }
  test('Iran and custom bypass can coexist and disable independently', () {
    for (final iran in [true, false]) {
      final settings = <String, Object?>{
        'routingMode': 'global',
        'bypassIran': iran,
        'customRulesEnabled': true,
        'customDomains': 'domain:example.net',
        'customIps': '203.0.113.0/24',
      };
      final xray =
          jsonDecode(
                const WindowsXrayConfigBuilder().build(
                  server: server,
                  settings: settings,
                  iranCidrs: const ['2.144.0.0/14'],
                ),
              )
              as Map;
      final xr = ((xray['routing'] as Map)['rules'] as List).cast<Map>();
      expect(
        xr.any((r) => (r['ip'] as List?)?.contains('2.144.0.0/14') == true),
        iran,
      );
      expect(
        xr.any((r) => (r['ip'] as List?)?.contains('203.0.113.0/24') == true),
        isTrue,
      );
      final sb =
          jsonDecode(
                const WindowsSingBoxTunConfigBuilder().build(
                  settings: settings,
                  xraySocksPort: 10808,
                  iranCidrs: const ['2.144.0.0/14'],
                  protectedProcessPaths: const [],
                ),
              )
              as Map;
      final sr = ((sb['route'] as Map)['rules'] as List).cast<Map>();
      expect(
        sr.any(
          (r) => (r['ip_cidr'] as List?)?.contains('2.144.0.0/14') == true,
        ),
        iran,
      );
      expect(
        sr.any(
          (r) => (r['ip_cidr'] as List?)?.contains('203.0.113.0/24') == true,
        ),
        isTrue,
      );
    }
  });
}

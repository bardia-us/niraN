import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:niran/platform/windows/windows_sing_box_tun_config_builder.dart';

void main() {
  const builder = WindowsSingBoxTunConfigBuilder();

  Map<String, Object?> settings({String routingMode = 'global'}) => {
    'routingMode': routingMode,
    'enableIpv6': true,
    'vpnInterfaceAddress': '10.10.14.1/30',
    'vpnInterfaceIpv6Address': 'fdfe:dcba:9876::1/126',
    'vpnMtu': 1500,
    'vpnDns': '1.1.1.1',
    'remoteDns': 'https://dns.google/dns-query',
    'domesticDns': '223.5.5.5',
    'dnsQueryStrategy': 'Auto',
    'preferIpv6': false,
    'xrayLogLevel': 'warning',
  };

  test('builds an isolated sing-box 1.14 TUN frontend config', () {
    final raw = builder.build(
      settings: settings(),
      xraySocksPort: 10808,
      iranCidrs: const ['2.144.0.0/14'],
      protectedProcessPaths: const [r'C:\niraN\xray\xray.exe'],
      proxyServerHost: 'edge.example.com',
    );
    final root = jsonDecode(raw) as Map<String, dynamic>;
    final inbound = (root['inbounds'] as List).single as Map;
    expect(inbound['type'], 'tun');
    expect(inbound['auto_route'], isTrue);
    expect(inbound['strict_route'], isTrue);
    final proxy = (root['outbounds'] as List).cast<Map>().firstWhere(
      (item) => item['tag'] == 'proxy',
    );
    expect(proxy['type'], 'socks');
    expect(proxy['server_port'], 10808);
    expect((root['route'] as Map)['final'], 'proxy');
    expect((root['log'] as Map)['level'], 'warn');
    final dns = root['dns'] as Map;
    expect(dns['strategy'], 'ipv4_only');
    expect((dns['servers'] as List).cast<Map>().first['detour'], isNull);
    final remoteDns = (dns['servers'] as List).cast<Map>().firstWhere(
      (server) => server['tag'] == 'remote-dns',
    );
    expect(remoteDns['server'], '8.8.8.8');
    expect((remoteDns['tls'] as Map)['server_name'], 'dns.google');
    expect(remoteDns['domain_resolver'], isNull);
    expect((dns['rules'] as List).cast<Map>().first['domain'], [
      'edge.example.com',
    ]);
  });

  test('TUN DNS honors explicit dual-stack and IPv6 strategies', () {
    final dualStack =
        jsonDecode(
              builder.build(
                settings: {...settings(), 'dnsQueryStrategy': 'UseIP'},
                xraySocksPort: 10808,
                iranCidrs: const ['2.144.0.0/14'],
                protectedProcessPaths: const [],
              ),
            )
            as Map<String, dynamic>;
    expect((dualStack['dns'] as Map)['strategy'], 'prefer_ipv4');

    final ipv6Only =
        jsonDecode(
              builder.build(
                settings: {...settings(), 'dnsQueryStrategy': 'UseIPv6'},
                xraySocksPort: 10808,
                iranCidrs: const ['2.144.0.0/14'],
                protectedProcessPaths: const [],
              ),
            )
            as Map<String, dynamic>;
    expect((ipv6Only['dns'] as Map)['strategy'], 'ipv6_only');
  });

  test('bypass Iran config routes frozen CIDRs and dot-ir directly', () {
    final root =
        jsonDecode(
              builder.build(
                settings: settings(routingMode: 'bypassIran'),
                xraySocksPort: 10808,
                iranCidrs: const ['2.144.0.0/14', '2001:470:1f0b::/48'],
                protectedProcessPaths: const [],
              ),
            )
            as Map<String, dynamic>;
    final rules = ((root['route'] as Map)['rules'] as List).cast<Map>();
    expect(
      rules.any(
        (rule) =>
            (rule['domain_suffix'] as List?)?.contains('.ir') == true &&
            rule['outbound'] == 'direct',
      ),
      isTrue,
    );
    expect(
      rules.any(
        (rule) =>
            (rule['ip_cidr'] as List?)?.contains('2.144.0.0/14') == true &&
            rule['outbound'] == 'direct',
      ),
      isTrue,
    );
  });

  test('generated config passes the pinned sing-box binary check', () async {
    if (!Platform.isWindows) return;
    final binary = File(r'windows\sing-box\bin\sing-box-v1.14.0.exe');
    if (!await binary.exists()) return;
    final directory = await Directory.systemTemp.createTemp('niran-sb-test-');
    try {
      final config = File('${directory.path}\\config.json');
      await config.writeAsString(
        builder.build(
          settings: settings(),
          xraySocksPort: 10808,
          iranCidrs: const ['2.144.0.0/14'],
          protectedProcessPaths: const [r'C:\niraN\xray\xray.exe'],
        ),
      );
      final result = await Process.run(binary.path, [
        'check',
        '--config',
        config.path,
      ]);
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    } finally {
      await directory.delete(recursive: true);
    }
  });
}

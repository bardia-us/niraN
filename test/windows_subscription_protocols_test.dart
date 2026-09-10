import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:niran/platform/windows/windows_server_order_policy.dart';
import 'package:niran/platform/windows/windows_subscription_parser.dart';
import 'package:niran/platform/windows/windows_xray_config_builder.dart';

void main() {
  const parser = WindowsSubscriptionParser();
  const builder = WindowsXrayConfigBuilder();
  const settings = <String, Object?>{
    'routingMode': 'global',
    'domainStrategy': 'AsIs',
    'remoteDns': 'https://dns.google/dns-query',
    'enableLocalDns': true,
    'enableFakeDns': false,
    'enableIpv6': true,
    'sniffingEnabled': true,
    'sniffingType': 'http,tls,quic',
    'enableUdp': true,
  };

  test('semantic id ignores remark and query ordering', () {
    final a = parser
        .parse('vless://id@example.com:443?security=tls&type=ws#One')
        .single;
    final b = parser
        .parse('vless://id@example.com:443?type=ws&security=tls#Two')
        .single;
    expect(a.id, b.id);
  });

  test('malformed entry cannot hide valid subscription entries', () {
    final result = parser.parseDetailed('''
vless://id@one.example:443?security=tls#One
ss://broken
trojan://password@two.example:443?security=tls#Two
''');
    expect(result.records, hasLength(2));
    expect(result.failedEntries, 1);
  });

  test(
    'informational VLESS stays visible but is rejected at connect boundary',
    () {
      final record = parser
          .parse(
            'vless://id@1.1.1.1:443?security=tls&type=tcp#'
            '${Uri.encodeComponent('هر دفعه آپدیت کنید - V4.8')}',
          )
          .single;
      expect(record.address, '1.1.1.1');
      expect(record.rejectionReason, contains('information only'));
    },
  );

  test('XHTTP Extra and Reality ML-DSA fields reach their Xray schema', () {
    final xhttp = parser
        .parse(
          'vless://id@example.com:443?security=tls&type=xhttp'
          '&extra=${Uri.encodeQueryComponent('{"noSSEHeader":false}')}'
          '&fp=android#XHTTP',
        )
        .single;
    final xhttpJson =
        jsonDecode(builder.build(server: xhttp, settings: settings)) as Map;
    final xhttpStream =
        ((xhttpJson['outbounds'] as List).first as Map)['streamSettings']
            as Map;
    expect(xhttpStream['xhttpSettings']['extra']['noSSEHeader'], isFalse);
    expect(xhttpStream['tlsSettings']['fingerprint'], 'android');

    final reality = parser
        .parse(
          'vless://id@example.com:443?security=reality&type=tcp'
          '&pbk=public-key&pqv=verify-key&fp=qq#Reality',
        )
        .single;
    final realityJson =
        jsonDecode(builder.build(server: reality, settings: settings)) as Map;
    final realityStream =
        ((realityJson['outbounds'] as List).first as Map)['streamSettings']
            as Map;
    expect(realityStream['realitySettings']['mldsa65Verify'], 'verify-key');
    expect(realityStream['realitySettings']['fingerprint'], 'qq');
    expect(realityStream['realitySettings'], isNot(contains('cipherSuites')));
  });

  test('Direct DNS is opt-in and mapped without replacing remote DNS', () {
    final server = parser
        .parse('vless://id@example.com:443?security=tls&type=ws#Server')
        .single;
    final json =
        jsonDecode(
              builder.build(
                server: server,
                settings: {
                  ...settings,
                  'directDnsEnabled': true,
                  'directDnsAddress': '178.22.122.100',
                },
              ),
            )
            as Map;
    final dnsServers = (json['dns'] as Map)['servers'] as List;
    expect(
      dnsServers.whereType<Map>().any(
        (entry) => entry['address'] == '178.22.122.100',
      ),
      isTrue,
    );
    expect(dnsServers, contains('https://dns.google/dns-query'));
  });

  test(
    'QUIC blocking is opt-in and maps identically for Normal and TUN Xray',
    () {
      final server = parser
          .parse('vless://id@example.com:443?security=tls&type=ws#Server')
          .single;

      bool hasQuicBlock(Map root) =>
          ((root['routing'] as Map)['rules'] as List).whereType<Map>().any(
            (rule) =>
                rule['network'] == 'udp' &&
                rule['port'] == '443' &&
                rule['outboundTag'] == 'blocked',
          );

      for (final tunEnabled in const [false, true]) {
        final allowed =
            jsonDecode(
                  builder.build(
                    server: server,
                    settings: {...settings, 'tunEnabled': tunEnabled},
                  ),
                )
                as Map;
        final blocked =
            jsonDecode(
                  builder.build(
                    server: server,
                    settings: {
                      ...settings,
                      'tunEnabled': tunEnabled,
                      'blockQuic': true,
                    },
                  ),
                )
                as Map;
        expect(hasQuicBlock(allowed), isFalse, reason: 'tun=$tunEnabled');
        expect(hasQuicBlock(blocked), isTrue, reason: 'tun=$tunEnabled');
      }
    },
  );

  test('Mux is configurable only for compatible VLESS and VMess profiles', () {
    Map muxFor(String link, {int concurrency = 8}) {
      final server = parser.parse(link).single;
      final root =
          jsonDecode(
                builder.build(
                  server: server,
                  settings: {
                    ...settings,
                    'muxEnabled': true,
                    'muxConcurrency': concurrency,
                  },
                ),
              )
              as Map;
      return ((root['outbounds'] as List).first as Map)['mux'] as Map;
    }

    for (final concurrency in const [1, 8, 16, 32]) {
      expect(
        muxFor(
          'vless://id@example.com:443?security=tls&type=ws#VLESS',
          concurrency: concurrency,
        ),
        {'enabled': true, 'concurrency': concurrency},
      );
    }
    expect(
      muxFor(
        'vmess://${base64Url.encode(utf8.encode(jsonEncode({'v': '2', 'ps': 'VMess', 'add': 'example.com', 'port': '443', 'id': '00000000-0000-4000-8000-000000000002', 'aid': '0', 'net': 'ws', 'tls': 'tls'})))}',
      ),
      {'enabled': true, 'concurrency': 8},
    );
    expect(
      muxFor('trojan://secret@example.com:443?security=tls&type=ws#Trojan'),
      {'enabled': false},
    );
    expect(muxFor('vless://id@example.com:443?security=tls&type=xhttp#XHTTP'), {
      'enabled': false,
    });
    expect(
      muxFor(
        'vless://id@example.com:443?security=reality&type=tcp'
        '&flow=xtls-rprx-vision&pbk=key#Vision',
      ),
      {'enabled': false},
    );
  });

  test(
    'parses SIP002 and legacy Shadowsocks with special unicode passwords',
    () {
      final credentials = base64Url
          .encode(utf8.encode('chacha20-ietf-poly1305:p@ss:رمز'))
          .replaceAll('=', '');
      final sip = parser.parse('ss://$credentials@example.com:8388#SIP').single;
      final legacyPayload = base64Url
          .encode(
            utf8.encode('chacha20-ietf-poly1305:p@ss:رمز@example.org:8389'),
          )
          .replaceAll('=', '');
      final legacy = parser.parse('ss://$legacyPayload#Legacy').single;
      expect(sip.protocol, 'shadowsocks');
      expect(sip.credential, 'p@ss:رمز');
      expect(legacy.address, 'example.org');
      final json =
          jsonDecode(builder.build(server: sip, settings: settings))
              as Map<String, dynamic>;
      final proxy = (json['outbounds'] as List).first as Map;
      final server =
          ((proxy['settings'] as Map)['servers'] as List).first as Map;
      expect(server['method'], 'chacha20-ietf-poly1305');
      expect(server['password'], 'p@ss:رمز');
    },
  );

  test('SOCKS HTTP and Hysteria2 produce concrete outbound settings', () {
    final records = parser.parse('''
socks5://user:p%40ss@socks.example:1080#SOCKS
http://user:pass@http.example:8080#HTTP
hy2://secret@hy.example:443?sni=edge.example#HY2
''');
    expect(records.map((e) => e.protocol), ['socks', 'http', 'hysteria2']);
    for (final record in records) {
      final json =
          jsonDecode(builder.build(server: record, settings: settings)) as Map;
      final proxy = (json['outbounds'] as List).first as Map;
      expect(proxy['protocol'], isNotEmpty);
      expect(proxy['settings'], isNotEmpty);
    }
  });

  test(
    'manual order survives semantic id changes without duplicating records',
    () {
      final old = parser.parse('''
vless://a@one.example:443?security=tls&type=ws#First
ss://Y2hhY2hhMjAtaWV0Zi1wb2x5MTMwNTpwYXNz@ss.example:8388#SS
trojan://p@three.example:443?security=tls#Third
''');
      final refreshed = parser.parse('''
vless://a@one.example:443?type=ws&security=tls#Renamed
ss://Y2hhY2hhMjAtaWV0Zi1wb2x5MTMwNTpwYXNz@ss.example:8388#SS renamed
trojan://p@three.example:443?security=tls#Third
''');
      final ordered = const WindowsServerOrderPolicy().reconcile(
        preferredIds: [old[2].id, old[1].id, old[0].id],
        previous: old,
        refreshed: refreshed,
      );
      expect(ordered.map((e) => e.address), [
        'three.example',
        'ss.example',
        'one.example',
      ]);
      expect(ordered.map((e) => e.id).toSet(), hasLength(3));
    },
  );

  test(
    'informational entries keep subscription position without manual order',
    () {
      final refreshed = parser.parse('''
vless://a@one.example:443?security=tls&type=ws#First
vless://notice@1.1.1.1:443?security=none&type=tcp#${Uri.encodeComponent('هر دفعه آپدیت کنید - V4.8')}
trojan://p@three.example:443?security=tls#Third
''');
      final ordered = const WindowsServerOrderPolicy().reconcile(
        preferredIds: const [],
        previous: const [],
        refreshed: refreshed,
      );
      expect(ordered.map((item) => item.name), [
        'First',
        'هر دفعه آپدیت کنید - V4.8',
        'Third',
      ]);
      expect(ordered[1].rejectionReason, contains('information only'));
    },
  );

  test('new informational entry is not appended after a manual order', () {
    final previous = parser.parse('''
vless://a@one.example:443?security=tls&type=ws#First
trojan://p@three.example:443?security=tls#Third
''');
    final refreshed = parser.parse('''
vless://a@one.example:443?security=tls&type=ws#First
vless://notice@1.1.1.1:443?security=none&type=tcp#${Uri.encodeComponent('هر دفعه آپدیت کنید - V4.8')}
trojan://p@three.example:443?security=tls#Third
''');
    final ordered = const WindowsServerOrderPolicy().reconcile(
      preferredIds: [previous[1].id, previous[0].id],
      previous: previous,
      refreshed: refreshed,
    );
    expect(ordered.map((item) => item.name), [
      'Third',
      'هر دفعه آپدیت کنید - V4.8',
      'First',
    ]);
  });

  test('Xray DNS and resolution settings reach supported runtime fields', () {
    final server = parser
        .parse('vless://id@example.com:443?security=tls&type=ws#Server')
        .single;
    final root =
        jsonDecode(
              builder.build(
                server: server,
                settings: {
                  ...settings,
                  'dnsQueryStrategy': 'UseSystem',
                  'dnsParallelQuery': true,
                  'dnsServeStale': true,
                  'directTargetStrategy': 'UseIPv4',
                  'proxyTargetStrategy': 'UseIP',
                  'proxyDialStrategy': 'UseIP',
                  'happyEyeballs': true,
                },
              ),
            )
            as Map;
    expect(root['dns'], containsPair('queryStrategy', 'UseSystem'));
    expect(root['dns'], containsPair('enableParallelQuery', true));
    expect(root['dns'], containsPair('serveStale', true));
    final outbounds = (root['outbounds'] as List).whereType<Map>().toList();
    final proxy = outbounds.singleWhere((item) => item['tag'] == 'proxy');
    final direct = outbounds.singleWhere((item) => item['tag'] == 'direct');
    expect(proxy['targetStrategy'], 'UseIP');
    expect(proxy['streamSettings']['sockopt']['domainStrategy'], 'UseIP');
    expect(
      proxy['streamSettings']['sockopt']['happyEyeballs'],
      containsPair('tryDelayMs', 250),
    );
    expect(direct['settings']['targetStrategy'], 'UseIPv4');
  });

  test('bundled Xray validates newly supported protocol configs', () async {
    if (!Platform.isWindows) return;
    final xray = File('windows/xray/bin/xray-v26.7.28.exe');
    if (!await xray.exists()) return;
    final records = parser.parse('''
ss://Y2hhY2hhMjAtaWV0Zi1wb2x5MTMwNTpwYXNz@ss.example:8388#SS
socks5://user:pass@socks.example:1080#SOCKS
http://user:pass@http.example:8080#HTTP
hy2://secret@hy.example:443?sni=hy.example#HY2
''');
    final directory = await Directory.systemTemp.createTemp('niraN-protocols-');
    try {
      for (final record in records) {
        final file = File(
          '${directory.path}${Platform.pathSeparator}${record.protocol}.json',
        );
        await file.writeAsString(
          builder.build(server: record, settings: settings),
        );
        final result = await Process.run(xray.absolute.path, [
          'run',
          '-test',
          '-c',
          file.path,
        ]);
        expect(
          result.exitCode,
          0,
          reason: '${record.protocol}: ${result.stdout}\n${result.stderr}',
        );
      }
    } finally {
      await directory.delete(recursive: true);
    }
  });

  test('bundled Xray accepts Fragment maxSplit runtime schema', () async {
    if (!Platform.isWindows) return;
    final xray = File('windows/xray/bin/xray-v26.7.28.exe');
    if (!await xray.exists()) return;
    final server = parser
        .parse('vless://id@example.com:443?security=tls&type=ws#Fragment')
        .single;
    final directory = await Directory.systemTemp.createTemp('niraN-fragment-');
    try {
      final file = File(
        '${directory.path}${Platform.pathSeparator}fragment.json',
      );
      await file.writeAsString(
        builder.build(
          server: server,
          settings: {
            ...settings,
            'fragmentEnabled': true,
            'fragmentPackets': 'tlshello',
            'fragmentLength': '10-20',
            'fragmentInterval': '0-5',
            'fragmentMaxSplit': '2-4',
          },
        ),
      );
      final result = await Process.run(xray.absolute.path, [
        'run',
        '-test',
        '-c',
        file.path,
      ]);
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    } finally {
      await directory.delete(recursive: true);
    }
  });

  test('bundled Xray accepts optional QUIC block and Mux schema', () async {
    if (!Platform.isWindows) return;
    final xray = File('windows/xray/bin/xray-v26.7.28.exe');
    if (!await xray.exists()) return;
    final server = parser
        .parse('vless://id@example.com:443?security=tls&type=ws#Mux')
        .single;
    final directory = await Directory.systemTemp.createTemp('niraN-mux-');
    try {
      for (final concurrency in const [1, 8, 16, 32]) {
        final file = File(
          '${directory.path}${Platform.pathSeparator}mux-$concurrency.json',
        );
        await file.writeAsString(
          builder.build(
            server: server,
            settings: {
              ...settings,
              'blockQuic': true,
              'muxEnabled': true,
              'muxConcurrency': concurrency,
            },
          ),
        );
        final result = await Process.run(xray.absolute.path, [
          'run',
          '-test',
          '-c',
          file.path,
        ]);
        expect(
          result.exitCode,
          0,
          reason:
              'concurrency=$concurrency: ${result.stdout}\n${result.stderr}',
        );
      }
    } finally {
      await directory.delete(recursive: true);
    }
  });
}

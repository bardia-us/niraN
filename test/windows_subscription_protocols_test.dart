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
}

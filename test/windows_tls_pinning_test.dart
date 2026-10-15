import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:niran/platform/windows/windows_core_selection.dart';
import 'package:niran/platform/windows/windows_server_record.dart';
import 'package:niran/platform/windows/windows_sing_box_proxy_config_builder.dart';
import 'package:niran/platform/windows/windows_subscription_parser.dart';
import 'package:niran/platform/windows/windows_xray_config_builder.dart';

const _first =
    '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';
const _second =
    'abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789';
const _colon =
    '01:23:45:67:89:AB:CD:EF:01:23:45:67:89:AB:CD:EF:'
    '01:23:45:67:89:AB:CD:EF:01:23:45:67:89:AB:CD:EF';

WindowsServerRecord _parse(String query) => const WindowsSubscriptionParser()
    .parse(
      'vless://00000000-0000-4000-8000-000000000001@example.com:443'
      '?security=tls&type=ws&$query#Synthetic',
    )
    .single;

Map _tls(WindowsServerRecord server) =>
    jsonDecode(
          const WindowsXrayConfigBuilder().build(
            server: server,
            settings: const {'routingMode': 'global'},
          ),
        )['outbounds'][0]['streamSettings']['tlsSettings']
        as Map;

void main() {
  for (final key in ['pcs', 'pinSHA256']) {
    test('$key emits a whole-certificate hex pin as an Xray string', () {
      final server = _parse('$key=${Uri.encodeQueryComponent(_colon)}');
      expect(_tls(server)['pinnedPeerCertSha256'], _first);
    });
  }
  test('multiple pins normalize without expanding equivalent alias sets', () {
    final server = _parse(
      'pcs=$_second,$_first,$_first&pinSHA256=$_first,${_second.toUpperCase()}',
    );
    expect(_tls(server)['pinnedPeerCertSha256'], '$_first,$_second');
  });
  test('vcn emits verification names as a string independent of SNI', () {
    final tls = _tls(
      _parse('vcn=verify.example.com,other.example.com&sni=sni.example.com'),
    );
    expect(tls['verifyPeerCertByName'], 'verify.example.com,other.example.com');
    expect(tls['serverName'], 'sni.example.com');
  });
  for (final names in ['', ',', 'verify.example.com,', ',verify.example.com']) {
    test(
      'empty verification-name list members fail before TLS generation: $names',
      () {
        final server = _parse('vcn=${Uri.encodeQueryComponent(names)}');
        expect(() => _tls(server), throwsFormatException);
        expect(
          () => const WindowsSubscriptionParser().exportShareLink(server),
          throwsFormatException,
        );
      },
    );
  }
  test(
    'conflicting repeated verification-name fields cannot lose a constraint',
    () {
      final server = _parse('vcn=first.example.com&vcn=second.example.com');
      expect(() => _tls(server), throwsFormatException);
      expect(
        () => const WindowsSubscriptionParser().exportShareLink(server),
        throwsFormatException,
      );
    },
  );
  test(
    'identical verification names preserve the FromMitM core convention',
    () {
      final server = _parse('vcn=%20FromMitM%20&vcn=FromMitM');
      expect(_tls(server)['verifyPeerCertByName'], 'FromMitM');
    },
  );
  for (final query in [
    'pcs=bad',
    'pcs=',
    'pcs=${_first.substring(1)}',
    'pcs=$_first,',
    'pinSHA256=sha256%2FAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA%3D',
    'pcs=$_first&pinSHA256=$_second',
    'pcs=$_first&pinSHA256=bad',
    'pcs=bad&pcs=$_first',
    'pcs=$_second&pcs=$_first',
  ]) {
    test('invalid or conflicting pins fail before generating TLS: $query', () {
      expect(() => _tls(_parse(query)), throwsFormatException);
    });
  }
  test('identical repeated pin fields do not lose the security constraint', () {
    expect(
      _tls(_parse('pcs=$_first&pcs=$_first'))['pinnedPeerCertSha256'],
      _first,
    );
  });
  test('pin and name fields cannot silently disappear on non-TLS profiles', () {
    for (final query in ['pcs=$_first', 'vcn=verify.example.com']) {
      final server = const WindowsSubscriptionParser()
          .parse(
            'vless://00000000-0000-4000-8000-000000000001@example.com:443?security=none&$query#Synthetic',
          )
          .single;
      expect(
        () => const WindowsXrayConfigBuilder().build(
          server: server,
          settings: const {'routingMode': 'global'},
        ),
        throwsFormatException,
      );
    }
  });
  test('old TLS and existing TLS options survive pin forwarding', () {
    final plain = _tls(
      _parse(
        'fp=firefox&alpn=h2,http%2F1.1&cs=TLS_AES_128_GCM_SHA256&ech=udp%3A%2F%2F1.1.1.1',
      ),
    );
    final pinned = _tls(
      _parse(
        'pcs=$_first&fp=firefox&alpn=h2,http%2F1.1&cs=TLS_AES_128_GCM_SHA256&ech=udp%3A%2F%2F1.1.1.1',
      ),
    );
    expect(plain.containsKey('pinnedPeerCertSha256'), isFalse);
    expect(plain.containsKey('verifyPeerCertByName'), isFalse);
    expect(pinned['fingerprint'], 'firefox');
    expect(pinned['alpn'], ['h2', 'http/1.1']);
    expect(pinned['cipherSuites'], 'TLS_AES_128_GCM_SHA256');
    expect(pinned['echConfigList'], 'udp://1.1.1.1');
    expect(pinned.containsKey('allowInsecure'), isFalse);
    pinned.remove('pinnedPeerCertSha256');
    expect(pinned, plain);
  });
  test('share export and re-import preserve original pin and name values', () {
    const parser = WindowsSubscriptionParser();
    final server = _parse(
      'pcs=${Uri.encodeQueryComponent(_colon)}&pinSHA256=$_first&vcn=verify.example.com&custom=value',
    );
    final restored = parser.parse(parser.exportShareLink(server)).single;
    expect(restored.parameters, server.parameters);
    expect(_tls(restored)['pinnedPeerCertSha256'], _first);
  });
  test(
    'share export cannot erase conflicting or invalid repeated pin fields',
    () {
      for (final query in [
        'pcs=bad&pcs=$_first',
        'pcs=$_second&pcs=$_first',
        'pcs=$_first&pinSHA256=$_second',
      ]) {
        expect(
          () =>
              const WindowsSubscriptionParser().exportShareLink(_parse(query)),
          throwsFormatException,
        );
      }
    },
  );
  for (final query in [
    'pcs=$_first',
    'pinSHA256=$_first',
    'vcn=verify.example.com',
    'vcn=',
  ]) {
    test(
      'sing-box explicitly rejects unsupported certificate constraint: $query',
      () {
        final server = _parse(query);
        expect(
          WindowsCoreSelection.singBoxUnsupportedReason(server, {}),
          isNotNull,
        );
        expect(
          () => const WindowsSingBoxProxyConfigBuilder().build(
            server: server,
            settings: const {'routingMode': 'global'},
          ),
          throwsFormatException,
        );
        expect(
          () => const WindowsSingBoxProxyConfigBuilder().buildSpeedtest(
            servers: [server],
            settings: const {},
            socksPorts: [20808],
            httpPorts: [20809],
          ),
          throwsFormatException,
        );
      },
    );
  }
  test('speed-test output forwards the same pin and name constraints', () {
    final root = jsonDecode(
      const WindowsXrayConfigBuilder().buildSpeedtest(
        servers: [_parse('pcs=$_first&vcn=verify.example.com')],
        settings: const {},
        socksPorts: [20808],
        httpPorts: [20809],
      ),
    );
    final tls = root['outbounds'][0]['streamSettings']['tlsSettings'];
    expect(tls['pinnedPeerCertSha256'], _first);
    expect(tls['verifyPeerCertByName'], 'verify.example.com');
  });
  test(
    'available Windows Xray accepts generated pin/name JSON offline',
    () async {
      if (!Platform.isWindows) return;
      final installed = File(
        '${Platform.environment['LOCALAPPDATA']}/Programs/niraN/xray/xray.exe',
      );
      final executable = installed.existsSync()
          ? installed
          : File('windows/xray/bin/xray-v26.7.28.exe').absolute;
      expect(executable.existsSync(), isTrue);
      final directory = await Directory.systemTemp.createTemp(
        'niran-tls-schema-',
      );
      addTearDown(() => directory.delete(recursive: true));
      for (final query in [
        'pcs=$_first&vcn=verify.example.com',
        'pinSHA256=${Uri.encodeQueryComponent(_colon)},$_second',
        'pcs=$_first&fp=unsafe',
      ]) {
        final file = File('${directory.path}/fixture.json');
        await file.writeAsString(
          const WindowsXrayConfigBuilder().build(
            server: _parse(query),
            settings: const {'routingMode': 'global'},
          ),
        );
        expect(
          (jsonDecode(
                await file.readAsString(),
              )['outbounds'][0]['streamSettings']['tlsSettings']
              as Map)['pinnedPeerCertSha256'],
          isA<String>(),
        );
        final result = await Process.run(executable.path, [
          'run',
          '-test',
          '-c',
          file.path,
        ], workingDirectory: executable.parent.path);
        expect(
          result.exitCode,
          0,
          reason: '${result.stdout}\n${result.stderr}',
        );
      }
    },
  );
}

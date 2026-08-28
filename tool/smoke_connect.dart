import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:niran/platform/windows/windows_subscription_parser.dart';
import 'package:niran/platform/windows/windows_server_record.dart';
import 'package:niran/platform/windows/windows_xray_config_builder.dart';

Future<void> main() async {
  final properties = File('windows/local.properties');
  final xray = File('windows/xray/bin/xray-v26.7.28.exe');
  if (!properties.existsSync() || !xray.existsSync()) {
    stderr.writeln('Private build inputs or bundled Xray are missing.');
    exitCode = 2;
    return;
  }

  final endpoint = _subscriptionEndpoint(properties);
  if (endpoint == null) {
    stderr.writeln('The internal subscription endpoint is invalid.');
    exitCode = 2;
    return;
  }

  final temporary = await Directory.systemTemp.createTemp('niraN-smoke-');
  final client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 12)
    ..userAgent = 'niraN-live-smoke/0.1.0';
  try {
    final request = await client
        .getUrl(endpoint)
        .timeout(const Duration(seconds: 12));
    final response = await request.close().timeout(const Duration(seconds: 12));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException('Subscription returned HTTP ${response.statusCode}');
    }
    final body = await response.transform(utf8.decoder).join();
    final servers = const WindowsSubscriptionParser()
        .parse(body)
        .where((server) => server.rejectionReason == null)
        .toList(growable: false);
    if (servers.isEmpty) throw const FormatException('No connectable servers');

    final directProbe = await _curlPublicIp(const []);
    final directIp = directProbe.value;
    if (directIp == null) {
      throw HttpException(
        'Could not verify the direct public IP (${directProbe.diagnostic})',
      );
    }

    const builder = WindowsXrayConfigBuilder();
    for (var index = 0; index < servers.length; index++) {
      final socksPort = await _freePort();
      var httpPort = await _freePort();
      while (httpPort == socksPort) {
        httpPort = await _freePort();
      }
      final settings = <String, Object?>{
        ..._settings,
        'localSocksPort': socksPort,
        'localHttpPort': httpPort,
      };
      final config = File('${temporary.path}\\config-$index.json');
      await config.writeAsString(
        builder.build(server: servers[index], settings: settings),
      );

      final coreLines = <String>[];
      final process = await Process.start(xray.absolute.path, [
        'run',
        '-c',
        config.path,
      ], workingDirectory: temporary.path);
      final outputSubscriptions = <StreamSubscription<String>>[
        process.stdout
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .listen(coreLines.add),
        process.stderr
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .listen(coreLines.add),
      ];
      try {
        if (!await _waitForProxy(httpPort)) {
          stdout.writeln(
            'Server ${index + 1}: local proxy startup failed '
            '(${_lastSafeLine(coreLines, servers[index])}).',
          );
          continue;
        }

        final httpProbe = await _curlPublicIp([
          '--proxy',
          'http://127.0.0.1:$httpPort',
        ]);
        final socksProbe = await _curlPublicIp([
          '--socks5-hostname',
          '127.0.0.1:$socksPort',
        ]);
        final httpIp = httpProbe.value;
        final socksIp = socksProbe.value;
        if (httpIp == null || socksIp == null) {
          stdout.writeln(
            'Server ${index + 1}: public IP probe failed '
            '(HTTP: ${httpProbe.diagnostic}, '
            'SOCKS: ${socksProbe.diagnostic}; '
            '${_lastSafeLine(coreLines, servers[index])}).',
          );
          continue;
        }
        final httpChanged = httpIp != directIp;
        final socksChanged = socksIp != directIp;
        if (!httpChanged || !socksChanged) {
          stdout.writeln(
            'Server ${index + 1}: proxy responded but public IP change failed '
            '(HTTP: $httpChanged, SOCKS: $socksChanged).',
          );
          continue;
        }

        stdout.writeln(
          'Real Xray connection succeeded with server ${index + 1}; '
          'HTTP verified: true; SOCKS verified: true; '
          'public IP changed on both paths: true; '
          'proxy exit IPs match: ${httpIp == socksIp}.',
        );
        return;
      } finally {
        process.kill();
        try {
          await process.exitCode.timeout(const Duration(seconds: 3));
        } on TimeoutException {
          process.kill(ProcessSignal.sigkill);
        }
        for (final subscription in outputSubscriptions) {
          await subscription.cancel();
        }
      }
    }

    stderr.writeln('No subscription server completed the live smoke test.');
    exitCode = 1;
  } finally {
    client.close(force: true);
    if (temporary.existsSync()) await temporary.delete(recursive: true);
  }
}

Uri? _subscriptionEndpoint(File properties) {
  final line = properties.readAsLinesSync().firstWhere(
    (value) => value.trimLeft().startsWith('NIRANG_SUBSCRIPTION_URL='),
    orElse: () => '',
  );
  if (line.isEmpty) return null;
  final endpoint = Uri.tryParse(line.substring(line.indexOf('=') + 1).trim());
  if (endpoint == null || endpoint.scheme != 'https' || endpoint.host.isEmpty) {
    return null;
  }
  return endpoint;
}

Future<int> _freePort() async {
  final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = socket.port;
  await socket.close();
  return port;
}

Future<bool> _waitForProxy(int port) async {
  final deadline = DateTime.now().add(const Duration(seconds: 8));
  while (DateTime.now().isBefore(deadline)) {
    try {
      final socket = await Socket.connect(
        InternetAddress.loopbackIPv4,
        port,
        timeout: const Duration(milliseconds: 350),
      );
      socket.destroy();
      return true;
    } on Object {
      await Future<void>.delayed(const Duration(milliseconds: 120));
    }
  }
  return false;
}

Future<({String? value, String diagnostic})> _curlPublicIp(
  List<String> proxyArguments,
) async {
  final failures = <String>[];
  for (final endpoint in const [
    'https://api.ip.sb/ip',
    'https://api64.ipify.org',
  ]) {
    try {
      final result = await Process.run('curl.exe', [
        '--silent',
        '--show-error',
        '--fail',
        '--connect-timeout',
        '15',
        '--max-time',
        '25',
        ...proxyArguments,
        endpoint,
      ]).timeout(const Duration(seconds: 28));
      final value = '${result.stdout}'.trim();
      if (result.exitCode == 0 && InternetAddress.tryParse(value) != null) {
        return (value: value, diagnostic: 'verified');
      }
      failures.add('curl-${result.exitCode}');
    } on TimeoutException {
      failures.add('process-timeout');
    } on Object {
      failures.add('process-error');
    }
  }
  return (value: null, diagnostic: failures.join(','));
}

String _lastSafeLine(List<String> lines, WindowsServerRecord server) {
  if (lines.isEmpty) return 'no Xray diagnostic';
  final line = lines.reversed.firstWhere(
    (value) => RegExp(
      r'error|failed|rejected|timeout',
      caseSensitive: false,
    ).hasMatch(value),
    orElse: () => lines.last,
  );
  return _safeCoreLine(line, server);
}

String _safeCoreLine(String line, WindowsServerRecord server) => line
    .replaceAll(server.address, 'server')
    .replaceAll(server.credential, 'credential')
    .replaceAll(RegExp(r'https?://\S+', caseSensitive: false), 'endpoint')
    .replaceAll(RegExp(r'\b(?:\d{1,3}\.){3}\d{1,3}\b'), 'address')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

const _settings = <String, Object?>{
  'connectionMode': 'proxy',
  'routingMode': 'global',
  'enableLocalDns': true,
  'enableFakeDns': false,
  'remoteDns': 'https://dns.google/dns-query',
  'domainStrategy': 'AsIs',
  'sniffingEnabled': true,
  'routeOnly': false,
  'enableIpv6': true,
  'preferIpv6': false,
};

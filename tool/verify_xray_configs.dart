import 'dart:convert';
import 'dart:io';

import 'package:niran/platform/windows/windows_subscription_parser.dart';
import 'package:niran/platform/windows/windows_xray_config_builder.dart';

Future<void> main() async {
  final properties = File('windows/local.properties');
  final xray = File('windows/xray/bin/xray-v26.7.28.exe');
  if (!properties.existsSync() || !xray.existsSync()) {
    stderr.writeln('Private build inputs or bundled Xray are missing.');
    exitCode = 2;
    return;
  }
  final endpointLine = properties.readAsLinesSync().firstWhere(
    (line) => line.trimLeft().startsWith('NIRANG_SUBSCRIPTION_URL='),
    orElse: () => '',
  );
  final endpoint = endpointLine.isEmpty
      ? null
      : Uri.tryParse(
          endpointLine.substring(endpointLine.indexOf('=') + 1).trim(),
        );
  if (endpoint == null || endpoint.scheme != 'https' || endpoint.host.isEmpty) {
    stderr.writeln('The internal subscription endpoint is invalid.');
    exitCode = 2;
    return;
  }

  final client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 12)
    ..userAgent = 'niraN-config-verifier/0.1.0';
  final temporary = await Directory.systemTemp.createTemp('niraN-config-test-');
  try {
    final response = await (await client.getUrl(endpoint)).close();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException('Subscription returned HTTP ${response.statusCode}');
    }
    final body = await response.transform(utf8.decoder).join();
    final servers = const WindowsSubscriptionParser().parse(body);
    if (servers.isEmpty) throw const FormatException('No supported servers');
    const builder = WindowsXrayConfigBuilder();
    for (var index = 0; index < servers.length; index++) {
      final config = File('${temporary.path}\\config-$index.json');
      await config.writeAsString(
        builder.build(server: servers[index], settings: _settings),
      );
      final result = await Process.run(xray.absolute.path, [
        'run',
        '-test',
        '-c',
        config.path,
      ]);
      if (result.exitCode != 0) {
        stderr.writeln(
          'Xray rejected subscription server ${index + 1} '
          '(${servers[index].protocol}).',
        );
        exitCode = 1;
        return;
      }
    }
    stdout.writeln(
      'Xray accepted generated configs for all ${servers.length} servers.',
    );
  } finally {
    client.close(force: true);
    await temporary.delete(recursive: true);
  }
}

const _settings = <String, Object?>{
  'connectionMode': 'proxy',
  'routingMode': 'global',
  'enableLocalDns': true,
  'enableFakeDns': false,
  'remoteDns': 'https://dns.google/dns-query',
  'localSocksPort': 10808,
  'domainStrategy': 'AsIs',
  'sniffingEnabled': true,
  'routeOnly': false,
  'enableIpv6': true,
  'preferIpv6': false,
};

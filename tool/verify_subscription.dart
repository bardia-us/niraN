import 'dart:convert';
import 'dart:io';

import 'package:niran/platform/windows/windows_subscription_parser.dart';

Future<void> main() async {
  final properties = File('windows/local.properties');
  if (!properties.existsSync()) {
    stderr.writeln('windows/local.properties is missing.');
    exitCode = 2;
    return;
  }
  String endpoint = '';
  for (final line in properties.readAsLinesSync()) {
    if (!line.trimLeft().startsWith('NIRANG_SUBSCRIPTION_URL=')) continue;
    endpoint = line.substring(line.indexOf('=') + 1).trim();
    break;
  }
  final uri = Uri.tryParse(endpoint);
  if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
    stderr.writeln('The internal subscription endpoint is not valid HTTPS.');
    exitCode = 2;
    return;
  }

  final client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 12)
    ..userAgent = 'niraN-subscription-verifier/0.1.0';
  try {
    final response = await (await client.getUrl(uri)).close();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      stderr.writeln('Subscription returned HTTP ${response.statusCode}.');
      exitCode = 1;
      return;
    }
    final body = await response.transform(utf8.decoder).join();
    final servers = const WindowsSubscriptionParser().parse(body);
    if (servers.isEmpty) {
      stderr.writeln('Subscription contains no supported servers.');
      exitCode = 1;
      return;
    }
    final protocols = servers.map((server) => server.protocol).toSet().toList()
      ..sort();
    final variants = <String, int>{};
    for (final server in servers) {
      final key =
          '${server.transport.toLowerCase()}+'
          '${server.security.toLowerCase()}';
      variants[key] = (variants[key] ?? 0) + 1;
    }
    stdout.writeln(
      'Verified ${servers.length} connectable servers (${protocols.join(', ')}); '
      'variants: ${variants.entries.map((entry) => '${entry.key}=${entry.value}').join(', ')}.',
    );
  } finally {
    client.close(force: true);
  }
}

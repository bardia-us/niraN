import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:niran/platform/windows/windows_traffic.dart';

void main() {
  test(
    'isolated bundled Xray reports real proxy bytes through loopback metrics',
    () async {
      final executable = File('windows/xray/bin/xray.exe').absolute;
      expect(await executable.exists(), isTrue);
      final directory = await Directory.systemTemp.createTemp(
        'niran-loopback-counters-',
      );
      final reservations = <ServerSocket>[
        await ServerSocket.bind(InternetAddress.loopbackIPv4, 0),
        await ServerSocket.bind(InternetAddress.loopbackIPv4, 0),
      ];
      final proxyPort = reservations[0].port;
      final metricsPort = reservations[1].port;
      for (final socket in reservations) {
        await socket.close();
      }
      final origin = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final originRequests = origin.listen((request) async {
        request.response.headers.contentType = ContentType.text;
        request.response.write('local counter fixture');
        await request.response.close();
      });
      final file = File('${directory.path}/isolated.json');
      await file.writeAsString(
        jsonEncode({
          'log': {'loglevel': 'error'},
          'inbounds': [
            {
              'tag': 'http-in',
              'listen': '127.0.0.1',
              'port': proxyPort,
              'protocol': 'http',
              'settings': {},
            },
          ],
          'outbounds': [
            {'tag': 'proxy', 'protocol': 'freedom', 'settings': {}},
          ],
          'stats': {},
          'policy': {
            'system': {
              'statsOutboundUplink': true,
              'statsOutboundDownlink': true,
            },
          },
          'metrics': {
            'tag': 'niran-metrics',
            'listen': '127.0.0.1:$metricsPort',
          },
        }),
      );
      final core = await Process.start(executable.path, [
        'run',
        '-c',
        file.path,
      ]);
      final stdoutSubscription = core.stdout.listen((_) {});
      final stderrSubscription = core.stderr.listen((_) {});
      final metrics = HttpClient()..findProxy = (_) => 'DIRECT';
      final proxied = HttpClient()
        ..findProxy = (_) => 'PROXY 127.0.0.1:$proxyPort';
      try {
        TrafficCounters? before;
        for (var attempt = 0; attempt < 40; attempt++) {
          try {
            before = await queryXrayTraffic(
              metrics,
              metricsPort,
            ).timeout(const Duration(milliseconds: 200));
            break;
          } on Object {
            await Future<void>.delayed(const Duration(milliseconds: 50));
          }
        }
        expect(
          before,
          isNotNull,
          reason: 'Isolated Core did not expose the documented Metrics payload',
        );
        expect(before!.upload, 0);
        expect(before.download, 0);
        final request = await proxied.getUrl(
          Uri.parse('http://127.0.0.1:${origin.port}/fixture'),
        );
        final response = await request.close();
        expect(
          await utf8.decoder.bind(response).join(),
          'local counter fixture',
        );
        final after = await queryXrayTraffic(metrics, metricsPort);
        expect(after.upload, greaterThan(0));
        expect(after.download, greaterThanOrEqualTo(21));
        // Reading metrics directly must not count the collector's own requests.
        final again = await queryXrayTraffic(metrics, metricsPort);
        expect(again.upload, after.upload);
        expect(again.download, after.download);
      } finally {
        metrics.close(force: true);
        proxied.close(force: true);
        core.kill();
        await core.exitCode.timeout(const Duration(seconds: 3));
        await stdoutSubscription.cancel();
        await stderrSubscription.cancel();
        await originRequests.cancel();
        await origin.close(force: true);
        await directory.delete(recursive: true);
      }
    },
  );
}

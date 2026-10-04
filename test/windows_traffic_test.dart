import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:niran/core/platform/native_models.dart';
import 'package:niran/platform/windows/windows_traffic.dart';
import 'package:niran/platform/windows/windows_server_record.dart';
import 'package:niran/platform/windows/windows_xray_config_builder.dart';
import 'dart:convert';

void main() {
  test(
    'first observation after midnight preserves unknown day across restart',
    () async {
      final dir = await Directory.systemTemp.createTemp('niran-unknown-day-');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/ledger.json');
      final ledger = WindowsTrafficLedger(file: file);
      final token = ledger.beginSession('a', DateTime(2026, 10, 1, 23));
      final after = DateTime(2026, 10, 2, 0, 10);
      ledger.record(token, const TrafficCounters(100, 200), after);
      expect(ledger.snapshot('a', after).todayDownload, isNull);
      await ledger.flush();
      final restored = WindowsTrafficLedger(file: file);
      await restored.load();
      expect(restored.snapshot('a', after).todayDownload, isNull);
      expect(restored.snapshot('a', after).lifetimeDownload, 200);
    },
  );
  test('stalled loopback metrics body aborts its request', () async {
    final origin = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final requests = origin.listen((request) async {
      request.response.write('{');
      await request.response.flush();
    });
    final client = HttpClient()..findProxy = (_) => 'DIRECT';
    addTearDown(() async {
      client.close(force: true);
      await requests.cancel();
      await origin.close(force: true);
    });
    await expectLater(
      queryXrayTraffic(
        client,
        origin.port,
      ).timeout(const Duration(milliseconds: 1400)),
      throwsA(isA<TimeoutException>()),
    );
    expect(
      () => client.getUrl(Uri.parse('http://127.0.0.1:${origin.port}/')),
      throwsStateError,
    );
  });
  test(
    'cross-midnight counter outage keeps lifetime but daily attribution unknown',
    () {
      final ledger = WindowsTrafficLedger();
      final before = DateTime(2026, 10, 1, 23);
      final after = DateTime(2026, 10, 2, 0, 10);
      final token = ledger.beginSession('a', before);
      ledger.record(token, const TrafficCounters(10, 20), before);
      ledger.unavailable('counterUnavailable');
      ledger.record(token, const TrafficCounters(100, 200), after);
      final snapshot = ledger.snapshot('a', after);
      expect(snapshot.lifetimeDownload, 200);
      expect(snapshot.todayDownload, isNull);
      expect(snapshot.aggregateTodayDownload, isNull);
      expect(ledger.snapshot('a', DateTime(2026, 10, 3)).todayDownload, 0);
    },
  );
  test(
    'bundled Xray validates a runtime configuration with HTTP byte counters',
    () async {
      final dir = await Directory.systemTemp.createTemp('niran-metrics-check-');
      addTearDown(() => dir.delete(recursive: true));
      final executable = File('windows/xray/bin/xray.exe');
      expect(await executable.exists(), isTrue);
      final server = WindowsServerRecord(
        id: 'a',
        name: 'a',
        country: '',
        protocol: 'vless',
        address: 'example.invalid',
        port: 443,
        credential: '00000000-0000-4000-8000-000000000001',
        transport: 'tcp',
        security: 'tls',
        parameters: const {},
      );
      final file = File('${dir.path}/config.json');
      await file.writeAsString(
        const WindowsXrayConfigBuilder().build(
          server: server,
          settings: const {'routingMode': 'global'},
          trafficMetricsPort: 19001,
        ),
      );
      final result = await Process.run(executable.absolute.path, [
        'run',
        '-test',
        '-c',
        file.path,
      ]);
      expect(
        result.exitCode,
        0,
        reason: 'Bundled Core rejected the synthetic metrics config',
      );
    },
  );
  test(
    'Xray runtime counters bind to loopback and leave test cores uninstrumented',
    () {
      final server = WindowsServerRecord(
        id: 'a',
        name: 'a',
        country: '',
        protocol: 'vless',
        address: 'example.invalid',
        port: 443,
        credential: '00000000-0000-4000-8000-000000000001',
        transport: 'tcp',
        security: 'tls',
        parameters: const {},
      );
      const builder = WindowsXrayConfigBuilder();
      final config =
          jsonDecode(
                builder.build(
                  server: server,
                  settings: const {'routingMode': 'global'},
                  trafficMetricsPort: 19001,
                ),
              )
              as Map;
      expect(config['metrics'], {
        'tag': 'niran-metrics',
        'listen': '127.0.0.1:19001',
      });
      expect((config['policy'] as Map)['system'], {
        'statsOutboundUplink': true,
        'statsOutboundDownlink': true,
      });
      final speedtest =
          jsonDecode(
                builder.buildSpeedtest(
                  servers: [server],
                  settings: const {},
                  socksPorts: [19002],
                  httpPorts: [19003],
                ),
              )
              as Map;
      expect(speedtest.containsKey('metrics'), isFalse);
      expect(speedtest.containsKey('stats'), isFalse);
    },
  );

  test('metrics parsing excludes direct and refuses missing counters', () {
    final value = TrafficCounters.fromXrayMetrics({
      'stats': {
        'outbound': {
          'proxy': {'uplink': 12, 'downlink': 34},
          'direct': {'uplink': 90000, 'downlink': 90000},
        },
      },
    });
    expect(value.upload, 12);
    expect(value.download, 34);
    expect(
      () => TrafficCounters.fromXrayMetrics({
        'stats': {'outbound': {}},
      }),
      throwsFormatException,
    );
  });
  test('absent native traffic keeps unknown totals instead of fake zero', () {
    final traffic = TrafficUsage.fromMap(const {});
    expect(traffic.available, isFalse);
    expect(traffic.lifetimeDownload, isNull);
    expect(traffic.aggregateTodayDownload, isNull);
    expect(const AppSnapshot().traffic.todayUpload, isNull);
  });

  test(
    'counter deltas survive reset and reconnect without double counting',
    () {
      final ledger = WindowsTrafficLedger();
      final start = DateTime(2026, 10, 1, 10);
      final first = ledger.beginSession('a', start);
      ledger.record(first, const TrafficCounters(100, 500), start);
      ledger.record(
        first,
        const TrafficCounters(140, 620),
        start.add(const Duration(seconds: 2)),
      );
      var value = ledger.snapshot('a', start);
      expect(value.sessionUpload, 140);
      expect(value.lifetimeDownload, 620);
      expect(value.uploadBytesPerSecond, 20);
      ledger.record(
        first,
        const TrafficCounters(10, 30),
        start.add(const Duration(seconds: 4)),
      );
      value = ledger.snapshot('a', start);
      expect(value.lifetimeUpload, 150);
      expect(value.lifetimeDownload, 650);
      final second = ledger.beginSession(
        'a',
        start.add(const Duration(seconds: 6)),
      );
      ledger.record(first, const TrafficCounters(9000, 9000), start);
      ledger.record(
        second,
        const TrafficCounters(25, 80),
        start.add(const Duration(seconds: 7)),
      );
      value = ledger.snapshot('a', start);
      expect(value.sessionUpload, 25);
      expect(value.lifetimeUpload, 175);
      expect(value.lifetimeDownload, 730);
    },
  );

  test(
    'local day rolls while offline and different configs aggregate once',
    () {
      final ledger = WindowsTrafficLedger();
      final yesterday = DateTime(2026, 10, 1, 23, 59, 58);
      final today = DateTime(2026, 10, 2, 0, 0, 1);
      final a = ledger.beginSession('a', yesterday);
      ledger.record(a, const TrafficCounters(50, 100), yesterday);
      ledger.record(a, const TrafficCounters(60, 120), today);
      final b = ledger.beginSession('b', today);
      ledger.record(b, const TrafficCounters(7, 40), today);
      ledger.endSession();
      final value = ledger.snapshot('a', today);
      expect(value.todayUpload, 10);
      expect(value.todayDownload, 20);
      expect(value.aggregateTodayUpload, 17);
      expect(value.aggregateTodayDownload, 60);
      expect(value.lifetimeUpload, 60);
      expect(value.available, isFalse);
      expect(value.uploadBytesPerSecond, isNull);
      expect(ledger.snapshot('missing', today).lifetimeDownload, isNull);
      expect(
        ledger.snapshot('a', DateTime(2026, 10, 3)).aggregateTodayDownload,
        0,
      );
    },
  );

  test(
    'checkpoint restores only recorded totals and leaves live rates unknown',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'niran-traffic-ledger-',
      );
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/traffic.json');
      final ledger = WindowsTrafficLedger(file: file);
      final at = DateTime(2026, 10, 1);
      final token = ledger.beginSession('a', at);
      ledger.record(token, const TrafficCounters(24, 91), at);
      await ledger.flush();
      final restored = WindowsTrafficLedger(file: file);
      await restored.load();
      final value = restored.snapshot('a', at);
      expect(value.lifetimeUpload, 24);
      expect(value.todayDownload, 91);
      expect(value.available, isFalse);
      expect(value.sessionDownload, isNull);
      expect(value.downloadBytesPerSecond, isNull);
    },
  );

  test(
    'stopping samples short sessions and ignores a result from an old core',
    () async {
      final pending = Completer<TrafficCounters>();
      final ledger = WindowsTrafficLedger();
      final monitor = WindowsTrafficMonitor(ledger: ledger, onChanged: () {});
      await monitor.start('a', query: () => pending.future);
      await monitor.stop(finalSample: false);
      await monitor.start('b', query: () async => const TrafficCounters(4, 30));
      pending.complete(const TrafficCounters(1000, 2000));
      await Future<void>.delayed(Duration.zero);
      await monitor.stop();
      expect(ledger.snapshot('a', DateTime.now()).lifetimeDownload, isNull);
      expect(ledger.snapshot('b', DateTime.now()).lifetimeDownload, 30);
    },
  );
}

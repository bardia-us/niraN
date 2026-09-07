import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:niran/platform/windows/windows_real_delay.dart';
import 'package:niran/platform/windows/windows_server_record.dart';
import 'package:niran/platform/windows/windows_xray_config_builder.dart';

Future<void> main() async {
  final localAppData = Platform.environment['LOCALAPPDATA'];
  if (localAppData == null) throw StateError('LOCALAPPDATA is unavailable');
  final niranCache = File('$localAppData\\niraN\\subscription-cache.json');
  final niranState = File('$localAppData\\niraN\\state.json');
  final v2rayRoot = Directory(
    '${Platform.environment['USERPROFILE']}\\Desktop\\v2rayN-windows-64',
  );
  final database = File('${v2rayRoot.path}\\guiConfigs\\guiNDB.db');
  final v2rayConfig = File('${v2rayRoot.path}\\guiConfigs\\guiNConfig.json');
  final xray = File('build\\windows\\x64\\runner\\Debug\\xray\\xray.exe');
  for (final file in [niranCache, niranState, database, v2rayConfig, xray]) {
    if (!file.existsSync()) throw StateError('Missing required audit input');
  }

  final cache = jsonDecode(niranCache.readAsStringSync()) as Map;
  final state = jsonDecode(niranState.readAsStringSync()) as Map;
  final referenceConfig = jsonDecode(v2rayConfig.readAsStringSync()) as Map;
  final servers = (cache['servers'] as List)
      .whereType<Map>()
      .map(
        (value) => WindowsServerRecord.fromJson(
          value.map((key, value) => MapEntry('$key', value)),
        ),
      )
      .toList(growable: false);
  final query = await Process.run('sqlite3.exe', [
    '-readonly',
    '-json',
    database.path,
    'SELECT p.Address AS address,p.Port AS port,e.Delay AS delay '
        'FROM ProfileItem p JOIN ProfileExItem e ON p.IndexId=e.IndexId '
        'WHERE e.Delay>0 ORDER BY e.Delay;',
  ]);
  if (query.exitCode != 0) throw StateError('Could not read v2rayN audit data');
  final referenceRows = (jsonDecode('${query.stdout}') as List)
      .whereType<Map>()
      .toList(growable: false);
  final matches = <({WindowsServerRecord server, int reference})>[];
  for (final server in servers) {
    final match = referenceRows.cast<Map?>().firstWhere(
      (row) =>
          '${row?['address'] ?? ''}'.toLowerCase() ==
              server.address.toLowerCase() &&
          (row?['port'] as num?)?.toInt() == server.port,
      orElse: () => null,
    );
    final delay = (match?['delay'] as num?)?.toInt();
    if (delay != null && delay > 0) {
      matches.add((server: server, reference: delay));
    }
  }
  if (matches.isEmpty) {
    throw StateError('No server with a stored v2rayN Real Delay matched niraN');
  }

  final speedSettings = Map<String, Object?>.from(
    (state['settings'] as Map).map((key, value) => MapEntry('$key', value)),
  );
  final speedItem = referenceConfig['SpeedTestItem'] as Map?;
  final referenceUrl = '${speedItem?['SpeedPingTestUrl'] ?? ''}';
  final target = Uri.tryParse(referenceUrl);
  if (target == null || !const {'http', 'https'}.contains(target.scheme)) {
    throw StateError('v2rayN Real Delay URL is invalid');
  }
  speedSettings['realDelayUrl'] = referenceUrl;
  final ports = await _reservePorts(matches.length * 2);
  final socksPorts = ports.take(matches.length).toList(growable: false);
  final httpPorts = ports.skip(matches.length).toList(growable: false);
  final temporary = await Directory.systemTemp.createTemp('niraN-delay-audit-');
  final config = File('${temporary.path}\\speedtest.json');
  Process? process;
  try {
    await config.writeAsString(
      const WindowsXrayConfigBuilder().buildSpeedtest(
        servers: matches.map((item) => item.server).toList(growable: false),
        settings: speedSettings,
        socksPorts: socksPorts,
        httpPorts: httpPorts,
      ),
      flush: true,
    );
    process = await Process.start(xray.absolute.path, [
      'run',
      '-c',
      config.path,
    ], workingDirectory: xray.parent.absolute.path);
    process.stdout.drain<void>();
    process.stderr.drain<void>();
    await Future.wait(httpPorts.map(_waitForPort));
    await Future<void>.delayed(const Duration(seconds: 1));
    for (var index = 0; index < httpPorts.length; index++) {
      final curl = await Process.run('curl.exe', [
        '--silent',
        '--show-error',
        '--output',
        'NUL',
        '--proxy',
        'http://127.0.0.1:${httpPorts[index]}',
        '--connect-timeout',
        '3',
        '--max-time',
        '9',
        '--write-out',
        '%{http_code} %{time_total}',
        target.toString(),
      ]);
      stdout.writeln(
        'Server ${index + 1} curl control: exit=${curl.exitCode} '
        '${curl.stdout.toString().trim()}',
      );
    }
    final timeoutSeconds = (speedItem?['SpeedTestTimeout'] as num?)?.toInt();
    final results = await Future.wait([
      for (var index = 0; index < matches.length; index++)
        measureWindowsRealDelay(
          target: target,
          proxyPort: httpPorts[index],
          timeout: Duration(seconds: timeoutSeconds ?? 9),
          trace: (phase, elapsedMs, detail) {
            stdout.writeln(
              'Server ${index + 1} trace: $phase ${elapsedMs}ms $detail',
            );
          },
        ),
    ]);
    for (var index = 0; index < matches.length; index++) {
      final measured = results[index];
      final reference = matches[index].reference;
      stdout.writeln(
        'Server ${index + 1}: v2rayN=$reference ms, '
        'niraN=${measured > 0 ? '$measured ms' : 'Timeout'}, '
        'delta=${measured > 0 ? '${measured - reference} ms' : 'n/a'}',
      );
    }
  } finally {
    if (process != null) {
      process.kill();
      try {
        await process.exitCode.timeout(const Duration(seconds: 3));
      } on TimeoutException {
        process.kill(ProcessSignal.sigkill);
      }
    }
    if (temporary.existsSync()) temporary.deleteSync(recursive: true);
  }
}

Future<List<int>> _reservePorts(int count) async {
  final sockets = <ServerSocket>[];
  try {
    for (var index = 0; index < count; index++) {
      sockets.add(await ServerSocket.bind(InternetAddress.loopbackIPv4, 0));
    }
    return sockets.map((socket) => socket.port).toList(growable: false);
  } finally {
    await Future.wait(sockets.map((socket) => socket.close()));
  }
}

Future<void> _waitForPort(int port) async {
  final deadline = DateTime.now().add(const Duration(seconds: 8));
  while (DateTime.now().isBefore(deadline)) {
    try {
      final socket = await Socket.connect(
        InternetAddress.loopbackIPv4,
        port,
        timeout: const Duration(milliseconds: 300),
      );
      socket.destroy();
      return;
    } on Object {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }
  throw TimeoutException('Temporary Xray listener did not become ready');
}

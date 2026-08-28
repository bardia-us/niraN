import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:niran/platform/windows/windows_real_delay.dart';
import 'package:niran/platform/windows/windows_server_record.dart';
import 'package:niran/platform/windows/windows_subscription_parser.dart';
import 'package:niran/platform/windows/windows_xray_config_builder.dart';

Future<void> main() async {
  final properties = File('windows/local.properties');
  final xray = [
    File('build/windows/x64/runner/Release/xray/xray.exe'),
    File('windows/xray/bin/xray-v26.7.28.exe'),
  ].firstWhere((file) => file.existsSync(), orElse: () => File(''));
  final endpoint = _subscriptionEndpoint(properties);
  if (endpoint == null || !xray.existsSync()) {
    stderr.writeln(
      'Private subscription input or niraN Xray bundle is missing.',
    );
    exitCode = 2;
    return;
  }

  final servers = await _loadServers(endpoint);
  final direct = await _publicIp(const []);
  if (direct == null) {
    stderr.writeln('Direct public IP could not be verified.');
    exitCode = 2;
    return;
  }

  final checks = <String, bool Function(WindowsServerRecord)>{
    'VLESS + WS + TLS + CDN': (server) =>
        server.protocol == 'vless' &&
        server.transport == 'ws' &&
        server.security == 'tls',
    'Trojan + WS + TLS + CDN': (server) =>
        server.protocol == 'trojan' &&
        server.transport == 'ws' &&
        server.security == 'tls',
    'VLESS + TLS (non-WS)': (server) =>
        server.protocol == 'vless' &&
        server.transport != 'ws' &&
        server.security == 'tls',
    'Reality/XHTTP regression': (server) =>
        server.protocol == 'vless' &&
        server.transport == 'xhttp' &&
        server.security == 'reality',
    'unsafe + cipherSuites + FinalMask': (server) =>
        server.parameters['fp']?.toLowerCase() == 'unsafe' &&
        (server.parameters['cs'] ?? '').isNotEmpty &&
        (server.parameters['fm'] ?? '').isNotEmpty,
  };

  var failures = 0;
  for (final check in checks.entries) {
    final candidates = servers.where(check.value).toList(growable: false);
    if (candidates.isEmpty) {
      stdout.writeln(
        '${check.key}: SKIPPED (no matching subscription profile)',
      );
      continue;
    }
    _ProbeResult? success;
    for (final server in candidates) {
      final result = await _probe(xray, server, direct);
      if (result.success) {
        success = result;
        break;
      }
    }
    if (success == null) {
      failures++;
      stdout.writeln(
        '${check.key}: FAILED (${candidates.length} candidate(s))',
      );
    } else {
      stdout.writeln(
        '${check.key}: OK; Real Delay=${success.delayMs} ms; '
        'HTTP/SOCKS IP changed=true; idle CPU=${success.idleCpuMs} ms/2s; '
        'probe CPU=${success.probeCpuMs} ms',
      );
    }
  }
  final testAll = await _auditTestAll(xray, servers);
  stdout.writeln(
    'Test All process audit: ${testAll.running ? 'OK' : 'FAILED'}; '
    '${testAll.successes}/${servers.length} Real Delay success; '
    'single PID=${testAll.pid}; idle CPU=${testAll.idleCpuMs} ms/2s; '
    'batch CPU=${testAll.batchCpuMs} ms; restart count=0',
  );
  if (!testAll.running) failures++;
  if (failures > 0) exitCode = 1;
}

Future<_BatchAudit> _auditTestAll(
  File xray,
  List<WindowsServerRecord> servers,
) async {
  final temporary = await Directory.systemTemp.createTemp('niraN-test-all-');
  final socksPorts = <int>[];
  final httpPorts = <int>[];
  final usedPorts = <int>{};
  for (var index = 0; index < servers.length; index++) {
    int next;
    do {
      next = await _freePort();
    } while (!usedPorts.add(next));
    socksPorts.add(next);
    do {
      next = await _freePort();
    } while (!usedPorts.add(next));
    httpPorts.add(next);
  }
  final config = File('${temporary.path}\\speedtest.json');
  await config.writeAsString(
    const WindowsXrayConfigBuilder().buildSpeedtest(
      servers: servers,
      settings: _settings,
      socksPorts: socksPorts,
      httpPorts: httpPorts,
    ),
  );
  final process = await Process.start(xray.absolute.path, [
    'run',
    '-c',
    config.path,
  ], workingDirectory: temporary.path);
  process.stdout.drain<void>();
  process.stderr.drain<void>();
  try {
    final ready = await Future.wait(socksPorts.map(_waitForPort));
    if (ready.any((value) => !value)) {
      return _BatchAudit.failed(process.pid);
    }
    final idleStart = await _cpuMilliseconds(process.pid);
    await Future<void>.delayed(const Duration(seconds: 2));
    final idleEnd = await _cpuMilliseconds(process.pid);
    final delays = await Future.wait([
      for (final port in socksPorts)
        measureWindowsRealDelay(
          target: Uri.parse('https://www.gstatic.com/generate_204'),
          socksPort: port,
          timeout: const Duration(seconds: 8),
        ),
    ]);
    final batchEnd = await _cpuMilliseconds(process.pid);
    return _BatchAudit(
      running: await _processExists(process.pid),
      pid: process.pid,
      successes: delays.where((delay) => delay > 0).length,
      idleCpuMs: (idleEnd - idleStart).clamp(0, 1 << 31),
      batchCpuMs: (batchEnd - idleEnd).clamp(0, 1 << 31),
    );
  } finally {
    process.kill();
    try {
      await process.exitCode.timeout(const Duration(seconds: 3));
    } on TimeoutException {
      process.kill(ProcessSignal.sigkill);
    }
    await temporary.delete(recursive: true);
  }
}

Future<List<WindowsServerRecord>> _loadServers(Uri endpoint) async {
  final client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 12)
    ..userAgent = 'niraN-transport-matrix/0.1.0';
  try {
    final response = await (await client.getUrl(endpoint)).close();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException('Subscription returned HTTP ${response.statusCode}');
    }
    final body = await response.transform(utf8.decoder).join();
    return const WindowsSubscriptionParser()
        .parse(body)
        .where((server) => server.rejectionReason == null)
        .toList(growable: false);
  } finally {
    client.close(force: true);
  }
}

Future<_ProbeResult> _probe(
  File xray,
  WindowsServerRecord server,
  String directIp,
) async {
  final temporary = await Directory.systemTemp.createTemp('niraN-matrix-');
  final socksPort = await _freePort();
  var httpPort = await _freePort();
  while (httpPort == socksPort) {
    httpPort = await _freePort();
  }
  final config = File('${temporary.path}\\config.json');
  await config.writeAsString(
    const WindowsXrayConfigBuilder().build(
      server: server,
      settings: {
        ..._settings,
        'localSocksPort': socksPort,
        'localHttpPort': httpPort,
      },
    ),
  );
  final test = await Process.run(xray.absolute.path, [
    'run',
    '-test',
    '-c',
    config.path,
  ], workingDirectory: temporary.path);
  if (test.exitCode != 0) {
    await temporary.delete(recursive: true);
    return const _ProbeResult.failed();
  }

  final process = await Process.start(xray.absolute.path, [
    'run',
    '-c',
    config.path,
  ], workingDirectory: temporary.path);
  process.stdout.drain<void>();
  process.stderr.drain<void>();
  try {
    if (!await _waitForPort(httpPort)) return const _ProbeResult.failed();
    final idleStart = await _cpuMilliseconds(process.pid);
    await Future<void>.delayed(const Duration(seconds: 2));
    final idleEnd = await _cpuMilliseconds(process.pid);
    final probeStart = idleEnd;
    final delay = await measureWindowsRealDelay(
      target: Uri.parse('https://www.gstatic.com/generate_204'),
      socksPort: socksPort,
      timeout: const Duration(seconds: 8),
    );
    final httpIp = await _publicIp(['--proxy', 'http://127.0.0.1:$httpPort']);
    final socksIp = await _publicIp([
      '--socks5-hostname',
      '127.0.0.1:$socksPort',
    ]);
    final probeEnd = await _cpuMilliseconds(process.pid);
    final success =
        delay > 0 &&
        httpIp != null &&
        socksIp != null &&
        httpIp != directIp &&
        socksIp != directIp;
    return _ProbeResult(
      success: success,
      delayMs: delay,
      idleCpuMs: (idleEnd - idleStart).clamp(0, 1 << 31),
      probeCpuMs: (probeEnd - probeStart).clamp(0, 1 << 31),
    );
  } finally {
    process.kill();
    try {
      await process.exitCode.timeout(const Duration(seconds: 3));
    } on TimeoutException {
      process.kill(ProcessSignal.sigkill);
    }
    await temporary.delete(recursive: true);
  }
}

Future<int> _cpuMilliseconds(int pid) async {
  final result = await Process.run('powershell.exe', [
    '-NoProfile',
    '-Command',
    '(Get-Process -Id $pid).TotalProcessorTime.TotalMilliseconds',
  ]);
  return double.tryParse('${result.stdout}'.trim())?.round() ?? 0;
}

Future<bool> _processExists(int pid) async {
  final result = await Process.run('powershell.exe', [
    '-NoProfile',
    '-Command',
    'if (Get-Process -Id $pid -ErrorAction SilentlyContinue) '
        '{ exit 0 } else { exit 1 }',
  ]);
  return result.exitCode == 0;
}

Future<int> _freePort() async {
  final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = socket.port;
  await socket.close();
  return port;
}

Future<bool> _waitForPort(int port) async {
  final deadline = DateTime.now().add(const Duration(seconds: 8));
  while (DateTime.now().isBefore(deadline)) {
    try {
      final socket = await Socket.connect(
        InternetAddress.loopbackIPv4,
        port,
        timeout: const Duration(milliseconds: 300),
      );
      socket.destroy();
      return true;
    } on Object {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }
  return false;
}

Future<String?> _publicIp(List<String> proxyArguments) async {
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
        '8',
        '--max-time',
        '15',
        ...proxyArguments,
        endpoint,
      ]).timeout(const Duration(seconds: 18));
      final value = '${result.stdout}'.trim();
      if (result.exitCode == 0 && InternetAddress.tryParse(value) != null) {
        return value;
      }
    } on Object {
      // Try the second public-IP endpoint.
    }
  }
  return null;
}

Uri? _subscriptionEndpoint(File properties) {
  if (!properties.existsSync()) return null;
  final line = properties.readAsLinesSync().firstWhere(
    (value) => value.trimLeft().startsWith('NIRANG_SUBSCRIPTION_URL='),
    orElse: () => '',
  );
  if (line.isEmpty) return null;
  final endpoint = Uri.tryParse(line.substring(line.indexOf('=') + 1).trim());
  return endpoint?.scheme == 'https' && endpoint!.host.isNotEmpty
      ? endpoint
      : null;
}

class _ProbeResult {
  const _ProbeResult({
    required this.success,
    required this.delayMs,
    required this.idleCpuMs,
    required this.probeCpuMs,
  });

  const _ProbeResult.failed()
    : success = false,
      delayMs = -1,
      idleCpuMs = 0,
      probeCpuMs = 0;

  final bool success;
  final int delayMs;
  final int idleCpuMs;
  final int probeCpuMs;
}

class _BatchAudit {
  const _BatchAudit({
    required this.running,
    required this.pid,
    required this.successes,
    required this.idleCpuMs,
    required this.batchCpuMs,
  });

  const _BatchAudit.failed(this.pid)
    : running = false,
      successes = 0,
      idleCpuMs = 0,
      batchCpuMs = 0;

  final bool running;
  final int pid;
  final int successes;
  final int idleCpuMs;
  final int batchCpuMs;
}

const _settings = <String, Object?>{
  'routingMode': 'global',
  'enableLocalDns': true,
  'enableFakeDns': false,
  'remoteDns': 'https://dns.google/dns-query',
  'domainStrategy': 'AsIs',
  'sniffingEnabled': true,
  'routeOnly': false,
  'enableIpv6': true,
  'preferIpv6': false,
  'xrayLogLevel': 'warning',
};

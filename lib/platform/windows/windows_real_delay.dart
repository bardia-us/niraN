import 'dart:async';
import 'dart:io';
import 'dart:math';

typedef DelayCommandRunner =
    Future<({int exitCode, String stdout})> Function(
      List<String> arguments,
      Duration timeout,
    );

/// Measures v2rayN-style Real Delay through one dedicated local HTTP proxy.
/// Core startup and listener warm-up are intentionally handled by the caller.
Future<int> measureWindowsRealDelay({
  required Uri target,
  required int socksPort,
  required Duration timeout,
  DelayCommandRunner? commandRunner,
}) async {
  final runner = commandRunner ?? _runCurl;
  final seconds = max(1, timeout.inSeconds);
  final arguments = [
    '--silent',
    '--show-error',
    '--fail',
    '--output',
    'NUL',
    '--socks5-hostname',
    '127.0.0.1:$socksPort',
    '--connect-timeout',
    '3',
    '--max-time',
    '$seconds',
    '--write-out',
    '%{time_total}\n',
    target.toString(),
    target.toString(),
  ];
  try {
    final result = await runner(
      arguments,
      timeout + const Duration(seconds: 1),
    );
    if (result.exitCode != 0) return -1;
    final samples = result.stdout
        .split(RegExp(r'\s+'))
        .map(double.tryParse)
        .whereType<double>()
        .map((seconds) => max(1, (seconds * 1000).round()))
        .toList(growable: false);
    return samples.length == 2 ? samples.reduce(min) : -1;
  } on Object {
    return -1;
  }
}

Future<({int exitCode, String stdout})> _runCurl(
  List<String> arguments,
  Duration timeout,
) async {
  final process = await Process.start('curl.exe', arguments);
  final stdoutFuture = process.stdout.transform(systemEncoding.decoder).join();
  process.stderr.drain<void>();
  try {
    final exitCode = await process.exitCode.timeout(timeout);
    return (exitCode: exitCode, stdout: await stdoutFuture);
  } on TimeoutException {
    process.kill();
    try {
      await process.exitCode.timeout(const Duration(seconds: 1));
    } on TimeoutException {
      process.kill(ProcessSignal.sigkill);
    }
    return (exitCode: -1, stdout: '');
  }
}

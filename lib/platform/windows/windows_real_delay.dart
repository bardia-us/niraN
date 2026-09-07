import 'dart:async';
import 'dart:io';
import 'dart:math';

typedef DelayHttpProbe =
    Future<int> Function(Uri target, int proxyPort, Duration timeout);
typedef DelayTrace = void Function(String phase, int elapsedMs, String detail);

/// Measures stable proxy latency through one dedicated local Xray proxy.
/// The median of one cold and two warm header timings avoids both cold-start
/// inflation and the artificial near-zero minimum produced by reused sessions.
Future<int> measureWindowsRealDelay({
  required Uri target,
  required int proxyPort,
  required Duration timeout,
  DelayHttpProbe? probe,
  DelayTrace? trace,
}) async {
  final total = Stopwatch()..start();
  try {
    trace?.call('dns', total.elapsedMilliseconds, 'delegated_to_xray');
    trace?.call('http_start', total.elapsedMilliseconds, 'three_samples');
    final delay =
        await (probe != null
                ? probe(target, proxyPort, timeout)
                : _probeWithHttpClient(target, proxyPort, timeout, trace))
            .timeout(timeout + const Duration(milliseconds: 250));
    trace?.call(
      delay > 0 ? 'complete' : 'failed',
      total.elapsedMilliseconds,
      delay > 0 ? 'ok' : 'invalid_response',
    );
    return delay > 0 ? max(1, delay) : -1;
  } on TimeoutException {
    trace?.call('timeout', total.elapsedMilliseconds, 'deadline');
    return -1;
  } on Object catch (error) {
    final detail = error is HandshakeException
        ? 'tls_${error.message.replaceAll(RegExp(r'[^a-zA-Z0-9 _-]'), '').trim()}'
        : error.runtimeType.toString();
    trace?.call('failed', total.elapsedMilliseconds, detail);
    return -1;
  }
}

Future<int> _probeWithHttpClient(
  Uri target,
  int proxyPort,
  Duration timeout,
  DelayTrace? trace,
) async {
  final client = HttpClient()
    ..connectionTimeout = Duration(
      milliseconds: min(timeout.inMilliseconds, 3000),
    )
    ..idleTimeout = timeout
    ..findProxy = (_) => 'PROXY 127.0.0.1:$proxyPort';
  final total = Stopwatch()..start();
  final samples = <int>[];
  try {
    for (var sample = 0; sample < 3; sample++) {
      final remaining = timeout - total.elapsed;
      if (remaining <= Duration.zero) break;
      final connectionWatch = Stopwatch()..start();
      try {
        final request = await client.getUrl(target).timeout(remaining);
        connectionWatch.stop();
        trace?.call(
          'tcp_connection',
          total.elapsedMilliseconds,
          'sample_${sample + 1}_${connectionWatch.elapsedMilliseconds}ms',
        );
        request.followRedirects = true;
        final responseWatch = Stopwatch()..start();
        trace?.call(
          'proxy_request',
          total.elapsedMilliseconds,
          'sample_${sample + 1}',
        );
        final response = await request.close().timeout(remaining);
        responseWatch.stop();
        trace?.call(
          'response_headers',
          total.elapsedMilliseconds,
          'sample_${sample + 1}_status_${response.statusCode}_${responseWatch.elapsedMilliseconds}ms',
        );
        await response.drain<void>().timeout(remaining);
        trace?.call(
          'request_complete',
          total.elapsedMilliseconds,
          'sample_${sample + 1}',
        );
        if (response.statusCode >= 200 && response.statusCode < 400) {
          samples.add(max(1, responseWatch.elapsedMilliseconds));
        }
      } on Object catch (error) {
        trace?.call(
          'sample_failed',
          total.elapsedMilliseconds,
          'sample_${sample + 1}_${error.runtimeType}',
        );
      }
      if (sample < 2) {
        final pause = timeout - total.elapsed;
        if (pause > const Duration(milliseconds: 75)) {
          await Future<void>.delayed(const Duration(milliseconds: 75));
        }
      }
    }
    if (samples.isEmpty) return -1;
    samples.sort();
    return samples[samples.length ~/ 2];
  } finally {
    client.close(force: true);
  }
}

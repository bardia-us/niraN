import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../../core/platform/native_models.dart';

final class TrafficCounters {
  const TrafficCounters(this.upload, this.download);
  final int upload;
  final int download;

  /// Xray Metrics includes other outbounds; only count the selected proxy.
  factory TrafficCounters.fromXrayMetrics(Map<dynamic, dynamic> payload) {
    final stats = payload['stats'];
    final outbounds = stats is Map ? stats['outbound'] : null;
    final proxy = outbounds is Map ? outbounds['proxy'] : null;
    if (proxy is! Map ||
        proxy['uplink'] is! int ||
        proxy['downlink'] is! int ||
        (proxy['uplink'] as int) < 0 ||
        (proxy['downlink'] as int) < 0) {
      throw const FormatException('Proxy traffic counters are unavailable');
    }
    return TrafficCounters(proxy['uplink'] as int, proxy['downlink'] as int);
  }
}

/// A local ledger of measured bytes. It stores IDs and counts, never profiles.
final class WindowsTrafficLedger {
  WindowsTrafficLedger({this.file});
  final File? file;
  final Map<String, _ConfigTraffic> _configs = {};
  Future<void> _writes = Future<void>.value();
  int _generation = 0;
  String? _activeId;
  TrafficCounters _previous = const TrafficCounters(0, 0);
  DateTime? _previousAt;
  DateTime? _sessionStartedAt;
  int _sessionUpload = 0;
  int _sessionDownload = 0;
  bool _observed = false;
  bool _available = false;
  String? _reason = 'disconnected';
  double? _uploadRate;
  double? _downloadRate;

  int beginSession(String id, DateTime at) {
    _activeId = id;
    _previous = const TrafficCounters(0, 0);
    _previousAt = null;
    _sessionStartedAt = at;
    _sessionUpload = _sessionDownload = 0;
    _observed = _available = false;
    _uploadRate = _downloadRate = null;
    _reason = 'waitingForCounters';
    return ++_generation;
  }

  void record(int generation, TrafficCounters counters, DateTime at) {
    if (generation != _generation ||
        _activeId == null ||
        counters.upload < 0 ||
        counters.download < 0) {
      return;
    }
    final deltaUp = counters.upload >= _previous.upload
        ? counters.upload - _previous.upload
        : counters.upload;
    final deltaDown = counters.download >= _previous.download
        ? counters.download - _previous.download
        : counters.download;
    final seconds = _previousAt == null
        ? 0.0
        : at.difference(_previousAt!).inMicroseconds / 1000000;
    _uploadRate = seconds > 0 ? deltaUp / seconds : null;
    _downloadRate = seconds > 0 ? deltaDown / seconds : null;
    _sessionUpload += deltaUp;
    _sessionDownload += deltaDown;
    final entry = _configs.putIfAbsent(_activeId!, _ConfigTraffic.new);
    final day = _day(at);
    if (entry.day != day) {
      entry.day = day;
      entry.todayUpload = entry.todayDownload = 0;
      // Normal polls have at most a two-second boundary uncertainty. An
      // outage spanning midnight cannot be truthfully assigned to either day.
      final intervalStart = _previousAt ?? _sessionStartedAt;
      entry.dayComplete =
          intervalStart == null ||
          _day(intervalStart) == day ||
          (_previousAt != null && seconds <= 6 && _available);
    }
    _previous = counters;
    _previousAt = at;
    entry.upload += deltaUp;
    entry.download += deltaDown;
    entry.todayUpload += deltaUp;
    entry.todayDownload += deltaDown;
    _observed = _available = true;
    _reason = null;
  }

  void unavailable(String reason) {
    _available = false;
    _uploadRate = _downloadRate = null;
    _reason = reason;
  }

  void endSession() {
    ++_generation;
    unavailable('disconnected');
  }

  TrafficUsage snapshot(String? selectedId, DateTime at) {
    final day = _day(at);
    final selected = _configs[selectedId];
    final active = selectedId != null && selectedId == _activeId;
    return TrafficUsage(
      available: active && _available,
      serverId: selectedId,
      localDay: day,
      sessionUpload: active && _observed ? _sessionUpload : null,
      sessionDownload: active && _observed ? _sessionDownload : null,
      lifetimeUpload: selected?.upload,
      lifetimeDownload: selected?.download,
      todayUpload: selected == null
          ? null
          : selected.day == day
          ? selected.dayComplete
                ? selected.todayUpload
                : null
          : 0,
      todayDownload: selected == null
          ? null
          : selected.day == day
          ? selected.dayComplete
                ? selected.todayDownload
                : null
          : 0,
      aggregateTodayUpload:
          _configs.isEmpty ||
              _configs.values.any((e) => e.day == day && !e.dayComplete)
          ? null
          : _configs.values.fold<int>(
              0,
              (sum, e) => sum + (e.day == day ? e.todayUpload : 0),
            ),
      aggregateTodayDownload:
          _configs.isEmpty ||
              _configs.values.any((e) => e.day == day && !e.dayComplete)
          ? null
          : _configs.values.fold<int>(
              0,
              (sum, e) => sum + (e.day == day ? e.todayDownload : 0),
            ),
      uploadBytesPerSecond: active && _available ? _uploadRate : null,
      downloadBytesPerSecond: active && _available ? _downloadRate : null,
      unavailableReason: active ? _reason : 'disconnected',
    );
  }

  Future<void> load() async {
    final target = file;
    if (target == null) return;
    final backup = File('${target.path}.bak');
    if (!await target.exists() && await backup.exists()) {
      await backup.rename(target.path);
    }
    if (!await target.exists()) return;
    try {
      final root = jsonDecode(await target.readAsString());
      if (root is! Map || root['version'] != 1 || root['configs'] is! Map) {
        return;
      }
      for (final item in (root['configs'] as Map).entries) {
        final value = item.value;
        if (item.key is! String || value is! Map) continue;
        final values = [
          value['upload'],
          value['download'],
          value['todayUpload'],
          value['todayDownload'],
        ];
        if (values.any((v) => v is! int || v < 0) || value['day'] is! String) {
          continue;
        }
        _configs[item.key as String] = _ConfigTraffic()
          ..upload = values[0] as int
          ..download = values[1] as int
          ..todayUpload = min(values[2] as int, values[0] as int)
          ..todayDownload = min(values[3] as int, values[1] as int)
          ..day = value['day'] as String
          ..dayComplete = value['dayComplete'] != false;
      }
    } on Object {
      // A damaged ledger means unobserved totals, never substituted zero.
    }
  }

  Future<void> flush() {
    final target = file;
    if (target == null) return Future<void>.value();
    final encoded = jsonEncode({
      'version': 1,
      'configs': {
        for (final item in _configs.entries) item.key: item.value.toMap(),
      },
    });
    final request = _writes.catchError((Object _) {}).then((_) async {
      await target.parent.create(recursive: true);
      final temporary = File('${target.path}.tmp');
      final backup = File('${target.path}.bak');
      await temporary.writeAsString(encoded, flush: true);
      if (await backup.exists()) await backup.delete();
      if (await target.exists()) await target.rename(backup.path);
      try {
        await temporary.rename(target.path);
        if (await backup.exists()) await backup.delete();
      } on Object {
        if (!await target.exists() && await backup.exists()) {
          await backup.rename(target.path);
        }
        rethrow;
      }
    });
    _writes = request;
    return request;
  }

  static String _day(DateTime value) {
    final local = value.toLocal();
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
  }
}

final class _ConfigTraffic {
  int upload = 0;
  int download = 0;
  int todayUpload = 0;
  int todayDownload = 0;
  String day = '';
  bool dayComplete = true;
  Map<String, Object?> toMap() => {
    'upload': upload,
    'download': download,
    'todayUpload': todayUpload,
    'todayDownload': todayDownload,
    'day': day,
    'dayComplete': dayComplete,
  };
}

typedef TrafficCounterQuery = Future<TrafficCounters> Function();

/// Serial polling, generation isolation and one final pre-stop observation.
final class WindowsTrafficMonitor {
  WindowsTrafficMonitor({required this.ledger, required this.onChanged});
  final WindowsTrafficLedger ledger;
  final void Function() onChanged;
  Timer? _timer;
  TrafficCounterQuery? _query;
  Future<void>? _pending;
  int _generation = 0;
  int _token = 0;
  int _pollCount = 0;

  Future<void> start(
    String serverId, {
    TrafficCounterQuery? query,
    String? unavailableReason,
  }) async {
    await stop(finalSample: false);
    _token = ledger.beginSession(serverId, DateTime.now());
    _query = query;
    if (query == null) {
      ledger.unavailable(unavailableReason ?? 'unsupportedCore');
    }
    onChanged();
    if (query != null) unawaited(sample());
    // Also publishes midnight changes when a supported Core is idle.
    _timer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (_query == null) {
        onChanged();
      } else {
        unawaited(sample());
      }
    });
  }

  Future<void> sample() {
    if (_pending case final running?) return running;
    final query = _query;
    if (query == null) return Future<void>.value();
    final generation = _generation;
    final token = _token;
    late final Future<void> request;
    request =
        (() async {
          try {
            final counters = await query().timeout(const Duration(seconds: 1));
            if (generation != _generation) return;
            ledger.record(token, counters, DateTime.now());
            if (++_pollCount % 5 == 0) await ledger.flush();
          } on Object {
            if (generation != _generation) return;
            ledger.unavailable('counterUnavailable');
          }
          if (generation == _generation) onChanged();
        })().whenComplete(() {
          if (identical(_pending, request)) _pending = null;
        });
    _pending = request;
    return request;
  }

  Future<void> stop({bool finalSample = true}) async {
    _timer?.cancel();
    _timer = null;
    if (finalSample && _query != null) {
      await _pending;
      await sample();
    }
    ++_generation;
    _pending = null;
    _query = null;
    ledger.endSession();
    await ledger.flush();
    onChanged();
  }
}

/// The caller owns this client's lifecycle. No system proxy or redirects.
Future<TrafficCounters> queryXrayTraffic(HttpClient client, int port) async {
  return _readXrayTraffic(client, port).timeout(
    const Duration(milliseconds: 900),
    onTimeout: () {
      // Future.timeout alone does not cancel a response body/socket. This
      // client belongs to this sample; terminate it before the next poll.
      client.close(force: true);
      throw TimeoutException('Metrics sample timed out');
    },
  );
}

Future<TrafficCounters> _readXrayTraffic(HttpClient client, int port) async {
  final request = await client.getUrl(
    Uri.parse('http://127.0.0.1:$port/debug/vars'),
  );
  request.followRedirects = false;
  final response = await request.close();
  if (response.statusCode != HttpStatus.ok) {
    throw const HttpException('Metrics unavailable');
  }
  final bytes = <int>[];
  await for (final chunk in response) {
    if (bytes.length + chunk.length > 256 * 1024) {
      throw const FormatException('Metrics response too large');
    }
    bytes.addAll(chunk);
  }
  final root = jsonDecode(utf8.decode(bytes));
  if (root is! Map) throw const FormatException('Metrics response is invalid');
  return TrafficCounters.fromXrayMetrics(root);
}

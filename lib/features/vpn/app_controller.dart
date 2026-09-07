import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/platform/native_models.dart';
import '../../core/platform/nirang_native.dart';
import '../../core/registration/device_registration.dart';

final appControllerProvider = AsyncNotifierProvider<AppController, AppSnapshot>(
  AppController.new,
);

final performanceModeProvider = Provider<bool>(
  (ref) => ref.watch(
    appControllerProvider.select(
      (value) => value.asData?.value.settings.performanceMode ?? false,
    ),
  ),
);

class AppController extends AsyncNotifier<AppSnapshot> {
  StreamSubscription<Map<dynamic, dynamic>>? _events;
  Future<void>? _logsRefresh;
  Future<void>? _subscriptionRefresh;
  int _settingsRevision = 0;

  @override
  Future<AppSnapshot> build() async {
    _events = NirangNative.events.listen(
      _handleEvent,
      onError: (Object error, StackTrace stack) {
        _set((value) => value.copyWith(subscriptionError: _errorText(error)));
      },
    );
    ref.onDispose(() => _events?.cancel());
    return _parseBootstrap(await NirangNative.initialize());
  }

  AppSnapshot? get _current => state.asData?.value;

  void _set(AppSnapshot Function(AppSnapshot value) update) {
    final current = _current;
    if (current != null) state = AsyncData(update(current));
  }

  Future<void> refreshSubscription() async {
    final active = _subscriptionRefresh;
    if (active != null) return active;
    late final Future<void> request;
    request = _refreshSubscriptionOnce().whenComplete(() {
      if (identical(_subscriptionRefresh, request)) _subscriptionRefresh = null;
    });
    _subscriptionRefresh = request;
    return request;
  }

  Future<void> _refreshSubscriptionOnce() async {
    _set(
      (value) =>
          value.copyWith(isRefreshing: true, clearSubscriptionError: true),
    );
    try {
      final data = await NirangNative.refreshSubscription();
      _set(
        (value) => value.copyWith(
          servers: _servers(data['servers']),
          usage: SubscriptionUsage.fromMap(_map(data['usage'])),
          lastUpdated: _number(data['lastUpdated']),
          deletedServerCount: _number(data['deletedServerCount']),
        ),
      );
    } catch (error) {
      _set((value) => value.copyWith(subscriptionError: _errorText(error)));
      throw PlatformException(
        code: 'subscription_refresh',
        message:
            'Subscription update failed. Check your connection and try again.',
      );
    } finally {
      _set((value) => value.copyWith(isRefreshing: false));
    }
  }

  Future<void> selectServer(String id) async {
    final previous = _current?.servers ?? const <ServerInfo>[];
    _set(
      (value) => value.copyWith(
        servers: [
          for (final server in value.servers)
            server.copyWith(selected: server.id == id),
        ],
      ),
    );
    try {
      final servers = await NirangNative.selectServer(id);
      _set((value) => value.copyWith(servers: _servers(servers)));
    } catch (_) {
      _set((value) => value.copyWith(servers: previous));
      rethrow;
    }
  }

  Future<void> reorderServers(int oldIndex, int newIndex) async {
    final previous = _current?.servers ?? const <ServerInfo>[];
    if (oldIndex < 0 || oldIndex >= previous.length) return;
    final target = newIndex > oldIndex ? newIndex - 1 : newIndex;
    if (target < 0 || target >= previous.length || target == oldIndex) return;
    final reordered = List<ServerInfo>.of(previous);
    final item = reordered.removeAt(oldIndex);
    reordered.insert(target, item);
    _set((value) => value.copyWith(servers: List.unmodifiable(reordered)));
    try {
      final servers = await NirangNative.reorderServers(
        reordered.map((server) => server.id).toList(growable: false),
      );
      _set((value) => value.copyWith(servers: _servers(servers)));
    } catch (_) {
      _set((value) => value.copyWith(servers: previous));
      rethrow;
    }
  }

  Future<void> updateServerProfile(
    String id,
    Map<String, String> values,
  ) async {
    final servers = await NirangNative.updateServerProfile(id, values);
    _set((value) => value.copyWith(servers: _servers(servers)));
  }

  Future<String> exportServerShareLink(String id) =>
      NirangNative.exportServerShareLink(id);

  Future<void> deleteServer(String id) async {
    final data = await NirangNative.deleteServer(id);
    _set(
      (value) => value.copyWith(
        servers: _servers(data['servers']),
        deletedServerCount: _number(data['deletedServerCount']),
      ),
    );
  }

  Future<int> restoreDeletedServers() async {
    final data = await NirangNative.restoreDeletedServers();
    _set(
      (value) => value.copyWith(
        servers: _servers(data['servers']),
        deletedServerCount: _number(data['deletedServerCount']),
      ),
    );
    return _number(data['restored']);
  }

  Future<void> connect() => NirangNative.connect(_current?.selectedServer?.id);
  Future<void> disconnect() => NirangNative.disconnect();
  Future<void> restartService() => NirangNative.restartService();

  Future<void> pingServer(String id) async {
    _set((value) => value.copyWith(isPinging: true));
    try {
      await NirangNative.pingServer(id);
    } catch (_) {
      _set((value) => value.copyWith(isPinging: false));
      rethrow;
    }
  }

  Future<int> tcpPingServer(String id) => NirangNative.tcpPingServer(id);

  Future<void> pingAll() async {
    _set((value) => value.copyWith(isPinging: true));
    try {
      await NirangNative.pingAll();
    } catch (_) {
      _set((value) => value.copyWith(isPinging: false));
      rethrow;
    }
  }

  Future<void> cancelPing() async {
    await NirangNative.cancelPing();
    _set((value) => value.copyWith(isPinging: false));
  }

  Future<void> clearSystemProxy() => NirangNative.clearSystemProxy();

  Future<void> setSystemProxy() => NirangNative.setSystemProxy();

  Future<void> updateSettings(Map<String, Object?> values) async {
    final previous = _current?.settings ?? const NativeSettings();
    final revision = ++_settingsRevision;
    _set((value) => value.copyWith(settings: previous.withUpdates(values)));
    try {
      final map = await NirangNative.updateSettings(values);
      if (revision == _settingsRevision) {
        _set((value) => value.copyWith(settings: NativeSettings.fromMap(map)));
      }
    } catch (_) {
      if (revision == _settingsRevision) {
        _set((value) => value.copyWith(settings: previous));
      }
      rethrow;
    }
  }

  Future<void> resetSettings() => updateSettings(const {
    'systemProxyEnabled': true,
    'tunEnabled': false,
    'routingMode': 'bypassIran',
    'customDomains': '',
    'customIps': '',
    'enableLocalDns': true,
    'enableFakeDns': false,
    'remoteDns': 'https://dns.google/dns-query',
    'directDnsEnabled': false,
    'directDnsAddress': '178.22.122.100',
    'vpnDns': '1.1.1.1',
    'vpnInterfaceAddress': '10.10.14.1/30',
    'vpnInterfaceIpv6Address': 'fdfe:dcba:9876::1/126',
    'localSocksPort': 10808,
    'localHttpPort': 10809,
    'enableUdp': true,
    'allowLanConnections': false,
    'localListenAddress': '0.0.0.0',
    'realPingConcurrency': 16,
    'realDelayUrl': 'https://www.gstatic.com/generate_204',
    'realDelayTimeoutSeconds': 8,
    'domainStrategy': 'AsIs',
    'sniffingEnabled': true,
    'sniffingType': 'http,tls,quic',
    'routeOnly': false,
    'xrayLogLevel': 'warning',
    'fragmentEnabled': false,
    'fragmentPackets': 'tlshello',
    'fragmentLength': '100-200',
    'fragmentInterval': '10-20',
    'fragmentMaxSplit': '0',
    'domesticDns': '223.5.5.5',
    'dnsQueryStrategy': 'Auto',
    'dnsParallelQuery': false,
    'dnsServeStale': false,
    'directTargetStrategy': 'AsIs',
    'proxyTargetStrategy': 'AsIs',
    'proxyDialStrategy': 'Auto',
    'happyEyeballs': false,
    'defaultFingerprint': 'chrome',
    'defaultUserAgent': '',
    'enableIpv6': true,
    'preferIpv6': false,
    'vpnMtu': 1500,
    'autoUpdate': true,
    'updateIntervalHours': 12,
    'themeMode': 'system',
    'language': 'en',
    'performanceMode': false,
    'performanceModePrompted': false,
    'showRecentLogsOnHome': true,
    'startWithWindows': false,
    'ipCheckUrl': 'https://api.ip.sb/geoip',
  });

  Future<void> refreshLogs() {
    final running = _logsRefresh;
    if (running != null) return running;
    late final Future<void> request;
    request =
        (() async {
          try {
            final logs = await NirangNative.getLogs();
            _set((value) => value.copyWith(logs: _logs(logs)));
          } catch (_) {
            // Keep the last valid log snapshot if the activity is being recreated.
          }
        })().whenComplete(() {
          if (identical(_logsRefresh, request)) _logsRefresh = null;
        });
    _logsRefresh = request;
    return request;
  }

  Future<void> clearLogs() async {
    await NirangNative.clearLogs();
    _set((value) => value.copyWith(logs: const []));
  }

  Future<void> openTelegram() => NirangNative.openTelegram();
  Future<void> openExternalUrl(Uri url) =>
      NirangNative.openExternalUrl(url.toString());
  Future<void> exitApplication() => NirangNative.exitApplication();

  Future<void> recordTelegramDecision(String decision) async {
    await NirangNative.recordTelegramDecision(decision);
    _set((value) => value.copyWith(telegramEligible: false));
  }

  void _handleEvent(Map<dynamic, dynamic> event) {
    final type = '${event['type'] ?? ''}';
    final data = event['data'];
    switch (type) {
      case 'connectionState':
        _set(
          (value) =>
              value.copyWith(connection: ConnectionInfo.fromMap(_map(data))),
        );
      case 'servers':
        _set((value) => value.copyWith(servers: _servers(data)));
      case 'serverPing':
        final update = _map(data);
        final id = '${update['id'] ?? ''}';
        _set(
          (value) => value.copyWith(
            servers: [
              for (final server in value.servers)
                if (server.id == id)
                  server.copyWith(
                    ping: _nullableNumber(update['ping']),
                    status: '${update['status'] ?? 'idle'}',
                  )
                else
                  server,
            ],
          ),
        );
      case 'subscription':
        final update = _map(data);
        _set(
          (value) => value.copyWith(
            servers: _servers(update['servers']),
            usage: SubscriptionUsage.fromMap(_map(update['usage'])),
            lastUpdated: _number(update['lastUpdated']),
            deletedServerCount: _number(update['deletedServerCount']),
          ),
        );
      case 'settings':
        _set(
          (value) =>
              value.copyWith(settings: NativeSettings.fromMap(_map(data))),
        );
      case 'logEntry':
        try {
          final entry = LogEntry.fromMap(_map(data));
          _set(
            (value) => value.copyWith(
              logs: List.unmodifiable(
                [
                  ...value.logs,
                  entry,
                ].skip(value.logs.length >= 250 ? value.logs.length - 249 : 0),
              ),
            ),
          );
        } catch (_) {
          // Ignore malformed native log events.
        }
      case 'coreVersion':
        _set((value) => value.copyWith(coreVersion: '$data'));
      case 'subscriptionError':
        _set((value) => value.copyWith(subscriptionError: '$data'));
      case 'accessBlocked':
        final details = _map(data);
        markDeviceAccessBlocked('${details['message'] ?? ''}');
      case 'pingCompleted':
      case 'pingCancelled':
        _set((value) => value.copyWith(isPinging: false));
    }
  }

  AppSnapshot _parseBootstrap(Map<dynamic, dynamic> map) => AppSnapshot(
    servers: _servers(map['servers']),
    connection: ConnectionInfo.fromMap(_map(map['connection'])),
    usage: SubscriptionUsage.fromMap(_map(map['usage'])),
    settings: NativeSettings.fromMap(_map(map['settings'])),
    logs: _logs(map['logs'] as List<dynamic>? ?? const []),
    lastUpdated: _number(map['lastUpdated']),
    coreVersion: '${map['coreVersion'] ?? 'Unavailable'}',
    appVersion: '${map['appVersion'] ?? '0.3.2'}',
    subscriptionConfigured: map['subscriptionConfigured'] == true,
    telegramEligible: map['telegramEligible'] == true,
    subscriptionError: map['subscriptionError']?.toString(),
    deletedServerCount: _number(map['deletedServerCount']),
  );
}

Map<dynamic, dynamic> _map(dynamic value) => value is Map ? value : const {};
int _number(dynamic value) =>
    value is num ? value.toInt() : int.tryParse('$value') ?? 0;
int? _nullableNumber(dynamic value) => value == null ? null : _number(value);
List<ServerInfo> _servers(dynamic value) => value is List
    ? value.whereType<Map>().map(ServerInfo.fromMap).toList(growable: false)
    : const [];
List<LogEntry> _logs(List<dynamic> value) {
  final result = <LogEntry>[];
  for (final item in value.whereType<Map>().take(250)) {
    try {
      result.add(LogEntry.fromMap(item));
    } catch (_) {
      // A malformed native entry must not take down the entire log viewer.
    }
  }
  return List.unmodifiable(result);
}

String _errorText(Object error) => error
    .toString()
    .replaceFirst(RegExp(r'^PlatformException\([^,]+,\s*'), '')
    .split(',')
    .first;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/services.dart';

import '../../core/platform/platform_backend.dart';
import 'windows_native_host.dart';
import 'windows_real_delay.dart';
import 'windows_server_record.dart';
import 'windows_subscription_parser.dart';
import 'windows_xray_config_builder.dart';

final class WindowsPlatformBackend implements NiranPlatformBackend {
  WindowsPlatformBackend({
    WindowsNativeHostApi? host,
    Directory? dataDirectory,
    Future<void> Function(int port)? proxyReadinessProbe,
    Future<void> Function(List<int> ports)? localPortPreflight,
    bool autoStartCore = true,
  }) : _host = host ?? MethodChannelWindowsNativeHost(),
       _dataDirectory = dataDirectory ?? _defaultDataDirectory(),
       _proxyReadinessProbe = proxyReadinessProbe,
       _localPortPreflight = localPortPreflight,
       _autoStartCore = autoStartCore {
    final nativeHost = _host;
    if (nativeHost is MethodChannelWindowsNativeHost) {
      _traySubscription = nativeHost.trayActions.listen(_handleTrayAction);
    }
  }

  static const _appVersionFallback = '0.3.0';
  static const _maxSubscriptionBytes = 4 * 1024 * 1024;
  static const _publicIpTimeout = Duration(seconds: 12);
  static const _connectTimeout = Duration(seconds: 8);

  final WindowsNativeHostApi _host;
  final Directory _dataDirectory;
  final Future<void> Function(int port)? _proxyReadinessProbe;
  final Future<void> Function(List<int> ports)? _localPortPreflight;
  final bool _autoStartCore;
  final _events = StreamController<Map<dynamic, dynamic>>.broadcast(sync: true);
  final _parser = const WindowsSubscriptionParser();
  final _configBuilder = const WindowsXrayConfigBuilder();

  List<WindowsServerRecord> _servers = [];
  WindowsSubscriptionUsage _usage = const WindowsSubscriptionUsage();
  final Set<String> _hiddenIds = {};
  final Map<String, Map<String, String>> _profileOverrides = {};
  final List<Map<String, Object?>> _logs = [];
  Map<String, Object?> _settings = _defaultSettings();
  Map<String, Object?> _buildConfig = {};
  String? _selectedId;
  int _lastUpdated = 0;
  int _openCount = 0;
  int _pingGeneration = 0;
  String _coreVersion = 'Unavailable';
  String _appVersion = _appVersionFallback;
  String? _subscriptionError;
  Map<String, Object?> _connection = _disconnectedConnection();
  Timer? _monitor;
  Timer? _subscriptionTimer;
  StreamSubscription<String>? _traySubscription;
  bool _initialized = false;
  bool _transitioning = false;
  bool _expectXray = false;
  bool _pollingXray = false;

  @override
  Stream<Map<dynamic, dynamic>> get events => _events.stream;

  File get _stateFile => File('${_dataDirectory.path}\\state.json');
  File get _subscriptionFile =>
      File('${_dataDirectory.path}\\subscription-cache.json');
  File get _xrayConfigFile => File('${_dataDirectory.path}\\xray\\config.json');
  File get _speedtestConfigFile =>
      File('${_dataDirectory.path}\\xray\\speedtest.json');

  @override
  Future<Map<dynamic, dynamic>> initialize() async {
    if (_initialized) return _bootstrap();
    if (_traySubscription?.isPaused == true) _traySubscription?.resume();
    await _dataDirectory.create(recursive: true);
    final recovered = await _host.recoverSystemProxy();
    if (await _xrayConfigFile.exists()) {
      await _xrayConfigFile.delete();
    }
    await _loadState();
    await _loadSubscriptionCache();
    _buildConfig = Map<String, Object?>.from(await _host.getBuildConfig());
    _appVersion = '${_buildConfig['appVersion'] ?? _appVersionFallback}';
    _settings = {
      ..._settings,
      'telegramUrlConfigured': _telegramUrl.isNotEmpty,
      'telegramContact': '${_buildConfig['telegramContact'] ?? ''}',
    };
    _settings['connectionMode'] = 'proxy';
    _settings['enableLocalDns'] = true;
    _settings['enableFakeDns'] = false;
    await _syncSystemProxyState(emit: false);
    _coreVersion = await _host.getXrayVersion();
    _openCount++;
    if (recovered) {
      _log('warning', 'Recovered Windows proxy settings after an unclean exit');
    }
    if (_servers.isEmpty && _subscriptionUrl.isNotEmpty) {
      try {
        await _refreshSubscription(emit: false);
      } on Object catch (error) {
        _subscriptionError = _safeError(error);
        _log('warning', 'Initial subscription update failed');
      }
    }
    _ensureSelection();
    await _persistState();
    _initialized = true;
    _scheduleSubscriptionUpdates();
    final selected = _server(_selectedId ?? '');
    if (_autoStartCore && selected != null) {
      try {
        await _startConnection(selected);
      } on Object {
        // Home exposes Core startup errors and a retry action.
      }
    }
    return _bootstrap();
  }

  @override
  Future<Map<dynamic, dynamic>> refreshSubscription() =>
      _refreshSubscription(emit: true);

  Future<Map<dynamic, dynamic>> _refreshSubscription({
    required bool emit,
  }) async {
    final endpoint = Uri.tryParse(_subscriptionUrl);
    if (endpoint == null ||
        endpoint.scheme != 'https' ||
        endpoint.host.isEmpty) {
      throw PlatformException(
        code: 'subscription',
        message: 'Internal subscription endpoint is not configured',
      );
    }
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 12)
      ..userAgent = 'niraN/$_appVersion Windows';
    try {
      final request = await client
          .getUrl(endpoint)
          .timeout(const Duration(seconds: 12));
      request.headers
        ..set(HttpHeaders.acceptHeader, 'text/plain, application/json')
        ..set(HttpHeaders.cacheControlHeader, 'no-cache');
      final response = await request.close().timeout(
        const Duration(seconds: 20),
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(
          'Subscription request failed with HTTP ${response.statusCode}',
        );
      }
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in response) {
        bytes.add(chunk);
        if (bytes.length > _maxSubscriptionBytes) {
          throw const HttpException('Subscription response is too large');
        }
      }
      final parsed = _parser.parse(utf8.decode(bytes.takeBytes()));
      if (parsed.isEmpty) {
        throw const FormatException(
          'Subscription contains no supported servers',
        );
      }
      _servers = parsed.map(_applyProfileOverride).toList(growable: false);
      _usage = WindowsSubscriptionUsage.fromHeader(
        response.headers.value('subscription-userinfo'),
      );
      _lastUpdated = DateTime.now().millisecondsSinceEpoch;
      _hiddenIds.clear();
      _subscriptionError = null;
      _ensureSelection();
      await _persistSubscriptionCache();
      await _persistState();
      _log('info', 'Subscription updated');
      final data = <String, Object?>{
        'servers': _safeServers(),
        'usage': _usage.toMap(),
        'lastUpdated': _lastUpdated,
        'deletedServerCount': _deletedCount,
      };
      if (emit) _emit('subscription', data);
      return data;
    } on Object catch (error) {
      _subscriptionError = _safeError(error);
      _log('warning', 'Subscription update failed');
      if (emit) _emit('subscriptionError', _subscriptionError);
      rethrow;
    } finally {
      client.close(force: true);
    }
  }

  @override
  Future<List<dynamic>> selectServer(String id) async {
    final server = _server(id);
    if (server == null) throw _platformError('not_found', 'Server not found');
    final switching = _connection['state'] == 'connected' && _selectedId != id;
    _selectedId = id;
    final optimistic = _safeServers();
    _emit('servers', optimistic);
    _log('info', switching ? 'Server switch requested' : 'Server selected');
    await _persistState();
    if (switching) {
      await _restartWith(server, switching: true);
    } else if (_connection['state'] != 'connected') {
      await _startConnection(server);
    }
    final servers = _safeServers();
    _emit('servers', servers);
    if (switching) _log('info', 'Server switched');
    return servers;
  }

  @override
  Future<List<dynamic>> updateServerProfile(
    String id,
    Map<String, String> values,
  ) async {
    final index = _servers.indexWhere((server) => server.id == id);
    if (index < 0) throw _platformError('not_found', 'Server not found');
    final finalMask = (values['fm'] ?? '').trim();
    if (finalMask.isNotEmpty) {
      final decoded = jsonDecode(finalMask);
      if (decoded is! Map) {
        throw _platformError(
          'invalid_finalmask',
          'FinalMask must be a JSON object',
        );
      }
    }
    final override = <String, String>{
      for (final key in const ['fp', 'cs', 'fm'])
        key: (values[key] ?? '').trim(),
    };
    _profileOverrides[id] = override;
    final parameters = Map<String, String>.from(_servers[index].parameters);
    for (final key in const ['fp', 'cs', 'fm']) {
      final value = override[key];
      if (value == null) {
        parameters.remove(key);
      } else {
        parameters[key] = value;
      }
    }
    final updated = _servers[index].copyWithParameters(parameters);
    _servers = [..._servers]..[index] = updated;
    await Future.wait([_persistState(), _persistSubscriptionCache()]);
    if (_connection['state'] == 'connected' && _connection['serverId'] == id) {
      await _restartWith(updated, switching: true);
    }
    _log('info', 'TLS profile settings updated');
    final safe = _safeServers();
    _emit('servers', safe);
    return safe;
  }

  @override
  Future<String> exportServerShareLink(String id) {
    final server = _server(id);
    if (server == null) throw _platformError('not_found', 'Server not found');
    return Future.value(_parser.exportShareLink(server));
  }

  @override
  Future<Map<dynamic, dynamic>> deleteServer(String id) async {
    if (_server(id) == null) {
      throw _platformError('not_found', 'Server not found');
    }
    if (_connection['serverId'] == id &&
        _connection['state'] != 'disconnected') {
      throw _platformError('busy', 'Disconnect this server before deleting it');
    }
    _hiddenIds.add(id);
    _ensureSelection();
    await _persistState();
    final result = <String, Object?>{
      'servers': _safeServers(),
      'deletedServerCount': _deletedCount,
    };
    _emit('servers', result['servers']);
    _log('info', 'Server hidden locally');
    return result;
  }

  @override
  Future<Map<dynamic, dynamic>> restoreDeletedServers() async {
    final restored = _deletedCount;
    _hiddenIds.clear();
    _ensureSelection();
    await _persistState();
    final result = <String, Object?>{
      'servers': _safeServers(),
      'deletedServerCount': 0,
      'restored': restored,
    };
    _emit('servers', result['servers']);
    if (restored > 0) _log('info', 'Deleted servers restored');
    return result;
  }

  @override
  Future<void> connect(String? id) async {
    if (_transitioning || _connection['state'] == 'connected') {
      throw _platformError(
        'busy',
        'A connection transition is already in progress',
      );
    }
    final server = _server(id ?? _selectedId ?? '');
    if (server == null) {
      throw _platformError('no_server', 'Select a server first');
    }
    if (server.rejectionReason case final reason?) {
      throw _platformError('not_connectable', reason);
    }
    _selectedId = server.id;
    await _startConnection(server);
  }

  Future<void> _startConnection(WindowsServerRecord server) async {
    _transitioning = true;
    _setConnection('preparing', server);
    try {
      _warnUnsupportedProfileFeatures(server);
      await _assertLocalProxyPortsAvailable();
      final cidrs = await _loadIranCidrs();
      final config = _configBuilder.build(
        server: server,
        settings: _settings,
        iranCidrs: cidrs,
      );
      await _xrayConfigFile.parent.create(recursive: true);
      await _xrayConfigFile.writeAsString(config, flush: true);
      _setConnection('connecting', server);
      await _host.startXray(_xrayConfigFile.path, tunMode: _tunEnabled);
      _expectXray = true;
      await _awaitProxyPort(_localHttpPort);
      if (_systemProxyEnabled) {
        await _host.enableSystemProxy(_localHttpPort);
      }
      _setConnection('connected', server);
      _log(
        'info',
        _tunEnabled
            ? 'Connected with local proxies and Windows TUN'
            : 'Connected with local SOCKS/HTTP proxies',
      );
      _startMonitor();
      unawaited(_updatePublicIp(server));
    } on Object catch (error) {
      _expectXray = false;
      await _bestEffortCleanup();
      _setConnection('error', server, error: _safeError(error));
      _log('error', 'Connection failed: ${_safeError(error)}');
      rethrow;
    } finally {
      _transitioning = false;
    }
  }

  @override
  Future<void> disconnect() async {
    if (_transitioning) {
      throw _platformError(
        'busy',
        'A connection transition is already in progress',
      );
    }
    _transitioning = true;
    _setConnection('stopping', _activeServer);
    _expectXray = false;
    _monitor?.cancel();
    Object? failure;
    try {
      try {
        await _host.disableSystemProxy();
      } on Object catch (error) {
        failure = error;
      }
      try {
        await _host.stopXray();
      } on Object catch (error) {
        failure ??= error;
      }
      await _collectCoreLogs();
      await _syncSystemProxyState();
      if (await _xrayConfigFile.exists()) await _xrayConfigFile.delete();
      if (failure == null) {
        _connection = _disconnectedConnection();
        _emit('connectionState', _connection);
        _log('info', 'Disconnected; Core/TUN stopped and proxy restored');
      } else {
        _setConnection(
          'error',
          _activeServer,
          error: 'Disconnect cleanup failed: ${_safeError(failure)}',
        );
        throw failure;
      }
    } finally {
      _transitioning = false;
    }
  }

  @override
  Future<void> clearSystemProxy() async {
    await _host.clearSystemProxy();
    await _syncSystemProxyState(emit: false);
    await _persistState();
    _emit('settings', _settings);
    _log('info', 'Windows System Proxy was cleared');
  }

  @override
  Future<void> setSystemProxy() async {
    if (_connection['state'] != 'connected') {
      throw _platformError('not_connected', 'Connect niraN Core first');
    }
    await _awaitProxyPort(_localHttpPort);
    await _host.enableSystemProxy(_localHttpPort);
    await _syncSystemProxyState(emit: false);
    await _persistState();
    _emit('settings', _settings);
    _log('info', 'Windows System Proxy was set to niraN');
  }

  @override
  Future<void> restartService() async {
    final server = _activeServer;
    if (_connection['state'] != 'connected' || server == null) {
      throw _platformError('not_connected', 'niraN is not connected');
    }
    await _restartWith(server, switching: false);
  }

  Future<void> _restartWith(
    WindowsServerRecord server, {
    required bool switching,
  }) async {
    if (_transitioning) throw _platformError('busy', 'Connection is busy');
    _transitioning = true;
    _setConnection(switching ? 'switching' : 'restarting', server);
    try {
      await _host.stopXray();
      await _collectCoreLogs();
      _warnUnsupportedProfileFeatures(server);
      await _assertLocalProxyPortsAvailable();
      final config = _configBuilder.build(
        server: server,
        settings: _settings,
        iranCidrs: await _loadIranCidrs(),
      );
      await _xrayConfigFile.writeAsString(config, flush: true);
      await _host.startXray(_xrayConfigFile.path, tunMode: _tunEnabled);
      _expectXray = true;
      await _awaitProxyPort(_localHttpPort);
      if (_systemProxyEnabled) {
        await _host.enableSystemProxy(_localHttpPort);
      }
      _setConnection('connected', server);
      _startMonitor();
      _log('info', switching ? 'Xray switched server' : 'Xray restarted');
      unawaited(_updatePublicIp(server));
    } on Object catch (error) {
      _expectXray = false;
      await _bestEffortCleanup();
      _setConnection('error', server, error: _safeError(error));
      rethrow;
    } finally {
      _transitioning = false;
    }
  }

  void _warnUnsupportedProfileFeatures(WindowsServerRecord server) {
    if (_queryEnabled(server.parameters['allowInsecure']) ||
        _queryEnabled(server.parameters['insecure']) ||
        _queryEnabled(server.parameters['allow_insecure'])) {
      _log(
        'warning',
        'allowInsecure is preserved for share export but Xray 26.7.28 '
            'does not support it; certificate verification remains enabled',
      );
    }
  }

  @override
  Future<void> pingServer(String id) async {
    final server = _server(id);
    if (server == null) throw _platformError('not_found', 'Server not found');
    final generation = ++_pingGeneration;
    await _runRealDelayBatch([server], generation);
    if (generation == _pingGeneration) _emit('pingCompleted', true);
  }

  @override
  Future<int> tcpPingServer(String id) async {
    final server = _server(id);
    if (server == null) throw _platformError('not_found', 'Server not found');
    try {
      final addresses = await InternetAddress.lookup(
        server.address,
      ).timeout(const Duration(seconds: 5));
      if (addresses.isEmpty) return -1;
      final watch = Stopwatch()..start();
      final socket = await Socket.connect(
        addresses.first,
        server.port,
        timeout: const Duration(seconds: 5),
      );
      watch.stop();
      socket.destroy();
      return max(1, watch.elapsedMilliseconds);
    } on Object {
      return -1;
    }
  }

  @override
  Future<void> pingAll() async {
    final generation = ++_pingGeneration;
    final candidates = _visibleServers;
    final batchSize = _integerSetting('realPingConcurrency', 16);
    for (
      var offset = 0;
      offset < candidates.length && generation == _pingGeneration;
      offset += batchSize
    ) {
      await _runRealDelayBatch(
        candidates.skip(offset).take(batchSize).toList(growable: false),
        generation,
      );
    }
    if (generation == _pingGeneration) _emit('pingCompleted', true);
  }

  Future<void> _runRealDelayBatch(
    List<WindowsServerRecord> servers,
    int generation,
  ) async {
    if (servers.isEmpty) return;
    for (final server in servers) {
      server
        ..pingMs = null
        ..pingStatus = 'testing';
      _emitPing(server);
    }
    final ports = await _reserveTestPorts(servers.length * 2);
    final socksPorts = ports.take(servers.length).toList(growable: false);
    final httpPorts = ports.skip(servers.length).toList(growable: false);
    try {
      await _speedtestConfigFile.parent.create(recursive: true);
      await _speedtestConfigFile.writeAsString(
        _configBuilder.buildSpeedtest(
          servers: servers,
          settings: _settings,
          socksPorts: socksPorts,
          httpPorts: httpPorts,
        ),
        flush: true,
      );
      await _host.startSpeedtestXray(_speedtestConfigFile.path);
      await Future.wait(httpPorts.map(_awaitProxyPort));
      // Match v2rayN's Realping lifecycle: Core startup and listener readiness
      // are outside the measured request, followed by a short warm-up period.
      await Future<void>.delayed(const Duration(seconds: 1));
      await Future.wait([
        for (var index = 0; index < servers.length; index++)
          () async {
            final delay = await _measureRealDelay(socksPorts[index]);
            if (generation != _pingGeneration) return;
            servers[index]
              ..pingMs = delay > 0 ? delay : null
              ..pingStatus = delay > 0 ? 'success' : 'timeout';
            _emitPing(servers[index]);
          }(),
      ]);
    } on Object catch (error) {
      _log('warning', 'Real-delay batch failed: ${_safeError(error)}');
      if (generation == _pingGeneration) {
        for (final server in servers) {
          server
            ..pingMs = null
            ..pingStatus = 'failed';
          _emitPing(server);
        }
      }
    } finally {
      try {
        await _host.stopSpeedtestXray();
      } on Object {
        // Dedicated native job owns only niraN speed-test Xray.
      }
      if (await _speedtestConfigFile.exists()) {
        await _speedtestConfigFile.delete();
      }
    }
  }

  Future<int> _measureRealDelay(int socksPort) async {
    final target = Uri.tryParse('${_settings['realDelayUrl'] ?? ''}');
    if (target == null || !const {'http', 'https'}.contains(target.scheme)) {
      return -1;
    }
    final timeout = Duration(
      seconds: _integerSetting('realDelayTimeoutSeconds', 8),
    );
    return measureWindowsRealDelay(
      target: target,
      socksPort: socksPort,
      timeout: timeout,
    );
  }

  Future<List<int>> _reserveTestPorts(int count) async {
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

  void _emitPing(WindowsServerRecord server) => _emit('serverPing', {
    'id': server.id,
    'ping': server.pingMs,
    'status': server.pingStatus,
  });

  @override
  Future<void> cancelPing() async {
    _pingGeneration++;
    for (final server in _servers.where(
      (item) => item.pingStatus == 'testing',
    )) {
      server.pingStatus = 'idle';
      _emitPing(server);
    }
    _emit('pingCancelled', true);
  }

  @override
  Future<Map<dynamic, dynamic>> updateSettings(
    Map<String, Object?> values,
  ) async {
    final previous = Map<String, Object?>.from(_settings);
    final updated = Map<String, Object?>.from(_settings);
    const stringKeys = {
      'routingMode',
      'customDomains',
      'customIps',
      'remoteDns',
      'vpnDns',
      'vpnInterfaceAddress',
      'domainStrategy',
      'themeMode',
      'language',
      'ipCheckUrl',
      'realDelayUrl',
      'localListenAddress',
      'sniffingType',
      'xrayLogLevel',
      'fragmentPackets',
      'fragmentLength',
      'fragmentInterval',
      'domesticDns',
      'defaultFingerprint',
      'defaultUserAgent',
    };
    const booleanKeys = {
      'enableLocalDns',
      'enableFakeDns',
      'sniffingEnabled',
      'routeOnly',
      'enableIpv6',
      'preferIpv6',
      'autoUpdate',
      'performanceMode',
      'performanceModePrompted',
      'showRecentLogsOnHome',
      'systemProxyEnabled',
      'tunEnabled',
      'enableUdp',
      'allowLanConnections',
      'fragmentEnabled',
    };
    for (final entry in values.entries) {
      if (stringKeys.contains(entry.key)) {
        updated[entry.key] = '${entry.value ?? ''}'.trim();
      } else if (booleanKeys.contains(entry.key) && entry.value is bool) {
        updated[entry.key] = entry.value;
      }
    }
    updated['connectionMode'] = 'proxy';
    _validateSettingChoice(updated, 'routingMode', const {
      'global',
      'bypassIran',
      'custom',
    });
    _validateSettingChoice(updated, 'domainStrategy', const {
      'AsIs',
      'IPIfNonMatch',
      'IPOnDemand',
    });
    _validateSettingChoice(updated, 'themeMode', const {
      'system',
      'light',
      'dark',
    });
    _validateSettingChoice(updated, 'language', const {'en', 'fa'});
    _validateSettingChoice(updated, 'xrayLogLevel', const {
      'debug',
      'info',
      'warning',
      'error',
      'none',
    });
    _validateSettingChoice(updated, 'sniffingType', const {
      'http,tls',
      'http,tls,quic',
    });
    _validateSettingChoice(updated, 'defaultFingerprint', const {
      'chrome',
      'firefox',
      'safari',
      'edge',
      'random',
      'randomized',
    });
    final listenAddress = '${updated['localListenAddress'] ?? ''}'.trim();
    if (InternetAddress.tryParse(listenAddress) == null) {
      throw _platformError(
        'invalid_settings',
        'Local listen address is invalid',
      );
    }
    final fragmentPackets = '${updated['fragmentPackets'] ?? ''}'.trim();
    final fragmentLength = '${updated['fragmentLength'] ?? ''}'.trim();
    final fragmentInterval = '${updated['fragmentInterval'] ?? ''}'.trim();
    if (!RegExp(r'^(tlshello|\d+-\d+)$').hasMatch(fragmentPackets) ||
        !RegExp(r'^\d+-\d+$').hasMatch(fragmentLength) ||
        !RegExp(r'^\d+-\d+$').hasMatch(fragmentInterval)) {
      throw _platformError(
        'invalid_settings',
        'Xray fragment values are invalid',
      );
    }
    final socksPort = values['localSocksPort'];
    if (socksPort != null) {
      final port = socksPort is num ? socksPort.toInt() : -1;
      if (port < 1024 || port > 65535) {
        throw _platformError('invalid_settings', 'Local SOCKS port is invalid');
      }
      updated['localSocksPort'] = port;
    }
    final httpPort = values['localHttpPort'];
    if (httpPort != null) {
      final port = httpPort is num ? httpPort.toInt() : -1;
      if (port < 1024 || port > 65535) {
        throw _platformError('invalid_settings', 'Local HTTP port is invalid');
      }
      updated['localHttpPort'] = port;
    }
    if (updated['localSocksPort'] == updated['localHttpPort']) {
      throw _platformError(
        'invalid_settings',
        'Local SOCKS and HTTP ports must be different',
      );
    }
    final mtu = values['vpnMtu'];
    if (mtu != null) {
      final value = mtu is num ? mtu.toInt() : -1;
      if (value < 1280 || value > 9000) {
        throw _platformError('invalid_settings', 'TUN MTU is invalid');
      }
      updated['vpnMtu'] = value;
    }
    final concurrency = values['realPingConcurrency'];
    if (concurrency != null) {
      final value = concurrency is num ? concurrency.toInt() : -1;
      if (!const {4, 8, 16, 32}.contains(value)) {
        throw _platformError('invalid_settings', 'Ping concurrency is invalid');
      }
      updated['realPingConcurrency'] = value;
    }
    final delayTimeout = values['realDelayTimeoutSeconds'];
    if (delayTimeout != null) {
      final value = delayTimeout is num ? delayTimeout.toInt() : -1;
      if (value < 3 || value > 30) {
        throw _platformError(
          'invalid_settings',
          'Real-delay timeout is invalid',
        );
      }
      updated['realDelayTimeoutSeconds'] = value;
    }
    final interval = values['updateIntervalHours'];
    if (interval != null) {
      final value = interval is num ? interval.toInt() : -1;
      if (!const {6, 12, 24}.contains(value)) {
        throw _platformError('invalid_settings', 'Update interval is invalid');
      }
      updated['updateIntervalHours'] = value;
    }
    final ipCheckValue = '${updated['ipCheckUrl']}'.trim();
    final ipCheck = Uri.tryParse(ipCheckValue);
    if (ipCheckValue.isNotEmpty &&
        (ipCheck == null ||
            ipCheck.scheme != 'https' ||
            ipCheck.host.isEmpty)) {
      throw _platformError('invalid_settings', 'Public IP provider is invalid');
    }
    final delayUrl = Uri.tryParse('${updated['realDelayUrl'] ?? ''}'.trim());
    if (delayUrl == null ||
        !const {'http', 'https'}.contains(delayUrl.scheme) ||
        delayUrl.host.isEmpty) {
      throw _platformError('invalid_settings', 'Real-delay URL is invalid');
    }
    final changedNetworkSetting = values.keys.any(_restartSettingKeys.contains);
    final enablingTun = values['tunEnabled'] == true && !_tunEnabled;
    if (enablingTun && _connection['state'] == 'connected') {
      // Fail before stopping a healthy Core. This only validates privileges
      // and bundled files; native code never requests elevation itself.
      await _host.validateTunPrerequisites();
    }
    _settings = updated;
    await _persistState();
    _emit('settings', _settings);
    _logSettingChanges(previous, updated, values.keys);
    _scheduleSubscriptionUpdates();
    if (changedNetworkSetting && _connection['state'] == 'connected') {
      try {
        await restartService();
      } on Object {
        _settings = previous;
        await _persistState();
        _emit('settings', _settings);
        // Preserve the previous working connection when a restart failed
        // after Core had already been stopped.
        if (_connection['state'] != 'connected' && _activeServer != null) {
          try {
            await _startConnection(_activeServer!);
          } on Object catch (recoveryError) {
            _log(
              'error',
              'Could not restore the previous connection: '
                  '${_safeError(recoveryError)}',
            );
          }
        }
        rethrow;
      }
    }
    return _settings;
  }

  @override
  Future<List<dynamic>> getLogs() async {
    await _collectCoreLogs();
    return List<dynamic>.unmodifiable(_logs);
  }

  @override
  Future<void> clearLogs() async {
    _logs.clear();
  }

  @override
  Future<void> openTelegram() async {
    final value = Uri.tryParse(_telegramUrl);
    if (value == null ||
        !const {'https', 'tg'}.contains(value.scheme.toLowerCase())) {
      throw _platformError(
        'not_configured',
        'Telegram channel is not configured',
      );
    }
    await _host.openExternalUrl(value.toString());
  }

  @override
  Future<void> openExternalUrl(String url) async {
    final value = Uri.tryParse(url);
    if (value == null ||
        value.scheme != 'https' ||
        value.host.toLowerCase() != 'github.com' ||
        !value.path.startsWith('/bardia-us/niraN/releases/')) {
      throw _platformError(
        'invalid_url',
        'Only official niraN release links are allowed',
      );
    }
    await _host.openExternalUrl(value.toString());
  }

  @override
  Future<void> recordTelegramDecision(String decision) async {
    _settings['telegramNever'] = decision == 'never';
    _settings['telegramLastShown'] = DateTime.now().millisecondsSinceEpoch;
    await _persistState();
  }

  @override
  Future<void> recordFlutterError(String message) async {
    _log('error', 'Flutter error: ${_truncate(_sanitize(message), 1200)}');
  }

  Future<void> _updatePublicIp(WindowsServerRecord server) async {
    final endpoint = Uri.tryParse('${_settings['ipCheckUrl']}');
    if (endpoint == null) return;
    final client = HttpClient()
      ..connectionTimeout = _publicIpTimeout
      ..findProxy = (_) => 'PROXY 127.0.0.1:$_localHttpPort';
    try {
      final request = await client.getUrl(endpoint).timeout(_publicIpTimeout);
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final response = await request.close().timeout(_publicIpTimeout);
      if (response.statusCode < 200 || response.statusCode >= 300) return;
      final payload = jsonDecode(
        await utf8.decoder.bind(response).join().timeout(_publicIpTimeout),
      );
      if (payload is! Map) return;
      final ip = '${payload['ip'] ?? payload['query'] ?? ''}'.trim();
      if (ip.isEmpty || _connection['serverId'] != server.id) return;
      _connection = {
        ..._connection,
        'publicIp': ip,
        'publicCountry':
            '${payload['country'] ?? payload['country_name'] ?? payload['country_code'] ?? ''}',
        'publicCity': '${payload['city'] ?? ''}',
        'publicIpChecked': true,
      };
      _emit('connectionState', _connection);
      _log('info', 'Public IP verified through Xray');
    } on Object {
      _log('warning', 'Public IP check failed');
    } finally {
      client.close(force: true);
    }
  }

  void _startMonitor() {
    _monitor?.cancel();
    _monitor = Timer.periodic(const Duration(seconds: 1), (_) {
      unawaited(_pollXray());
    });
  }

  Future<void> _pollXray() async {
    if (_pollingXray) return;
    _pollingXray = true;
    try {
      await _collectCoreLogs();
      await _syncSystemProxyState();
      if (!_expectXray || _transitioning) return;
      final status = await _host.getXrayStatus();
      if (status['running'] == true) return;
      _expectXray = false;
      _monitor?.cancel();
      Object? proxyRestoreFailure;
      try {
        await _host.disableSystemProxy();
      } on Object catch (error) {
        proxyRestoreFailure = error;
      }
      await _syncSystemProxyState();
      final exitCode = status['exitCode'];
      final server = _activeServer;
      final restoreSuffix = proxyRestoreFailure == null
          ? ''
          : '; Windows proxy restore failed: '
                '${_safeError(proxyRestoreFailure)}';
      _setConnection(
        'error',
        server,
        error:
            'Xray exited unexpectedly'
            '${exitCode == null || exitCode == -1 ? '' : ' ($exitCode)'}$restoreSuffix',
      );
      _log(
        'error',
        proxyRestoreFailure == null
            ? 'Xray crashed; Windows proxy settings were restored'
            : 'Xray crashed; Windows proxy restoration failed',
      );
    } on Object catch (error) {
      _log('warning', 'Xray monitor failed: ${_safeError(error)}');
    } finally {
      _pollingXray = false;
    }
  }

  Future<void> _collectCoreLogs() async {
    try {
      final lines = await _host.drainXrayLogs();
      for (final raw in lines) {
        final line = _sanitize(raw.trim());
        if (line.isEmpty) continue;
        final lower = line.toLowerCase();
        _log(
          lower.contains('error') || lower.contains('failed')
              ? 'error'
              : lower.contains('warning')
              ? 'warning'
              : 'info',
          'Xray: $line',
        );
      }
    } on Object {
      // Logging is best effort and must not affect the connection.
    }
  }

  Future<void> _waitForPort(int port) async {
    final deadline = DateTime.now().add(_connectTimeout);
    Object? lastError;
    while (DateTime.now().isBefore(deadline)) {
      try {
        final socket = await Socket.connect(
          InternetAddress.loopbackIPv4,
          port,
          timeout: const Duration(milliseconds: 350),
        );
        socket.destroy();
        return;
      } on Object catch (error) {
        lastError = error;
        await Future<void>.delayed(const Duration(milliseconds: 120));
      }
    }
    throw TimeoutException('Xray HTTP proxy did not become ready: $lastError');
  }

  Future<void> _awaitProxyPort(int port) =>
      _proxyReadinessProbe?.call(port) ?? _waitForPort(port);

  Future<void> _bestEffortCleanup() async {
    _monitor?.cancel();
    try {
      await _host.disableSystemProxy();
    } on Object {
      // The native host keeps a persistent recovery marker for next launch.
    }
    await _syncSystemProxyState();
    try {
      await _host.stopXray();
    } on Object {
      // The native job object prevents an orphan process when the app exits.
    }
    await _collectCoreLogs();
    if (await _xrayConfigFile.exists()) {
      await _xrayConfigFile.delete();
    }
  }

  Future<void> _assertLocalProxyPortsAvailable() async {
    final ports = {_localSocksPort, _localHttpPort};
    if (ports.length != 2) {
      throw _platformError(
        'port_in_use',
        'Local SOCKS and HTTP ports must be different.',
      );
    }
    final injected = _localPortPreflight;
    if (injected != null) {
      await injected(ports.toList(growable: false));
      return;
    }
    final reservations = <ServerSocket>[];
    try {
      for (final port in ports) {
        reservations.add(
          await ServerSocket.bind(
            InternetAddress.loopbackIPv4,
            port,
            shared: false,
          ),
        );
      }
    } on Object {
      throw _platformError(
        'port_in_use',
        'Local proxy port is already in use. '
            'Close v2rayN or change the niraN local port.',
      );
    } finally {
      for (final socket in reservations) {
        await socket.close();
      }
    }
  }

  void _scheduleSubscriptionUpdates() {
    _subscriptionTimer?.cancel();
    if (_settings['autoUpdate'] != true || _subscriptionUrl.isEmpty) return;
    final hours = _integerSetting('updateIntervalHours', 12);
    final interval = Duration(hours: hours);
    _subscriptionTimer = Timer.periodic(interval, (_) {
      unawaited(_refreshSubscriptionQuietly());
    });
    final stale =
        _lastUpdated == 0 ||
        DateTime.now().millisecondsSinceEpoch - _lastUpdated >=
            interval.inMilliseconds;
    if (_initialized && stale) {
      unawaited(_refreshSubscriptionQuietly());
    }
  }

  Future<void> _refreshSubscriptionQuietly() async {
    try {
      await _refreshSubscription(emit: true);
    } on Object {
      // The UI receives subscriptionError while the cached list remains usable.
    }
  }

  Future<List<String>> _loadIranCidrs() async {
    if (_settings['routingMode'] != 'bypassIran') return const [];
    final values = <String>[];
    for (final asset in [
      'assets/routing/iran_ipv4.txt',
      if (_settings['enableIpv6'] == true) 'assets/routing/iran_ipv6.txt',
    ]) {
      final content = await rootBundle.loadString(asset);
      values.addAll(
        const LineSplitter()
            .convert(content)
            .map((line) => line.trim())
            .where((line) => line.isNotEmpty && !line.startsWith('#')),
      );
    }
    return values;
  }

  void _setConnection(
    String state,
    WindowsServerRecord? server, {
    String? error,
  }) {
    _connection = <String, Object?>{
      'state': state,
      'serverId': server?.id,
      'serverName': server?.name,
      'publicIp': state == 'connected' ? _connection['publicIp'] : null,
      'publicCountry': state == 'connected'
          ? _connection['publicCountry']
          : null,
      'publicCity': state == 'connected' ? _connection['publicCity'] : null,
      'publicIpChecked':
          state == 'connected' && _connection['publicIpChecked'] == true,
      'error': error,
    };
    _emit('connectionState', _connection);
  }

  Map<String, Object?> _bootstrap() => {
    'servers': _safeServers(),
    'usage': _usage.toMap(),
    'lastUpdated': _lastUpdated,
    'connection': _connection,
    'settings': _settings,
    'logs': List<Map<String, Object?>>.unmodifiable(_logs),
    'coreVersion': _coreVersion,
    'appVersion': _appVersion,
    'subscriptionConfigured': _subscriptionUrl.isNotEmpty,
    'telegramEligible': _telegramEligible,
    'subscriptionError': _subscriptionError,
    'deletedServerCount': _deletedCount,
  };

  Future<void> _loadState() async {
    if (!await _stateFile.exists()) return;
    try {
      final payload = jsonDecode(await _stateFile.readAsString());
      if (payload is! Map) return;
      _selectedId = payload['selectedId']?.toString();
      _hiddenIds
        ..clear()
        ..addAll(
          (payload['hiddenIds'] as List? ?? const []).map((id) => '$id'),
        );
      final overrides = payload['profileOverrides'];
      if (overrides is Map) {
        _profileOverrides
          ..clear()
          ..addAll(
            overrides.map(
              (id, value) => MapEntry(
                '$id',
                value is Map
                    ? value.map((key, item) => MapEntry('$key', '$item'))
                    : <String, String>{},
              ),
            ),
          );
      }
      final settings = payload['settings'];
      if (settings is Map) {
        final legacyTun =
            !settings.containsKey('tunEnabled') &&
            settings['connectionMode'] == 'vpn';
        _settings = {
          ..._settings,
          ...settings.map((key, value) => MapEntry('$key', value)),
          if (legacyTun) 'tunEnabled': true,
        };
      }
      _settings['connectionMode'] = 'proxy';
      _openCount = (payload['openCount'] as num?)?.toInt() ?? 0;
    } on Object {
      _log('warning', 'Ignored a damaged settings cache');
    }
  }

  Future<void> _loadSubscriptionCache() async {
    if (!await _subscriptionFile.exists()) return;
    try {
      final payload = jsonDecode(await _subscriptionFile.readAsString());
      if (payload is! Map) return;
      _servers = (payload['servers'] as List? ?? const [])
          .whereType<Map>()
          .map(
            (item) => WindowsServerRecord.fromJson(
              item.map((key, value) => MapEntry('$key', value)),
            ),
          )
          .toList(growable: false);
      final usage = payload['usage'];
      if (usage is Map) {
        _usage = WindowsSubscriptionUsage.fromJson(
          usage.map((key, value) => MapEntry('$key', value)),
        );
      }
      _lastUpdated = (payload['lastUpdated'] as num?)?.toInt() ?? 0;
    } on Object {
      _servers = [];
      _log('warning', 'Ignored a damaged subscription cache');
    }
  }

  Future<void> _persistState() => _writeJson(_stateFile, {
    'selectedId': _selectedId,
    'hiddenIds': _hiddenIds.toList(growable: false),
    'profileOverrides': _profileOverrides,
    'settings': _settings,
    'openCount': _openCount,
  });

  Future<void> _persistSubscriptionCache() => _writeJson(_subscriptionFile, {
    'servers': _servers.map((server) => server.toPrivateJson()).toList(),
    'usage': _usage.toJson(),
    'lastUpdated': _lastUpdated,
  });

  Future<void> _writeJson(File target, Object value) async {
    await target.parent.create(recursive: true);
    final temporary = File('${target.path}.tmp');
    await temporary.writeAsString(jsonEncode(value), flush: true);
    if (await target.exists()) await target.delete();
    await temporary.rename(target.path);
  }

  void _ensureSelection() {
    if (_selectedId == null || _server(_selectedId!) == null) {
      _selectedId = _visibleServers.firstOrNull?.id;
    }
  }

  WindowsServerRecord? _server(String id) {
    for (final server in _servers) {
      if (server.id == id && !_hiddenIds.contains(id)) return server;
    }
    return null;
  }

  WindowsServerRecord _applyProfileOverride(WindowsServerRecord server) {
    final override = _profileOverrides[server.id];
    if (override == null) return server;
    final parameters = Map<String, String>.from(server.parameters);
    for (final entry in override.entries) {
      if (entry.value.isEmpty) {
        parameters.remove(entry.key);
      } else {
        parameters[entry.key] = entry.value;
      }
    }
    return server.copyWithParameters(parameters);
  }

  WindowsServerRecord? get _activeServer {
    final id = _connection['serverId']?.toString() ?? _selectedId;
    return id == null ? null : _server(id);
  }

  List<WindowsServerRecord> get _visibleServers =>
      _servers.where((server) => !_hiddenIds.contains(server.id)).toList();

  List<Map<String, Object?>> _safeServers() => _visibleServers
      .map((server) => server.safeMetadata(_selectedId))
      .toList(growable: false);

  int get _deletedCount =>
      _servers.where((server) => _hiddenIds.contains(server.id)).length;

  String get _subscriptionUrl =>
      '${_buildConfig['subscriptionUrl'] ?? ''}'.trim();
  String get _telegramUrl => '${_buildConfig['telegramUrl'] ?? ''}'.trim();

  bool get _telegramEligible {
    if (_telegramUrl.isEmpty ||
        _settings['telegramNever'] == true ||
        _openCount < 3) {
      return false;
    }
    final last = (_settings['telegramLastShown'] as num?)?.toInt() ?? 0;
    return DateTime.now().millisecondsSinceEpoch - last >=
        const Duration(days: 7).inMilliseconds;
  }

  void _validateSettingChoice(
    Map<String, Object?> values,
    String key,
    Set<String> allowed,
  ) {
    if (!allowed.contains('${values[key]}')) {
      throw _platformError('invalid_settings', '$key value is invalid');
    }
  }

  int _integerSetting(String key, int fallback) =>
      _settings[key] is num ? (_settings[key]! as num).toInt() : fallback;

  bool get _systemProxyEnabled => _settings['systemProxyEnabled'] != false;
  bool get _tunEnabled => _settings['tunEnabled'] == true;
  int get _localSocksPort => _integerSetting(
    'localSocksPort',
    WindowsXrayConfigBuilder.defaultSocksPort,
  );
  int get _localHttpPort => _integerSetting(
    'localHttpPort',
    WindowsXrayConfigBuilder.defaultHttpPort,
  );

  void _emit(String type, Object? data) {
    if (!_events.isClosed) _events.add({'type': type, 'data': data});
  }

  void _log(String level, String message) {
    final entry = <String, Object?>{
      'time': DateTime.now().millisecondsSinceEpoch,
      'level': level,
      'message': _truncate(_sanitize(message), 1200),
    };
    _logs.add(entry);
    if (_logs.length > 250) _logs.removeRange(0, _logs.length - 250);
    _emit('logEntry', entry);
  }

  void _logSettingChanges(
    Map<String, Object?> previous,
    Map<String, Object?> updated,
    Iterable<String> requested,
  ) {
    final changed = requested
        .where((key) => previous[key] != updated[key])
        .where(
          (key) => !const {
            'customDomains',
            'customIps',
            'remoteDns',
            'domesticDns',
            'vpnDns',
            'defaultUserAgent',
            'ipCheckUrl',
            'realDelayUrl',
          }.contains(key),
        )
        .toList(growable: false);
    if (changed.isNotEmpty) {
      _log('info', 'Settings changed: ${changed.join(', ')}');
    }
    if (requested.any(_restartSettingKeys.contains) &&
        _connection['state'] == 'connected') {
      _log('info', 'Core configuration refresh queued');
    }
  }

  void _handleTrayAction(String action) {
    unawaited(() async {
      try {
        switch (action) {
          case 'setProxy':
            await setSystemProxy();
          case 'clearProxy':
            await clearSystemProxy();
          case 'toggleTun':
            await updateSettings({'tunEnabled': !_tunEnabled});
        }
      } on Object catch (error) {
        _log('error', 'Tray action failed: ${_safeError(error)}');
      }
    }());
  }

  Future<void> _syncSystemProxyState({bool emit = true}) async {
    try {
      final actual = await _host.getSystemProxyState(_localHttpPort);
      final safe = const {'niran', 'clear', 'other'}.contains(actual)
          ? actual
          : 'other';
      final changed =
          _settings['systemProxyState'] != safe ||
          _settings['systemProxyEnabled'] != (safe == 'niran');
      _settings['systemProxyState'] = safe;
      _settings['systemProxyEnabled'] = safe == 'niran';
      if (changed && emit) _emit('settings', _settings);
    } on Object catch (error) {
      _settings['systemProxyState'] = 'other';
      _settings['systemProxyEnabled'] = false;
      _log(
        'warning',
        'Could not read Windows proxy state: ${_safeError(error)}',
      );
      if (emit) _emit('settings', _settings);
    }
  }

  String _sanitize(String input) => input
      .replaceAll(RegExp(r'https?://\S+', caseSensitive: false), 'endpoint')
      .replaceAll(
        RegExp(r'(vless|vmess|trojan)://\S+', caseSensitive: false),
        'configuration',
      )
      .replaceAll(RegExp(r'[0-9a-fA-F]{8}-[0-9a-fA-F-]{27,}'), 'identifier')
      .replaceAll(
        RegExp(
          r'(["\x27]?(?:password|credential|uuid|subscription(?:url)?|id)["\x27]?\s*[:=]\s*)[^,\s}\]]+',
          caseSensitive: false,
        ),
        r'$1[redacted]',
      );

  String _safeError(Object error) {
    if (error is PlatformException && error.message != null) {
      return _truncate(_sanitize(error.message!), 240);
    }
    final value = _sanitize('$error');
    return _truncate(value, 240);
  }

  String _truncate(String value, int limit) =>
      value.length <= limit ? value : value.substring(0, limit);

  PlatformException _platformError(String code, String message) =>
      PlatformException(code: code, message: message);

  static Directory _defaultDataDirectory() {
    final root = Platform.environment['LOCALAPPDATA'];
    if (root == null || root.trim().isEmpty) {
      return Directory('${Directory.systemTemp.path}\\niraN');
    }
    return Directory('$root\\niraN');
  }

  static Map<String, Object?> _defaultSettings() => {
    'connectionMode': 'proxy',
    'systemProxyEnabled': true,
    'systemProxyState': 'other',
    'tunEnabled': false,
    'routingMode': 'bypassIran',
    'customDomains': '',
    'customIps': '',
    'enableLocalDns': true,
    'enableFakeDns': false,
    'remoteDns': 'https://dns.google/dns-query',
    'vpnDns': '1.1.1.1',
    'vpnInterfaceAddress': '10.10.14.1/30',
    'localSocksPort': WindowsXrayConfigBuilder.defaultSocksPort,
    'localHttpPort': WindowsXrayConfigBuilder.defaultHttpPort,
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
    'domesticDns': '223.5.5.5',
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
    'ipCheckUrl': 'https://api.ip.sb/geoip',
    'telegramUrlConfigured': false,
    'telegramContact': '',
  };

  static Map<String, Object?> _disconnectedConnection() => {
    'state': 'disconnected',
    'serverId': null,
    'serverName': null,
    'publicIp': null,
    'publicCountry': null,
    'publicCity': null,
    'publicIpChecked': false,
    'error': null,
  };

  static bool _queryEnabled(String? value) =>
      const {'1', 'true', 'yes', 'on'}.contains(value?.trim().toLowerCase());

  static const _restartSettingKeys = {
    'tunEnabled',
    'routingMode',
    'customDomains',
    'customIps',
    'enableLocalDns',
    'enableFakeDns',
    'remoteDns',
    'vpnDns',
    'vpnInterfaceAddress',
    'localSocksPort',
    'localHttpPort',
    'vpnMtu',
    'domainStrategy',
    'sniffingEnabled',
    'routeOnly',
    'enableIpv6',
    'preferIpv6',
    'enableUdp',
    'allowLanConnections',
    'localListenAddress',
    'sniffingType',
    'xrayLogLevel',
    'fragmentEnabled',
    'fragmentPackets',
    'fragmentLength',
    'fragmentInterval',
    'domesticDns',
    'defaultFingerprint',
    'defaultUserAgent',
  };
}

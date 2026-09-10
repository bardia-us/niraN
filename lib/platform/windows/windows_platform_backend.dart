import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/services.dart';

import '../../core/platform/platform_backend.dart';
import '../../core/registration/device_registration.dart';
import 'windows_native_host.dart';
import 'windows_auto_start.dart';
import 'windows_real_delay.dart';
import 'windows_remote_access.dart';
import 'windows_server_record.dart';
import 'windows_server_order_policy.dart';
import 'windows_sing_box_tun_config_builder.dart';
import 'windows_subscription_parser.dart';
import 'windows_xray_config_builder.dart';

final class WindowsPlatformBackend implements NiranPlatformBackend {
  WindowsPlatformBackend({
    WindowsNativeHostApi? host,
    Directory? dataDirectory,
    Future<void> Function(int port)? proxyReadinessProbe,
    Future<void> Function()? tunReadinessProbe,
    Future<void> Function(List<int> ports)? localPortPreflight,
    Future<int> Function(WindowsServerRecord server)? endpointLatencyProbe,
    Future<int> Function(int httpPort)? realDelayProbe,
    RemoteAccessController? remoteAccess,
    AutoStartController? autoStartController,
    bool autoStartCore = true,
    bool? useSingBoxTunFrontend,
  }) : _host = host ?? MethodChannelWindowsNativeHost(),
       _dataDirectory = dataDirectory ?? _defaultDataDirectory(),
       _proxyReadinessProbe = proxyReadinessProbe,
       _tunReadinessProbe = tunReadinessProbe,
       _localPortPreflight = localPortPreflight,
       _endpointLatencyProbe = endpointLatencyProbe,
       _realDelayProbe = realDelayProbe,
       _remoteAccess = remoteAccess ?? windowsRemoteAccess,
       _autoStartController =
           autoStartController ?? WindowsAutoStartController(),
       _autoStartCore = autoStartCore,
       _singBoxTunFrontendEnabled =
           useSingBoxTunFrontend ?? _defaultSingBoxTunFrontendEnabled {
    final nativeHost = _host;
    if (nativeHost is MethodChannelWindowsNativeHost) {
      _traySubscription = nativeHost.trayActions.listen(_handleTrayAction);
    }
  }

  static const _appVersionFallback = '0.3.5';
  static const _maxSubscriptionBytes = 4 * 1024 * 1024;
  static const _publicIpTimeout = Duration(seconds: 12);
  static const _connectTimeout = Duration(seconds: 8);
  static const _settingsSchemaVersion = 2;
  // Keep an internal kill switch for support builds while using the validated
  // sing-box frontend by default for Windows TUN.
  static const _defaultSingBoxTunFrontendEnabled = bool.fromEnvironment(
    'NIRAN_SINGBOX_TUN',
    defaultValue: true,
  );

  final WindowsNativeHostApi _host;
  final Directory _dataDirectory;
  final Future<void> Function(int port)? _proxyReadinessProbe;
  final Future<void> Function()? _tunReadinessProbe;
  final Future<void> Function(List<int> ports)? _localPortPreflight;
  final Future<int> Function(WindowsServerRecord server)? _endpointLatencyProbe;
  final Future<int> Function(int httpPort)? _realDelayProbe;
  final RemoteAccessController _remoteAccess;
  final AutoStartController _autoStartController;
  final bool _autoStartCore;
  final bool _singBoxTunFrontendEnabled;
  final _events = StreamController<Map<dynamic, dynamic>>.broadcast(sync: true);
  final _parser = const WindowsSubscriptionParser();
  final _configBuilder = const WindowsXrayConfigBuilder();
  final _tunConfigBuilder = const WindowsSingBoxTunConfigBuilder();
  final _orderPolicy = const WindowsServerOrderPolicy();

  List<WindowsServerRecord> _servers = [];
  WindowsSubscriptionUsage _usage = const WindowsSubscriptionUsage();
  final Set<String> _hiddenIds = {};
  final Map<String, Map<String, String>> _profileOverrides = {};
  final Map<bool, List<String>> _iranCidrsCache = {};
  List<String> _manualOrderIds = [];
  final List<Map<String, Object?>> _logs = [];
  final Map<String, int> _recentCoreLogs = {};
  Map<String, Object?> _settings = _defaultSettings();
  Map<String, Object?> _buildConfig = {};
  String? _selectedId;
  int _lastUpdated = 0;
  int _openCount = 0;
  int _pingGeneration = 0;
  Future<void>? _activePingOperation;
  String _coreVersion = 'Unavailable';
  String? _coreVersionMismatch;
  String _singBoxVersion = 'Unavailable';
  String? _singBoxVersionMismatch;
  String _appVersion = _appVersionFallback;
  String? _subscriptionError;
  Map<String, Object?> _connection = _disconnectedConnection();
  Timer? _monitor;
  Timer? _subscriptionTimer;
  StreamSubscription<String>? _traySubscription;
  bool _initialized = false;
  bool _transitioning = false;
  bool _expectXray = false;
  bool _expectTunFrontend = false;
  bool _tunFrontendMayExist = false;
  bool _pollingXray = false;
  Future<Map<dynamic, dynamic>>? _subscriptionRefresh;
  Future<void>? _startupCompletion;
  Future<void>? _coreCheck;
  HttpClient? _publicIpClient;

  @override
  Stream<Map<dynamic, dynamic>> get events => _events.stream;

  File get _stateFile => File('${_dataDirectory.path}\\state.json');
  File get _subscriptionFile =>
      File('${_dataDirectory.path}\\subscription-cache.json');
  File get _xrayConfigFile => File('${_dataDirectory.path}\\xray\\config.json');
  File get _speedtestConfigFile =>
      File('${_dataDirectory.path}\\xray\\speedtest.json');
  File get _tunConfigFile => File('${_dataDirectory.path}\\sing-box\\tun.json');
  List<String> get _protectedCorePaths {
    final executableDirectory = File(Platform.resolvedExecutable).parent.path;
    return [
      '$executableDirectory\\xray\\xray.exe',
      '$executableDirectory\\sing-box\\sing-box.exe',
    ];
  }

  @override
  Future<Map<dynamic, dynamic>> initialize() async {
    if (_initialized) return _bootstrap();
    if (_traySubscription?.isPaused == true) _traySubscription?.resume();
    await _dataDirectory.create(recursive: true);
    await Future.wait([
      _recoverAtomicFile(_stateFile),
      _recoverAtomicFile(_subscriptionFile),
    ]);
    final recoveredFuture = _host.recoverSystemProxy().catchError((
      Object error,
    ) {
      _log('warning', 'Windows proxy recovery check failed');
      return false;
    });
    await Future.wait([
      _loadState(),
      _loadSubscriptionCache(),
      (() async {
        if (await _xrayConfigFile.exists()) await _xrayConfigFile.delete();
        if (await _tunConfigFile.exists()) await _tunConfigFile.delete();
      })(),
    ]);
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
    final recovered = await recoveredFuture;
    await _syncSystemProxyState(emit: false);
    if (recovered) {
      _log('warning', 'Recovered Windows proxy settings after an unclean exit');
    }
    _openCount++;
    _ensureSelection();
    await _persistState();
    _initialized = true;
    _scheduleSubscriptionUpdates();
    _startupCompletion ??= _completeStartup();
    return _bootstrap();
  }

  Future<void> _completeStartup() async {
    try {
      await _remoteAccess.requireAllowed();
    } on Object catch (error) {
      if (await _enforceBlockedAccess(error)) return;
      _log(
        'warning',
        'Startup access check unavailable; cached access retained',
      );
    }
    try {
      await _ensureCoreCompatibility();
      if (_coreVersionMismatch != null) return;
      _ensureSelection();
      final selected = _server(_selectedId ?? '');
      if (_autoStartCore &&
          selected != null &&
          _connection['state'] == 'disconnected') {
        try {
          await _startConnection(selected);
        } on Object {
          // Home exposes Core startup errors and a retry action.
        }
      }
    } on Object catch (error) {
      _log('warning', 'Background startup task failed: ${_safeError(error)}');
    }
  }

  @override
  Future<Map<dynamic, dynamic>> refreshSubscription() {
    final active = _subscriptionRefresh;
    if (active != null) return active;
    late final Future<Map<dynamic, dynamic>> request;
    request = _refreshSubscription(emit: true).whenComplete(() {
      if (identical(_subscriptionRefresh, request)) _subscriptionRefresh = null;
    });
    _subscriptionRefresh = request;
    return request;
  }

  Future<Map<dynamic, dynamic>> _refreshSubscription({
    required bool emit,
  }) async {
    try {
      final remote = await _remoteAccess.fetchSubscription();
      if (remote.bytes.length > _maxSubscriptionBytes) {
        throw const HttpException('Subscription response is too large');
      }
      final result = _parser.parseDetailed(utf8.decode(remote.bytes));
      if (result.records.isEmpty) {
        throw const FormatException(
          'Subscription contains no supported servers',
        );
      }
      final previousServers = _servers;
      final previouslySelected = _server(_selectedId ?? '');
      final refreshed = result.records
          .map(_applyProfileOverride)
          .toList(growable: false);
      _servers = _orderPolicy.reconcile(
        preferredIds: _manualOrderIds,
        previous: previousServers,
        refreshed: refreshed,
      );
      if (_manualOrderIds.isNotEmpty) {
        _manualOrderIds = _servers.map((server) => server.id).toList();
      }
      if (previouslySelected != null &&
          !_servers.any((server) => server.id == _selectedId)) {
        final matches = _servers.where(
          (server) =>
              server.protocol.toLowerCase() ==
                  previouslySelected.protocol.toLowerCase() &&
              server.address.toLowerCase() ==
                  previouslySelected.address.toLowerCase() &&
              server.port == previouslySelected.port &&
              server.credential == previouslySelected.credential,
        );
        if (matches.length == 1) _selectedId = matches.single.id;
      }
      _usage = WindowsSubscriptionUsage.fromHeader(remote.usageHeader);
      _lastUpdated = DateTime.now().millisecondsSinceEpoch;
      _hiddenIds.clear();
      _subscriptionError = null;
      _ensureSelection();
      await _persistSubscriptionCache();
      await _persistState();
      _log(
        'info',
        'Subscription replaced authoritatively: ${_servers.length} supported, '
            '${result.failedEntries} malformed, ${result.unsupportedEntries} unsupported',
      );
      final data = <String, Object?>{
        'servers': _safeServers(),
        'usage': _usage.toMap(),
        'lastUpdated': _lastUpdated,
        'deletedServerCount': _deletedCount,
      };
      if (emit) _emit('subscription', data);
      return data;
    } on Object catch (error) {
      await _enforceBlockedAccess(error);
      _subscriptionError = _safeError(error);
      _log('warning', 'Subscription update failed');
      if (emit) _emit('subscriptionError', _subscriptionError);
      rethrow;
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
  Future<List<dynamic>> reorderServers(List<String> ids) async {
    final visible = _visibleServers;
    final visibleIds = visible.map((server) => server.id).toSet();
    if (ids.length != visible.length ||
        ids.toSet().length != ids.length ||
        !ids.toSet().containsAll(visibleIds)) {
      throw _platformError('invalid_order', 'Server order is invalid');
    }
    final byId = {for (final server in _servers) server.id: server};
    final hidden = _servers.where((server) => _hiddenIds.contains(server.id));
    _servers = [for (final id in ids) byId[id]!, ...hidden];
    _manualOrderIds = List<String>.of(ids);
    await Future.wait([_persistState(), _persistSubscriptionCache()]);
    final safe = _safeServers();
    _emit('servers', safe);
    return safe;
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
    final timing = Stopwatch()..start();
    _transitioning = true;
    _setConnection('preparing', server);
    try {
      _setConnection('connecting', server);
      await _startCorePipeline(server, timing);
      _setConnection('connected', server);
      _log('info', 'Connection timing: ready ${timing.elapsedMilliseconds}ms');
      _log(
        'info',
        _usesSingBoxTun
            ? 'Connected: sing-box TUN -> local Xray SOCKS -> server'
            : _tunEnabled
            ? 'Connected with native Xray TUN'
            : 'Connected with local SOCKS/HTTP proxies',
      );
      _startMonitor();
      unawaited(_updatePublicIp(server));
      if (_proxyReadinessProbe == null) {
        unawaited(_pingConnectedServer(server));
      }
    } on Object catch (error) {
      _expectXray = false;
      await _bestEffortCleanup();
      if (await _enforceBlockedAccess(error, cleanup: false)) rethrow;
      _setConnection('error', server, error: _connectionUserError(error));
      _log('error', 'Connection failed: ${_safeError(error)}');
      rethrow;
    } finally {
      _transitioning = false;
    }
  }

  bool get _usesSingBoxTun => _tunEnabled && _singBoxTunFrontendEnabled;

  Future<void> _startCorePipeline(
    WindowsServerRecord server,
    Stopwatch timing,
  ) async {
    await _ensureCoreCompatibility();
    if (_coreVersionMismatch case final mismatch?) {
      throw _platformError('core_version_mismatch', mismatch);
    }
    if (_singBoxVersionMismatch case final mismatch?) {
      throw _platformError('core_version_mismatch', mismatch);
    }
    if (_tunEnabled) {
      if (_usesSingBoxTun) {
        await _host.validateTunFrontendPrerequisites();
      } else {
        await _host.validateTunPrerequisites();
      }
      await _stopSpeedtestForTunTransition();
    }
    _warnUnsupportedProfileFeatures(server);
    await _assertLocalProxyPortsAvailable();
    final cidrs = await _loadIranCidrs();
    final xraySettings = _usesSingBoxTun
        ? {
            ..._settings,
            'tunEnabled': false,
            'routingMode': 'global',
            // sing-box exclusively owns TUN DNS interception and routing.
            // Keeping Xray's port-53 dns-out rule here creates a DNS loop when
            // sing-box sends its bootstrap query through the local SOCKS port.
            'enableLocalDns': false,
            'enableFakeDns': false,
            'directDnsEnabled': false,
          }
        : _settings;
    final config = _configBuilder.build(
      server: server,
      settings: xraySettings,
      iranCidrs: cidrs,
    );
    await _xrayConfigFile.parent.create(recursive: true);
    await _xrayConfigFile.writeAsString(config, flush: true);
    if (_usesSingBoxTun) {
      final tunConfig = _tunConfigBuilder.build(
        settings: _settings,
        xraySocksPort: _localSocksPort,
        iranCidrs: cidrs,
        protectedProcessPaths: _protectedCorePaths,
        proxyServerHost: server.address,
      );
      await _tunConfigFile.parent.create(recursive: true);
      await _tunConfigFile.writeAsString(tunConfig, flush: true);
    }

    _log('info', 'Connection timing: Xray startup requested');
    await _host.startXray(
      _xrayConfigFile.path,
      tunMode: _tunEnabled && !_usesSingBoxTun,
    );
    _expectXray = true;
    _log(
      'info',
      'Connection timing: Xray started ${timing.elapsedMilliseconds}ms',
    );
    final proxyWait = Stopwatch()..start();
    if (_usesSingBoxTun) {
      await Future.wait([
        _awaitProxyPort(_localSocksPort),
        _awaitProxyPort(_localHttpPort),
      ]);
    } else {
      await _awaitProxyPort(_localHttpPort);
    }
    _log(
      'info',
      'Connection timing: proxy ready ${proxyWait.elapsedMilliseconds}ms '
          '(total ${timing.elapsedMilliseconds}ms)',
    );
    await _deleteRuntimeConfig(_xrayConfigFile);
    if (_usesSingBoxTun) {
      final tunWait = Stopwatch()..start();
      _log('info', 'Connection timing: sing-box TUN startup requested');
      _tunFrontendMayExist = true;
      await _host.startTunFrontend(_tunConfigFile.path);
      _expectTunFrontend = true;
      await _awaitTunReady();
      _log(
        'info',
        'Connection timing: TUN ready ${tunWait.elapsedMilliseconds}ms '
            '(total ${timing.elapsedMilliseconds}ms)',
      );
      await _deleteRuntimeConfig(_tunConfigFile);
    }
    if (_systemProxyEnabled) {
      await _host.enableSystemProxy(_localHttpPort);
    }
  }

  Future<void> _deleteRuntimeConfig(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } on Object {
      _log('warning', 'Could not remove a temporary Core configuration');
    }
  }

  String _normalizedVersion(String value) =>
      value.trim().toLowerCase().replaceFirst(RegExp(r'^v'), '');

  Future<void> _ensureCoreCompatibility() =>
      _coreCheck ??= _checkCoreCompatibility();

  Future<void> _checkCoreCompatibility() async {
    _coreVersion = await _host.getXrayVersion();
    _emit('coreVersion', _coreVersion);
    final expected = '${_buildConfig['expectedCoreVersion'] ?? ''}'.trim();
    if (expected.isNotEmpty &&
        _normalizedVersion(_coreVersion) != _normalizedVersion(expected)) {
      _coreVersionMismatch =
          'Bundled Xray Core $_coreVersion does not match expected $expected';
      _log('error', _coreVersionMismatch!);
      return;
    }
    _coreVersionMismatch = null;
    if (_singBoxTunFrontendEnabled) {
      _singBoxVersion = await _host.getSingBoxVersion();
      final expectedSingBox = '${_buildConfig['expectedSingBoxVersion'] ?? ''}'
          .trim();
      if (expectedSingBox.isNotEmpty &&
          _normalizedVersion(_singBoxVersion) !=
              _normalizedVersion(expectedSingBox)) {
        _singBoxVersionMismatch =
            'Bundled sing-box $_singBoxVersion does not match expected '
            '$expectedSingBox';
        _log('error', _singBoxVersionMismatch!);
        return;
      }
      _singBoxVersionMismatch = null;
    }
    _log(
      'info',
      _singBoxTunFrontendEnabled
          ? 'Runtime Cores verified: Xray $_coreVersion, '
                'sing-box $_singBoxVersion'
          : 'Runtime Core verified: Xray $_coreVersion; staged sing-box TUN '
                'frontend is disabled',
    );
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
    _expectTunFrontend = false;
    _monitor?.cancel();
    _publicIpClient?.close(force: true);
    _publicIpClient = null;
    _pingGeneration++;
    _resetTestingPings();
    try {
      await _stopCorePipeline();
      _connection = _disconnectedConnection();
      _emit('connectionState', _connection);
      _log('info', 'Disconnected; Core/TUN stopped and proxy restored');
    } on Object catch (error) {
      _setConnection(
        'error',
        _activeServer,
        error: 'Disconnect cleanup failed: ${_safeError(error)}',
      );
      rethrow;
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
      _publicIpClient?.close(force: true);
      _publicIpClient = null;
      _expectXray = false;
      _expectTunFrontend = false;
      _monitor?.cancel();
      _pingGeneration++;
      _resetTestingPings();
      await _stopCorePipeline(preserveSystemProxyPreference: true);
      final timing = Stopwatch()..start();
      await _startCorePipeline(server, timing);
      _setConnection('connected', server);
      _startMonitor();
      _log(
        'info',
        switching ? 'Connection switched server' : 'Connection restarted',
      );
      unawaited(_updatePublicIp(server));
      if (_proxyReadinessProbe == null) {
        unawaited(_pingConnectedServer(server));
      }
    } on Object catch (error) {
      _expectXray = false;
      await _bestEffortCleanup();
      if (await _enforceBlockedAccess(error, cleanup: false)) rethrow;
      _setConnection('error', server, error: _connectionUserError(error));
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
  Future<void> pingServer(String id) =>
      _runExclusivePing(() => _pingServerOnce(id));

  Future<void> _pingServerOnce(String id) async {
    final server = _server(id);
    if (server == null) throw _platformError('not_found', 'Server not found');
    final generation = ++_pingGeneration;
    if (_tunEnabled && _connection['state'] == 'connected') {
      await _runTunSafeLatencyBatch([server], generation);
    } else {
      await _runRealDelayBatch([server], generation);
    }
    if (generation == _pingGeneration) _emit('pingCompleted', true);
  }

  @override
  Future<int> tcpPingServer(String id) async {
    final server = _server(id);
    if (server == null) throw _platformError('not_found', 'Server not found');
    final injected = _endpointLatencyProbe;
    if (injected != null) {
      try {
        return await injected(
          server,
        ).timeout(const Duration(seconds: 5), onTimeout: () => -1);
      } on Object {
        return -1;
      }
    }
    return (() async {
      try {
        final addresses = await InternetAddress.lookup(
          server.address,
        ).timeout(const Duration(seconds: 3));
        if (addresses.isEmpty) return -1;
        final watch = Stopwatch()..start();
        final socket = await Socket.connect(
          addresses.first,
          server.port,
          timeout: const Duration(seconds: 4),
        );
        watch.stop();
        socket.destroy();
        return max(1, watch.elapsedMilliseconds);
      } on Object {
        return -1;
      }
    }()).timeout(const Duration(seconds: 5), onTimeout: () => -1);
  }

  @override
  Future<void> pingAll() => _runExclusivePing(_pingAllOnce);

  Future<void> _pingAllOnce() async {
    final generation = ++_pingGeneration;
    final candidates = _visibleServers;
    final batchSize = _integerSetting('realPingConcurrency', 16);
    if (_tunEnabled && _connection['state'] == 'connected') {
      for (
        var offset = 0;
        offset < candidates.length && generation == _pingGeneration;
        offset += batchSize
      ) {
        await _runTunSafeLatencyBatch(
          candidates.skip(offset).take(batchSize).toList(growable: false),
          generation,
        );
      }
      if (generation == _pingGeneration) _emit('pingCompleted', true);
      return;
    }
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

  Future<void> _runTunSafeLatencyBatch(
    List<WindowsServerRecord> servers,
    int generation,
  ) async {
    for (final server in servers) {
      server
        ..pingMs = null
        ..pingStatus = 'testing';
      _emitPing(server);
    }
    await Future.wait([
      for (final server in servers)
        () async {
          final activeId = _connection['serverId']?.toString();
          final delay = server.id == activeId
              ? await _measureRealDelay(_localHttpPort, trace: true)
              : await tcpPingServer(server.id);
          if (generation != _pingGeneration) return;
          server
            ..pingMs = delay > 0 ? delay : null
            ..pingStatus = delay > 0 ? 'success' : 'timeout';
          _emitPing(server);
        }().timeout(
          _realDelayOperationTimeout,
          onTimeout: () {
            if (generation != _pingGeneration) return;
            server
              ..pingMs = null
              ..pingStatus = 'timeout';
            _emitPing(server);
          },
        ),
    ]);
  }

  Future<void> _runRealDelayBatch(
    List<WindowsServerRecord> servers,
    int generation,
  ) async {
    if (servers.isEmpty) return;
    var acceptResults = true;
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
      await (() async {
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
        final coreTiming = Stopwatch()..start();
        await _host.startSpeedtestXray(_speedtestConfigFile.path);
        _log(
          'info',
          'Latency timing: test Core started ${coreTiming.elapsedMilliseconds}ms',
        );
        await Future.wait(
          httpPorts.map(_awaitProxyPort),
        ).timeout(const Duration(seconds: 4));
        _log(
          'info',
          'Latency timing: proxies ready ${coreTiming.elapsedMilliseconds}ms',
        );
        // Match v2rayN's Realping lifecycle: Core startup and listener readiness
        // are outside the measured request, followed by a very short warm-up.
        await Future<void>.delayed(const Duration(milliseconds: 180));
        await Future.wait([
          for (var index = 0; index < servers.length; index++)
            () async {
              final delay = await _measureRealDelay(httpPorts[index]);
              if (!acceptResults || generation != _pingGeneration) return;
              servers[index]
                ..pingMs = delay > 0 ? delay : null
                ..pingStatus = delay > 0 ? 'success' : 'timeout';
              _emitPing(servers[index]);
            }(),
        ]);
      }()).timeout(_realDelayOperationTimeout);
    } on TimeoutException {
      acceptResults = false;
      if (generation == _pingGeneration) {
        for (final server in servers.where(
          (item) => item.pingStatus == 'testing',
        )) {
          server
            ..pingMs = null
            ..pingStatus = 'timeout';
          _emitPing(server);
        }
      }
    } on Object catch (error) {
      acceptResults = false;
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
        await _host.stopSpeedtestXray().timeout(const Duration(seconds: 1));
      } on Object {
        // Dedicated native job owns only niraN speed-test Xray.
      }
      if (await _speedtestConfigFile.exists()) {
        await _speedtestConfigFile.delete();
      }
    }
  }

  Future<int> _measureRealDelay(int httpPort, {bool trace = false}) async {
    final injected = _realDelayProbe;
    if (injected != null) return injected(httpPort);
    final target = Uri.tryParse('${_settings['realDelayUrl'] ?? ''}');
    if (target == null || !const {'http', 'https'}.contains(target.scheme)) {
      return -1;
    }
    final configured = _integerSetting('realDelayTimeoutSeconds', 8);
    final timeout = Duration(seconds: configured.clamp(3, 15));
    return measureWindowsRealDelay(
      target: target,
      proxyPort: httpPort,
      timeout: timeout,
      trace: trace
          ? (phase, elapsedMs, detail) {
              _log('info', 'Latency timing: $phase ${elapsedMs}ms $detail');
            }
          : null,
    );
  }

  Duration get _realDelayOperationTimeout {
    final configured = _integerSetting('realDelayTimeoutSeconds', 8);
    // Listener startup is measured separately and gets a small bounded grace
    // period instead of racing the HTTP probe's own deadline.
    return Duration(seconds: configured.clamp(3, 15) + 2);
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
    unawaited(_host.stopSpeedtestXray());
    _resetTestingPings();
    _emit('pingCancelled', true);
  }

  Future<void> _stopSpeedtestForTunTransition() async {
    _pingGeneration++;
    _resetTestingPings();
    try {
      await _host.stopSpeedtestXray().timeout(const Duration(seconds: 1));
    } on Object {
      // Native ownership prevents an orphan speed-test process.
    }
  }

  void _resetTestingPings() {
    for (final server in _servers.where(
      (item) => item.pingStatus == 'testing',
    )) {
      server.pingStatus = 'idle';
      _emitPing(server);
    }
  }

  Future<void> _pingConnectedServer(WindowsServerRecord server) async {
    await _runExclusivePing(() => _pingConnectedServerOnce(server));
  }

  Future<void> _pingConnectedServerOnce(WindowsServerRecord server) async {
    if (_servers.any((item) => item.pingStatus == 'testing')) return;
    final generation = ++_pingGeneration;
    server
      ..pingMs = null
      ..pingStatus = 'testing';
    _emitPing(server);
    try {
      final delay = await _measureRealDelay(_localHttpPort, trace: true);
      if (generation != _pingGeneration) return;
      server
        ..pingMs = delay > 0 ? delay : null
        ..pingStatus = delay > 0 ? 'success' : 'timeout';
      _emitPing(server);
    } on Object {
      if (generation != _pingGeneration) return;
      server
        ..pingMs = null
        ..pingStatus = 'timeout';
      _emitPing(server);
    }
  }

  Future<void> _runExclusivePing(Future<void> Function() operation) {
    final active = _activePingOperation;
    if (active != null) {
      _log('debug', 'Ignored a duplicate latency request');
      return active;
    }
    late final Future<void> request;
    request = Future<void>.sync(operation).whenComplete(() {
      if (identical(_activePingOperation, request)) {
        _activePingOperation = null;
      }
    });
    _activePingOperation = request;
    return request;
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
      'directDnsAddress',
      'vpnDns',
      'vpnInterfaceAddress',
      'vpnInterfaceIpv6Address',
      'domainStrategy',
      'dnsQueryStrategy',
      'directTargetStrategy',
      'proxyTargetStrategy',
      'proxyDialStrategy',
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
      'fragmentMaxSplit',
      'domesticDns',
      'defaultFingerprint',
      'defaultUserAgent',
    };
    const booleanKeys = {
      'enableLocalDns',
      'enableFakeDns',
      'directDnsEnabled',
      'dnsParallelQuery',
      'dnsServeStale',
      'happyEyeballs',
      'sniffingEnabled',
      'routeOnly',
      'blockQuic',
      'muxEnabled',
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
      'startWithWindows',
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
    _validateSettingChoice(updated, 'dnsQueryStrategy', const {
      'Auto',
      'UseIP',
      'UseIPv4',
      'UseIPv6',
      'UseSystem',
    });
    const outboundStrategies = {
      'AsIs',
      'UseIP',
      'UseIPv4',
      'UseIPv6',
      'UseIPv4v6',
      'UseIPv6v4',
    };
    _validateSettingChoice(updated, 'directTargetStrategy', outboundStrategies);
    _validateSettingChoice(updated, 'proxyTargetStrategy', outboundStrategies);
    _validateSettingChoice(updated, 'proxyDialStrategy', {
      'Auto',
      ...outboundStrategies,
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
      'ios',
      'android',
      'edge',
      '360',
      'qq',
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
    final fragmentMaxSplit = '${updated['fragmentMaxSplit'] ?? ''}'.trim();
    if (!(fragmentPackets == 'tlshello' ||
            _validIntegerRange(fragmentPackets, minimum: 1)) ||
        !_validIntegerRange(fragmentLength, minimum: 1) ||
        !_validIntegerRange(fragmentInterval, minimum: 0) ||
        !_validIntegerRange(fragmentMaxSplit, minimum: 0, allowSingle: true)) {
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
    final muxConcurrency = values['muxConcurrency'];
    if (muxConcurrency != null) {
      final value = muxConcurrency is num ? muxConcurrency.toInt() : -1;
      if (!const {1, 4, 8, 16, 32}.contains(value)) {
        throw _platformError('invalid_settings', 'Mux concurrency is invalid');
      }
      updated['muxConcurrency'] = value;
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
    for (final key in const [
      'remoteDns',
      'vpnDns',
      'domesticDns',
      'directDnsAddress',
    ]) {
      if (!_validDnsResolvers('${updated[key] ?? ''}')) {
        throw _platformError('invalid_settings', '$key value is invalid');
      }
    }
    if (!_validTunAddress(
          '${updated['vpnInterfaceAddress'] ?? ''}',
          type: InternetAddressType.IPv4,
        ) ||
        !_validTunAddress(
          '${updated['vpnInterfaceIpv6Address'] ?? ''}',
          type: InternetAddressType.IPv6,
        )) {
      throw _platformError(
        'invalid_settings',
        'TUN gateway address is invalid',
      );
    }
    final changedNetworkSetting = values.keys.any(_restartSettingKeys.contains);
    final enablingTun = values['tunEnabled'] == true && !_tunEnabled;
    if (enablingTun) {
      // Validate before changing state or stopping a healthy Core.
      await _host.validateTunPrerequisites();
    }
    if (values.containsKey('startWithWindows') &&
        previous['startWithWindows'] != updated['startWithWindows']) {
      await _autoStartController.setEnabled(
        updated['startWithWindows'] == true,
      );
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
    if (_buildConfig.isEmpty) {
      _buildConfig = Map<String, Object?>.from(await _host.getBuildConfig());
    }
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
  Future<void> exitApplication() => _host.exitApplication();

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
    final timing = Stopwatch()..start();
    _publicIpClient?.close(force: true);
    final client = HttpClient()
      ..connectionTimeout = _publicIpTimeout
      ..findProxy = (_) => 'PROXY 127.0.0.1:$_localHttpPort';
    _publicIpClient = client;
    try {
      for (var attempt = 0; attempt < 2; attempt++) {
        var stage = 'request_start';
        try {
          _log(
            'info',
            'IP timing: attempt ${attempt + 1} started '
                '${timing.elapsedMilliseconds}ms',
          );
          final request = await client
              .getUrl(endpoint)
              .timeout(_publicIpTimeout);
          request.headers.set(HttpHeaders.acceptHeader, 'application/json');
          stage = 'response_headers';
          final response = await request.close().timeout(_publicIpTimeout);
          _log(
            'info',
            'IP timing: headers ${timing.elapsedMilliseconds}ms '
                'status ${response.statusCode}',
          );
          if (response.statusCode < 200 || response.statusCode >= 300) {
            await response.drain<void>();
            throw HttpException('IP endpoint returned ${response.statusCode}');
          }
          stage = 'response_body';
          final payload = jsonDecode(
            await utf8.decoder.bind(response).join().timeout(_publicIpTimeout),
          );
          if (payload is! Map) throw const FormatException('Invalid IP result');
          final ip = '${payload['ip'] ?? payload['query'] ?? ''}'.trim();
          if (ip.isEmpty) throw const FormatException('Missing public IP');
          if (_connection['serverId'] != server.id ||
              _connection['state'] != 'connected') {
            return;
          }
          _connection = {
            ..._connection,
            'publicIp': ip,
            'publicCountry':
                '${payload['country'] ?? payload['country_name'] ?? payload['country_code'] ?? ''}',
            'publicCity': '${payload['city'] ?? ''}',
            'publicIpChecked': true,
          };
          _emit('connectionState', _connection);
          _log(
            'info',
            'Public IP verified through Xray in '
                '${timing.elapsedMilliseconds}ms',
          );
          return;
        } on Object catch (error) {
          _log(
            'warning',
            'IP timing: attempt ${attempt + 1} failed at $stage '
                '(${error.runtimeType})',
          );
          if (attempt == 0 &&
              _connection['serverId'] == server.id &&
              _connection['state'] == 'connected') {
            await Future<void>.delayed(const Duration(milliseconds: 350));
            continue;
          }
          rethrow;
        }
      }
    } on Object {
      if (_connection['serverId'] == server.id &&
          _connection['state'] == 'connected') {
        _log('warning', 'Public IP check failed');
      }
    } finally {
      client.close(force: true);
      if (identical(_publicIpClient, client)) _publicIpClient = null;
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
      Map<dynamic, dynamic>? tunStatus;
      if (_expectTunFrontend) {
        tunStatus = await _host.getTunFrontendStatus();
      }
      final xrayRunning = status['running'] == true;
      final tunRunning = !_expectTunFrontend || tunStatus?['running'] == true;
      if (xrayRunning && tunRunning) return;
      _expectXray = false;
      _expectTunFrontend = false;
      _monitor?.cancel();
      Object? cleanupFailure;
      try {
        await _stopCorePipeline();
      } on Object catch (error) {
        cleanupFailure = error;
      }
      final exitCode = status['exitCode'];
      final tunExitCode = tunStatus?['exitCode'];
      final server = _activeServer;
      final cleanupSuffix = cleanupFailure == null
          ? ''
          : '; cleanup failed: ${_safeError(cleanupFailure)}';
      final failedCore = !xrayRunning ? 'Xray' : 'sing-box TUN';
      final failedExitCode = !xrayRunning ? exitCode : tunExitCode;
      _setConnection(
        'error',
        server,
        error:
            '$failedCore exited unexpectedly'
            '${failedExitCode == null || failedExitCode == -1 ? '' : ' ($failedExitCode)'}$cleanupSuffix',
      );
      _log(
        'error',
        cleanupFailure == null
            ? '$failedCore crashed; the connection pipeline was stopped'
            : '$failedCore crashed; connection cleanup was incomplete',
      );
    } on Object catch (error) {
      _log('warning', 'Xray monitor failed: ${_safeError(error)}');
    } finally {
      _pollingXray = false;
    }
  }

  Future<void> _collectCoreLogs() async {
    try {
      final xrayLines = await _host.drainXrayLogs();
      final tunLines = _singBoxTunFrontendEnabled
          ? await _host.drainTunFrontendLogs()
          : const <String>[];
      final now = DateTime.now().millisecondsSinceEpoch;
      if (_recentCoreLogs.length > 100) {
        _recentCoreLogs.removeWhere((_, seen) => now - seen > 60000);
      }
      for (final entry in [
        for (final line in xrayLines) ('Xray', line),
        for (final line in tunLines) ('sing-box', line),
      ]) {
        final (source, raw) = entry;
        final line = _sanitize(raw.trim());
        if (line.isEmpty) continue;
        final lastSeen = _recentCoreLogs[line];
        if (lastSeen != null && now - lastSeen < 10000) continue;
        _recentCoreLogs[line] = now;
        final lower = line.toLowerCase();
        _log(
          lower.contains('error') || lower.contains('failed')
              ? 'error'
              : lower.contains('warning')
              ? 'warning'
              : 'info',
          '$source: $line',
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

  Future<void> _stopCorePipeline({
    bool preserveSystemProxyPreference = false,
  }) async {
    final systemProxyWasEnabled = _systemProxyEnabled;
    final shouldStopTunFrontend = _expectTunFrontend || _tunFrontendMayExist;
    _monitor?.cancel();
    _publicIpClient?.close(force: true);
    _publicIpClient = null;
    _pingGeneration++;
    _resetTestingPings();
    _expectXray = false;
    _expectTunFrontend = false;
    Object? failure;
    try {
      await _host.disableSystemProxy();
    } on Object catch (error) {
      failure = error;
    }
    try {
      await _host.stopSpeedtestXray().timeout(const Duration(seconds: 1));
    } on Object catch (error) {
      failure ??= error;
    }
    if (_singBoxTunFrontendEnabled && shouldStopTunFrontend) {
      try {
        await _host.stopTunFrontend().timeout(const Duration(seconds: 2));
        _tunFrontendMayExist = false;
      } on Object catch (error) {
        failure ??= error;
      }
    }
    try {
      await _host.stopXray().timeout(const Duration(seconds: 2));
    } on Object catch (error) {
      failure ??= error;
    }
    await _collectCoreLogs();
    await _syncSystemProxyState();
    if (preserveSystemProxyPreference) {
      _settings['systemProxyEnabled'] = systemProxyWasEnabled;
    }
    if (await _xrayConfigFile.exists()) {
      await _xrayConfigFile.delete();
    }
    if (await _tunConfigFile.exists()) {
      await _tunConfigFile.delete();
    }
    if (failure != null) throw failure;
  }

  Future<void> _bestEffortCleanup() async {
    try {
      await _stopCorePipeline();
    } on Object catch (error) {
      _log('warning', 'Connection cleanup failed: ${_safeError(error)}');
    }
  }

  Future<bool> _enforceBlockedAccess(
    Object error, {
    bool cleanup = true,
  }) async {
    if (error is! DeviceAccessException ||
        error.reason != 'blocked_by_administrator') {
      return false;
    }
    _expectXray = false;
    _expectTunFrontend = false;
    _monitor?.cancel();
    if (cleanup) await _bestEffortCleanup();
    _connection = _disconnectedConnection();
    _emit('connectionState', _connection);
    _emit('accessBlocked', {'reason': error.reason, 'message': error.message});
    _log('warning', 'Remote access was blocked; Core and proxies stopped');
    return true;
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
    if (_settings['autoUpdate'] != true) return;
    final hours = _integerSetting('updateIntervalHours', 12);
    final interval = Duration(hours: hours);
    _subscriptionTimer = Timer.periodic(interval, (_) {
      unawaited(_refreshSubscriptionQuietly());
    });
  }

  Future<void> _refreshSubscriptionQuietly() async {
    try {
      await refreshSubscription();
    } on Object {
      // The UI receives subscriptionError while the cached list remains usable.
    }
  }

  Future<List<String>> _loadIranCidrs() async {
    if (_settings['routingMode'] != 'bypassIran') return const [];
    final includeIpv6 = _settings['enableIpv6'] == true;
    final cached = _iranCidrsCache[includeIpv6];
    if (cached != null) return cached;
    final values = <String>[];
    for (final asset in [
      'assets/routing/iran_ipv4.txt',
      if (includeIpv6) 'assets/routing/iran_ipv6.txt',
    ]) {
      final content = await rootBundle.loadString(asset);
      values.addAll(
        const LineSplitter()
            .convert(content)
            .map((line) => line.trim())
            .where((line) => line.isNotEmpty && !line.startsWith('#')),
      );
    }
    return _iranCidrsCache[includeIpv6] = List.unmodifiable(values);
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
    'subscriptionConfigured': true,
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
      _manualOrderIds = (payload['manualOrderIds'] as List? ?? const [])
          .map((id) => '$id')
          .where((id) => id.isNotEmpty)
          .toList(growable: false);
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
          if (!settings.containsKey('directDnsEnabled'))
            'directDnsEnabled': false,
          if (!settings.containsKey('directDnsAddress'))
            'directDnsAddress': '178.22.122.100',
          if (!settings.containsKey('fragmentMaxSplit'))
            'fragmentMaxSplit': '0',
          if (!settings.containsKey('vpnInterfaceIpv6Address'))
            'vpnInterfaceIpv6Address': 'fdfe:dcba:9876::1/126',
          if (!settings.containsKey('dnsQueryStrategy'))
            'dnsQueryStrategy': 'Auto',
          if (!settings.containsKey('dnsParallelQuery'))
            'dnsParallelQuery': false,
          if (!settings.containsKey('dnsServeStale')) 'dnsServeStale': false,
          if (!settings.containsKey('directTargetStrategy'))
            'directTargetStrategy': 'AsIs',
          if (!settings.containsKey('proxyTargetStrategy'))
            'proxyTargetStrategy': 'AsIs',
          if (!settings.containsKey('proxyDialStrategy'))
            'proxyDialStrategy': 'Auto',
          if (!settings.containsKey('happyEyeballs')) 'happyEyeballs': false,
          if (!settings.containsKey('blockQuic'))
            'blockQuic': settings['blockQuicForTcpTransports'] == true,
          if (!settings.containsKey('muxEnabled')) 'muxEnabled': false,
          if (!settings.containsKey('muxConcurrency')) 'muxConcurrency': 8,
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
      final stored = jsonDecode(await _subscriptionFile.readAsString());
      final protected = stored is Map && stored['format'] == 'dpapi-v1';
      final payload = protected
          ? jsonDecode(await _host.unprotectData('${stored['payload'] ?? ''}'))
          : stored;
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
      if (!protected) await _persistSubscriptionCache();
    } on Object {
      _servers = [];
      _log('warning', 'Ignored a damaged subscription cache');
    }
  }

  Future<void> _persistState() => _writeJson(_stateFile, {
    'settingsSchemaVersion': _settingsSchemaVersion,
    'selectedId': _selectedId,
    'hiddenIds': _hiddenIds.toList(growable: false),
    'profileOverrides': _profileOverrides,
    'manualOrderIds': _manualOrderIds,
    'settings': _settings,
    'openCount': _openCount,
  });

  Future<void> _persistSubscriptionCache() async {
    final plain = jsonEncode({
      'servers': _servers.map((server) => server.toPrivateJson()).toList(),
      'usage': _usage.toJson(),
      'lastUpdated': _lastUpdated,
    });
    final protected = await _host.protectData(plain);
    await _writeJson(_subscriptionFile, {
      'format': 'dpapi-v1',
      'payload': protected,
    });
  }

  Future<void> _writeJson(File target, Object value) async {
    await target.parent.create(recursive: true);
    final temporary = File('${target.path}.tmp');
    final backup = File('${target.path}.bak');
    await temporary.writeAsString(jsonEncode(value), flush: true);
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
  }

  Future<void> _recoverAtomicFile(File target) async {
    final backup = File('${target.path}.bak');
    if (!await target.exists() && await backup.exists()) {
      await backup.rename(target.path);
    } else if (await target.exists() && await backup.exists()) {
      await backup.delete();
    }
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

  Future<void> _awaitTunReady() async {
    final probe = _tunReadinessProbe;
    if (probe != null) return probe();
    if (_proxyReadinessProbe != null) return;
    final configured = '${_settings['vpnInterfaceAddress'] ?? ''}'.trim();
    final address = configured.split('/').first;
    final deadline = DateTime.now().add(const Duration(seconds: 4));
    while (DateTime.now().isBefore(deadline)) {
      try {
        final interfaces = await NetworkInterface.list(
          includeLoopback: false,
          type: InternetAddressType.any,
        );
        if (interfaces.any(
          (item) =>
              item.name.toLowerCase() == 'niran' ||
              item.addresses.any((candidate) => candidate.address == address),
        )) {
          return;
        }
      } on Object {
        // The next bounded probe may observe the adapter after route setup.
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    throw _platformError('tun_startup', 'TUN interface did not become ready');
  }

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
        RegExp(
          r'(vless|vmess|trojan|ss|socks5?|hy2|hysteria2)://\S+',
          caseSensitive: false,
        ),
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

  String _connectionUserError(Object error) {
    final details = _safeError(error).toLowerCase();
    if (_tunEnabled &&
        (details.contains('unable to set route') ||
            details.contains('route setup'))) {
      return 'TUN route setup failed. Run niraN as administrator and check network settings.';
    }
    if (_tunEnabled &&
        (details.contains('tun') || details.contains('wintun'))) {
      return 'TUN could not start. Check administrator permission and TUN settings.';
    }
    if (details.contains('xhttp extra')) {
      return 'XHTTP Extra is invalid. Please check the profile settings.';
    }
    if (details.contains('dns')) {
      return 'The DNS configuration is invalid. Please check DNS settings.';
    }
    if (details.contains('fragment')) {
      return 'The Fragment configuration is invalid. Please check its values.';
    }
    if (details.contains('mtu')) {
      return 'The VPN MTU is invalid. Please check TUN settings.';
    }
    if (error is TimeoutException ||
        details.contains('timeout') ||
        details.contains('timed out')) {
      return 'Connection timed out. Check the server or your network.';
    }
    return 'Could not connect. Check the selected server and settings.';
  }

  String _truncate(String value, int limit) =>
      value.length <= limit ? value : value.substring(0, limit);

  bool _validDnsResolvers(String raw) {
    final values = raw
        .split(RegExp(r'[,\n]'))
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty);
    if (values.isEmpty) return false;
    return values.every((value) {
      if (InternetAddress.tryParse(value) != null) return true;
      final uri = Uri.tryParse(value);
      if (uri != null && uri.scheme == 'https' && uri.host.isNotEmpty) {
        return true;
      }
      return RegExp(
        r'^(?=.{1,253}$)(?:[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,63}$',
      ).hasMatch(value);
    });
  }

  bool _validTunAddress(String raw, {required InternetAddressType type}) {
    final parts = raw.trim().split('/');
    if (parts.length != 2) return false;
    final address = InternetAddress.tryParse(parts.first);
    final prefix = int.tryParse(parts.last);
    if (address == null || address.type != type || prefix == null) return false;
    return type == InternetAddressType.IPv4
        ? prefix >= 16 && prefix <= 30
        : prefix >= 1 && prefix <= 126;
  }

  bool _validIntegerRange(
    String value, {
    required int minimum,
    bool allowSingle = false,
  }) {
    final match = RegExp(
      allowSingle ? r'^(\d+)(?:-(\d+))?$' : r'^(\d+)-(\d+)$',
    ).firstMatch(value);
    if (match == null) return false;
    final from = int.tryParse(match.group(1) ?? '');
    final to = int.tryParse(match.group(2) ?? match.group(1) ?? '');
    return from != null && to != null && from >= minimum && to >= from;
  }

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
    'directDnsEnabled': false,
    'directDnsAddress': '178.22.122.100',
    'vpnDns': '1.1.1.1',
    'vpnInterfaceAddress': '10.10.14.1/30',
    'vpnInterfaceIpv6Address': 'fdfe:dcba:9876::1/126',
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
    'blockQuic': false,
    'muxEnabled': false,
    'muxConcurrency': 8,
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
    'directDnsEnabled',
    'remoteDns',
    'directDnsAddress',
    'vpnDns',
    'vpnInterfaceAddress',
    'vpnInterfaceIpv6Address',
    'localSocksPort',
    'localHttpPort',
    'vpnMtu',
    'domainStrategy',
    'sniffingEnabled',
    'routeOnly',
    'blockQuic',
    'muxEnabled',
    'muxConcurrency',
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
    'fragmentMaxSplit',
    'domesticDns',
    'dnsQueryStrategy',
    'dnsParallelQuery',
    'dnsServeStale',
    'directTargetStrategy',
    'proxyTargetStrategy',
    'proxyDialStrategy',
    'happyEyeballs',
    'defaultFingerprint',
    'defaultUserAgent',
  };
}

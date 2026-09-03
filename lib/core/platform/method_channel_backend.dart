import 'package:flutter/services.dart';

import 'platform_backend.dart';

/// Compatibility implementation for the existing niraNG Kotlin bridge.
final class MethodChannelPlatformBackend implements NiranPlatformBackend {
  static const _methods = MethodChannel('dev.nirang.client/control');
  static const _events = EventChannel('dev.nirang.client/events');

  @override
  Stream<Map<dynamic, dynamic>> get events => _events
      .receiveBroadcastStream()
      .where((event) => event is Map)
      .cast<Map<dynamic, dynamic>>();

  @override
  Future<Map<dynamic, dynamic>> initialize() async =>
      (await _methods.invokeMethod<Map<dynamic, dynamic>>('initialize')) ?? {};

  @override
  Future<Map<dynamic, dynamic>> refreshSubscription() async =>
      (await _methods.invokeMethod<Map<dynamic, dynamic>>(
        'refreshSubscription',
      )) ??
      {};

  @override
  Future<List<dynamic>> selectServer(String id) async =>
      (await _methods.invokeMethod<List<dynamic>>('selectServer', {
        'id': id,
      })) ??
      const [];

  @override
  Future<List<dynamic>> reorderServers(List<String> ids) async =>
      (await _methods.invokeMethod<List<dynamic>>('reorderServers', {
        'ids': ids,
      })) ??
      const [];

  @override
  Future<List<dynamic>> updateServerProfile(
    String id,
    Map<String, String> values,
  ) async =>
      (await _methods.invokeMethod<List<dynamic>>('updateServerProfile', {
        'id': id,
        'values': values,
      })) ??
      const [];

  @override
  Future<String> exportServerShareLink(String id) async =>
      (await _methods.invokeMethod<String>('exportServerShareLink', {
        'id': id,
      })) ??
      '';

  @override
  Future<Map<dynamic, dynamic>> deleteServer(String id) async =>
      (await _methods.invokeMethod<Map<dynamic, dynamic>>('deleteServer', {
        'id': id,
      })) ??
      {};

  @override
  Future<Map<dynamic, dynamic>> restoreDeletedServers() async =>
      (await _methods.invokeMethod<Map<dynamic, dynamic>>(
        'restoreDeletedServers',
      )) ??
      {};

  @override
  Future<void> connect(String? id) =>
      _methods.invokeMethod('connect', {'id': id});

  @override
  Future<void> disconnect() => _methods.invokeMethod('disconnect');

  @override
  Future<void> setSystemProxy() => _methods.invokeMethod('setSystemProxy');

  @override
  Future<void> clearSystemProxy() => _methods.invokeMethod('clearSystemProxy');

  @override
  Future<void> restartService() => _methods.invokeMethod('restartService');

  @override
  Future<void> pingServer(String id) =>
      _methods.invokeMethod('pingServer', {'id': id});

  @override
  Future<int> tcpPingServer(String id) async =>
      (await _methods.invokeMethod<int>('tcpPingServer', {'id': id})) ?? -1;

  @override
  Future<void> pingAll() => _methods.invokeMethod('pingAll');

  @override
  Future<void> cancelPing() => _methods.invokeMethod('cancelPing');

  @override
  Future<Map<dynamic, dynamic>> updateSettings(
    Map<String, Object?> values,
  ) async =>
      (await _methods.invokeMethod<Map<dynamic, dynamic>>(
        'updateSettings',
        values,
      )) ??
      {};

  @override
  Future<List<dynamic>> getLogs() async =>
      (await _methods.invokeMethod<List<dynamic>>('getLogs')) ?? const [];

  @override
  Future<void> clearLogs() => _methods.invokeMethod('clearLogs');

  @override
  Future<void> openTelegram() => _methods.invokeMethod('openTelegram');

  @override
  Future<void> openExternalUrl(String url) =>
      _methods.invokeMethod('openExternalUrl', {'url': url});

  @override
  Future<void> exitApplication() => _methods.invokeMethod('exitApplication');

  @override
  Future<void> recordTelegramDecision(String decision) =>
      _methods.invokeMethod('recordTelegramDecision', {'decision': decision});

  @override
  Future<void> recordFlutterError(String message) =>
      _methods.invokeMethod('recordFlutterError', {'message': message});
}

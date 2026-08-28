import 'dart:io';

import '../../platform/windows/windows_platform_backend.dart';
import 'method_channel_backend.dart';
import 'platform_backend.dart';

/// Stable facade used by shared Flutter features.
///
/// No Flutter widget imports or calls a Windows, C++, Kotlin, or VpnService API
/// directly. Platform selection happens once behind this facade.
class NirangNative {
  NirangNative._();

  static final NiranPlatformBackend _backend = Platform.isWindows
      ? WindowsPlatformBackend()
      : MethodChannelPlatformBackend();

  static Stream<Map<dynamic, dynamic>> get events => _backend.events;

  static Future<Map<dynamic, dynamic>> initialize() => _backend.initialize();
  static Future<Map<dynamic, dynamic>> refreshSubscription() =>
      _backend.refreshSubscription();
  static Future<List<dynamic>> selectServer(String id) =>
      _backend.selectServer(id);
  static Future<List<dynamic>> updateServerProfile(
    String id,
    Map<String, String> values,
  ) => _backend.updateServerProfile(id, values);
  static Future<String> exportServerShareLink(String id) =>
      _backend.exportServerShareLink(id);
  static Future<Map<dynamic, dynamic>> deleteServer(String id) =>
      _backend.deleteServer(id);
  static Future<Map<dynamic, dynamic>> restoreDeletedServers() =>
      _backend.restoreDeletedServers();
  static Future<void> connect(String? id) => _backend.connect(id);
  static Future<void> disconnect() => _backend.disconnect();
  static Future<void> setSystemProxy() => _backend.setSystemProxy();
  static Future<void> clearSystemProxy() => _backend.clearSystemProxy();
  static Future<void> restartService() => _backend.restartService();
  static Future<void> pingServer(String id) => _backend.pingServer(id);
  static Future<int> tcpPingServer(String id) => _backend.tcpPingServer(id);
  static Future<void> pingAll() => _backend.pingAll();
  static Future<void> cancelPing() => _backend.cancelPing();
  static Future<Map<dynamic, dynamic>> updateSettings(
    Map<String, Object?> values,
  ) => _backend.updateSettings(values);
  static Future<List<dynamic>> getLogs() => _backend.getLogs();
  static Future<void> clearLogs() => _backend.clearLogs();
  static Future<void> openTelegram() => _backend.openTelegram();
  static Future<void> openExternalUrl(String url) =>
      _backend.openExternalUrl(url);
  static Future<void> recordTelegramDecision(String decision) =>
      _backend.recordTelegramDecision(decision);
  static Future<void> recordFlutterError(String message) =>
      _backend.recordFlutterError(message);
}

import 'dart:async';

/// Platform contract consumed by the shared Flutter application.
///
/// Android implements this contract through Kotlin/VpnService in niraNG. The
/// Windows application implements it with the backend under `lib/platform`.
abstract interface class NiranPlatformBackend {
  Stream<Map<dynamic, dynamic>> get events;

  Future<Map<dynamic, dynamic>> initialize();
  Future<Map<dynamic, dynamic>> refreshSubscription();
  Future<List<dynamic>> selectServer(String id);
  Future<List<dynamic>> reorderServers(List<String> ids);
  Future<List<dynamic>> updateServerProfile(
    String id,
    Map<String, String> values,
  );
  Future<String> exportServerShareLink(String id);
  Future<Map<dynamic, dynamic>> deleteServer(String id);
  Future<Map<dynamic, dynamic>> restoreDeletedServers();
  Future<void> connect(String? id);
  Future<void> disconnect();
  Future<void> setSystemProxy();
  Future<void> clearSystemProxy();
  Future<void> restartService();
  Future<void> pingServer(String id);
  Future<int> tcpPingServer(String id);
  Future<void> pingAll();
  Future<void> cancelPing();
  Future<Map<dynamic, dynamic>> updateSettings(Map<String, Object?> values);
  Future<List<dynamic>> getLogs();
  Future<void> clearLogs();
  Future<void> openTelegram();
  Future<void> openExternalUrl(String url);
  Future<void> exitApplication();
  Future<void> recordTelegramDecision(String decision);
  Future<void> recordFlutterError(String message);
}

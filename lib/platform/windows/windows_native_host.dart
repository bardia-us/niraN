import 'dart:async';

import 'package:flutter/services.dart';

abstract interface class WindowsNativeHostApi {
  Future<Map<dynamic, dynamic>> getBuildConfig();
  Future<Map<dynamic, dynamic>> getDeviceRegistrationInfo();
  Future<String> protectData(String value);
  Future<String> unprotectData(String value);
  Future<void> exitApplication();
  Future<void> validateTunPrerequisites();
  Future<void> validateTunFrontendPrerequisites();
  Future<void> startXray(String configPath, {required bool tunMode});
  Future<void> stopXray();
  Future<void> startTunFrontend(String configPath);
  Future<void> stopTunFrontend();
  Future<Map<dynamic, dynamic>> getTunFrontendStatus();
  Future<List<String>> drainTunFrontendLogs();
  Future<String> getSingBoxVersion();
  Future<void> startSpeedtestXray(String configPath);
  Future<void> stopSpeedtestXray();
  Future<Map<dynamic, dynamic>> getXrayStatus();
  Future<List<String>> drainXrayLogs();
  Future<String> getXrayVersion();
  Future<void> enableSystemProxy(int httpPort);
  Future<void> disableSystemProxy();
  Future<void> clearSystemProxy();
  Future<String> getSystemProxyState(int httpPort);
  Future<bool> recoverSystemProxy();
  Future<void> openExternalUrl(String url);
}

final class MethodChannelWindowsNativeHost implements WindowsNativeHostApi {
  static const _channel = MethodChannel('dev.niran.windows/host');
  final _trayActions = StreamController<String>.broadcast(sync: true);

  MethodChannelWindowsNativeHost() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'trayAction') {
        final action = '${call.arguments ?? ''}';
        if (action.isNotEmpty) _trayActions.add(action);
      }
    });
  }

  Stream<String> get trayActions => _trayActions.stream;

  @override
  Future<Map<dynamic, dynamic>> getBuildConfig() async =>
      (await _channel.invokeMethod<Map<dynamic, dynamic>>('getBuildConfig')) ??
      {};

  @override
  Future<Map<dynamic, dynamic>> getDeviceRegistrationInfo() async =>
      (await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'getDeviceRegistrationInfo',
      )) ??
      {};

  @override
  Future<String> protectData(String value) async =>
      (await _channel.invokeMethod<String>('protectData', {'value': value})) ??
      (throw const FormatException('Windows data protection failed'));

  @override
  Future<String> unprotectData(String value) async =>
      (await _channel.invokeMethod<String>('unprotectData', {
        'value': value,
      })) ??
      (throw const FormatException('Windows data protection failed'));

  @override
  Future<void> exitApplication() => _channel.invokeMethod('exitApplication');

  @override
  Future<void> validateTunPrerequisites() =>
      _channel.invokeMethod('validateTunPrerequisites');

  @override
  Future<void> validateTunFrontendPrerequisites() =>
      _channel.invokeMethod('validateTunFrontendPrerequisites');

  @override
  Future<void> startXray(String configPath, {required bool tunMode}) =>
      _channel.invokeMethod('startXray', {
        'configPath': configPath,
        'tunMode': tunMode,
      });

  @override
  Future<void> stopXray() => _channel.invokeMethod('stopXray');

  @override
  Future<void> startTunFrontend(String configPath) =>
      _channel.invokeMethod('startTunFrontend', {'configPath': configPath});

  @override
  Future<void> stopTunFrontend() => _channel.invokeMethod('stopTunFrontend');

  @override
  Future<Map<dynamic, dynamic>> getTunFrontendStatus() async =>
      (await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'getTunFrontendStatus',
      )) ??
      {};

  @override
  Future<List<String>> drainTunFrontendLogs() async =>
      (await _channel.invokeMethod<List<dynamic>>(
        'drainTunFrontendLogs',
      ))?.map((line) => '$line').toList(growable: false) ??
      const [];

  @override
  Future<String> getSingBoxVersion() async =>
      (await _channel.invokeMethod<String>('getSingBoxVersion')) ??
      'Unavailable';

  @override
  Future<void> startSpeedtestXray(String configPath) =>
      _channel.invokeMethod('startSpeedtestXray', {'configPath': configPath});

  @override
  Future<void> stopSpeedtestXray() =>
      _channel.invokeMethod('stopSpeedtestXray');

  @override
  Future<Map<dynamic, dynamic>> getXrayStatus() async =>
      (await _channel.invokeMethod<Map<dynamic, dynamic>>('getXrayStatus')) ??
      {};

  @override
  Future<List<String>> drainXrayLogs() async =>
      (await _channel.invokeMethod<List<dynamic>>(
        'drainXrayLogs',
      ))?.map((line) => '$line').toList(growable: false) ??
      const [];

  @override
  Future<String> getXrayVersion() async =>
      (await _channel.invokeMethod<String>('getXrayVersion')) ?? 'Unavailable';

  @override
  Future<void> enableSystemProxy(int httpPort) =>
      _channel.invokeMethod('enableSystemProxy', {'httpPort': httpPort});

  @override
  Future<void> disableSystemProxy() =>
      _channel.invokeMethod('disableSystemProxy');

  @override
  Future<void> clearSystemProxy() => _channel.invokeMethod('clearSystemProxy');

  @override
  Future<String> getSystemProxyState(int httpPort) async =>
      (await _channel.invokeMethod<String>('getSystemProxyState', {
        'httpPort': httpPort,
      })) ??
      'other';

  @override
  Future<bool> recoverSystemProxy() async =>
      (await _channel.invokeMethod<bool>('recoverSystemProxy')) ?? false;

  @override
  Future<void> openExternalUrl(String url) =>
      _channel.invokeMethod('openExternalUrl', {'url': url});
}

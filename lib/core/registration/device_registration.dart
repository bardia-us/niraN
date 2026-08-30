import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

final deviceAccessBlock = ValueNotifier<String?>(null);

void markDeviceAccessBlocked([String? message]) {
  deviceAccessBlock.value = message?.trim().isNotEmpty == true
      ? message!.trim()
      : 'blocked_by_administrator';
}

void clearDeviceAccessBlocked() {
  deviceAccessBlock.value = null;
}

const deviceRegistrationEndpoint = 'https://neovip.ir/apiniraN/api.php';
const _currentConsentVersion = 2;

abstract interface class DeviceRegistrationCoordinator {
  Future<bool> initialize();
  Future<void> accept();
  Future<void> exitApplication();
}

abstract interface class RemoteAccessController {
  Future<void> requireAllowed();
  Future<RemoteSubscription> fetchSubscription();
}

final class RemoteSubscription {
  const RemoteSubscription(this.bytes, this.usageHeader);

  final List<int> bytes;
  final String? usageHeader;
}

final class DeviceAccessException implements IOException {
  const DeviceAccessException(this.reason, this.message);

  final String reason;
  final String message;

  @override
  String toString() => message;
}

abstract interface class DeviceRegistrationInfoProvider {
  Future<DeviceRegistrationInfo> read();
  Future<void> exitApplication();
}

final class DeviceRegistrationInfo {
  const DeviceRegistrationInfo({
    required this.deviceName,
    required this.windowsUsername,
    required this.windowsVersion,
    required this.appVersion,
    this.systemId = '',
    this.systemIdSource = 'unknown',
  });

  final String deviceName;
  final String windowsUsername;
  final String windowsVersion;
  final String appVersion;
  final String systemId;
  final String systemIdSource;
}

String deriveWindowsDeviceKey(String systemId) {
  final normalized = systemId.trim().toLowerCase();
  if (!RegExp(r'^[0-9a-f]{32,256}$').hasMatch(normalized) ||
      normalized.length.isOdd) {
    throw const DeviceAccessException(
      'device_identity_unavailable',
      'A stable Windows device identity is unavailable',
    );
  }
  return sha256
      .convert(utf8.encode('niraN-device-key-v1\u0000windows\u0000$normalized'))
      .toString();
}

abstract interface class DeviceRegistrationTransport {
  Future<void> send(Map<String, Object?> payload);
}

final class HttpsDeviceRegistrationTransport
    implements DeviceRegistrationTransport {
  HttpsDeviceRegistrationTransport({
    Uri? endpoint,
    this.timeout = const Duration(seconds: 8),
  }) : endpoint = endpoint ?? Uri.parse(deviceRegistrationEndpoint) {
    if (this.endpoint.scheme != 'https' ||
        this.endpoint.toString() != deviceRegistrationEndpoint) {
      throw ArgumentError(
        'Device registration endpoint must be the niraN HTTPS API',
      );
    }
  }

  final Uri endpoint;
  final Duration timeout;

  @override
  Future<void> send(Map<String, Object?> payload) async {
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final request = await client.postUrl(endpoint).timeout(timeout);
      request
        ..followRedirects = false
        ..headers.contentType = ContentType.json
        ..headers.set(HttpHeaders.acceptHeader, 'application/json')
        ..headers.set(HttpHeaders.userAgentHeader, 'niraN-device-registry/2');
      request.write(jsonEncode(payload));
      final response = await request.close().timeout(timeout);
      final body = await utf8.decoder.bind(response).join().timeout(timeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(
          'Device registration returned HTTP ${response.statusCode}',
          uri: endpoint,
        );
      }
      final decoded = jsonDecode(body);
      if (decoded is! Map || decoded['ok'] != true) {
        throw const FormatException('Invalid device registration response');
      }
    } finally {
      client.close(force: true);
    }
  }
}

final class DeviceRegistrationService implements DeviceRegistrationCoordinator {
  DeviceRegistrationService({
    required DeviceRegistrationInfoProvider infoProvider,
    DeviceRegistrationTransport? transport,
    Directory? dataDirectory,
    DateTime Function()? clock,
    Random? random,
  }) : _infoProvider = infoProvider,
       _transport = transport ?? HttpsDeviceRegistrationTransport(),
       _dataDirectory = dataDirectory ?? _defaultDataDirectory(),
       _clock = clock ?? DateTime.now,
       _random = random ?? Random.secure();

  final DeviceRegistrationInfoProvider _infoProvider;
  final DeviceRegistrationTransport _transport;
  final Directory _dataDirectory;
  final DateTime Function() _clock;
  final Random _random;
  Map<String, Object?>? _record;
  Future<void>? _sync;

  File get _file => File(
    '${_dataDirectory.path}${Platform.pathSeparator}device-registration.json',
  );

  @override
  Future<bool> initialize() async {
    await _load();
    final accepted =
        _record?['consent_accepted'] == true &&
        _record?['consent_version'] == _currentConsentVersion;
    if (accepted) unawaited(_syncRegistration());
    return accepted;
  }

  @override
  Future<void> accept() async {
    final now = _clock().toUtc().toIso8601String();
    _record ??= <String, Object?>{};
    _record = {
      ...?_record,
      'schema_version': 2,
      'consent_accepted': true,
      'consent_version': _currentConsentVersion,
      'installation_id': '${_record?['installation_id'] ?? _uuidV4()}',
      'first_seen': '${_record?['first_seen'] ?? now}',
      'last_seen': now,
      'last_sync_succeeded': false,
    };
    await _persist();
    unawaited(_syncRegistration());
  }

  @override
  Future<void> exitApplication() => _infoProvider.exitApplication();

  Future<void> _load() async {
    if (!await _file.exists()) return;
    try {
      final decoded = jsonDecode(await _file.readAsString());
      if (decoded is Map) {
        _record = decoded.map((key, value) => MapEntry('$key', value));
      }
    } on Object {
      // A damaged local record never grants consent and is replaced on accept.
      _record = null;
    }
  }

  Future<void> _syncRegistration() {
    final active = _sync;
    if (active != null) return active;
    final operation = _performSync();
    _sync = operation;
    operation.whenComplete(() => _sync = null);
    return operation;
  }

  Future<void> _performSync() async {
    final current = _record;
    if (current == null || current['consent_accepted'] != true) return;
    try {
      final info = await _infoProvider.read();
      final now = _clock().toUtc().toIso8601String();
      final updated = <String, Object?>{
        ...current,
        'schema_version': 2,
        'device_name': _clean(info.deviceName, fallback: 'Windows PC'),
        'windows_username': _clean(
          info.windowsUsername,
          fallback: 'Unknown user',
        ),
        'windows_version': _clean(info.windowsVersion, fallback: 'Windows'),
        'app_version': _clean(info.appVersion, fallback: 'unknown'),
        'last_seen': now,
      };
      updated.remove('device_model');
      _record = updated;
      await _persist();
      await _transport.send({
        'schema_version': 2,
        'installation_id': updated['installation_id'],
        'device_name': updated['device_name'],
        'windows_username': updated['windows_username'],
        'windows_version': updated['windows_version'],
        'app_version': updated['app_version'],
        'first_seen': updated['first_seen'],
        'last_seen': updated['last_seen'],
      });
      _record = {...updated, 'last_sync_succeeded': true};
      await _persist();
    } on Object {
      _record = {...(_record ?? current), 'last_sync_succeeded': false};
      try {
        await _persist();
      } on Object {
        // Registration is best effort after explicit consent.
      }
    }
  }

  Future<void> _persist() async {
    final record = _record;
    if (record == null) return;
    await _dataDirectory.create(recursive: true);
    final temporary = File('${_file.path}.tmp');
    await temporary.writeAsString(jsonEncode(record), flush: true);
    await temporary.rename(_file.path);
  }

  String _uuidV4() {
    final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes
        .map((value) => value.toRadixString(16).padLeft(2, '0'))
        .join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  static String _clean(String value, {required String fallback}) {
    final clean = value.replaceAll(RegExp(r'[\x00-\x1f\x7f]'), ' ').trim();
    if (clean.isEmpty) return fallback;
    return clean.length <= 160 ? clean : clean.substring(0, 160);
  }

  static Directory _defaultDataDirectory() {
    final root = Platform.environment['LOCALAPPDATA'];
    if (root == null || root.trim().isEmpty) {
      return Directory(
        '${Directory.systemTemp.path}${Platform.pathSeparator}niraN',
      );
    }
    return Directory('$root${Platform.pathSeparator}niraN');
  }
}

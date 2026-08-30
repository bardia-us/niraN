import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import '../../core/registration/device_registration.dart';
import 'windows_device_registration.dart';

const _schemaVersion = 5;
const _consentVersion = 3;
const _endpoint = 'https://neovip.ir/apiniraN/api.php';

final windowsRemoteAccess = WindowsRemoteAccessService(
  infoProvider: WindowsDeviceRegistrationInfoProvider(),
);

final class RegistryResponse {
  const RegistryResponse({
    required this.statusCode,
    required this.bytes,
    required this.json,
    required this.usageHeader,
  });

  final int statusCode;
  final List<int> bytes;
  final Map<String, Object?>? json;
  final String? usageHeader;
}

abstract interface class WindowsRegistryTransport {
  Future<RegistryResponse> send(
    Map<String, Object?> payload, {
    String? token,
    int maximumBytes = 8192,
  });
}

final class HttpsWindowsRegistryTransport implements WindowsRegistryTransport {
  HttpsWindowsRegistryTransport({
    Uri? endpoint,
    this.timeout = const Duration(seconds: 12),
  }) : endpoint = endpoint ?? Uri.parse(_endpoint) {
    if (this.endpoint.scheme != 'https' ||
        this.endpoint.toString() != _endpoint) {
      throw ArgumentError(
        'Registry endpoint must be the official niraN HTTPS API',
      );
    }
  }

  final Uri endpoint;
  final Duration timeout;

  @override
  Future<RegistryResponse> send(
    Map<String, Object?> payload, {
    String? token,
    int maximumBytes = 8192,
  }) async {
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final request = await client.postUrl(endpoint).timeout(timeout);
      request
        ..followRedirects = false
        ..headers.contentType = ContentType.json
        ..headers.set(HttpHeaders.acceptHeader, 'application/json, text/plain')
        ..headers.set(HttpHeaders.userAgentHeader, 'niraN-device-access/0.3.1');
      if (token != null) {
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      }
      request.write(jsonEncode(payload));
      final response = await request.close().timeout(
        const Duration(seconds: 20),
      );
      final output = BytesBuilder(copy: false);
      await for (final chunk in response) {
        output.add(chunk);
        if (output.length > maximumBytes) {
          throw const HttpException('Registry response is too large');
        }
      }
      final bytes = output.takeBytes();
      Map<String, Object?>? json;
      if (response.headers.contentType?.mimeType == 'application/json' ||
          response.statusCode < 200 ||
          response.statusCode >= 300) {
        final decoded = jsonDecode(utf8.decode(bytes));
        if (decoded is Map) {
          json = decoded.map((key, value) => MapEntry('$key', value));
        }
      }
      return RegistryResponse(
        statusCode: response.statusCode,
        bytes: bytes,
        json: json,
        usageHeader: response.headers.value('subscription-userinfo'),
      );
    } finally {
      client.close(force: true);
    }
  }
}

final class WindowsRemoteAccessService
    implements DeviceRegistrationCoordinator, RemoteAccessController {
  WindowsRemoteAccessService({
    required DeviceRegistrationInfoProvider infoProvider,
    WindowsRegistryTransport? transport,
    Directory? dataDirectory,
    DateTime Function()? clock,
    Random? random,
  }) : _infoProvider = infoProvider,
       _transport = transport ?? HttpsWindowsRegistryTransport(),
       _dataDirectory = dataDirectory ?? _defaultDataDirectory(),
       _clock = clock ?? DateTime.now,
       _random = random ?? Random.secure();

  final DeviceRegistrationInfoProvider _infoProvider;
  final WindowsRegistryTransport _transport;
  final Directory _dataDirectory;
  final DateTime Function() _clock;
  final Random _random;
  Map<String, Object?>? _record;
  Future<void>? _operation;
  bool _loaded = false;

  File get _file => File(
    '${_dataDirectory.path}${Platform.pathSeparator}device-registration.json',
  );

  @override
  Future<bool> initialize() async {
    await _load();
    final accepted =
        _record?['consent_accepted'] == true &&
        _record?['consent_version'] == _consentVersion;
    if (accepted) await requireAllowed();
    return accepted;
  }

  @override
  Future<void> accept() async {
    await _load();
    final now = _now();
    _record = {
      ...?_record,
      'schema_version': _schemaVersion,
      'consent_accepted': true,
      'consent_version': _consentVersion,
      'installation_id': '${_record?['installation_id'] ?? _uuidV4()}',
      'first_seen': '${_record?['first_seen'] ?? now}',
      'last_seen': now,
      'remote_access_state': 'unknown',
    };
    await _persist();
    await _register();
  }

  @override
  Future<void> exitApplication() => _infoProvider.exitApplication();

  @override
  Future<void> requireAllowed() async {
    await _load();
    if (_record?['consent_accepted'] != true ||
        _record?['consent_version'] != _consentVersion) {
      throw const DeviceAccessException(
        'consent_required',
        'Device registration consent is required',
      );
    }
    final active = _operation;
    if (active != null) return active;
    final operation = _token == null ? _register() : _status();
    _operation = operation;
    try {
      await operation;
    } finally {
      if (identical(_operation, operation)) _operation = null;
    }
  }

  @override
  Future<RemoteSubscription> fetchSubscription() async {
    await requireAllowed();
    var response = await _transport.send(
      _authorizedPayload('subscription'),
      token: _token,
      maximumBytes: 4 * 1024 * 1024,
    );
    if (response.statusCode == HttpStatus.unauthorized) {
      await _clearToken();
      await _register();
      response = await _transport.send(
        _authorizedPayload('subscription'),
        token: _token,
        maximumBytes: 4 * 1024 * 1024,
      );
    }
    await _throwIfDenied(response, requireAllowedPayload: false);
    if (response.bytes.isEmpty) {
      throw const FormatException('Subscription response is empty');
    }
    return RemoteSubscription(response.bytes, response.usageHeader);
  }

  Future<void> _register() async {
    final response = await _transport.send(await _registrationPayload());
    await _throwIfDenied(response);
    final token = '${response.json?['access_token'] ?? ''}';
    if (!RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(token)) {
      throw const FormatException('Registration token is invalid');
    }
    _record = {
      ...?_record,
      'access_token': token,
      'remote_access_state': 'allowed',
      'last_seen': _now(),
    };
    await _persist();
  }

  Future<void> _status() async {
    final response = await _transport.send(
      _authorizedPayload('status'),
      token: _token,
    );
    if (response.statusCode == HttpStatus.unauthorized) {
      await _clearToken();
      await _register();
      return;
    }
    await _throwIfDenied(response);
    _record = {
      ...?_record,
      'remote_access_state': 'allowed',
      'last_seen': _now(),
    };
    await _persist();
  }

  Future<Map<String, Object?>> _registrationPayload() async {
    final current = _record;
    if (current == null) {
      throw const DeviceAccessException(
        'registration_unavailable',
        'Registration is unavailable',
      );
    }
    final info = await _infoProvider.read();
    final deviceKey = deriveWindowsDeviceKey(info.systemId);
    final updated = <String, Object?>{
      ...current,
      'schema_version': _schemaVersion,
      'device_key': deviceKey,
      'device_identity_source': _clean(info.systemIdSource, 'unknown'),
      'device_name': _clean(info.deviceName, 'Windows PC'),
      'windows_username': _clean(info.windowsUsername, 'Unknown user'),
      'windows_version': _clean(info.windowsVersion, 'Windows'),
      'app_version': _clean(info.appVersion, '0.3.1'),
      'last_seen': _now(),
    };
    _record = updated;
    await _persist();
    return {
      'action': 'register',
      'schema_version': _schemaVersion,
      'platform': 'windows',
      'installation_id': updated['installation_id'],
      'device_key': deviceKey,
      'device_name': updated['device_name'],
      'windows_username': updated['windows_username'],
      'windows_version': updated['windows_version'],
      'app_name': 'niraN',
      'app_version': updated['app_version'],
      'first_seen': updated['first_seen'],
      'last_seen': updated['last_seen'],
    };
  }

  Map<String, Object?> _authorizedPayload(String action) {
    final installationId = '${_record?['installation_id'] ?? ''}';
    final deviceKey = '${_record?['device_key'] ?? ''}';
    final appVersion = '${_record?['app_version'] ?? ''}';
    if (!RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        ).hasMatch(installationId) ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(deviceKey) ||
        appVersion.isEmpty) {
      throw const DeviceAccessException(
        'invalid_device_credentials',
        'Device access credentials are unavailable',
      );
    }
    return {
      'action': action,
      'schema_version': _schemaVersion,
      'platform': 'windows',
      'installation_id': installationId,
      'device_key': deviceKey,
      'app_name': 'niraN',
      'app_version': appVersion,
    };
  }

  Future<void> _throwIfDenied(
    RegistryResponse response, {
    bool requireAllowedPayload = true,
  }) async {
    final json = response.json;
    if (response.statusCode >= 200 &&
        response.statusCode < 300 &&
        (!requireAllowedPayload || json?['allowed'] == true)) {
      return;
    }
    final blocked =
        json?['blocked'] == true || response.statusCode == HttpStatus.forbidden;
    final outdated =
        json?['update_required'] == true || response.statusCode == 426;
    final rawReason = '${json?['reason'] ?? 'access_denied'}';
    final reason = RegExp(r'^[a-z0-9_]{1,64}$').hasMatch(rawReason)
        ? rawReason
        : 'access_denied';
    if (blocked) {
      _record = {...?_record, 'remote_access_state': 'blocked'};
      await _persist();
      throw DeviceAccessException(
        reason,
        'This Windows device has been blocked by the administrator',
      );
    }
    if (outdated) {
      _record = {...?_record, 'remote_access_state': 'outdated'};
      await _persist();
      throw DeviceAccessException(
        reason,
        'niraN must be updated to ${json?['minimum_version'] ?? '0.3.1'} or newer',
      );
    }
    throw DeviceAccessException(reason, 'Device access could not be verified');
  }

  Future<void> _clearToken() async {
    _record = {...?_record, 'remote_access_state': 'unknown'}
      ..remove('access_token');
    await _persist();
  }

  String? get _token {
    final value = '${_record?['access_token'] ?? ''}';
    return RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(value) ? value : null;
  }

  Future<void> _load() async {
    if (_loaded) return;
    _loaded = true;
    if (!await _file.exists()) return;
    try {
      final decoded = jsonDecode(await _file.readAsString());
      if (decoded is Map) {
        _record = decoded.map((key, value) => MapEntry('$key', value));
      }
    } on Object {
      _record = null;
    }
  }

  Future<void> _persist() async {
    if (_record == null) return;
    await _dataDirectory.create(recursive: true);
    final temporary = File('${_file.path}.tmp');
    await temporary.writeAsString(jsonEncode(_record), flush: true);
    if (await _file.exists()) await _file.delete();
    await temporary.rename(_file.path);
  }

  String _uuidV4() {
    final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes
        .map((value) => value.toRadixString(16).padLeft(2, '0'))
        .join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  String _now() => _clock().toUtc().toIso8601String();

  static String _clean(String value, String fallback) {
    final clean = value.replaceAll(RegExp(r'[\x00-\x1f\x7f]'), ' ').trim();
    if (clean.isEmpty) return fallback;
    return clean.length <= 160 ? clean : clean.substring(0, 160);
  }

  static Directory _defaultDataDirectory() {
    final root = Platform.environment['LOCALAPPDATA'];
    return Directory(
      root == null || root.trim().isEmpty
          ? '${Directory.systemTemp.path}${Platform.pathSeparator}niraN'
          : '$root${Platform.pathSeparator}niraN',
    );
  }
}

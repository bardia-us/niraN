import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import '../../core/registration/device_registration.dart';

/// Deliberately excludes URLs, bodies, tokens, identity and exception.toString.
final class AccessDiagnostic {
  const AccessDiagnostic(
    this.operation,
    this.stage, {
    this.error,
    this.status,
    this.elapsedMs,
    this.byteCount,
  });
  final String operation;
  final String stage;
  final Object? error;
  final int? status;
  final int? elapsedMs;
  final int? byteCount;
  String get line {
    final failure = error == null ? null : AccessFailure.from(error!);
    return '[AccessDiag] op=${const {'register', 'status', 'subscription'}.contains(operation) ? operation : 'unknown'} '
        'stage=${const {'request', 'headers', 'complete', 'failed', 'local'}.contains(stage) ? stage : 'unknown'}'
        '${status == null ? '' : ' http=$status'}'
        '${elapsedMs == null ? '' : ' ms=$elapsedMs'}'
        '${byteCount == null ? '' : ' bytes=$byteCount'}'
        '${failure == null ? '' : ' kind=${failure.kind} reason=${failure.reason} os=${failure.osCode ?? '-'}'}';
  }
}

abstract final class WindowsAccessDiagnostics {
  static const enabled = bool.fromEnvironment('NIRAN_NETWORK_DIAGNOSTICS');
  static final _events = StreamController<AccessDiagnostic>.broadcast(
    sync: true,
  );
  static Stream<AccessDiagnostic> get events => _events.stream;
  static final _recent = <AccessDiagnostic>[];
  static List<AccessDiagnostic> get recent => List.unmodifiable(_recent);
  static void record(AccessDiagnostic value) {
    _recent.add(value);
    if (_recent.length > 48) _recent.removeAt(0);
    _events.add(value);
  }
}

final class RegistryHttpFailure implements IOException {
  const RegistryHttpFailure(this.status);
  final int status;
  @override
  String toString() => 'Registry HTTP $status';
}

final class AccessFailure {
  const AccessFailure(this.kind, {this.reason = 'none', this.osCode});
  final String kind;
  final String reason;
  final int? osCode;
  static AccessFailure from(Object error) {
    if (error is TlsException) {
      return AccessFailure(
        'tls',
        reason:
            error.message.toUpperCase().contains('CERTIFICATE_VERIFY_FAILED')
            ? 'certificate_verify_failed'
            : 'tls_handshake',
      );
    }
    if (error is TimeoutException) return const AccessFailure('timeout');
    if (error is SocketException) {
      return AccessFailure('socket', osCode: error.osError?.errorCode);
    }
    if (error is RegistryHttpFailure) {
      return AccessFailure('http', osCode: error.status);
    }
    if (error is FileSystemException) {
      return AccessFailure('storage', osCode: error.osError?.errorCode);
    }
    if (error is DeviceAccessException) {
      const known = {
        'consent_required',
        'registration_unavailable',
        'invalid_device_credentials',
        'blocked_by_administrator',
        'update_required',
        'access_denied',
        'invalid_token',
        'device_not_found',
        'invalid_credentials',
        'installation_not_found',
        'token_expired',
      };
      return AccessFailure(
        'device',
        reason: known.contains(error.reason)
            ? error.reason
            : 'other_access_error',
      );
    }
    if (error is FormatException) return const AccessFailure('format');
    if (error is PlatformException) {
      const known = {
        'data_protection',
        'device_identity',
        'registration',
        'network_state',
        'build_config',
      };
      return AccessFailure(
        'native',
        reason: known.contains(error.code) ? error.code : 'native_error',
      );
    }
    if (error is HttpException) return const AccessFailure('http');
    return const AccessFailure('unknown');
  }

  PlatformException get subscriptionException => PlatformException(
    code: 'subscription_$kind',
    message: 'Subscription failed ($kind). See AccessDiag in Logs.',
    details: {'kind': kind, 'reason': reason, 'osCode': osCode},
  );
}

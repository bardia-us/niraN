import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niran/core/widgets/operation_error.dart';
import 'package:niran/core/registration/device_registration.dart';
import 'package:niran/platform/windows/windows_access_diagnostics.dart';
import 'package:niran/platform/windows/windows_network_diagnostics.dart';

void main() {
  test('API response wins over Windows stale offline signal', () {
    expect(
      const NetworkEvidence(
        connected: false,
        internetReported: false,
        apiStatus: 405,
      ).state,
      'api_reachable',
    );
  });
  test('disconnected, local-only and API-limited networks remain distinct', () {
    expect(
      const NetworkEvidence(connected: false).state,
      'windows_reports_disconnected',
    );
    expect(
      const NetworkEvidence(connected: true, internetReported: false).state,
      'local_network_only_or_restricted',
    );
    expect(
      const NetworkEvidence(connected: true, internetReported: true).state,
      'windows_internet_api_unreachable',
    );
    expect(const NetworkEvidence().state, 'network_state_unknown');
    expect(const NetworkEvidence(apiStatus: 403).state, 'api_http_response');
  });
  test(
    'diagnostics deduplicate in-flight checks and bound stalled probes',
    () async {
      var probes = 0;
      final diagnostics = WindowsNetworkDiagnostics(
        deadline: const Duration(milliseconds: 25),
        readNetwork: () async => {'connected': true, 'internet': false},
        probeApi: () {
          probes++;
          return Completer<int>().future;
        },
      );
      final first = diagnostics.check();
      expect(identical(first, diagnostics.check()), isTrue);
      final result = await first.timeout(const Duration(seconds: 1));
      expect(result.probeFailure, 'timeout');
      expect(result.state, 'local_network_only_or_restricted');
      await diagnostics.check();
      expect(probes, 1);
    },
  );
  test('failed OS inspection is unknown rather than disconnected', () async {
    final diagnostics = WindowsNetworkDiagnostics(
      readNetwork: () async => throw StateError('private local details'),
      probeApi: () async => throw const SocketException('private API URL'),
    );
    final evidence = await diagnostics.check();
    expect(evidence.state, 'network_state_unknown');
    expect(evidence.line, isNot(contains('private')));
  });
  test(
    'failure categories preserve TLS auth storage HTTP and socket distinctions',
    () {
      expect(
        AccessFailure.from(const HandshakeException('secret')).kind,
        'tls',
      );
      expect(
        AccessFailure.from(
          const DeviceAccessException('invalid_device_credentials', 'secret'),
        ).reason,
        'invalid_device_credentials',
      );
      expect(
        AccessFailure.from(const FileSystemException('secret')).kind,
        'storage',
      );
      expect(AccessFailure.from(const RegistryHttpFailure(502)).osCode, 502);
      expect(
        AccessFailure.from(
          const SocketException('secret', osError: OSError('secret', 11001)),
        ).osCode,
        11001,
      );
    },
  );
  test(
    'diagnostic lines never include raw reasons credentials or exceptions',
    () {
      const secret = 'TOKEN_DO_NOT_LOG_123456789012345678901234567890';
      for (final error in <Object>[
        const DeviceAccessException(secret, secret),
        const SocketException(secret),
        const FormatException(secret),
        PlatformException(code: secret, message: secret, details: secret),
        StateError(secret),
      ]) {
        final event = AccessDiagnostic(
          secret,
          secret,
          error: error,
          status: 502,
          elapsedMs: 1,
        );
        expect(event.line, isNot(contains(secret)));
        expect(event.line, contains('http=502'));
        expect(event.line, contains('op=unknown'));
      }
    },
  );
  testWidgets('subscription TLS error does not blame internet connectivity', (
    tester,
  ) async {
    late String message;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            message = friendlyErrorMessage(
              context,
              PlatformException(code: 'subscription_tls'),
            );
            return const SizedBox();
          },
        ),
      ),
    );
    expect(message.toLowerCase(), contains('certificate'));
    expect(message, isNot(contains('Check your connection')));
  });
}

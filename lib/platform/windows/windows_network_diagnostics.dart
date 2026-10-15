import 'dart:async';
import 'dart:io';
import '../../core/registration/device_registration.dart';
import 'windows_access_diagnostics.dart';
import 'windows_native_host.dart';

/// Evidence, not a gate: Windows/NCSI can be wrong under filtering/VPNs.
final class NetworkEvidence {
  const NetworkEvidence({
    this.connected,
    this.internetReported,
    this.apiStatus,
    this.probeFailure,
  });
  final bool? connected;
  final bool? internetReported;
  final int? apiStatus;
  final String? probeFailure;
  String get state {
    if (apiStatus == 405) return 'api_reachable';
    if (apiStatus != null) return 'api_http_response';
    if (connected == false) return 'windows_reports_disconnected';
    if (internetReported == true) return 'windows_internet_api_unreachable';
    if (connected == true) return 'local_network_only_or_restricted';
    return 'network_state_unknown';
  }

  String get line =>
      '[NetworkDiag] state=$state windows_network=${connected ?? 'unknown'} '
      'windows_internet=${internetReported ?? 'unknown'} api_http=${apiStatus ?? '-'} '
      'probe=${probeFailure ?? 'none'}';
}

final class WindowsNetworkDiagnostics {
  WindowsNetworkDiagnostics({
    required this.readNetwork,
    this.deadline = const Duration(seconds: 3),
    Future<int> Function()? probeApi,
  }) : _probeApi = probeApi;
  final Future<Map<dynamic, dynamic>> Function() readNetwork;
  final Duration deadline;
  final Future<int> Function()? _probeApi;
  Future<NetworkEvidence>? _active;
  DateTime? _lastCheck;
  NetworkEvidence? _lastEvidence;

  Future<NetworkEvidence> check() {
    final pending = _active;
    if (pending != null) return pending;
    if (_lastCheck != null &&
        DateTime.now().difference(_lastCheck!) < const Duration(seconds: 15) &&
        _lastEvidence != null) {
      return Future.value(_lastEvidence);
    }
    late final Future<NetworkEvidence> future;
    future = _check()
        .then((value) {
          _lastCheck = DateTime.now();
          _lastEvidence = value;
          return value;
        })
        .whenComplete(() {
          if (identical(_active, future)) _active = null;
        });
    return _active = future;
  }

  Future<NetworkEvidence> _check() async {
    Map<dynamic, dynamic> network = {};
    int? status;
    String? failure;
    await Future.wait([
      (() async {
        try {
          network = await readNetwork().timeout(deadline);
        } on Object {
          /* Unknown is not offline. */
        }
      })(),
      (() async {
        try {
          status = await (_probeApi?.call() ?? _httpProbe()).timeout(deadline);
        } on Object catch (error) {
          failure = AccessFailure.from(error).kind;
        }
      })(),
    ]);
    return NetworkEvidence(
      connected: network['connected'] is bool
          ? network['connected'] as bool
          : null,
      internetReported: network['internet'] is bool
          ? network['internet'] as bool
          : null,
      apiStatus: status,
      probeFailure: failure,
    );
  }

  Future<int> _httpProbe() async {
    final client = HttpClient()..connectionTimeout = deadline;
    try {
      return await (() async {
        final request = await client.getUrl(
          Uri.parse(deviceRegistrationEndpoint),
        );
        request.followRedirects = false;
        request.headers.set(
          HttpHeaders.userAgentHeader,
          'niraN-network-diagnostic/0.3.9',
        );
        final response = await request.close();
        // Headers establish reachability; never download a subscription/body.
        return response.statusCode;
      })().timeout(deadline);
    } finally {
      client.close(force: true);
    }
  }
}

Future<Map<dynamic, dynamic>> readWindowsNetworkState(
  WindowsNativeHostApi host,
) async => host is WindowsNetworkStateHostApi
    ? (host as WindowsNetworkStateHostApi).getNetworkState()
    : {};

import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:niran/platform/windows/windows_remote_access.dart';
import 'package:niran/core/update_checker.dart';

void main() {
  test('update check closes a stalled body at its total deadline', () async {
    final client = _Client(_Response());
    await HttpOverrides.runZoned(() async {
      try {
        await expectLater(
          const GitHubUpdateChecker(timeout: Duration(milliseconds: 20))
              .check('0.3.9+13')
              .timeout(
                const Duration(milliseconds: 250),
                onTimeout: () => throw StateError('No update body deadline'),
              ),
          throwsA(isA<TimeoutException>()),
        );
        expect(client.forceClosed, isTrue);
      } finally {
        client.close(force: true);
      }
    }, createHttpClient: (_) => client);
  });
  test('registry total deadline closes a stalled response body', () async {
    final response = _Response();
    final client = _Client(response);
    await HttpOverrides.runZoned(() async {
      try {
        await expectLater(
          HttpsWindowsRegistryTransport(
                timeout: const Duration(milliseconds: 20),
              )
              .send({'action': 'status'})
              .timeout(
                const Duration(milliseconds: 250),
                onTimeout: () =>
                    throw StateError('No overall response-body deadline'),
              ),
          throwsA(isA<TimeoutException>()),
        );
        expect(client.forceClosed, isTrue);
      } finally {
        client.close(force: true);
      }
    }, createHttpClient: (_) => client);
  });
}

class _Client implements HttpClient {
  _Client(this.response);
  final _Response response;
  bool forceClosed = false;
  @override
  Future<HttpClientRequest> postUrl(Uri url) async => _Request(response);
  @override
  Future<HttpClientRequest> getUrl(Uri url) async => _Request(response);
  @override
  void close({bool force = false}) {
    forceClosed = force;
    if (!response.body.isClosed) unawaited(response.body.close());
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _Request implements HttpClientRequest {
  _Request(this.response);
  final _Response response;
  @override
  HttpHeaders get headers => _Headers();
  @override
  Future<HttpClientResponse> close() async => response;
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _Headers implements HttpHeaders {
  @override
  ContentType get contentType => ContentType.json;
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _Response extends Stream<List<int>> implements HttpClientResponse {
  final body = StreamController<List<int>>();
  @override
  int get statusCode => HttpStatus.ok;
  @override
  HttpHeaders get headers => _Headers();
  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => body.stream.listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

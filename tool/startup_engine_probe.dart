// Diagnostic entrypoint only. Never package this as the release application.
import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:niran/main.dart' as application;
import 'package:niran/core/platform/nirang_native.dart';

Future<void> main() async {
  await application.main();
  final service = await developer.Service.getInfo();
  final uri = service.serverUri;
  if (uri == null) throw StateError('Profile VM service is required');
  final client = HttpClient();
  Future<Map<String, dynamic>> rpc(
    String method, [
    Map<String, String>? query,
  ]) async {
    final request = await client.getUrl(
      uri.resolve(method).replace(queryParameters: query),
    );
    final response = await request.close();
    return jsonDecode(await utf8.decoder.bind(response).join())
        as Map<String, dynamic>;
  }

  await rpc('setVMTimelineFlags', {
    'recordedStreams': jsonEncode(['Dart', 'Embedder', 'GC']),
  });
  Timer(const Duration(seconds: 26), () async {
    try {
      final timeline = await rpc('getVMTimeline');
      final result = timeline['result'] as Map;
      final directory = File(Platform.resolvedExecutable).parent;
      await File(
        '${directory.path}/startup-engine-timeline.json',
      ).writeAsString(jsonEncode(result));
      stdout.writeln('STARTUP_ENGINE_TIMELINE_SAVED');
    } finally {
      client.close(force: true);
      // Use normal application cleanup; never kill the user core/process.
      await NirangNative.exitApplication();
    }
  });
}

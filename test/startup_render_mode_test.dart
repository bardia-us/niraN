import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:niran/core/render_mode.dart';

void main() {
  late Directory directory;
  setUp(
    () async =>
        directory = await Directory.systemTemp.createTemp('niran-mode-test-'),
  );
  tearDown(() async => directory.delete(recursive: true));
  test(
    'existing settings select lightweight before graphics initialization',
    () async {
      await File(
        '${directory.path}/state.json',
      ).writeAsString('{"settings":{"performanceMode":true}}');
      expect(await readStartupPerformanceMode(directory), true);
      await File(
        '${directory.path}/state.json',
      ).writeAsString('{"settings":{"performanceMode":false}}');
      expect(await readStartupPerformanceMode(directory), false);
    },
  );
  test(
    'corrupt primary follows backend defaults without consuming a valid backup',
    () async {
      final damaged = File('${directory.path}/state.json');
      await damaged.writeAsString('{');
      await File(
        '${directory.path}/state.json.bak',
      ).writeAsString('{"settings":{"performanceMode":true}}');
      expect(await readStartupPerformanceMode(directory), false);
      expect(await damaged.readAsString(), '{');
    },
  );
  test(
    'missing or non-boolean preferences preserve normal rendering',
    () async {
      expect(await readStartupPerformanceMode(directory), false);
      await File(
        '${directory.path}/state.json',
      ).writeAsString('{"settings":{"performanceMode":"true"}}');
      expect(await readStartupPerformanceMode(directory), false);
    },
  );
}

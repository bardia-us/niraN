import 'dart:convert';
import 'dart:io';

import 'package:niran/platform/windows/windows_real_delay.dart';

Future<void> main(List<String> arguments) async {
  final local = Platform.environment['LOCALAPPDATA'];
  if (local == null) throw StateError('LOCALAPPDATA is unavailable');
  final state = jsonDecode(
    await File('$local\\niraN\\state.json').readAsString(),
  ) as Map;
  final settings = (state['settings'] as Map).cast<String, Object?>();
  final target = Uri.parse('${settings['realDelayUrl']}');
  final port = (settings['localHttpPort'] as num?)?.toInt() ?? 10809;
  final timeout = Duration(
    seconds: ((settings['realDelayTimeoutSeconds'] as num?)?.toInt() ?? 8)
        .clamp(3, 15),
  );
  final count = arguments.isEmpty ? 20 : int.parse(arguments.first);
  final values = <int>[];
  for (var index = 0; index < count; index++) {
    final value = await measureWindowsRealDelay(
      target: target,
      proxyPort: port,
      timeout: timeout,
    );
    values.add(value);
    stdout.writeln('${index + 1}: ${value > 0 ? '${value}ms' : 'timeout'}');
  }
  final successes = values.where((value) => value > 0).toList()..sort();
  stdout.writeln('timeouts=${values.where((value) => value <= 0).length}');
  if (successes.isNotEmpty) {
    final average = successes.reduce((a, b) => a + b) / successes.length;
    stdout.writeln(
      'min=${successes.first}ms median=${successes[successes.length ~/ 2]}ms '
      'average=${average.toStringAsFixed(1)}ms max=${successes.last}ms',
    );
  }
}

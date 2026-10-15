// Read-only diagnostics: this tool never launches the app or reads app data.
import 'dart:convert';
import 'dart:io';

void main(List<String> arguments) {
  if (arguments.length != 1) {
    stderr.writeln('Usage: dart tool/read_startup_trace.dart <trace.jsonl>');
    exitCode = 64;
    return;
  }
  final previous = <String, int>{};
  stdout.writeln('Origin       Total ms   Since prior ms   Phase');
  for (final line in File(arguments.single).readAsLinesSync()) {
    try {
      final record = jsonDecode(line);
      if (record is! Map ||
          !const ['process', 'dart'].contains(record['origin']) ||
          record['elapsedUs'] is! int ||
          record['phase'] is! String ||
          !RegExp(r'^[a-zA-Z_]{1,64}$').hasMatch(record['phase'] as String)) {
        continue;
      }
      final origin = record['origin'] as String;
      final elapsed = record['elapsedUs'] as int;
      if (elapsed < 0) continue;
      final delta = elapsed - (previous[origin] ?? 0);
      previous[origin] = elapsed;
      stdout.writeln(
        '${origin.padRight(11)} '
        '${(elapsed / 1000).toStringAsFixed(2).padLeft(9)} '
        '${(delta / 1000).toStringAsFixed(2).padLeft(16)}   '
        '${record['phase']}',
      );
    } on Object {
      // Ignore a partial final line or unrelated output without exposing it.
    }
  }
  stdout.writeln('Origins are separate clocks; compare deltas within each.');
}

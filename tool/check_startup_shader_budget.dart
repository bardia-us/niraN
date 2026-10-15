// Native performance regression check. Run after startup_shader_stage_probe.
import 'dart:convert';
import 'dart:io';

void main(List<String> arguments) {
  final events = File(
    arguments.first,
  ).readAsLinesSync().map((line) => jsonDecode(line) as Map).toList();
  final start =
      events.lastWhere((e) => e['phase'] == 'program_start')['us'] as int;
  final end =
      events.lastWhere((e) => e['phase'] == 'raster_complete')['us'] as int;
  final budget = int.parse(arguments[1]);
  stdout.writeln('Shader ready: ${end - start}us; budget: ${budget}us');
  if (end - start > budget) exitCode = 1;
}

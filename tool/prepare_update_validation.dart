import 'dart:io';

import 'package:niran/core/portable_update_script.dart';
import 'package:niran/core/setup_update_script.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.isEmpty) throw ArgumentError('Missing update mode');
  switch (arguments.first) {
    case 'portable':
      if (arguments.length != 6) {
        throw ArgumentError(
          'portable <archive> <install> <work> <version> <pid>',
        );
      }
      final plan = PortableUpdatePlan(
        archivePath: arguments[1],
        installDirectory: arguments[2],
        workDirectory: arguments[3],
        version: arguments[4],
        processId: int.parse(arguments[5]),
      );
      final script = File(plan.scriptPath);
      await script.writeAsString(plan.buildScript(), flush: true);
      stdout.write(script.path);
    case 'setup':
      if (arguments.length != 7) {
        throw ArgumentError(
          'setup <installer> <install> <work> <version> <pid> <registry-key>',
        );
      }
      final plan = SetupUpdatePlan(
        installerPath: arguments[1],
        installDirectory: arguments[2],
        workDirectory: arguments[3],
        version: arguments[4],
        processId: int.parse(arguments[5]),
        uninstallRegistryKey: arguments[6],
      );
      final script = File(plan.scriptPath);
      await script.writeAsString(plan.buildScript(), flush: true);
      stdout.write(script.path);
    default:
      throw ArgumentError('Unsupported update mode');
  }
}

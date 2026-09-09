import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:niran/core/setup_update_script.dart';

void main() {
  test(
    'setup helper upgrades in place, preserves external state, and records completion',
    () async {
      final root = await Directory.systemTemp.createTemp('niran-setup-update-');
      try {
        final install = Directory('${root.path}\\installed')..createSync();
        final work = Directory('${root.path}\\downloads')..createSync();
        final externalState = File('${root.path}\\settings.json');
        await externalState.writeAsString('preserve');
        await File('${install.path}\\niraN.exe').writeAsString('old');
        final installer = File(
          '${work.path}\\niraN-v0.3.4-windows-x64-setup.exe',
        );
        await installer.writeAsBytes(const [1]);
        final fakeInstaller = File('${root.path}\\fake-setup.ps1');
        await fakeInstaller.writeAsString(r'''
param([string]$InstallDirectory, [string]$Version)
[IO.File]::WriteAllText((Join-Path $InstallDirectory 'niraN.exe'), "new-$Version")
exit 0
''');
        final plan = SetupUpdatePlan(
          processId: 0,
          installerPath: installer.path,
          installDirectory: install.path,
          workDirectory: work.path,
          version: '0.3.4',
        );
        final script = File(plan.scriptPath);
        await script.writeAsString(plan.buildScript());

        final result = await Process.run('powershell.exe', [
          '-NoLogo',
          '-NoProfile',
          '-NonInteractive',
          '-ExecutionPolicy',
          'Bypass',
          '-File',
          script.path,
          '-SkipRestart',
          '-TestInstallerScript',
          fakeInstaller.path,
        ]);

        expect(result.exitCode, 0, reason: '${result.stderr}');
        expect(
          await File('${install.path}\\niraN.exe').readAsString(),
          'new-0.3.4',
        );
        expect(await externalState.readAsString(), 'preserve');
        expect(await installer.exists(), isFalse);
        final state = jsonDecode(await File(plan.resultPath).readAsString());
        expect(state['state'], 'completed');
        expect(state['installDirectory'], install.path);
      } finally {
        if (await root.exists()) await root.delete(recursive: true);
      }
    },
    skip: !Platform.isWindows,
  );

  test(
    'setup helper failure leaves the current installation usable',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'niran-setup-failure-',
      );
      try {
        final install = Directory('${root.path}\\installed')..createSync();
        final work = Directory('${root.path}\\downloads')..createSync();
        await File('${install.path}\\niraN.exe').writeAsString('old');
        final installer = File(
          '${work.path}\\niraN-v0.3.4-windows-x64-setup.exe',
        );
        await installer.writeAsBytes(const [1]);
        final fakeInstaller = File('${root.path}\\failed-setup.ps1');
        await fakeInstaller.writeAsString('exit 23');
        final plan = SetupUpdatePlan(
          processId: 0,
          installerPath: installer.path,
          installDirectory: install.path,
          workDirectory: work.path,
          version: '0.3.4',
        );
        final script = File(plan.scriptPath);
        await script.writeAsString(plan.buildScript());

        final result = await Process.run('powershell.exe', [
          '-NoLogo',
          '-NoProfile',
          '-NonInteractive',
          '-ExecutionPolicy',
          'Bypass',
          '-File',
          script.path,
          '-SkipRestart',
          '-TestInstallerScript',
          fakeInstaller.path,
        ]);

        expect(result.exitCode, 1);
        expect(await File('${install.path}\\niraN.exe').readAsString(), 'old');
        expect(await installer.exists(), isTrue);
        final state = jsonDecode(await File(plan.resultPath).readAsString());
        expect(state['state'], 'failed');
      } finally {
        if (await root.exists()) await root.delete(recursive: true);
      }
    },
    skip: !Platform.isWindows,
  );
}

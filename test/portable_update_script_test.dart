import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:niran/core/portable_update_script.dart';

void main() {
  test(
    'portable updater extracts rooted ZIP, replaces files, preserves data and renames folder',
    () async {
      final fixture = await _UpdateFixture.create();
      try {
        final result = await fixture.run();
        expect(result.exitCode, 0, reason: '${result.stderr}');
        final renamed = Directory(
          '${fixture.root.path}${Platform.pathSeparator}niraN-0.3.3-windows-x64',
        );
        final helperLog = await File(
          '${fixture.work.path}\\update-helper.log',
        ).readAsString();
        expect(await fixture.install.exists(), isFalse, reason: helperLog);
        expect(await renamed.exists(), isTrue);
        expect(await File('${renamed.path}\\niraN.exe').readAsString(), 'new');
        expect(
          await File('${renamed.path}\\user-note.txt').readAsString(),
          'keep',
        );
        expect(
          await File('${renamed.path}\\data\\app.so').readAsString(),
          'payload',
        );
        expect(await fixture.archive.exists(), isFalse);
        final state =
            jsonDecode(await fixture.resultFile.readAsString()) as Map;
        expect(state['state'], 'completed');
        expect(
          '${state['installDirectory']}'.toLowerCase(),
          endsWith(r'\niran-0.3.3-windows-x64'),
        );
      } finally {
        await fixture.dispose();
      }
    },
    skip: !Platform.isWindows,
  );

  test(
    'portable updater falls back to the existing folder if rename fails',
    () async {
      final fixture = await _UpdateFixture.create();
      try {
        final result = await fixture.run(simulateRenameFailure: true);
        expect(result.exitCode, 0, reason: '${result.stderr}');
        expect(await fixture.install.exists(), isTrue);
        expect(
          await File('${fixture.install.path}\\niraN.exe').readAsString(),
          'new',
        );
        expect(
          await File('${fixture.install.path}\\user-note.txt').readAsString(),
          'keep',
        );
        final state =
            jsonDecode(await fixture.resultFile.readAsString()) as Map;
        expect(state['state'], 'completed');
        expect(state['installDirectory'], fixture.install.path);
      } finally {
        await fixture.dispose();
      }
    },
    skip: !Platform.isWindows,
  );

  test(
    'invalid payload preserves current app and keeps ZIP for retry',
    () async {
      final fixture = await _UpdateFixture.create(includeExecutable: false);
      try {
        final result = await fixture.run();
        expect(result.exitCode, isNot(0));
        expect(await fixture.install.exists(), isTrue);
        expect(
          await File('${fixture.install.path}\\niraN.exe').readAsString(),
          'old',
        );
        expect(
          await File('${fixture.install.path}\\user-note.txt').readAsString(),
          'keep',
        );
        expect(await fixture.archive.exists(), isTrue);
        final state =
            jsonDecode(await fixture.resultFile.readAsString()) as Map;
        expect(state['state'], 'failed');
      } finally {
        await fixture.dispose();
      }
    },
    skip: !Platform.isWindows,
  );

  test(
    'script has a single-instance mutex and repairs auto-start after rename',
    () async {
      final root = await Directory.systemTemp.createTemp('niran-script-test-');
      try {
        final script = PortableUpdatePlan(
          processId: 0,
          archivePath: '${root.path}\\update.zip',
          installDirectory: '${root.path}\\niraN-0.3.2-windows-x64',
          workDirectory: '${root.path}\\work',
          version: '0.3.3',
        ).buildScript();
        expect(script, contains('niraN-Portable-Updater-v1'));
        expect(script, contains(r'$Mutex.WaitOne(0)'));
        expect(
          script,
          contains("Set-ItemProperty -Path \$RunKey -Name 'niraN'"),
        );
        expect(script, contains(r'''-Value ('"{0}"' -f $NewExecutable)'''));
        expect(script, isNot(contains('Wait-Process')));
      } finally {
        await root.delete(recursive: true);
      }
    },
  );

  test('a second updater cannot run concurrently', () async {
    final fixture = await _UpdateFixture.create();
    try {
      final first = await Process.start(
        'powershell.exe',
        fixture.arguments(holdMutexMilliseconds: 1200),
        workingDirectory: fixture.work.path,
      );
      await Future<void>.delayed(const Duration(milliseconds: 250));
      final second = await Process.run(
        'powershell.exe',
        fixture.arguments(),
        workingDirectory: fixture.work.path,
      );
      expect(second.exitCode, isNot(0));
      expect(await first.exitCode, 0);
    } finally {
      await fixture.dispose();
    }
  }, skip: !Platform.isWindows);
}

final class _UpdateFixture {
  _UpdateFixture({
    required this.root,
    required this.install,
    required this.work,
    required this.archive,
    required this.script,
  });

  final Directory root;
  final Directory install;
  final Directory work;
  final File archive;
  final File script;

  File get resultFile => File('${work.path}\\update-result.json');

  static Future<_UpdateFixture> create({bool includeExecutable = true}) async {
    final root = await Directory.systemTemp.createTemp('niran-update-flow-');
    final install = Directory('${root.path}\\niraN-0.3.2-windows-x64');
    final payload = Directory('${root.path}\\niraN-0.3.3-windows-x64');
    final work = Directory('${root.path}\\work');
    await install.create();
    await payload.create();
    await work.create();
    await File('${install.path}\\niraN.exe').writeAsString('old');
    await File('${install.path}\\user-note.txt').writeAsString('keep');
    await Directory('${payload.path}\\data').create();
    await File('${payload.path}\\data\\app.so').writeAsString('payload');
    if (includeExecutable) {
      await File('${payload.path}\\niraN.exe').writeAsString('new');
    }
    final archive = File('${work.path}\\niraN-0.3.3-windows-x64.zip');
    final zipped = await Process.run('powershell.exe', [
      '-NoLogo',
      '-NoProfile',
      '-NonInteractive',
      '-Command',
      "Add-Type -AssemblyName System.IO.Compression.FileSystem; [IO.Compression.ZipFile]::CreateFromDirectory('${payload.path}', '${archive.path}', [IO.Compression.CompressionLevel]::Optimal, \$true)",
    ]);
    if (zipped.exitCode != 0) {
      throw StateError('Could not create update fixture: ${zipped.stderr}');
    }
    await payload.delete(recursive: true);
    final plan = PortableUpdatePlan(
      processId: 0,
      archivePath: archive.path,
      installDirectory: install.path,
      workDirectory: work.path,
      version: '0.3.3',
    );
    final script = File(plan.scriptPath);
    await script.writeAsString(plan.buildScript());
    return _UpdateFixture(
      root: root,
      install: install,
      work: work,
      archive: archive,
      script: script,
    );
  }

  List<String> arguments({
    bool simulateRenameFailure = false,
    int holdMutexMilliseconds = 0,
  }) => [
    '-NoLogo',
    '-NoProfile',
    '-NonInteractive',
    '-ExecutionPolicy',
    'Bypass',
    '-File',
    script.path,
    '-SkipRestart',
    if (simulateRenameFailure) '-SimulateRenameFailure',
    if (holdMutexMilliseconds > 0) ...[
      '-HoldMutexMilliseconds',
      '$holdMutexMilliseconds',
    ],
  ];

  Future<ProcessResult> run({bool simulateRenameFailure = false}) =>
      Process.run(
        'powershell.exe',
        arguments(simulateRenameFailure: simulateRenameFailure),
        workingDirectory: work.path,
      );

  Future<void> dispose() async {
    if (await root.exists()) await root.delete(recursive: true);
  }
}

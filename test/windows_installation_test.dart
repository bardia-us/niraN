import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:niran/core/windows_installation.dart';

void main() {
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('niran-install-type-');
  });

  tearDown(() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  test('setup marker identifies an installed copy', () async {
    await File(
      '${directory.path}${Platform.pathSeparator}${NativeWindowsInstallationProbe.setupMarkerName}',
    ).writeAsString('setup');
    final probe = NativeWindowsInstallationProbe(
      executableDirectory: directory,
      registryInstallLocation: () async => null,
    );

    expect(await probe.detect(), WindowsInstallationType.setup);
  });

  test(
    'matching uninstall registration and uninstaller identify setup',
    () async {
      await File(
        '${directory.path}${Platform.pathSeparator}unins000.exe',
      ).writeAsBytes(const [1]);
      final probe = NativeWindowsInstallationProbe(
        executableDirectory: directory,
        registryInstallLocation: () async => '${directory.path}\\',
      );

      expect(await probe.detect(), WindowsInstallationType.setup);
    },
  );

  test('mismatched or incomplete registration remains portable', () async {
    await File(
      '${directory.path}${Platform.pathSeparator}unins000.exe',
    ).writeAsBytes(const [1]);
    final probe = NativeWindowsInstallationProbe(
      executableDirectory: directory,
      registryInstallLocation: () async => '${directory.path}-other',
    );

    expect(await probe.detect(), WindowsInstallationType.portable);
  });
}

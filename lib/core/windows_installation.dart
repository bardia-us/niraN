import 'dart:io';

enum WindowsInstallationType { portable, setup }

abstract interface class WindowsInstallationProbe {
  Future<WindowsInstallationType> detect();
}

final class NativeWindowsInstallationProbe implements WindowsInstallationProbe {
  NativeWindowsInstallationProbe({
    Directory? executableDirectory,
    Future<String?> Function()? registryInstallLocation,
  }) : _executableDirectory =
           executableDirectory ?? File(Platform.resolvedExecutable).parent,
       _registryInstallLocation =
           registryInstallLocation ?? _readRegistryInstallLocation;

  static const setupMarkerName = '.niran-setup-install';
  static const uninstallRegistryKey =
      r'HKCU\Software\Microsoft\Windows\CurrentVersion\Uninstall\{E6E8B457-32B6-4B93-BB91-AB9242BF54E4}_is1';

  final Directory _executableDirectory;
  final Future<String?> Function() _registryInstallLocation;

  @override
  Future<WindowsInstallationType> detect() async {
    if (await File(
      '${_executableDirectory.path}${Platform.pathSeparator}$setupMarkerName',
    ).exists()) {
      return WindowsInstallationType.setup;
    }
    final registryLocation = await _registryInstallLocation();
    if (registryLocation == null ||
        _normalized(registryLocation) !=
            _normalized(_executableDirectory.absolute.path)) {
      return WindowsInstallationType.portable;
    }
    final uninstallerStream = _executableDirectory.list().where(
      (entity) =>
          entity is File &&
          RegExp(
            r'^unins\d*\.exe$',
            caseSensitive: false,
          ).hasMatch(entity.uri.pathSegments.last),
    );
    final hasUninstaller = !(await uninstallerStream.isEmpty);
    return hasUninstaller
        ? WindowsInstallationType.setup
        : WindowsInstallationType.portable;
  }

  static Future<String?> _readRegistryInstallLocation() async {
    try {
      final result = await Process.run('reg.exe', [
        'query',
        uninstallRegistryKey,
        '/v',
        'InstallLocation',
      ]);
      if (result.exitCode != 0) return null;
      return RegExp(
        r'^\s*InstallLocation\s+REG_(?:EXPAND_)?SZ\s+(.+?)\s*$',
        multiLine: true,
        caseSensitive: false,
      ).firstMatch('${result.stdout}')?.group(1)?.trim();
    } on Object {
      return null;
    }
  }

  static String _normalized(String value) {
    var normalized = value.trim().replaceAll('/', r'\').toLowerCase();
    while (normalized.endsWith(r'\')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    return normalized;
  }
}

final class FixedWindowsInstallationProbe implements WindowsInstallationProbe {
  const FixedWindowsInstallationProbe(this.type);

  final WindowsInstallationType type;

  @override
  Future<WindowsInstallationType> detect() async => type;
}

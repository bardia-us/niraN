import 'dart:io';

abstract interface class AutoStartController {
  Future<void> setEnabled(bool enabled);
}

final class WindowsAutoStartController implements AutoStartController {
  WindowsAutoStartController({String? executablePath})
    : _executablePath = executablePath ?? Platform.resolvedExecutable;

  static const _runKey = r'HKCU\Software\Microsoft\Windows\CurrentVersion\Run';
  final String _executablePath;

  static String commandValue(String executablePath) => '"$executablePath"';

  @override
  Future<void> setEnabled(bool enabled) async {
    if (!enabled) {
      final query = await Process.run('reg.exe', [
        'query',
        _runKey,
        '/v',
        'niraN',
      ]);
      if (query.exitCode == 1) return;
      if (query.exitCode != 0) {
        throw FileSystemException(
          'Could not inspect Windows auto-start',
          _executablePath,
        );
      }
    }
    final result = await Process.run('reg.exe', [
      enabled ? 'add' : 'delete',
      _runKey,
      '/v',
      'niraN',
      if (enabled) ...['/t', 'REG_SZ', '/d', commandValue(_executablePath)],
      '/f',
    ]);
    if (result.exitCode != 0) {
      throw FileSystemException(
        enabled
            ? 'Could not enable Windows auto-start'
            : 'Could not disable Windows auto-start',
        _executablePath,
      );
    }
  }
}

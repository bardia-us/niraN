import 'dart:convert';
import 'dart:io';

import 'update_checker.dart';

/// Persistent Windows release lifecycle state.
///
/// A fresh install records the current version as already seen. Only a real
/// upgrade from an older installed version is eligible for What's New.
final class WindowsReleaseState {
  WindowsReleaseState({Directory? directory})
    : _directory = directory ?? _defaultDirectory();

  final Directory _directory;

  File get _file =>
      File('${_directory.path}${Platform.pathSeparator}release-state.json');

  Future<bool> shouldShowWhatsNew(String currentVersion) async {
    final current = SemanticVersion.parse(currentVersion);
    final stored = await _read();
    final previousText = '${stored['installed_version'] ?? ''}';
    if (previousText.isEmpty) {
      await _write({
        'installed_version': current.toString(),
        'seen_version': current.toString(),
      });
      return false;
    }

    SemanticVersion previous;
    try {
      previous = SemanticVersion.parse(previousText);
    } on FormatException {
      await _write({
        'installed_version': current.toString(),
        'seen_version': current.toString(),
      });
      return false;
    }

    final upgraded = current.compareTo(previous) > 0;
    if (upgraded) {
      await _write({
        ...stored,
        'installed_version': current.toString(),
        'upgraded_from_version': previous.toString(),
      });
    } else if (current.compareTo(previous) != 0) {
      await _write({...stored, 'installed_version': current.toString()});
    }
    return upgraded && '${stored['seen_version'] ?? ''}' != current.toString();
  }

  Future<void> markSeen(String version) async {
    final normalized = SemanticVersion.parse(version).toString();
    await _write({
      ...await _read(),
      'installed_version': normalized,
      'seen_version': normalized,
    });
  }

  Future<Map<String, Object?>> _read() async {
    if (!await _file.exists()) return <String, Object?>{};
    try {
      final decoded = jsonDecode(await _file.readAsString());
      if (decoded is Map) {
        return decoded.map((key, value) => MapEntry('$key', value));
      }
    } on Object {
      // A damaged optional release-state file must never block startup.
    }
    return <String, Object?>{};
  }

  Future<void> _write(Map<String, Object?> value) async {
    await _directory.create(recursive: true);
    final temporary = File('${_file.path}.tmp');
    await temporary.writeAsString(jsonEncode(value), flush: true);
    if (await _file.exists()) await _file.delete();
    await temporary.rename(_file.path);
  }

  static Directory _defaultDirectory() {
    final localAppData = Platform.environment['LOCALAPPDATA'];
    return Directory(
      localAppData == null || localAppData.trim().isEmpty
          ? '${Directory.systemTemp.path}${Platform.pathSeparator}niraN'
          : '$localAppData${Platform.pathSeparator}niraN',
    );
  }
}

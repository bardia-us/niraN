import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import 'update_checker.dart';

enum UpdateDownloadStatus { idle, downloading, paused, ready, failed }

@immutable
class UpdateDownloadSnapshot {
  const UpdateDownloadSnapshot({
    this.status = UpdateDownloadStatus.idle,
    this.version = '',
    this.fileName = '',
    this.received = 0,
    this.total = 0,
    this.error,
  });
  final UpdateDownloadStatus status;
  final String version;
  final String fileName;
  final int received;
  final int total;
  final String? error;
  double? get progress => total > 0 ? (received / total).clamp(0, 1) : null;
}

/// Process-wide Windows downloader. Its lifetime is independent from dialogs
/// and it persists enough metadata to resume a partial GitHub asset next run.
final class WindowsUpdateManager extends ChangeNotifier {
  WindowsUpdateManager._();
  static final instance = WindowsUpdateManager._();
  static bool isSupportedWindowsAssetName(String name) =>
      RegExp(
        r'^niraN-(?:v)?\d+\.\d+\.\d+-windows-x64\.(zip|exe|msix)$',
        caseSensitive: false,
      ).hasMatch(name) &&
      !name.contains(RegExp(r'[\\/]'));

  UpdateDownloadSnapshot snapshot = const UpdateDownloadSnapshot();
  ReleaseAsset? _asset;
  HttpClientRequest? _request;
  Future<void>? _task;
  bool _pauseRequested = false;
  int _lastNotifiedBytes = 0;
  DateTime _lastNotifiedAt = DateTime.fromMillisecondsSinceEpoch(0);

  Directory get _directory {
    final root = Platform.environment['LOCALAPPDATA'];
    return Directory(
      '${root?.trim().isNotEmpty == true ? root : Directory.systemTemp.path}${Platform.pathSeparator}niraN${Platform.pathSeparator}updates',
    );
  }

  File get _stateFile =>
      File('${_directory.path}${Platform.pathSeparator}download.json');
  File get _partialFile => File(
    '${_directory.path}${Platform.pathSeparator}${snapshot.fileName}.part',
  );
  File get _completeFile =>
      File('${_directory.path}${Platform.pathSeparator}${snapshot.fileName}');

  Future<void> initialize(String currentVersion) async {
    await _directory.create(recursive: true);
    if (!await _stateFile.exists()) {
      await _cleanupUnknown();
      return;
    }
    try {
      final data =
          jsonDecode(await _stateFile.readAsString()) as Map<String, dynamic>;
      final version = '${data['version'] ?? ''}';
      if (SemanticVersion.parse(
            version,
          ).compareTo(SemanticVersion.parse(currentVersion)) <=
          0) {
        await delete();
        return;
      }
      final url = Uri.parse('${data['url']}');
      final name = '${data['fileName']}';
      if (!_safeAsset(url, name)) {
        throw const FormatException('Unsafe update metadata');
      }
      _asset = ReleaseAsset(
        name: name,
        url: url,
        size: (data['total'] as num?)?.toInt() ?? 0,
        sha256: data['sha256']?.toString(),
      );
      final complete = File('${_directory.path}${Platform.pathSeparator}$name');
      final partial = File('${complete.path}.part');
      final ready = await complete.exists();
      snapshot = UpdateDownloadSnapshot(
        status: ready
            ? UpdateDownloadStatus.ready
            : UpdateDownloadStatus.paused,
        version: version,
        fileName: name,
        received: ready
            ? await complete.length()
            : await partial.exists()
            ? await partial.length()
            : 0,
        total: _asset!.size,
      );
      notifyListeners();
    } on Object {
      await delete();
    }
    await _cleanupUnknown();
  }

  Future<void> start(ReleaseAsset asset, SemanticVersion version) async {
    if (_task != null) return;
    if (!_safeAsset(asset.url, asset.name)) {
      throw const FormatException('Unsafe update asset');
    }
    if (asset.size <= 0 || asset.sha256 == null) {
      throw const FormatException(
        'Release asset has no verifiable size/SHA-256',
      );
    }
    if (_asset?.url != asset.url || snapshot.version != '$version') {
      await delete();
    }
    _asset = asset;
    snapshot = UpdateDownloadSnapshot(
      status: UpdateDownloadStatus.downloading,
      version: '$version',
      fileName: asset.name,
      received: await _existingPartial(asset.name),
      total: asset.size,
    );
    _pauseRequested = false;
    await _persist();
    notifyListeners();
    late final Future<void> task;
    task = _download().whenComplete(() {
      if (identical(_task, task)) _task = null;
    });
    _task = task;
  }

  Future<void> resume() async {
    final asset = _asset;
    if (asset == null) return;
    await start(asset, SemanticVersion.parse(snapshot.version));
  }

  Future<void> pause() async {
    _pauseRequested = true;
    _request?.abort();
    snapshot = UpdateDownloadSnapshot(
      status: UpdateDownloadStatus.paused,
      version: snapshot.version,
      fileName: snapshot.fileName,
      received: snapshot.received,
      total: snapshot.total,
    );
    await _persist();
    notifyListeners();
  }

  Future<void> delete() async {
    _pauseRequested = true;
    _request?.abort();
    if (await _directory.exists()) {
      await for (final entity in _directory.list()) {
        if (entity is File &&
            (entity.path.endsWith('.part') ||
                entity.path.endsWith('.zip') ||
                entity.path.endsWith('.exe') ||
                entity.path.endsWith('.msix') ||
                entity.path.endsWith('download.json'))) {
          try {
            await entity.delete();
          } on Object {
            // Cleanup is best-effort; a running installer may hold the file.
          }
        }
      }
    }
    _asset = null;
    snapshot = const UpdateDownloadSnapshot();
    notifyListeners();
  }

  /// Returns true when the portable ZIP updater was started and niraN must
  /// exit so its files can be replaced safely.
  Future<bool> launch() async {
    if (snapshot.status != UpdateDownloadStatus.ready ||
        !await _completeFile.exists()) {
      throw StateError('Update file is not ready');
    }
    final asset = _asset;
    if (asset == null ||
        await _completeFile.length() != asset.size ||
        asset.sha256 == null ||
        (await sha256.bind(_completeFile.openRead()).first)
                .toString()
                .toLowerCase() !=
            asset.sha256!.toLowerCase()) {
      await delete();
      throw const FormatException(
        'Stored update failed size/SHA-256 verification',
      );
    }
    final ext = snapshot.fileName.toLowerCase();
    if (ext.endsWith('.exe')) {
      await Process.start(
        _completeFile.path,
        const [],
        mode: ProcessStartMode.detached,
      );
      return false;
    } else if (ext.endsWith('.zip')) {
      final script = File(
        '${_directory.path}${Platform.pathSeparator}install-update.ps1',
      );
      final destination = File(Platform.resolvedExecutable).parent.path;
      final staging =
          '${_directory.path}${Platform.pathSeparator}staging-${snapshot.version}';
      final executable = '$destination${Platform.pathSeparator}niraN.exe';
      await script.writeAsString('''
\$ErrorActionPreference = 'Stop'
Wait-Process -Id $pid -Timeout 60 -ErrorAction SilentlyContinue
Start-Sleep -Milliseconds 400
if (Test-Path -LiteralPath '${_ps(staging)}') { Remove-Item -LiteralPath '${_ps(staging)}' -Recurse -Force }
Expand-Archive -LiteralPath '${_ps(_completeFile.path)}' -DestinationPath '${_ps(staging)}' -Force
\$candidate = Get-ChildItem -LiteralPath '${_ps(staging)}' -Filter 'niraN.exe' -Recurse -File | Select-Object -First 1
if (\$null -eq \$candidate) { throw 'The update archive does not contain niraN.exe' }
Copy-Item -Path (Join-Path \$candidate.Directory.FullName '*') -Destination '${_ps(destination)}' -Recurse -Force
Start-Process -FilePath '${_ps(executable)}'
Remove-Item -LiteralPath '${_ps(_completeFile.path)}' -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath '${_ps(staging)}' -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath \$PSCommandPath -Force -ErrorAction SilentlyContinue
''', flush: true);
      await Process.start('powershell.exe', [
        '-NoLogo',
        '-NoProfile',
        '-NonInteractive',
        '-ExecutionPolicy',
        'Bypass',
        '-File',
        script.path,
      ], mode: ProcessStartMode.detached);
      return true;
    } else {
      await Process.start('explorer.exe', [
        _completeFile.path,
      ], mode: ProcessStartMode.detached);
      return false;
    }
  }

  Future<void> _download() async {
    final asset = _asset!;
    final partial = _partialFile;
    var existing = await _existingPartial(asset.name);
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    try {
      final request = await client.getUrl(asset.url);
      _request = request;
      request.headers.set(HttpHeaders.userAgentHeader, 'niraN-updater/0.3.3');
      if (existing > 0) {
        request.headers.set(HttpHeaders.rangeHeader, 'bytes=$existing-');
      }
      final response = await request.close().timeout(
        const Duration(seconds: 30),
      );
      if (existing > 0 && response.statusCode != HttpStatus.partialContent) {
        existing = 0;
        if (await partial.exists()) await partial.delete();
      }
      if (response.statusCode != HttpStatus.ok &&
          response.statusCode != HttpStatus.partialContent) {
        throw HttpException('Download failed (${response.statusCode})');
      }
      final sink = partial.openWrite(
        mode: existing > 0 ? FileMode.append : FileMode.write,
      );
      var received = existing;
      try {
        await for (final chunk in response) {
          sink.add(chunk);
          received += chunk.length;
          _progress(received, asset.size);
        }
      } finally {
        await sink.flush();
        await sink.close();
      }
      if (_pauseRequested) return;
      final length = await partial.length();
      if (length != asset.size) {
        throw const FormatException(
          'Downloaded file size does not match release asset',
        );
      }
      final digest = (await sha256.bind(partial.openRead()).first).toString();
      if (digest.toLowerCase() != asset.sha256!.toLowerCase()) {
        throw const FormatException(
          'Downloaded file SHA-256 verification failed',
        );
      }
      if (await _completeFile.exists()) await _completeFile.delete();
      await partial.rename(_completeFile.path);
      snapshot = UpdateDownloadSnapshot(
        status: UpdateDownloadStatus.ready,
        version: snapshot.version,
        fileName: snapshot.fileName,
        received: length,
        total: asset.size,
      );
      await _persist();
      notifyListeners();
    } on Object catch (error) {
      if (!_pauseRequested) {
        snapshot = UpdateDownloadSnapshot(
          status: UpdateDownloadStatus.failed,
          version: snapshot.version,
          fileName: snapshot.fileName,
          received: await partial.exists() ? await partial.length() : 0,
          total: asset.size,
          error: '$error',
        );
        await _persist();
        notifyListeners();
      }
    } finally {
      _request = null;
      client.close(force: true);
    }
  }

  void _progress(int received, int total) {
    snapshot = UpdateDownloadSnapshot(
      status: UpdateDownloadStatus.downloading,
      version: snapshot.version,
      fileName: snapshot.fileName,
      received: received,
      total: total,
    );
    final now = DateTime.now();
    if (received - _lastNotifiedBytes >= 512 * 1024 ||
        now.difference(_lastNotifiedAt) > const Duration(milliseconds: 350)) {
      _lastNotifiedBytes = received;
      _lastNotifiedAt = now;
      unawaited(_persist());
      notifyListeners();
    }
  }

  Future<int> _existingPartial(String name) async {
    final f = File('${_directory.path}${Platform.pathSeparator}$name.part');
    return await f.exists() ? await f.length() : 0;
  }

  bool _safeAsset(Uri url, String name) =>
      url.scheme == 'https' &&
      const {
        'github.com',
        'objects.githubusercontent.com',
        'github-releases.githubusercontent.com',
      }.contains(url.host) &&
      isSupportedWindowsAssetName(name);
  String _ps(String value) => value.replaceAll("'", "''");
  Future<void> _persist() async {
    final a = _asset;
    if (a == null) return;
    await _directory.create(recursive: true);
    await _stateFile.writeAsString(
      jsonEncode({
        'version': snapshot.version,
        'fileName': snapshot.fileName,
        'url': '${a.url}',
        'total': a.size,
        'sha256': a.sha256,
      }),
      flush: true,
    );
  }

  Future<void> _cleanupUnknown() async {
    if (!await _directory.exists()) return;
    final keep = {_stateFile.path, _partialFile.path, _completeFile.path};
    await for (final e in _directory.list()) {
      if (e is File && !keep.contains(e.path)) {
        try {
          await e.delete();
        } on Object {
          // Cleanup is best-effort; never break startup for a locked file.
        }
      }
    }
  }
}

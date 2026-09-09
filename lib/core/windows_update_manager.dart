import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import 'portable_update_script.dart';
import 'setup_update_script.dart';
import 'update_checker.dart';
import 'windows_installation.dart';

enum UpdateDownloadStatus {
  idle,
  downloading,
  paused,
  cancelled,
  downloaded,
  verifying,
  readyToUpdate,
  closingApp,
  extracting,
  replacingFiles,
  renamingFolder,
  restarting,
  updateCompleted,
  updateFailed,
  failed,
}

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

/// Process-wide, resumable Windows updater. Download ownership is independent
/// from dialogs and only one network task can mutate its files at a time.
final class WindowsUpdateManager extends ChangeNotifier {
  WindowsUpdateManager._({
    Directory? directory,
    Set<String>? allowedHosts,
    bool allowHttp = false,
    WindowsInstallationProbe? installationProbe,
  }) : _directoryOverride = directory,
       _allowedHosts = allowedHosts ?? _productionHosts,
       _allowHttp = allowHttp,
       _installationProbe =
           installationProbe ?? NativeWindowsInstallationProbe();

  static final instance = WindowsUpdateManager._();

  @visibleForTesting
  factory WindowsUpdateManager.forTesting({
    required Directory directory,
    Set<String> allowedHosts = const {'127.0.0.1', 'localhost'},
    WindowsInstallationType installationType = WindowsInstallationType.portable,
  }) => WindowsUpdateManager._(
    directory: directory,
    allowedHosts: allowedHosts,
    allowHttp: true,
    installationProbe: FixedWindowsInstallationProbe(installationType),
  );

  static const _productionHosts = {
    'github.com',
    'objects.githubusercontent.com',
    'github-releases.githubusercontent.com',
    'release-assets.githubusercontent.com',
  };
  static const _downloadBufferSize = 256 * 1024;
  static const _maximumRedirects = 5;
  static const _downloadsKnownFolderId =
      '{374DE290-123F-4565-9164-39C4925E467B}';

  static bool isSupportedWindowsAssetName(String name) =>
      ReleaseAsset.packageFromName(name) != null &&
      !name.contains(RegExp(r'[\\/]'));

  UpdateDownloadSnapshot snapshot = const UpdateDownloadSnapshot();
  ReleaseAsset? _asset;
  HttpClientRequest? _request;
  Future<void>? _task;
  Directory? _resolvedDirectory;
  final Directory? _directoryOverride;
  final Set<String> _allowedHosts;
  final bool _allowHttp;
  final WindowsInstallationProbe _installationProbe;
  WindowsInstallationType? _installationType;
  int _generation = 0;
  int _focusRequest = 0;
  bool _launching = false;
  int _lastNotifiedBytes = 0;
  DateTime _lastNotifiedAt = DateTime.fromMillisecondsSinceEpoch(0);

  bool get isActive =>
      snapshot.status == UpdateDownloadStatus.downloading ||
      snapshot.status == UpdateDownloadStatus.verifying;

  int get focusRequest => _focusRequest;

  Future<WindowsInstallationType> get installationType async =>
      _installationType ??= await _installationProbe.detect();

  Future<ReleaseAsset?> assetFor(ReleaseCheckResult release) async {
    final type = await installationType;
    return release.assetFor(
      type == WindowsInstallationType.setup
          ? WindowsUpdatePackage.setupExe
          : WindowsUpdatePackage.portableZip,
    );
  }

  void requestManagerFocus() {
    _focusRequest++;
    notifyListeners();
  }

  bool get isInstalling => switch (snapshot.status) {
    UpdateDownloadStatus.closingApp ||
    UpdateDownloadStatus.extracting ||
    UpdateDownloadStatus.replacingFiles ||
    UpdateDownloadStatus.renamingFolder ||
    UpdateDownloadStatus.restarting => true,
    _ => false,
  };

  @visibleForTesting
  Future<void> get activeTask => _task ?? Future<void>.value();

  Future<void> initialize(String currentVersion) async {
    final directory = await _directory();
    await directory.create(recursive: true);
    await _cleanupLegacyDirectory(directory);
    final stateFile = _stateFile(directory);
    if (!await stateFile.exists()) {
      await _cleanupUnknown(directory);
      return;
    }
    try {
      final data =
          jsonDecode(await stateFile.readAsString()) as Map<String, dynamic>;
      final version = '${data['version'] ?? ''}';
      final helperResult = await _readHelperResult(directory, version);
      if (SemanticVersion.parse(
            version,
          ).compareTo(SemanticVersion.parse(currentVersion)) <=
          0) {
        if (helperResult?.state == 'completed') {
          snapshot = UpdateDownloadSnapshot(
            status: UpdateDownloadStatus.updateCompleted,
            version: version,
            fileName: '${data['fileName'] ?? ''}',
            received: (data['total'] as num?)?.toInt() ?? 0,
            total: (data['total'] as num?)?.toInt() ?? 0,
          );
          await _cleanupCompletedArtifacts(directory);
          notifyListeners();
          return;
        }
        await delete();
        return;
      }
      final url = Uri.parse('${data['url']}');
      final name = '${data['fileName']}';
      if (!_safeAsset(url, name)) {
        throw const FormatException('Unsafe update metadata');
      }
      final restoredAsset = ReleaseAsset(
        name: name,
        url: url,
        size: (data['total'] as num?)?.toInt() ?? 0,
        sha256: data['sha256']?.toString(),
      );
      if (!await _assetMatchesInstallation(restoredAsset)) {
        throw const FormatException(
          'Stored update does not match this installation type',
        );
      }
      _asset = restoredAsset;
      final complete = _completeFile(directory, name);
      final partial = _partialFile(directory, name);
      final completeExists = await complete.exists();
      final savedStatus = '${data['status'] ?? ''}';
      snapshot = UpdateDownloadSnapshot(
        status: helperResult?.state == 'failed'
            ? UpdateDownloadStatus.updateFailed
            : completeExists
            ? UpdateDownloadStatus.readyToUpdate
            : savedStatus == UpdateDownloadStatus.cancelled.name
            ? UpdateDownloadStatus.cancelled
            : UpdateDownloadStatus.paused,
        version: version,
        fileName: name,
        received: completeExists
            ? await complete.length()
            : await partial.exists()
            ? await partial.length()
            : 0,
        total: _asset!.size,
        error: helperResult?.state == 'failed' ? helperResult?.message : null,
      );
      notifyListeners();
    } on Object {
      await delete();
    }
    await _cleanupUnknown(directory);
  }

  Future<void> start(ReleaseAsset asset, SemanticVersion version) async {
    if (!_safeAsset(asset.url, asset.name)) {
      throw const FormatException('Unsafe update asset');
    }
    if (asset.version?.compareTo(version) != 0 ||
        !await _assetMatchesInstallation(asset)) {
      throw const FormatException(
        'Update package does not match this installation',
      );
    }
    if (asset.size <= 0 || asset.sha256 == null) {
      throw const FormatException(
        'Release asset has no verifiable size/SHA-256',
      );
    }
    if (isActive) return;
    await _waitForPreviousTask();
    if (_task != null) return;
    if (_asset?.url != asset.url || snapshot.version != '$version') {
      await delete();
    }
    final directory = await _directory();
    await directory.create(recursive: true);
    _asset = asset;
    final partial = _partialFile(directory, asset.name);
    var existing = await partial.exists() ? await partial.length() : 0;
    if (existing >= asset.size) {
      await partial.delete();
      existing = 0;
    }
    final generation = ++_generation;
    snapshot = UpdateDownloadSnapshot(
      status: UpdateDownloadStatus.downloading,
      version: '$version',
      fileName: asset.name,
      received: existing,
      total: asset.size,
    );
    await _persist(directory);
    notifyListeners();
    late final Future<void> task;
    task = _download(generation, directory).whenComplete(() {
      if (identical(_task, task)) _task = null;
    });
    _task = task;
  }

  /// Returns true only when the complete APK-equivalent archive belongs to
  /// the exact latest release and still matches GitHub's size and SHA-256.
  /// A download for an older release is never offered for installation.
  Future<bool> hasVerifiedDownload(
    ReleaseAsset asset,
    SemanticVersion version,
  ) async {
    if (!_safeAsset(asset.url, asset.name) ||
        asset.version?.compareTo(version) != 0 ||
        !await _assetMatchesInstallation(asset) ||
        asset.size <= 0 ||
        asset.sha256 == null ||
        snapshot.version != '$version' ||
        snapshot.fileName != asset.name) {
      return false;
    }
    final directory = await _directory();
    final complete = _completeFile(directory, asset.name);
    if (!await complete.exists() || await complete.length() != asset.size) {
      return false;
    }
    final digest = (await sha256.bind(complete.openRead()).first).toString();
    if (digest.toLowerCase() != asset.sha256!.toLowerCase()) return false;
    _asset = asset;
    snapshot = UpdateDownloadSnapshot(
      status: UpdateDownloadStatus.readyToUpdate,
      version: '$version',
      fileName: asset.name,
      received: asset.size,
      total: asset.size,
    );
    await _persist(directory);
    notifyListeners();
    return true;
  }

  Future<void> resume() async {
    final asset = _asset;
    if (asset == null || isActive) return;
    await start(asset, SemanticVersion.parse(snapshot.version));
  }

  Future<void> pause() async {
    if (snapshot.status != UpdateDownloadStatus.downloading) return;
    ++_generation;
    _request?.abort();
    snapshot = UpdateDownloadSnapshot(
      status: UpdateDownloadStatus.paused,
      version: snapshot.version,
      fileName: snapshot.fileName,
      received: snapshot.received,
      total: snapshot.total,
    );
    await _persist(await _directory());
    notifyListeners();
  }

  Future<void> cancel() async {
    if (snapshot.status != UpdateDownloadStatus.downloading) return;
    ++_generation;
    _request?.abort();
    snapshot = UpdateDownloadSnapshot(
      status: UpdateDownloadStatus.cancelled,
      version: snapshot.version,
      fileName: snapshot.fileName,
      received: snapshot.received,
      total: snapshot.total,
    );
    await _persist(await _directory());
    notifyListeners();
  }

  /// Deletes only inactive updater-owned files. Active downloads must first be
  /// paused or cancelled, preventing late callbacks from recreating files.
  Future<void> delete() async {
    if (isActive || isInstalling || _task != null || _launching) return;
    ++_generation;
    final directory = await _directory();
    if (await directory.exists()) {
      await for (final entity in directory.list()) {
        if (entity is File && _isUpdaterOwned(entity.path)) {
          try {
            await entity.delete();
          } on Object {
            // Cleanup is best-effort; an installer may hold the file.
          }
        } else if (entity is Directory &&
            _isUpdaterOwnedDirectory(entity.path)) {
          try {
            await entity.delete(recursive: true);
          } on Object {
            // Cleanup is best-effort.
          }
        }
      }
    }
    _asset = null;
    snapshot = const UpdateDownloadSnapshot();
    notifyListeners();
  }

  Future<void> openFolder() async {
    final directory = await _directory();
    await directory.create(recursive: true);
    final completed = snapshot.fileName.isEmpty
        ? null
        : _completeFile(directory, snapshot.fileName);
    if (completed != null && await completed.exists()) {
      await Process.start('explorer.exe', [
        '/select,',
        completed.path,
      ], mode: ProcessStartMode.detached);
    } else {
      await Process.start('explorer.exe', [
        directory.path,
      ], mode: ProcessStartMode.detached);
    }
  }

  /// Returns true when the matching update helper was started and niraN must
  /// exit so the portable bundle or setup installation can be upgraded.
  Future<bool> launch() async {
    if (_launching) throw StateError('Update is already starting');
    _launching = true;
    try {
      return await _launchInternal();
    } finally {
      _launching = false;
    }
  }

  Future<bool> _launchInternal() async {
    final directory = await _directory();
    final complete = _completeFile(directory, snapshot.fileName);
    if (snapshot.status != UpdateDownloadStatus.readyToUpdate &&
            snapshot.status != UpdateDownloadStatus.updateFailed ||
        !await complete.exists()) {
      throw StateError('Update file is not ready');
    }
    final asset = _asset;
    final valid =
        asset != null &&
        await complete.length() == asset.size &&
        asset.sha256 != null &&
        (await sha256.bind(complete.openRead()).first)
                .toString()
                .toLowerCase() ==
            asset.sha256!.toLowerCase();
    if (!valid) {
      try {
        await complete.delete();
      } on Object {
        // The failed file remains deletable from Settings if currently locked.
      }
      snapshot = UpdateDownloadSnapshot(
        status: UpdateDownloadStatus.failed,
        version: snapshot.version,
        fileName: snapshot.fileName,
        total: snapshot.total,
        error: 'Stored update failed size/SHA-256 verification',
      );
      await _persist(directory);
      notifyListeners();
      throw const FormatException(
        'Stored update failed size/SHA-256 verification',
      );
    }
    if (!await _assetMatchesInstallation(asset)) {
      throw const FormatException(
        'Stored update does not match this installation type',
      );
    }
    final ext = snapshot.fileName.toLowerCase();
    if (ext.endsWith('.exe')) {
      final plan = SetupUpdatePlan(
        processId: pid,
        installerPath: complete.path,
        installDirectory: File(Platform.resolvedExecutable).parent.path,
        workDirectory: directory.path,
        version: snapshot.version,
      );
      final script = File(plan.scriptPath);
      await script.writeAsString(plan.buildScript(), flush: true);
      final helperResult = _resultFile(directory);
      if (await helperResult.exists()) await helperResult.delete();
      snapshot = UpdateDownloadSnapshot(
        status: UpdateDownloadStatus.closingApp,
        version: snapshot.version,
        fileName: snapshot.fileName,
        received: snapshot.received,
        total: snapshot.total,
      );
      await _persist(directory);
      notifyListeners();
      final helper = await _startUpdateHelper(script, directory);
      final helperError = StringBuffer();
      unawaited(helper.stdout.drain<void>());
      helper.stderr.transform(utf8.decoder).listen(helperError.write);
      final launchError = await _waitForHelperStartup(
        directory,
        snapshot.version,
        helper,
        helperError,
      );
      if (launchError != null) {
        await _recordLaunchFailure(directory, launchError);
        throw StateError(
          '$launchError '
          'The app was kept open and the verified setup was preserved.',
        );
      }
      return true;
    }
    if (ext.endsWith('.zip')) {
      final plan = PortableUpdatePlan(
        processId: pid,
        archivePath: complete.path,
        installDirectory: File(Platform.resolvedExecutable).parent.path,
        workDirectory: directory.path,
        version: snapshot.version,
      );
      final script = File(plan.scriptPath);
      await script.writeAsString(plan.buildScript(), flush: true);
      // Do not let a stale result from an earlier attempt satisfy the launch
      // handshake. The helper writes a fresh `closingApp` state before it
      // starts waiting for this process to exit.
      final helperResult = _resultFile(directory);
      if (await helperResult.exists()) {
        await helperResult.delete();
      }
      snapshot = UpdateDownloadSnapshot(
        status: UpdateDownloadStatus.closingApp,
        version: snapshot.version,
        fileName: snapshot.fileName,
        received: snapshot.received,
        total: snapshot.total,
      );
      await _persist(directory);
      notifyListeners();
      final helper = await _startUpdateHelper(script, directory);
      unawaited(helper.stdout.drain<void>());
      final helperError = StringBuffer();
      helper.stderr.transform(utf8.decoder).listen(helperError.write);
      final launchError = await _waitForHelperStartup(
        directory,
        snapshot.version,
        helper,
        helperError,
      );
      if (launchError != null) {
        await _recordLaunchFailure(directory, launchError);
        throw StateError(
          '$launchError '
          'The app was kept open and the downloaded ZIP was preserved.',
        );
      }
      return true;
    }
    await openFolder();
    return false;
  }

  Future<Process> _startUpdateHelper(File script, Directory directory) =>
      Process.start(
        'powershell.exe',
        [
          '-NoLogo',
          '-NoProfile',
          '-NonInteractive',
          '-WindowStyle',
          'Hidden',
          '-ExecutionPolicy',
          'Bypass',
          '-File',
          script.path,
        ],
        // Keep the helper observable until it confirms startup. The app exits
        // only after this handshake, so a failed helper cannot strand users.
        mode: ProcessStartMode.normal,
        workingDirectory: directory.path,
      );

  Future<void> _recordLaunchFailure(
    Directory directory,
    String launchError,
  ) async {
    snapshot = UpdateDownloadSnapshot(
      status: UpdateDownloadStatus.updateFailed,
      version: snapshot.version,
      fileName: snapshot.fileName,
      received: snapshot.received,
      total: snapshot.total,
      error: launchError,
    );
    await _persist(directory);
    notifyListeners();
  }

  Future<String?> _waitForHelperStartup(
    Directory directory,
    String version,
    Process helper,
    StringBuffer helperError,
  ) async {
    int? exitCode;
    unawaited(helper.exitCode.then((value) => exitCode = value));
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (DateTime.now().isBefore(deadline)) {
      final result = await _readHelperResult(directory, version);
      if (result != null) {
        if (result.state == 'closingApp') return null;
        return result.message.isEmpty
            ? 'The update helper reported ${result.state}.'
            : result.message;
      }
      if (exitCode != null) {
        final detail = helperError.toString().trim();
        return detail.isEmpty
            ? 'The update helper exited with code $exitCode.'
            : 'The update helper exited with code $exitCode: $detail';
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    helper.kill();
    return 'The update helper did not confirm startup within 5 seconds.';
  }

  Future<void> _download(int generation, Directory directory) async {
    final asset = _asset!;
    final partial = _partialFile(directory, asset.name);
    var existing = await partial.exists() ? await partial.length() : 0;
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    try {
      final response = await _openDownloadResponse(
        client,
        asset.url,
        existing: existing,
        generation: generation,
      );
      if (generation != _generation) return;
      if (existing > 0 && response.statusCode == HttpStatus.partialContent) {
        final contentRange = response.headers.value(
          HttpHeaders.contentRangeHeader,
        );
        if (contentRange == null ||
            !contentRange.startsWith('bytes $existing-')) {
          throw const FormatException('Server returned an invalid byte range');
        }
      } else if (existing > 0 && response.statusCode == HttpStatus.ok) {
        existing = 0;
        if (await partial.exists()) await partial.delete();
      } else if (response.statusCode != HttpStatus.ok) {
        throw HttpException('Download failed (${response.statusCode})');
      }

      final sink = partial.openWrite(
        mode: existing > 0 ? FileMode.append : FileMode.write,
      );
      final buffer = BytesBuilder(copy: false);
      var received = existing;
      try {
        await for (final chunk in response.timeout(
          const Duration(seconds: 45),
        )) {
          if (generation != _generation) break;
          buffer.add(chunk);
          received += chunk.length;
          if (buffer.length >= _downloadBufferSize) {
            sink.add(buffer.takeBytes());
          }
          _progress(received, asset.size, generation);
        }
        if (buffer.isNotEmpty) sink.add(buffer.takeBytes());
      } finally {
        await sink.flush();
        await sink.close();
      }
      if (generation != _generation) return;
      final length = await partial.length();
      snapshot = UpdateDownloadSnapshot(
        status: UpdateDownloadStatus.downloaded,
        version: snapshot.version,
        fileName: snapshot.fileName,
        received: length,
        total: asset.size,
      );
      notifyListeners();
      snapshot = UpdateDownloadSnapshot(
        status: UpdateDownloadStatus.verifying,
        version: snapshot.version,
        fileName: snapshot.fileName,
        received: length,
        total: asset.size,
      );
      await _persist(directory);
      notifyListeners();
      if (length != asset.size) {
        await partial.delete();
        throw const FormatException(
          'Downloaded file size does not match release asset',
        );
      }
      final digest = (await sha256.bind(partial.openRead()).first).toString();
      if (generation != _generation) return;
      if (digest.toLowerCase() != asset.sha256!.toLowerCase()) {
        await partial.delete();
        throw const FormatException(
          'Downloaded file SHA-256 verification failed',
        );
      }
      final complete = _completeFile(directory, asset.name);
      if (await complete.exists()) await complete.delete();
      await partial.rename(complete.path);
      if (generation != _generation) return;
      snapshot = UpdateDownloadSnapshot(
        status: UpdateDownloadStatus.readyToUpdate,
        version: snapshot.version,
        fileName: snapshot.fileName,
        received: asset.size,
        total: asset.size,
      );
      await _persist(directory);
      notifyListeners();
    } on Object catch (error) {
      if (generation == _generation) {
        snapshot = UpdateDownloadSnapshot(
          status: UpdateDownloadStatus.failed,
          version: snapshot.version,
          fileName: snapshot.fileName,
          received: await partial.exists() ? await partial.length() : 0,
          total: asset.size,
          error: '$error',
        );
        await _persist(directory);
        notifyListeners();
      }
    } finally {
      _request = null;
      client.close(force: true);
    }
  }

  Future<HttpClientResponse> _openDownloadResponse(
    HttpClient client,
    Uri initial, {
    required int existing,
    required int generation,
  }) async {
    var current = initial;
    for (var redirect = 0; redirect <= _maximumRedirects; redirect++) {
      if (!_safeUri(current)) {
        throw const FormatException('Update redirect is not trusted');
      }
      final request = await client.getUrl(current);
      if (generation != _generation) {
        request.abort();
        throw const HttpException('Update download was cancelled');
      }
      _request = request;
      request
        ..followRedirects = false
        ..headers.set(HttpHeaders.userAgentHeader, 'niraN-updater/0.3.4');
      if (existing > 0) {
        request.headers.set(HttpHeaders.rangeHeader, 'bytes=$existing-');
      }
      final response = await request.close().timeout(
        const Duration(seconds: 30),
      );
      if (!_redirectStatuses.contains(response.statusCode)) return response;
      if (redirect == _maximumRedirects) {
        throw const HttpException('Too many update redirects');
      }
      final location = response.headers.value(HttpHeaders.locationHeader);
      if (location == null || location.trim().isEmpty) {
        throw const HttpException('Update redirect has no destination');
      }
      final next = current.resolve(location.trim());
      if (!_safeUri(next)) {
        throw const FormatException('Update redirect is not trusted');
      }
      await response.drain<void>();
      current = next;
    }
    throw const HttpException('Too many update redirects');
  }

  static const _redirectStatuses = {
    HttpStatus.movedPermanently,
    HttpStatus.found,
    HttpStatus.seeOther,
    HttpStatus.temporaryRedirect,
    HttpStatus.permanentRedirect,
  };

  void _progress(int received, int total, int generation) {
    if (generation != _generation) return;
    snapshot = UpdateDownloadSnapshot(
      status: UpdateDownloadStatus.downloading,
      version: snapshot.version,
      fileName: snapshot.fileName,
      received: received,
      total: total,
    );
    final now = DateTime.now();
    if (received - _lastNotifiedBytes >= 1024 * 1024 ||
        now.difference(_lastNotifiedAt) > const Duration(milliseconds: 400)) {
      _lastNotifiedBytes = received;
      _lastNotifiedAt = now;
      notifyListeners();
    }
  }

  Future<void> _waitForPreviousTask() async {
    final previous = _task;
    if (previous == null) return;
    try {
      await previous.timeout(const Duration(seconds: 2));
    } on Object {
      return;
    }
  }

  bool _safeUri(Uri url) =>
      (_allowHttp ? const {'http', 'https'} : const {'https'}).contains(
        url.scheme,
      ) &&
      url.userInfo.isEmpty &&
      _allowedHosts.contains(url.host.toLowerCase());

  bool _safeAsset(Uri url, String name) =>
      _safeUri(url) && isSupportedWindowsAssetName(name);

  Future<bool> _assetMatchesInstallation(ReleaseAsset asset) async {
    final expected = await installationType == WindowsInstallationType.setup
        ? WindowsUpdatePackage.setupExe
        : WindowsUpdatePackage.portableZip;
    return asset.package == expected;
  }

  Future<Directory> _directory() async {
    final existing = _resolvedDirectory;
    if (existing != null) return existing;
    if (_directoryOverride != null) {
      return _resolvedDirectory = _directoryOverride;
    }
    var downloadsPath = '';
    try {
      final result = Process.runSync('reg.exe', [
        'query',
        r'HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders',
        '/v',
        _downloadsKnownFolderId,
      ]);
      if (result.exitCode == 0) {
        final match = RegExp(
          r'REG_(?:EXPAND_)?SZ\s+(.+)$',
          multiLine: true,
        ).firstMatch('${result.stdout}');
        downloadsPath = match?.group(1)?.trim() ?? '';
      }
    } on Object {
      // Fall back to the current user's profile if the registry is unavailable.
    }
    downloadsPath = _expandEnvironment(downloadsPath);
    if (downloadsPath.isEmpty) {
      final profile = Platform.environment['USERPROFILE']?.trim() ?? '';
      downloadsPath = profile.isEmpty
          ? Directory.systemTemp.path
          : '$profile${Platform.pathSeparator}Downloads';
    }
    return _resolvedDirectory = Directory(
      '$downloadsPath${Platform.pathSeparator}niraN',
    );
  }

  String _expandEnvironment(String value) => value.replaceAllMapped(
    RegExp(r'%([^%]+)%'),
    (match) => _environmentValue(match.group(1)!) ?? match.group(0)!,
  );

  String? _environmentValue(String name) {
    for (final entry in Platform.environment.entries) {
      if (entry.key.toLowerCase() == name.toLowerCase()) return entry.value;
    }
    return null;
  }

  File _stateFile(Directory directory) =>
      File('${directory.path}${Platform.pathSeparator}.niran-update.json');
  File _resultFile(Directory directory) =>
      File('${directory.path}${Platform.pathSeparator}update-result.json');
  File _partialFile(Directory directory, String name) =>
      File('${directory.path}${Platform.pathSeparator}$name.part');
  File _completeFile(Directory directory, String name) =>
      File('${directory.path}${Platform.pathSeparator}$name');

  Future<void> _persist(Directory directory) async {
    final asset = _asset;
    if (asset == null) return;
    await directory.create(recursive: true);
    await _stateFile(directory).writeAsString(
      jsonEncode({
        'version': snapshot.version,
        'fileName': snapshot.fileName,
        'url': '${asset.url}',
        'total': asset.size,
        'sha256': asset.sha256,
        'status': snapshot.status.name,
        'installationType': (await installationType).name,
      }),
      flush: true,
    );
  }

  Future<void> _cleanupUnknown(Directory directory) async {
    if (!await directory.exists()) return;
    final keep = {
      _stateFile(directory).path,
      if (snapshot.fileName.isNotEmpty)
        _partialFile(directory, snapshot.fileName).path,
      if (snapshot.fileName.isNotEmpty)
        _completeFile(directory, snapshot.fileName).path,
    };
    await for (final entity in directory.list()) {
      if (entity is File &&
          _isUpdaterOwned(entity.path) &&
          !keep.contains(entity.path)) {
        try {
          await entity.delete();
        } on Object {
          // Never break startup for a temporarily locked update file.
        }
      } else if (entity is Directory && _isUpdaterOwnedDirectory(entity.path)) {
        try {
          await entity.delete(recursive: true);
        } on Object {
          // Never break startup for a temporarily locked update directory.
        }
      }
    }
  }

  Future<void> _cleanupCompletedArtifacts(Directory directory) async {
    for (final file in [
      _stateFile(directory),
      _resultFile(directory),
      File('${directory.path}${Platform.pathSeparator}update-helper.log'),
    ]) {
      try {
        if (await file.exists()) await file.delete();
      } on Object {
        // A short-lived helper lock is harmless and retried on next startup.
      }
    }
  }

  bool _isUpdaterOwned(String path) {
    final name = path.split(Platform.pathSeparator).last;
    if (name == '.niran-update.json' ||
        name == 'update-result.json' ||
        name == 'update-helper.log' ||
        RegExp(
          r'^install-(?:setup-)?update-\d+\.\d+\.\d+\.ps1$',
        ).hasMatch(name)) {
      return true;
    }
    final base = name.endsWith('.part')
        ? name.substring(0, name.length - '.part'.length)
        : name;
    return isSupportedWindowsAssetName(base);
  }

  bool _isUpdaterOwnedDirectory(String path) {
    final name = path.split(Platform.pathSeparator).last;
    return RegExp(r'^(?:staging|backup)-\d+\.\d+\.\d+$').hasMatch(name);
  }

  Future<({String state, String message})?> _readHelperResult(
    Directory directory,
    String version,
  ) async {
    final file = _resultFile(directory);
    if (!await file.exists()) return null;
    try {
      final value = jsonDecode(await file.readAsString());
      if (value is! Map || '${value['version'] ?? ''}' != version) return null;
      return (
        state: '${value['state'] ?? ''}',
        message: '${value['message'] ?? ''}',
      );
    } on Object {
      return null;
    }
  }

  Future<void> _cleanupLegacyDirectory(Directory current) async {
    final local = Platform.environment['LOCALAPPDATA']?.trim() ?? '';
    if (local.isEmpty) return;
    final legacy = Directory(
      '$local${Platform.pathSeparator}niraN${Platform.pathSeparator}updates',
    );
    if (legacy.path.toLowerCase() == current.path.toLowerCase() ||
        !await legacy.exists()) {
      return;
    }
    await for (final entity in legacy.list()) {
      if (entity is File && _isUpdaterOwned(entity.path)) {
        try {
          await entity.delete();
        } on Object {
          // Best-effort cleanup of updater files created by older versions.
        }
      }
    }
  }
}

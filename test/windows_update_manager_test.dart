import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niran/core/update_checker.dart';
import 'package:niran/core/windows_installation.dart';
import 'package:niran/core/windows_update_manager.dart';

void main() {
  group('WindowsUpdateManager', () {
    late Directory directory;
    late HttpServer server;
    late List<int> payload;
    late List<String?> ranges;
    var supportRanges = true;
    var corruptPayload = false;
    String? redirectLocation;
    var requestCount = 0;

    setUp(() async {
      directory = await Directory.systemTemp.createTemp('niran-updater-test-');
      payload = List<int>.generate(4 * 1024 * 1024, (index) => index % 251);
      ranges = <String?>[];
      supportRanges = true;
      corruptPayload = false;
      redirectLocation = null;
      requestCount = 0;
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      unawaited(() async {
        await for (final request in server) {
          requestCount++;
          if (redirectLocation case final location?) {
            request.response
              ..statusCode = HttpStatus.found
              ..headers.set(HttpHeaders.locationHeader, location);
            await request.response.close();
            continue;
          }
          final range = request.headers.value(HttpHeaders.rangeHeader);
          ranges.add(range);
          var start = 0;
          if (supportRanges && range != null) {
            start = int.parse(
              RegExp(r'bytes=(\d+)-').firstMatch(range)!.group(1)!,
            );
            request.response.statusCode = HttpStatus.partialContent;
            request.response.headers.set(
              HttpHeaders.contentRangeHeader,
              'bytes $start-${payload.length - 1}/${payload.length}',
            );
          }
          final bytes = corruptPayload
              ? List<int>.filled(payload.length - start, 7)
              : payload.sublist(start);
          request.response.contentLength = bytes.length;
          try {
            for (var offset = 0; offset < bytes.length; offset += 64 * 1024) {
              final end = (offset + 64 * 1024).clamp(0, bytes.length);
              request.response.add(bytes.sublist(offset, end));
              await request.response.flush();
              await Future<void>.delayed(const Duration(milliseconds: 4));
            }
          } on Object {
            // Pause/cancel intentionally aborts the client connection.
          } finally {
            await request.response.close();
          }
        }
      }());
    });

    tearDown(() async {
      await server.close(force: true);
      if (await directory.exists()) await directory.delete(recursive: true);
    });

    ReleaseAsset asset({String? digest}) => ReleaseAsset(
      name: 'niraN-0.3.3-windows-x64.zip',
      url: Uri.parse('http://127.0.0.1:${server.port}/asset.zip'),
      size: payload.length,
      sha256: digest ?? sha256.convert(payload).toString(),
    );

    WindowsUpdateManager manager() =>
        WindowsUpdateManager.forTesting(directory: directory);

    test('selects only the package matching the installation type', () async {
      final portable = asset();
      final setup = ReleaseAsset(
        name: 'niraN-v0.3.3-windows-x64-setup.exe',
        url: Uri.parse('http://127.0.0.1:${server.port}/setup.exe'),
        size: payload.length,
        sha256: sha256.convert(payload).toString(),
      );
      final release = ReleaseCheckResult(
        latestVersion: SemanticVersion.parse('0.3.3'),
        releaseUrl: Uri.parse(
          'https://github.com/bardia-us/niraN/releases/tag/v0.3.3',
        ),
        updateAvailable: true,
        portableAsset: portable,
        setupAsset: setup,
      );
      final portableManager = manager();
      final setupManager = WindowsUpdateManager.forTesting(
        directory: directory,
        installationType: WindowsInstallationType.setup,
      );

      expect(await portableManager.assetFor(release), same(portable));
      expect(await setupManager.assetFor(release), same(setup));
      await expectLater(
        portableManager.start(setup, release.latestVersion),
        throwsFormatException,
      );
      await expectLater(
        setupManager.start(portable, release.latestVersion),
        throwsFormatException,
      );
    });

    test('pause aborts network and resume continues with Range', () async {
      final updater = manager();
      await updater.start(asset(), SemanticVersion.parse('0.3.3'));
      await _waitFor(() => updater.snapshot.received >= 1024 * 1024);
      await updater.pause();
      expect(updater.snapshot.status, UpdateDownloadStatus.paused);
      await updater.activeTask;

      final partial = File(
        '${directory.path}${Platform.pathSeparator}niraN-0.3.3-windows-x64.zip.part',
      );
      final pausedLength = await partial.length();
      expect(pausedLength, greaterThan(0));
      expect(pausedLength, lessThan(payload.length));

      await updater.resume();
      await updater.activeTask;
      expect(updater.snapshot.status, UpdateDownloadStatus.readyToUpdate);
      expect(updater.snapshot.progress, 1);
      expect(ranges.whereType<String>(), contains('bytes=$pausedLength-'));
      expect(await partial.exists(), isFalse);
      expect(
        await File(
          '${directory.path}${Platform.pathSeparator}niraN-0.3.3-windows-x64.zip',
        ).readAsBytes(),
        payload,
      );
    });

    test('server without Range support restarts cleanly from zero', () async {
      supportRanges = false;
      final partial = File(
        '${directory.path}${Platform.pathSeparator}niraN-0.3.3-windows-x64.zip.part',
      );
      await partial.writeAsBytes(payload.take(300000).toList());
      final updater = manager();
      final release = asset();
      await File(
        '${directory.path}${Platform.pathSeparator}.niran-update.json',
      ).writeAsString(
        jsonEncode({
          'version': '0.3.3',
          'fileName': release.name,
          'url': '${release.url}',
          'total': release.size,
          'sha256': release.sha256,
          'status': 'paused',
        }),
      );
      await updater.initialize('0.3.2');
      await updater.resume();
      await updater.activeTask;
      expect(ranges.single, 'bytes=300000-');
      expect(updater.snapshot.status, UpdateDownloadStatus.readyToUpdate);
      expect(
        await File(
          '${directory.path}${Platform.pathSeparator}niraN-0.3.3-windows-x64.zip',
        ).length(),
        payload.length,
      );
    });

    test('cancel retains partial and inactive delete removes it', () async {
      final updater = manager();
      await updater.start(asset(), SemanticVersion.parse('0.3.3'));
      await _waitFor(() => updater.snapshot.received >= 1024 * 1024);
      await updater.cancel();
      expect(updater.snapshot.status, UpdateDownloadStatus.cancelled);
      await updater.activeTask;
      final partial = File(
        '${directory.path}${Platform.pathSeparator}niraN-0.3.3-windows-x64.zip.part',
      );
      expect(await partial.exists(), isTrue);
      await updater.delete();
      expect(updater.snapshot.status, UpdateDownloadStatus.idle);
      expect(await partial.exists(), isFalse);
    });

    test('verification failure never exposes a completed archive', () async {
      corruptPayload = true;
      final updater = manager();
      await updater.start(asset(), SemanticVersion.parse('0.3.3'));
      await updater.activeTask;
      expect(updater.snapshot.status, UpdateDownloadStatus.failed);
      expect(updater.snapshot.error, contains('SHA-256'));
      expect(
        await File(
          '${directory.path}${Platform.pathSeparator}niraN-0.3.3-windows-x64.zip',
        ).exists(),
        isFalse,
      );
      expect(
        await File(
          '${directory.path}${Platform.pathSeparator}niraN-0.3.3-windows-x64.zip.part',
        ).exists(),
        isFalse,
      );
    });

    test('completed update state removes stale helper metadata', () async {
      final state = File(
        '${directory.path}${Platform.pathSeparator}.niran-update.json',
      );
      final result = File(
        '${directory.path}${Platform.pathSeparator}update-result.json',
      );
      final log = File(
        '${directory.path}${Platform.pathSeparator}update-helper.log',
      );
      await state.writeAsString(
        jsonEncode({
          'version': '0.3.3',
          'fileName': 'niraN-0.3.3-windows-x64.zip',
          'total': payload.length,
        }),
      );
      await result.writeAsString(
        jsonEncode({'version': '0.3.3', 'state': 'completed'}),
      );
      await log.writeAsString('completed');
      final updater = manager();

      await updater.initialize('0.3.3');

      expect(updater.snapshot.status, UpdateDownloadStatus.updateCompleted);
      expect(await state.exists(), isFalse);
      expect(await result.exists(), isFalse);
      expect(await log.exists(), isFalse);
    });

    test('duplicate start does not create a second network task', () async {
      final updater = manager();
      final release = asset();
      await updater.start(release, SemanticVersion.parse('0.3.3'));
      await updater.start(release, SemanticVersion.parse('0.3.3'));
      await updater.activeTask;
      expect(requestCount, 1);
      expect(updater.snapshot.status, UpdateDownloadStatus.readyToUpdate);
    });

    test('unsafe redirect is rejected before contacting its target', () async {
      redirectLocation = 'http://untrusted.invalid/update.zip';
      final updater = manager();
      await updater.start(asset(), SemanticVersion.parse('0.3.3'));
      await updater.activeTask;
      expect(updater.snapshot.status, UpdateDownloadStatus.failed);
      expect(updater.snapshot.error, contains('not trusted'));
      expect(requestCount, 1);
    });

    test(
      'restart offers install only for the exact verified release',
      () async {
        final release = asset();
        final updater = manager();
        await updater.start(release, SemanticVersion.parse('0.3.3'));
        await updater.activeTask;

        final restored = manager();
        await restored.initialize('0.3.2');
        expect(
          await restored.hasVerifiedDownload(
            release,
            SemanticVersion.parse('0.3.3'),
          ),
          isTrue,
        );
        expect(
          await restored.hasVerifiedDownload(
            release,
            SemanticVersion.parse('0.3.4'),
          ),
          isFalse,
        );
      },
    );
  });
}

Future<void> _waitFor(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('Condition was not reached');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

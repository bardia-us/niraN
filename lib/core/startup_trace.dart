import 'dart:convert';
import 'dart:io';
import 'dart:ui';

enum StartupPhase {
  dartMain,
  bindingReady,
  renderModeLoaded,
  loadingFrameBuilt,
  deviceCheckStarted,
  deviceCheckFinished,
  accessCheckStarted,
  accessCheckFinished,
  graphicsStarted,
  graphicsFinished,
  authorizedUiReady,
  settingsStarted,
  settingsFilesLoaded,
  settingsProxyReady,
  settingsReady,
  controllerReady,
  homeBuildRequested,
  homeFramePresented,
  homeRasterReady,
  coreStartRequested,
  coreStartFinished,
  accessRefreshStarted,
  accessRefreshFinished,
}

/// Opt-in phase timings. Fixed names prevent credentials/settings being logged.
/// Dart elapsed time begins at main, separate from native process creation.
abstract final class StartupTrace {
  static final _clock = Stopwatch();
  static File? _file;
  static int _framesRecorded = 0;

  static void frames(List<FrameTiming> timings) {
    final file = _file;
    if (file == null) return;
    for (final timing in timings) {
      if (_framesRecorded++ >= 24) return;
      try {
        file.writeAsStringSync(
          '${jsonEncode({'origin': 'frame', 'phase': 'frame_timing', 'buildUs': timing.buildDuration.inMicroseconds, 'rasterUs': timing.rasterDuration.inMicroseconds, 'totalUs': timing.totalSpan.inMicroseconds, 'vsyncOverheadUs': timing.vsyncOverhead.inMicroseconds, 'rasterQueueUs': timing.timestampInMicroseconds(FramePhase.rasterStart) - timing.timestampInMicroseconds(FramePhase.buildFinish)})}\n',
          mode: FileMode.append,
        );
      } on Object {
        /* Optional fixed numeric diagnostics only. */
      }
    }
  }

  static void start() {
    final path = Platform.environment['NIRAN_STARTUP_TRACE_FILE'];
    if (path == null || path.isEmpty) return;
    _clock.start();
    _file = File(path);
    mark(StartupPhase.dartMain);
  }

  static void mark(StartupPhase phase) {
    final file = _file;
    if (file == null) return;
    try {
      file.writeAsStringSync(
        '${jsonEncode({'origin': 'dart', 'phase': phase.name, 'elapsedUs': _clock.elapsedMicroseconds})}\n',
        mode: FileMode.append,
      );
    } on Object {
      // Diagnostics must never break normal startup or permission gates.
    }
  }
}

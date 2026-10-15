import 'dart:async';
import 'dart:ui';

/// Releases optional startup work only after a usable Home frame is rasterized.
/// Frame IDs also distinguish buffered/loading reports and warm-up frames.
final class StartupUiReadiness {
  final _ready = Completer<void>();
  int? _frameNumber;
  Future<void> get ready => _ready.future;
  bool get isReady => _ready.isCompleted;

  void expectFrame(int frameNumber) => _frameNumber ??= frameNumber;

  void recordTimings(List<FrameTiming> timings) {
    final threshold = _frameNumber;
    if (isReady || threshold == null) return;
    if (timings.any((frame) => frame.frameNumber >= threshold)) {
      _ready.complete();
    }
  }
}

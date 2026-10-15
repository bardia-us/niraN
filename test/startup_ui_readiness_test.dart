import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:niran/core/startup_ui_readiness.dart';

FrameTiming frame(int vsync) => FrameTiming(
  frameNumber: vsync,
  vsyncStart: vsync,
  buildStart: vsync + 10,
  buildFinish: vsync + 20,
  rasterStart: vsync + 30,
  rasterFinish: vsync + 40,
  rasterFinishWallTime: 0,
);

void main() {
  test(
    'loading and buffered older frames cannot release usable UI work',
    () async {
      final gate = StartupUiReadiness();
      var ready = false;
      gate.ready.then((_) => ready = true);
      gate.recordTimings([frame(100)]);
      await Future<void>.delayed(Duration.zero);
      expect(ready, isFalse);
      gate.expectFrame(300);
      gate.recordTimings([frame(100), frame(200)]);
      await Future<void>.delayed(Duration.zero);
      expect(ready, isFalse);
      gate.recordTimings([frame(300)]);
      await gate.ready;
      expect(ready, isTrue);
      gate.recordTimings([frame(400)]);
      expect(gate.isReady, isTrue);
    },
  );
  test(
    'later rebuilds do not move the original Home readiness threshold',
    () async {
      final gate = StartupUiReadiness();
      gate.expectFrame(300);
      gate.expectFrame(500);
      gate.recordTimings([frame(300)]);
      expect(gate.isReady, isTrue);
    },
  );
}

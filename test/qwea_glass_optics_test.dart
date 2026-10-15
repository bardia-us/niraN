import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/widgets/shared/lightweight_liquid_glass.dart';
import 'package:niran/core/widgets/glass_surface.dart';
import 'package:niran/core/widgets/snapshot_glass.dart';

Future<ui.Image> _backdrop({bool ramp = false}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    const Rect.fromLTWH(0, 0, 240, 160),
    ramp
        ? (Paint()
            ..shader = ui.Gradient.linear(Offset.zero, const Offset(240, 0), [
              Colors.black,
              Colors.red,
            ]))
        : (Paint()..color = const Color(0xFF101010)),
  );
  final picture = recorder.endRecording();
  try {
    return await picture.toImage(240, 160);
  } finally {
    picture.dispose();
  }
}

Future<ByteData> _render(
  WidgetTester tester, {
  bool ramp = false,
  bool surface = false,
  bool small = false,
  bool modal = true,
  double blur = 0,
  Brightness brightness = Brightness.dark,
}) async {
  final source = (await tester.runAsync(() => _backdrop(ramp: ramp)))!;
  final snapshot = GlassSnapshot(
    image: source,
    origin: Offset.zero,
    pixelRatio: 1,
  );
  await tester.runAsync(warmSnapshotGlass);
  if (!modal) await tester.runAsync(LightweightLiquidGlass.preWarm);
  final key = GlobalKey();
  const foreground = Positioned(
    left: 114,
    top: 74,
    width: 12,
    height: 12,
    child: ColoredBox(color: Colors.yellow),
  );
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        theme: ThemeData(brightness: brightness),
        home: Align(
          alignment: Alignment.topLeft,
          child: RepaintBoundary(
            key: key,
            child: SizedBox(
              width: 240,
              height: 160,
              child: Builder(
                builder: (_) {
                  final scene = Stack(
                    children: [
                      Positioned.fill(child: RawImage(image: source)),
                      Positioned(
                        left: 20,
                        top: 20,
                        width: small ? 48 : 200,
                        height: small ? 48 : 120,
                        child: surface
                            ? GlassSurface(
                                blur: blur,
                                saturation: 1,
                                radius: 20,
                                child: SizedBox.expand(),
                              )
                            : SnapshotGlassBackdrop(
                                radius: small ? 24 : 20,
                                blur: 0,
                                saturation: 1,
                                lightIntensity: ramp ? 0 : .055,
                                fallback: const SizedBox.expand(),
                              ),
                      ),
                      if (!small) foreground,
                    ],
                  );
                  return modal
                      ? SnapshotGlassScope(snapshot: snapshot, child: scene)
                      : scene;
                },
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  final bytes = (await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 1);
    try {
      return await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    } finally {
      image.dispose();
    }
  }))!;
  await tester.pumpWidget(const SizedBox());
  snapshot.dispose();
  return bytes;
}

int _red(ByteData bytes, int x, int y) => bytes.getUint8((y * 240 + x) * 4);

void main() {
  testWidgets('lens has equal opposing rim lobes, not a one-sided glow', (
    tester,
  ) async {
    final pixels = await _render(tester);
    // Pixel centres lie about 1px inside the rounded edge: the upstream
    // hairline peaks at d=-1, while deeper pixels include asymmetric glow.
    final front = _red(pixels, 26, 26);
    final back = _red(pixels, 213, 133);
    expect(front, greaterThan(70));
    expect(back, greaterThan(70));
    expect((front - back).abs(), lessThan(15));
    expect(
      _red(pixels, 100, 80),
      inInclusiveRange(14, 18),
      reason: 'Rim lighting must not whiten the flat interior',
    );
    expect(_red(pixels, 120, 80), 255, reason: 'Foreground remains sharp');
  });

  testWidgets(
    'small circular lens does not clamp its whole interior to its far edge',
    (tester) async {
      final pixels = await _render(tester, ramp: true, small: true);
      // x=24 is 4px inside the circle at its horizontal midpoint. Refraction
      // must be scaled for a 48px control, not the 160px panel displacement.
      expect(_red(pixels, 24, 44), inInclusiveRange(26, 33));
      expect(_red(pixels, 44, 44), inInclusiveRange(44, 50));
      expect(_red(pixels, 12, 44), inInclusiveRange(11, 16));
    },
  );

  for (final brightness in Brightness.values) {
    testWidgets(
      'glass transmits backdrop instead of a milky body on $brightness',
      (tester) async {
        final pixels = await _render(
          tester,
          surface: true,
          brightness: brightness,
        );
        expect(
          _red(pixels, 100, 80),
          lessThan(50),
          reason:
              'Body tint must not replace the dark backdrop with grey/white',
        );
        expect(_red(pixels, 120, 80), 255);
      },
    );
  }

  testWidgets(
    'live reference surface separates its rim from the transmitted backdrop',
    (tester) async {
      final pixels = await _render(tester, surface: true, modal: false);
      final front = _red(pixels, 26, 26);
      final back = _red(pixels, 213, 133);
      // Persistent surfaces now use liquid_glass_widgets, not the modal's
      // QWEA hairline at d=-1. Assert actual visible separation/readability
      // rather than requiring identical highlight coordinates in two models.
      final body = _red(pixels, 100, 80);
      expect(front, greaterThan(body + 12));
      expect(back, greaterThan(body + 12));
      expect(body, lessThan(50));
      expect(_red(pixels, 120, 80), 255);
    },
  );

  testWidgets('raw-only modal fallback keeps its optical rim', (tester) async {
    final pixels = await _render(tester, surface: true, blur: 18);
    expect(_red(pixels, 26, 26), greaterThan(65));
    expect(_red(pixels, 213, 133), greaterThan(65));
    expect(_red(pixels, 100, 80), lessThan(35));
  });
}

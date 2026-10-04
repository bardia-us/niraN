import 'dart:ui' as ui;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niran/core/widgets/snapshot_glass.dart';

Future<ui.Image> _source() async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    const Rect.fromLTWH(0, 0, 320, 240),
    Paint()
      ..shader = ui.Gradient.linear(Offset.zero, const Offset(320, 0), [
        Colors.black,
        Colors.red,
      ]),
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(320, 240);
  picture.dispose();
  return image;
}

void main() {
  testWidgets('GPU startup warmup draws the actual shader once', (
    tester,
  ) async {
    final result = await tester.runAsync(() async {
      final first = prewarmSnapshotGlassGpu();
      final second = prewarmSnapshotGlassGpu();
      return (shared: identical(first, second), completed: await first);
    });
    expect(result!.shared, isTrue);
    expect(result.completed, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'modal crop captures intersected physical bounds and its global origin',
    (tester) async {
      final key = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(devicePixelRatio: 2),
            child: Stack(
              children: [
                Positioned(
                  left: 40,
                  top: 30,
                  child: GlassSnapshotBoundary(
                    key: key,
                    child: const SizedBox(
                      width: 120,
                      height: 80,
                      child: ColoredBox(color: Colors.red),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      final crop = await tester.runAsync(
        () => captureGlassSnapshot(
          key,
          region: const Rect.fromLTWH(65, 50, 40, 30),
          blur: 16,
        ),
      );
      expect(crop, isNotNull);
      expect(crop!.origin, const Offset(65, 50));
      expect(crop.logicalSize, const Size(40, 30));
      expect(crop.image.width, 80);
      expect(crop.image.height, 60);
      expect(crop.blurredImage!.width, 80);
      expect(crop.blurredImage!.height, 60);
      crop.dispose();
      final clipped = await tester.runAsync(
        () => captureGlassSnapshot(
          key,
          region: const Rect.fromLTWH(20, 10, 80, 70),
        ),
      );
      expect(clipped!.origin, const Offset(40, 30));
      expect(clipped.logicalSize, const Size(60, 50));
      clipped.dispose();
      expect(
        await tester.runAsync(
          () => captureGlassSnapshot(
            key,
            region: const Rect.fromLTWH(500, 500, 40, 30),
          ),
        ),
        isNull,
      );
      final full = await tester.runAsync(() => captureGlassSnapshot(key));
      expect(full!.origin, const Offset(40, 30));
      expect(full.logicalSize, const Size(120, 80));
      full.dispose();
    },
  );

  testWidgets(
    'one-off Gaussian image destroys fine detail and is used by the lens',
    (tester) async {
      final sourceKey = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(devicePixelRatio: 1),
            child: Scaffold(
              body: RepaintBoundary(
                key: sourceKey,
                child: const SizedBox(
                  width: 320,
                  height: 240,
                  child: CustomPaint(painter: _FineStripes()),
                ),
              ),
            ),
          ),
        ),
      );
      final snapshot = await tester.runAsync(
        () => captureGlassSnapshot(sourceKey, blur: 16),
      );
      expect(snapshot, isNotNull);
      expect(snapshot!.blurredImage, isNotNull);
      final blurred = snapshot.blurredImage!;
      final sourcePixels = await tester.runAsync(
        () => snapshot.image.toByteData(format: ui.ImageByteFormat.rawRgba),
      );
      final blurredPixels = await tester.runAsync(
        () => blurred.toByteData(format: ui.ImageByteFormat.rawRgba),
      );
      int red(ByteData bytes, int x) => bytes.getUint8((120 * 320 + x) * 4);
      expect(
        (red(sourcePixels!, 100) - red(sourcePixels, 102)).abs(),
        greaterThan(200),
      );
      expect(
        (red(blurredPixels!, 100) - red(blurredPixels, 102)).abs(),
        lessThan(8),
      );
      await tester.runAsync(warmSnapshotGlass);
      const key = ValueKey('Gaussian lens pixels');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SnapshotGlassScope(
              snapshot: snapshot,
              child: RepaintBoundary(
                key: key,
                child: SizedBox(
                  width: 320,
                  height: 240,
                  child: Stack(
                    children: [
                      Positioned.fill(child: RawImage(image: snapshot.image)),
                      const Positioned(
                        left: 60,
                        top: 60,
                        width: 200,
                        height: 120,
                        child: SnapshotGlassBackdrop(
                          blur: 16,
                          saturation: 1,
                          refraction: 0,
                          lightIntensity: 0,
                          fallback: ColoredBox(color: Colors.green),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(key),
      );
      final lensPixels = await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 1);
        final bytes = await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        );
        image.dispose();
        return bytes!;
      });
      expect((red(lensPixels!, 100) - red(lensPixels, 102)).abs(), lessThan(8));
      expect(red(lensPixels, 100), inInclusiveRange(110, 140));
      await tester.pumpWidget(const SizedBox());
      snapshot.dispose();
      expect(snapshot.image.debugDisposed, isTrue);
      expect(blurred.debugDisposed, isTrue);
    },
  );

  testWidgets('nonlinear glass samples the real image near its curved edge', (
    tester,
  ) async {
    final source = await tester.runAsync(_source);
    final snapshot = GlassSnapshot(
      image: source!,
      origin: Offset.zero,
      pixelRatio: 1,
    );
    final program = await tester.runAsync(warmSnapshotGlass);
    expect(program, isNotNull);
    const key = ValueKey('glass pixels');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SnapshotGlassScope(
            snapshot: snapshot,
            child: RepaintBoundary(
              key: key,
              child: SizedBox(
                width: 320,
                height: 240,
                child: Stack(
                  children: [
                    Positioned.fill(child: RawImage(image: source)),
                    const Positioned(
                      left: 60,
                      top: 60,
                      width: 200,
                      height: 120,
                      child: SnapshotGlassBackdrop(
                        radius: 20,
                        blur: 0,
                        saturation: 1,
                        lightIntensity: 0,
                        fallback: ColoredBox(color: Colors.green),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.runAsync(() async {
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pumpAndSettle();
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(key),
    );
    final pixels = await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 1);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      image.dispose();
      return bytes!;
    });
    int red(int x, int y) => pixels!.getUint8((y * 320 + x) * 4);
    // Compare the source ramp at the same x, outside and inside the lens.
    expect(red(160, 120), closeTo(red(160, 30), 2));
    // Near the left rim, the real red ramp is sampled farther inside the image.
    expect(red(64, 120), greaterThan(57));
    // At the same x closer to the rounded corner the SDF normal differs.
    // A single affine magnifier cannot produce this y-dependent displacement.
    expect((red(80, 65) - red(80, 120)).abs(), greaterThan(2));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    snapshot.dispose();
  });

  testWidgets('missing modal snapshot retains the supplied live fallback', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: SizedBox(
          width: 100,
          height: 60,
          child: SnapshotGlassBackdrop(fallback: Text('Live glass fallback')),
        ),
      ),
    );
    expect(find.text('Live glass fallback'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('physical image pixels align after a nonzero snapshot origin', (
    tester,
  ) async {
    final source = await tester.runAsync(_source);
    final snapshot = GlassSnapshot(
      image: source!,
      origin: const Offset(40, 30),
      pixelRatio: 2,
    );
    await tester.runAsync(warmSnapshotGlass);
    const key = ValueKey('dpi pixels');
    await tester.pumpWidget(
      MaterialApp(
        home: RepaintBoundary(
          key: key,
          child: SizedBox(
            width: 320,
            height: 240,
            child: SnapshotGlassScope(
              snapshot: snapshot,
              child: Stack(
                children: [
                  Positioned(
                    left: 40,
                    top: 30,
                    width: 160,
                    height: 120,
                    child: RawImage(image: source),
                  ),
                  Positioned(
                    left: 60,
                    top: 50,
                    width: 120,
                    height: 80,
                    child: Transform.scale(
                      scale: .8,
                      child: const SnapshotGlassBackdrop(
                        radius: 12,
                        blur: 0,
                        saturation: 1,
                        refraction: 0,
                        lightIntensity: 0,
                        fallback: ColoredBox(color: Colors.green),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(key),
    );
    final pixels = await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 1);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      image.dispose();
      return bytes!;
    });
    int red(int x, int y) => pixels!.getUint8((y * 800 + x) * 4);
    // x=120 maps to source physical x=160; pixel ratio and origin both matter.
    expect(red(120, 90), closeTo(red(120, 35), 2));
    expect(red(120, 90), inInclusiveRange(115, 130));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    snapshot.dispose();
  });

  testWidgets('capture keeps global origin and physical pixel ratio', (
    tester,
  ) async {
    final key = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(devicePixelRatio: 2),
          child: Stack(
            children: [
              Positioned(
                left: 40,
                top: 30,
                child: RepaintBoundary(
                  key: key,
                  child: const SizedBox(
                    width: 120,
                    height: 80,
                    child: ColoredBox(color: Colors.red),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    final snapshot = await tester.runAsync(() => captureGlassSnapshot(key));
    expect(snapshot, isNotNull);
    expect(snapshot!.origin, const Offset(40, 30));
    expect(snapshot.pixelRatio, 2);
    expect(snapshot.logicalSize, const Size(120, 80));
    expect(snapshot.image.width, 240);
    expect(snapshot.image.height, 160);
    snapshot.dispose();
    snapshot.dispose();
    await tester.pumpWidget(
      MaterialApp(
        home: SnapshotGlassScope(
          snapshot: snapshot,
          child: const SizedBox(
            width: 120,
            height: 80,
            child: SnapshotGlassBackdrop(fallback: Text('Disposed fallback')),
          ),
        ),
      ),
    );
    expect(find.text('Disposed fallback'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cached modal shader follows a changing compositor transform', (
    tester,
  ) async {
    final source = await tester.runAsync(_source);
    final snapshot = GlassSnapshot(
      image: source!,
      origin: const Offset(40, 30),
      pixelRatio: 2,
    );
    await tester.runAsync(warmSnapshotGlass);
    final scale = ValueNotifier(.8);
    const key = ValueKey('animated pixels');
    await tester.pumpWidget(
      MaterialApp(
        home: RepaintBoundary(
          key: key,
          child: SnapshotGlassScope(
            snapshot: snapshot,
            repaint: scale,
            child: Stack(
              children: [
                Positioned(
                  left: 40,
                  top: 30,
                  width: 160,
                  height: 120,
                  child: RawImage(image: source),
                ),
                Positioned(
                  left: 60,
                  top: 50,
                  width: 120,
                  height: 80,
                  child: ValueListenableBuilder<double>(
                    valueListenable: scale,
                    child: const RepaintBoundary(
                      child: SnapshotGlassBackdrop(
                        radius: 12,
                        blur: 0,
                        saturation: 1,
                        refraction: 0,
                        lightIntensity: 0,
                        fallback: ColoredBox(color: Colors.green),
                      ),
                    ),
                    builder: (_, value, child) =>
                        Transform.scale(scale: value, child: child),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    scale.value = 1;
    await tester.pumpAndSettle();
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(key),
    );
    final pixels = await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 1);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      image.dispose();
      return bytes!;
    });
    int red(int x, int y) => pixels!.getUint8((y * 800 + x) * 4);
    expect(red(150, 90), closeTo(red(150, 35), 2));
    await tester.pumpWidget(const SizedBox());
    snapshot.dispose();
    scale.dispose();
  });

  testWidgets('pending source paint completes before modal capture', (
    tester,
  ) async {
    final key = GlobalKey();
    late BuildContext launchContext;
    await tester.pumpWidget(
      MaterialApp(
        home: GlassSnapshotSource(
          boundaryKey: key,
          child: GlassSnapshotBoundary(
            key: key,
            child: Builder(
              builder: (context) {
                launchContext = context;
                return const SizedBox(
                  width: 120,
                  height: 80,
                  child: ColoredBox(color: Colors.blue),
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.runAsync(warmSnapshotGlass);
    tester
        .renderObject<RenderRepaintBoundary>(find.byKey(key))
        .markNeedsPaint();
    Future<GlassSnapshot?>? pending;
    await tester.runAsync(() async {
      pending = prepareGlassSnapshot(
        launchContext,
        region: const Rect.fromLTWH(10, 10, 80, 60),
      );
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pump();
    final snapshot = await tester.runAsync(() => pending!);
    expect(snapshot, isNotNull);
    expect(snapshot!.origin, const Offset(10, 10));
    expect(snapshot.logicalSize, const Size(80, 60));
    snapshot.dispose();
    expect(tester.takeException(), isNull);
  });

  testWidgets('opening safely abandons a source unmounted while waiting', (
    tester,
  ) async {
    final key = GlobalKey();
    late BuildContext launchContext;
    await tester.pumpWidget(
      MaterialApp(
        home: GlassSnapshotSource(
          boundaryKey: key,
          child: RepaintBoundary(
            key: key,
            child: Builder(
              builder: (context) {
                launchContext = context;
                return const SizedBox(width: 120, height: 80);
              },
            ),
          ),
        ),
      ),
    );
    await tester.runAsync(warmSnapshotGlass);
    Future<GlassSnapshot?>? pending;
    await tester.runAsync(() async {
      pending = prepareGlassSnapshot(launchContext);
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pumpWidget(const SizedBox());
    expect(await tester.runAsync(() => pending!), isNull);
    expect(
      await tester.runAsync(() => prepareGlassSnapshot(launchContext)),
      isNull,
    );
    expect(await tester.runAsync(() => captureGlassSnapshot(key)), isNull);
    expect(tester.takeException(), isNull);
  });
}

class _FineStripes extends CustomPainter {
  const _FineStripes();
  @override
  void paint(Canvas canvas, Size size) {
    for (var x = 0.0; x < size.width; x += 2) {
      canvas.drawRect(
        Rect.fromLTWH(x, 0, 2, size.height),
        Paint()..color = (x ~/ 2).isEven ? Colors.red : Colors.blue,
      );
    }
  }

  @override
  bool shouldRepaint(_FineStripes oldDelegate) => false;
}

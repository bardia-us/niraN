import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// A modal owns this image until its route has finished its reverse transition.
/// No pixels leave the process and no image is captured during repaint.
class GlassSnapshot {
  GlassSnapshot({
    required this.image,
    required this.origin,
    required this.pixelRatio,
    this.blurredImage,
    this.blurredSigma = 0,
  }) : assert(pixelRatio > 0);

  final ui.Image image;
  final Offset origin;
  final double pixelRatio;
  final ui.Image? blurredImage;
  final double blurredSigma;
  bool _disposed = false;
  bool get isDisposed => _disposed;
  Size get logicalSize =>
      Size(image.width / pixelRatio, image.height / pixelRatio);

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    if (blurredImage != null && !identical(blurredImage, image)) {
      blurredImage!.dispose();
    }
    image.dispose();
  }
}

class GlassSnapshotSource extends InheritedWidget {
  const GlassSnapshotSource({
    required this.boundaryKey,
    required super.child,
    super.key,
  });
  final GlobalKey boundaryKey;
  static GlobalKey? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<GlassSnapshotSource>()?.boundaryKey;
  @override
  bool updateShouldNotify(GlassSnapshotSource oldWidget) =>
      boundaryKey != oldWidget.boundaryKey;
}

/// A normal repaint boundary with a public regional capture operation. Flutter
/// exposes regional toImage on OffsetLayer, whose owning layer is protected.
class GlassSnapshotBoundary extends RepaintBoundary {
  const GlassSnapshotBoundary({super.key, required super.child});
  @override
  RenderRepaintBoundary createRenderObject(BuildContext context) =>
      _RenderGlassSnapshotBoundary();
}

class _RenderGlassSnapshotBoundary extends RenderRepaintBoundary {
  Future<ui.Image> toImageRegion(Rect bounds, double pixelRatio) {
    final currentLayer = layer;
    if (currentLayer is! OffsetLayer) {
      throw StateError('Snapshot source is not painted');
    }
    return currentLayer.toImage(bounds, pixelRatio: pixelRatio);
  }
}

class SnapshotGlassScope extends InheritedWidget {
  const SnapshotGlassScope({
    required this.snapshot,
    required super.child,
    this.repaint,
    super.key,
  });
  final GlassSnapshot snapshot;
  final Listenable? repaint;
  static Listenable? repaintOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SnapshotGlassScope>()?.repaint;
  static GlassSnapshot? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<SnapshotGlassScope>()
      ?.snapshot;
  @override
  bool updateShouldNotify(SnapshotGlassScope oldWidget) =>
      snapshot != oldWidget.snapshot || repaint != oldWidget.repaint;
}

Future<ui.FragmentProgram?>? _program;
ui.FragmentProgram? _loadedProgram;

Future<bool>? _gpuWarmup;

/// Optional startup optimization. Call without awaiting startup; completion is
/// bounded, and all synthetic GPU resources are freed even after a timeout.
/// This exercises first draw, but its onscreen benefit requires Profile data.
Future<bool> prewarmSnapshotGlassGpu() => _gpuWarmup ??= _drawSyntheticGlass()
    .timeout(const Duration(milliseconds: 350), onTimeout: () => false);

Future<bool> _drawSyntheticGlass() async {
  final elapsed = Stopwatch()..start();
  bool expired() => elapsed.elapsedMilliseconds >= 350;
  ui.Image? source;
  ui.Image? blurred;
  ui.Image? rendered;
  ui.FragmentShader? shader;
  try {
    final program = await warmSnapshotGlass();
    if (program == null || expired()) return false;
    const dimension = 128;
    const rect = Rect.fromLTWH(0, 0, 128, 128);
    var recorder = ui.PictureRecorder();
    var canvas = Canvas(recorder);
    canvas.drawRect(rect, Paint()..color = const Color(0xFF181923));
    canvas.drawCircle(
      const Offset(36, 48),
      18,
      Paint()..color = const Color(0xFF6B83DF),
    );
    source = await _rasterWarmupPicture(recorder, dimension);
    if (expired()) return false;
    final views = ui.PlatformDispatcher.instance.views;
    final ratio = (views.isEmpty ? 1.0 : views.first.devicePixelRatio).clamp(
      1.0,
      2.0,
    );
    recorder = ui.PictureRecorder();
    canvas = Canvas(recorder);
    canvas.drawImage(
      source,
      Offset.zero,
      Paint()
        ..imageFilter = ui.ImageFilter.blur(
          sigmaX: 16 * ratio,
          sigmaY: 16 * ratio,
          tileMode: ui.TileMode.mirror,
        ),
    );
    blurred = await _rasterWarmupPicture(recorder, dimension);
    if (expired()) return false;
    shader = program.fragmentShader();
    // Match the real Canvas lens's uniform layout and three-sample shader.
    const floats = [
      128.0,
      128.0,
      0.0,
      0.0,
      1.0,
      0.0,
      0.0,
      1.0,
      128.0,
      128.0,
      20.0,
      1.2,
      1.0,
      .055,
    ];
    for (var i = 0; i < floats.length; i++) {
      shader.setFloat(i, floats[i]);
    }
    shader.setImageSampler(0, blurred);
    recorder = ui.PictureRecorder();
    Canvas(recorder).drawRect(rect, Paint()..shader = shader);
    rendered = await _rasterWarmupPicture(recorder, dimension);
    return !expired();
  } on Object {
    return false;
  } finally {
    rendered?.dispose();
    shader?.dispose();
    blurred?.dispose();
    source?.dispose();
  }
}

Future<ui.Image> _rasterWarmupPicture(
  ui.PictureRecorder recorder,
  int dimension,
) async {
  final picture = recorder.endRecording();
  try {
    return await picture.toImage(dimension, dimension);
  } finally {
    picture.dispose();
  }
}

/// Compile/load once; each surface keeps its own mutable shader uniforms.
Future<ui.FragmentProgram?> warmSnapshotGlass() => _program ??=
    ui.FragmentProgram.fromAsset('shaders/desktop_liquid_glass.frag')
        .then<ui.FragmentProgram?>((value) => _loadedProgram = value)
        .catchError((Object _) => null);

/// Wait for a painted background before opening a modal. The frame wait also
/// works in release, where Flutter exposes no public repaint-dirty flag.
Future<GlassSnapshot?> prepareGlassSnapshot(
  BuildContext context, {
  Rect? region,
}) async {
  if (!context.mounted) return null;
  final sourceKey = GlassSnapshotSource.maybeOf(context);
  if (sourceKey == null || sourceKey.currentContext == null) return null;
  if (await warmSnapshotGlass() == null || !context.mounted) return null;
  await WidgetsBinding.instance.endOfFrame;
  if (!context.mounted || sourceKey.currentContext == null) return null;
  final snapshot = await captureGlassSnapshot(
    sourceKey,
    blur: 16,
    region: region,
  );
  if (!context.mounted || sourceKey.currentContext == null) {
    snapshot?.dispose();
    return null;
  }
  return snapshot;
}

Future<GlassSnapshot?> captureGlassSnapshot(
  GlobalKey boundaryKey, {
  double blur = 0,
  Rect? region,
}) async {
  final context = boundaryKey.currentContext;
  final boundary = context?.findRenderObject();
  if (context == null ||
      boundary is! RenderRepaintBoundary ||
      !boundary.hasSize ||
      boundary.size.isEmpty) {
    return null;
  }
  var needsPaint = false;
  // debugNeedsPaint itself is unavailable in Profile/Release builds.
  assert(() {
    needsPaint = boundary.debugNeedsPaint;
    return true;
  }());
  if (needsPaint) return null;
  final ratio = (MediaQuery.maybeDevicePixelRatioOf(context) ?? 1).clamp(
    1.0,
    2.0,
  );
  final sigma = blur.isFinite ? blur.clamp(0.0, 20.0) : 0.0;
  final fullBounds = Offset.zero & boundary.size;
  var bounds = fullBounds;
  if (region != null) {
    if (!region.left.isFinite ||
        !region.top.isFinite ||
        !region.right.isFinite ||
        !region.bottom.isFinite ||
        region.isEmpty) {
      return null;
    }
    bounds = Rect.fromPoints(
      boundary.globalToLocal(region.topLeft),
      boundary.globalToLocal(region.bottomRight),
    ).intersect(fullBounds);
    if (bounds.isEmpty) return null;
    if (boundary is! _RenderGlassSnapshotBoundary && bounds != fullBounds) {
      return null;
    }
  }
  // The raw + filtered pair has a 48 MB persistent RGBA budget. Oversized
  // windows retain live frosted glass rather than allocating unbounded images.
  final maxPixels = sigma > 0 ? 6000000 : 12000000;
  if ((bounds.width * ratio).ceil() * (bounds.height * ratio).ceil() >
      maxPixels) {
    return null;
  }
  final origin = boundary.localToGlobal(bounds.topLeft);
  ui.Image? image;
  ui.Image? filtered;
  try {
    image = boundary is _RenderGlassSnapshotBoundary
        ? await boundary.toImageRegion(bounds, ratio)
        : await boundary.toImage(pixelRatio: ratio);
    if (sigma > 0) {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawImage(
        image,
        Offset.zero,
        Paint()
          ..imageFilter = ui.ImageFilter.blur(
            sigmaX: sigma * ratio,
            sigmaY: sigma * ratio,
            tileMode: ui.TileMode.mirror,
          ),
      );
      final picture = recorder.endRecording();
      try {
        filtered = await picture.toImage(image.width, image.height);
      } finally {
        picture.dispose();
      }
    }
    return GlassSnapshot(
      image: image,
      blurredImage: filtered,
      blurredSigma: sigma,
      origin: origin,
      pixelRatio: ratio,
    );
  } on Object {
    filtered?.dispose();
    image?.dispose();
    return null;
  }
}

/// A real image-sampling lens, restricted to frozen modal backdrops on Skia.
/// It cannot replace a continuously changing live-backdrop shader filter.
class SnapshotGlassBackdrop extends StatefulWidget {
  const SnapshotGlassBackdrop({
    required this.fallback,
    super.key,
    this.radius = 16,
    this.blur = 16,
    this.saturation = 1.2,
    this.refraction = 1,
    this.lightIntensity = .055,
  });
  final Widget fallback;
  final double radius, blur, saturation, refraction, lightIntensity;
  @override
  State<SnapshotGlassBackdrop> createState() => _SnapshotGlassBackdropState();
}

class _SnapshotGlassBackdropState extends State<SnapshotGlassBackdrop> {
  ui.FragmentShader? _shader;
  bool _loading = false;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final snapshot = SnapshotGlassScope.maybeOf(context);
    if (snapshot == null ||
        snapshot.isDisposed ||
        _shader != null ||
        _loading) {
      return;
    }
    final loaded = _loadedProgram;
    if (loaded != null) {
      _shader = loaded.fragmentShader();
      return;
    }
    _loading = true;
    warmSnapshotGlass().then((program) {
      if (!mounted || program == null) return;
      setState(() => _shader = program.fragmentShader());
    });
  }

  @override
  void dispose() {
    _shader?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = SnapshotGlassScope.maybeOf(context);
    final shader = _shader;
    if (snapshot == null || snapshot.isDisposed || shader == null) {
      return widget.fallback;
    }
    // A raw-only snapshot cannot provide genuine Gaussian diffusion. Keep the
    // existing live filter if the modal's one-off preprocessing was unavailable.
    if (widget.blur > 0 && snapshot.blurredImage == null) {
      return widget.fallback;
    }
    return _SnapshotLens(
      shader: shader,
      snapshot: snapshot,
      radius: widget.radius,
      blur: widget.blur,
      saturation: widget.saturation,
      refraction: widget.refraction,
      lightIntensity: widget.lightIntensity,
      repaint: SnapshotGlassScope.repaintOf(context),
    );
  }
}

class _SnapshotLens extends LeafRenderObjectWidget {
  const _SnapshotLens({
    required this.shader,
    required this.snapshot,
    required this.radius,
    required this.blur,
    required this.saturation,
    required this.refraction,
    required this.lightIntensity,
    required this.repaint,
  });
  final ui.FragmentShader shader;
  final GlassSnapshot snapshot;
  final double radius, blur, saturation, refraction, lightIntensity;
  final Listenable? repaint;
  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderSnapshotLens(this);
  @override
  void updateRenderObject(
    BuildContext context,
    _RenderSnapshotLens renderObject,
  ) => renderObject.configuration = this;
}

class _RenderSnapshotLens extends RenderBox {
  _RenderSnapshotLens(this._configuration);
  _SnapshotLens _configuration;
  set configuration(_SnapshotLens value) {
    if (attached && _configuration.repaint != value.repaint) {
      _configuration.repaint?.removeListener(markNeedsPaint);
      value.repaint?.addListener(markNeedsPaint);
    }
    _configuration = value;
    markNeedsPaint();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _configuration.repaint?.addListener(markNeedsPaint);
  }

  @override
  void detach() {
    _configuration.repaint?.removeListener(markNeedsPaint);
    super.detach();
  }

  @override
  void performLayout() => size = constraints.biggest;
  @override
  void paint(PaintingContext context, Offset offset) {
    final config = _configuration;
    if (size.isEmpty || config.snapshot.isDisposed) return;
    final transform = getTransformTo(null);
    final global = localToGlobal(Offset.zero) - config.snapshot.origin;
    final floats = <double>[
      size.width,
      size.height,
      global.dx,
      global.dy,
      transform.entry(0, 0),
      transform.entry(0, 1),
      transform.entry(1, 0),
      transform.entry(1, 1),
      config.snapshot.logicalSize.width,
      config.snapshot.logicalSize.height,
      config.radius.clamp(0.0, size.shortestSide / 2),
      config.saturation.clamp(0.0, 2.0),
      config.refraction.clamp(0.0, 1.5),
      config.lightIntensity.clamp(0.0, .15),
    ];
    for (var i = 0; i < floats.length; i++) {
      config.shader.setFloat(i, floats[i]);
    }
    config.shader.setImageSampler(
      0,
      config.blur > 0 ? config.snapshot.blurredImage! : config.snapshot.image,
    );
    final canvas = context.canvas;
    canvas.save();
    // FlutterFragCoord is relative to this lens even when the route animates.
    canvas.translate(offset.dx, offset.dy);
    canvas.drawRect(Offset.zero & size, Paint()..shader = config.shader);
    canvas.restore();
  }
}

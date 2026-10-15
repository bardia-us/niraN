// Isolated Windows renderer benchmark: no account, API, proxy, or TUN calls.
import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:niran/core/theme/app_theme.dart';
import 'package:niran/core/widgets/glass_dialog.dart';
import 'package:niran/core/widgets/glass_menu.dart';
import 'package:niran/features/vpn/app_controller.dart';
import 'package:niran/core/widgets/windows_glass_shader_warmup.dart';

void main() {
  PaintingBinding.shaderWarmUp = const WindowsGlassShaderWarmUp();
  runApp(
    ProviderScope(
      overrides: [performanceModeProvider.overrideWithValue(false)],
      child: const _Bench(),
    ),
  );
}

class _Bench extends StatefulWidget {
  const _Bench();
  @override
  State<_Bench> createState() => _BenchState();
}

class _BenchState extends State<_Bench> {
  final navigator = GlobalKey<NavigatorState>();
  final captureKey = GlobalKey();
  final frames = <String, List<List<double>>>{};
  String? phase;
  bool dark = true;
  @override
  void initState() {
    super.initState();
    SchedulerBinding.instance.addTimingsCallback(_timings);
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_run()));
  }

  void _timings(List<FrameTiming> timings) {
    final key = phase;
    if (key == null) return;
    frames
        .putIfAbsent(key, () => [])
        .addAll(
          timings.map(
            (t) => [
              t.buildDuration.inMicroseconds / 1000,
              t.rasterDuration.inMicroseconds / 1000,
            ],
          ),
        );
  }

  Future<void> _run() async {
    await Future<void>.delayed(const Duration(seconds: 1));
    for (final isDark in [true, false]) {
      setState(() => dark = isDark);
      await Future<void>.delayed(const Duration(milliseconds: 400));
      for (final kind in ['menu', 'dialog']) {
        for (var cycle = 0; cycle < 3; cycle++) {
          phase =
              '${dark ? 'dark' : 'light'}-$kind-${cycle == 0 ? 'cold' : 'warm'}';
          final context = navigator.currentState!.overlay!.context;
          if (!context.mounted) return;
          final future = kind == 'menu'
              ? showGlassMenu<int>(
                  context: context,
                  position: const Offset(750, 110),
                  items: const [
                    GlassMenuItem(
                      value: 1,
                      icon: Icons.restart_alt,
                      label: 'Restart Core',
                    ),
                    GlassMenuItem(
                      value: 2,
                      icon: Icons.sort,
                      label: 'Sort by results',
                    ),
                    GlassMenuItem(
                      value: 3,
                      icon: Icons.speed,
                      label: 'Test TCP delays',
                    ),
                    GlassMenuItem(
                      value: 4,
                      icon: Icons.timer,
                      label: 'Test real delays',
                    ),
                    GlassMenuItem(
                      value: 5,
                      icon: Icons.sync,
                      label: 'Update now',
                    ),
                  ],
                )
              : showNirangDialog<int>(
                  context: context,
                  builder: (context) => NirangAlertDialog(
                    title: const Text('Language'),
                    content: const Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ListTile(
                          title: Text('English'),
                          leading: Icon(Icons.radio_button_checked),
                        ),
                        ListTile(
                          title: Text('فارسی'),
                          leading: Icon(Icons.radio_button_off),
                        ),
                      ],
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Cancel'),
                      ),
                    ],
                  ),
                );
          await Future<void>.delayed(const Duration(milliseconds: 240));
          if (cycle == 2 && kind == 'menu') {
            // Keep screenshot readback out of the animation timing samples.
            phase = null;
            final boundary =
                captureKey.currentContext!.findRenderObject()
                    as RenderRepaintBoundary;
            final image = await boundary.toImage();
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            await File(
              'build/glass-menu-${dark ? 'dark' : 'light'}.png',
            ).writeAsBytes(bytes!.buffer.asUint8List(), flush: true);
            image.dispose();
            phase = '${dark ? 'dark' : 'light'}-$kind-warm';
          }
          navigator.currentState!.pop();
          await future;
          await Future<void>.delayed(const Duration(milliseconds: 240));
          if (cycle == 0 && kind == 'menu') {
            await _captureTimeline('${dark ? 'dark' : 'light'}-cold');
          }
          phase = null;
        }
      }
    }
    final report = <String, Object?>{};
    for (final entry in frames.entries) {
      final ui = entry.value.map((f) => f[0]).toList()..sort();
      final raster = entry.value.map((f) => f[1]).toList()..sort();
      double p95(List<double> values) =>
          values[((values.length - 1) * .95).round()];
      report[entry.key] = {
        'frames': ui.length,
        'uiP95Ms': p95(ui),
        'rasterP95Ms': p95(raster),
        'rasterMaxMs': raster.last,
        'over8_33ms': entry.value
            .where((f) => f[0] > 8.33 || f[1] > 8.33)
            .length,
        'over16_67ms': entry.value
            .where((f) => f[0] > 16.67 || f[1] > 16.67)
            .length,
      };
    }
    await File('build/popup-profile.json').writeAsString(
      const JsonEncoder.withIndent('  ').convert(report),
      flush: true,
    );
    await _captureTimeline('last');
    await const MethodChannel(
      'dev.niran.windows/host',
    ).invokeMethod<void>('exitApplication');
  }

  Future<void> _captureTimeline(String name) async {
    final service = await developer.Service.getInfo();
    if (service.serverUri != null) {
      final client = HttpClient()..findProxy = (_) => 'DIRECT';
      try {
        final request = await client.getUrl(
          service.serverUri!.resolve('getVMTimeline'),
        );
        final response = await request.close();
        final timeline = await response.transform(utf8.decoder).join();
        await File('build/popup-timeline-$name.json').writeAsString(timeline);
      } finally {
        client.close(force: true);
      }
    }
  }

  @override
  void dispose() {
    SchedulerBinding.instance.removeTimingsCallback(_timings);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    navigatorKey: navigator,
    builder: (_, child) => RepaintBoundary(key: captureKey, child: child!),
    theme: dark ? AppTheme.dark : AppTheme.light,
    home: Scaffold(
      body: ListView.builder(
        itemCount: 60,
        itemBuilder: (_, i) => ListTile(
          leading: CircleAvatar(
            backgroundColor: Colors.primaries[i % Colors.primaries.length],
            child: Text('$i'),
          ),
          title: Text('Synthetic server row $i'),
          subtitle: const Text('High contrast background text behind popup'),
          trailing: Text(
            '${30 + i} ms',
            style: const TextStyle(color: Colors.green),
          ),
        ),
      ),
    ),
  );
}

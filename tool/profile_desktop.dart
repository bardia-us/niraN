// Actual application pages with synthetic state. No registration, network,
// persisted app data, proxy, TUN or real server operations are invoked.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:niran/core/platform/native_models.dart';
import 'package:niran/core/widgets/windows_glass_shader_warmup.dart';
import 'package:niran/features/vpn/app_controller.dart';
import 'package:niran/main.dart';

void main() {
  PaintingBinding.shaderWarmUp = const WindowsGlassShaderWarmUp();
  runApp(
    ProviderScope(
      overrides: [appControllerProvider.overrideWith(_PreviewController.new)],
      child: const _Preview(),
    ),
  );
}

class _PreviewController extends AppController {
  @override
  Future<AppSnapshot> build() async => const AppSnapshot(
    appVersion: '',
    subscriptionConfigured: true,
    settings: NativeSettings(
      themeMode: 'dark',
      performanceModePrompted: true,
      showRecentLogsOnHome: true,
    ),
    connection: ConnectionInfo(
      state: 'connected',
      publicIp: '2001:db8::1',
      publicCity: 'Paris',
      publicCountry: 'FR',
      publicIpChecked: true,
    ),
    servers: [
      ServerInfo(
        id: 'one',
        name: '🇮🇷 آلمان نیم بها 🇩🇪',
        country: 'DE',
        protocol: 'VLESS',
        transport: 'XHTTP',
        security: 'TLS',
        port: 443,
        selected: true,
        ping: 92,
        status: 'success',
      ),
      ServerInfo(
        id: 'two',
        selected: false,
        name: '🇫🇷 Paris · Europe',
        country: 'FR',
        protocol: 'Trojan',
        transport: 'TCP',
        security: 'TLS',
        port: 443,
        ping: 128,
        status: 'success',
      ),
      ServerInfo(
        id: 'three',
        selected: false,
        name: 'Private route 🇳🇱',
        country: 'NL',
        protocol: 'VMess',
        transport: 'WS',
        security: 'TLS',
        port: 443,
        ping: 149,
        status: 'success',
      ),
    ],
    usage: SubscriptionUsage(
      used: 8 * 1024 * 1024 * 1024,
      total: 80 * 1024 * 1024 * 1024,
    ),
  );

  @override
  Future<void> updateSettings(Map<String, Object?> values) async {
    state = AsyncData(
      state.requireValue.copyWith(
        settings: state.requireValue.settings.withUpdates(values),
      ),
    );
  }

  @override
  Future<void> refreshLogs() async {}
}

class _Preview extends ConsumerStatefulWidget {
  const _Preview();
  @override
  ConsumerState<_Preview> createState() => _PreviewState();
}

class _PreviewState extends ConsumerState<_Preview> {
  final capture = GlobalKey();
  final frames = <String, List<FrameTiming>>{};
  String? phase;
  @override
  void initState() {
    super.initState();
    SchedulerBinding.instance.addTimingsCallback(_timings);
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_run()));
  }

  void _timings(List<FrameTiming> batch) {
    if (phase case final value?) {
      frames.putIfAbsent(value, () => []).addAll(batch);
    }
  }

  NavigationRail _rail() {
    NavigationRail? result;
    void walk(Element element) {
      if (element.widget is NavigationRail) {
        result = element.widget as NavigationRail;
      }
      element.visitChildren(walk);
    }

    (capture.currentContext! as Element).visitChildren(walk);
    return result!;
  }

  Future<void> _run() async {
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    for (final mode in ['dark', 'light']) {
      await ref.read(appControllerProvider.notifier).updateSettings({
        'themeMode': mode,
      });
      await Future<void>.delayed(const Duration(milliseconds: 350));
      for (final index in [1, 2, 3, 0, 1, 2, 0]) {
        phase = '$mode-page-$index';
        _rail().onDestinationSelected!(index);
        await Future<void>.delayed(const Duration(milliseconds: 300));
        phase = null;
        final boundary =
            capture.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final image = await boundary.toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File(
          'build/desktop-$mode-$index.png',
        ).writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      }
    }
    final report = <String, Object>{};
    for (final entry in frames.entries) {
      if (entry.value.isEmpty) continue;
      final build =
          entry.value.map((t) => t.buildDuration.inMicroseconds / 1000).toList()
            ..sort();
      final raster =
          entry.value
              .map((t) => t.rasterDuration.inMicroseconds / 1000)
              .toList()
            ..sort();
      report[entry.key] = {
        'frames': raster.length,
        'buildP95Ms': build[((build.length - 1) * .95).round()],
        'rasterP95Ms': raster[((raster.length - 1) * .95).round()],
        'rasterMaxMs': raster.last,
        'over8_33ms': entry.value
            .where(
              (t) =>
                  t.buildDuration.inMicroseconds > 8333 ||
                  t.rasterDuration.inMicroseconds > 8333,
            )
            .length,
        'over16_67ms': entry.value
            .where(
              (t) =>
                  t.buildDuration.inMicroseconds > 16667 ||
                  t.rasterDuration.inMicroseconds > 16667,
            )
            .length,
      };
    }
    await File(
      'build/desktop-profile.json',
    ).writeAsString(const JsonEncoder.withIndent('  ').convert(report));
    await const MethodChannel(
      'dev.niran.windows/host',
    ).invokeMethod<void>('exitApplication');
  }

  @override
  void dispose() {
    SchedulerBinding.instance.removeTimingsCallback(_timings);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      RepaintBoundary(key: capture, child: const NirangApp());
}

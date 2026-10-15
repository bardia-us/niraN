// Renderer-only benchmark. Synthetic controls, no credentials, native backend,
// connections, updater downloads, registration, or persisted user settings.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:niran/core/theme/app_theme.dart';
import 'package:niran/core/widgets/settings_group.dart';
import 'package:niran/core/widgets/windows_glass_shader_warmup.dart';

void main() {
  PaintingBinding.shaderWarmUp = const WindowsGlassShaderWarmUp();
  runApp(const _SettingsBench());
}

class _SettingsBench extends StatefulWidget {
  const _SettingsBench();
  @override
  State<_SettingsBench> createState() => _SettingsBenchState();
}

class _SettingsBenchState extends State<_SettingsBench> {
  final controller = ExpansibleController();
  final samples = <String, List<FrameTiming>>{};
  String? phase;
  bool dark = true, baseline = true;
  @override
  void initState() {
    super.initState();
    SchedulerBinding.instance.addTimingsCallback(_timings);
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_run()));
  }

  void _timings(List<FrameTiming> frames) {
    if (phase case final key?) {
      samples.putIfAbsent(key, () => []).addAll(frames);
    }
  }

  Future<void> _run() async {
    await Future<void>.delayed(const Duration(milliseconds: 600));
    for (final isDark in [true, false]) {
      for (final useBaseline in [true, false]) {
        setState(() {
          dark = isDark;
          baseline = useBaseline;
        });
        await Future<void>.delayed(const Duration(milliseconds: 400));
        for (var cycle = 0; cycle < 4; cycle++) {
          phase =
              '${dark ? 'dark' : 'light'}-${baseline ? 'before' : 'cached'}-${cycle == 0 ? 'cold' : 'warm'}';
          controller.expand();
          await Future<void>.delayed(const Duration(milliseconds: 450));
          controller.collapse();
          await Future<void>.delayed(const Duration(milliseconds: 450));
          phase = null;
        }
      }
    }
    final report = <String, Object>{};
    for (final entry in samples.entries) {
      final builds =
          entry.value
              .map((frame) => frame.buildDuration.inMicroseconds / 1000)
              .toList()
            ..sort();
      final raster =
          entry.value
              .map((frame) => frame.rasterDuration.inMicroseconds / 1000)
              .toList()
            ..sort();
      report[entry.key] = {
        'frames': builds.length,
        'buildP95Ms': builds[((builds.length - 1) * .95).round()],
        'rasterP95Ms': raster[((raster.length - 1) * .95).round()],
        'rasterMaxMs': raster.last,
        'over16ms': entry.value
            .where(
              (frame) =>
                  frame.buildDuration.inMicroseconds > 16667 ||
                  frame.rasterDuration.inMicroseconds > 16667,
            )
            .length,
      };
    }
    await File(
      'build/settings-profile.json',
    ).writeAsString(const JsonEncoder.withIndent('  ').convert(report));
    exit(0);
  }

  @override
  void dispose() {
    SchedulerBinding.instance.removeTimingsCallback(_timings);
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    theme: dark ? AppTheme.dark : AppTheme.light,
    home: Scaffold(
      appBar: AppBar(title: const Text('Settings renderer measurement')),
      body: Builder(
        builder: (context) {
          final children = <Widget>[
            const ListTile(
              leading: Icon(Icons.system_update_alt),
              title: Text('Check for updates'),
              subtitle: Text('Current version: unchanged'),
            ),
            const ListTile(
              leading: Icon(Icons.download_done),
              title: Text('Download information'),
              subtitle: Text('Synthetic renderer fixture'),
            ),
          ];
          return ListView(
            children: [
              if (baseline)
                ExpansionTile(
                  key: const ValueKey('before'),
                  controller: controller,
                  maintainState: true,
                  tilePadding: const EdgeInsets.symmetric(horizontal: 16),
                  childrenPadding: const EdgeInsets.only(bottom: 6),
                  shape: Border(
                    bottom: BorderSide(
                      color: Theme.of(
                        context,
                      ).colorScheme.outlineVariant.withValues(alpha: .45),
                    ),
                  ),
                  collapsedShape: Border(
                    bottom: BorderSide(
                      color: Theme.of(
                        context,
                      ).colorScheme.outlineVariant.withValues(alpha: .30),
                    ),
                  ),
                  title: Text(
                    'UPDATES',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      letterSpacing: .8,
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  children: children,
                )
              else
                SettingsGroup(
                  key: const ValueKey('cached'),
                  title: 'Updates',
                  controller: controller,
                  children: children,
                ),
            ],
          );
        },
      ),
    ),
  );
}

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../features/vpn/app_controller.dart';

bool lightweightRenderingOf(BuildContext context) {
  try {
    return ProviderScope.containerOf(
      context,
      listen: false,
    ).read(performanceModeProvider);
  } on StateError {
    return false; // Standalone widgets keep their existing normal appearance.
  }
}

/// Read only the existing preference before any optional graphics initialize.
/// The ProviderScope freezes this value for the entire process lifetime.
Future<bool> readStartupPerformanceMode(Directory directory) async {
  for (final suffix in ['state.json', 'state.json.bak']) {
    final file = File('${directory.path}${Platform.pathSeparator}$suffix');
    try {
      if (!await file.exists()) continue;
      if (await file.length() > 4 * 1024 * 1024) return false;
      final state = jsonDecode(await file.readAsString());
      if (state is Map && state['settings'] is Map) {
        return (state['settings'] as Map)['performanceMode'] == true;
      }
      return false;
    } on Object {
      // Corrupt/unavailable preferences must not prevent a normal launch.
      // Match existing backend defaults for corrupt primary files; backups
      // are recovered only when the primary is absent. Do not mutate storage.
      return false;
    }
  }
  return false;
}

/// Tint-only chrome. No blur, capture, image filter, rim shader or saveLayer.
class LightweightChrome extends StatelessWidget {
  const LightweightChrome({required this.child, this.radius = 0, super.key});
  final Widget child;
  final double radius;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final opaque =
        context.dependOnInheritedWidgetOfExactType<LightweightModalScope>() !=
        null;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface.withValues(alpha: opaque ? 1 : .90),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: colors.outlineVariant.withValues(alpha: .48)),
      ),
      child: child,
    );
  }
}

/// Modal bodies are solid in lightweight mode; toolbar tint stays independent.
class LightweightModalScope extends InheritedWidget {
  const LightweightModalScope({required super.child, super.key});
  @override
  bool updateShouldNotify(LightweightModalScope oldWidget) => false;
}

/// The only lightweight backdrop filter: a bounded toolbar, no lens or capture.
class LightweightHeader extends StatelessWidget {
  const LightweightHeader({super.key});
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return ClipRect(
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 5, sigmaY: 5),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colors.surface.withValues(
              alpha: theme.brightness == Brightness.dark ? .66 : .72,
            ),
            border: Border(
              bottom: BorderSide(
                color: colors.outlineVariant.withValues(alpha: .5),
              ),
            ),
          ),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}

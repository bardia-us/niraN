import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart' as glass;
import '../../features/vpn/app_controller.dart';
import 'glass_surface.dart';
import 'live_liquid_glass.dart';

class GlassMenuButton extends ConsumerWidget {
  const GlassMenuButton({
    required this.onPressed,
    required this.tooltip,
    this.icon = const UnequalMenuIcon(),
    this.focusNode,
    super.key,
  });
  final VoidCallback onPressed;
  final String tooltip;
  final Widget icon;
  final FocusNode? focusNode;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(performanceModeProvider) || !liveGlassReady) {
      return GlassSurface(
        radius: 22,
        liveLiquid: true,
        child: IconButton(
          onPressed: onPressed,
          tooltip: tooltip,
          focusNode: focusNode,
          icon: icon,
        ),
      );
    }
    return Tooltip(
      message: tooltip,
      child: glass.GlassIconButton(
        icon: IconTheme.merge(
          data: IconThemeData(color: Theme.of(context).colorScheme.onSurface),
          child: icon,
        ),
        onPressed: onPressed,
        focusNode: focusNode,
        semanticLabel: tooltip,
        useOwnLayer: true,
        quality: glass.GlassQuality.premium,
        settings: niranLiquidSettings(Theme.of(context).brightness),
      ),
    );
  }
}

class UnequalMenuIcon extends StatelessWidget {
  const UnequalMenuIcon({super.key});
  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: 22,
    child: CustomPaint(
      painter: _MenuPainter(
        IconTheme.of(context).color ?? Theme.of(context).colorScheme.onSurface,
      ),
    ),
  );
}

class _MenuPainter extends CustomPainter {
  const _MenuPainter(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.9
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(const Offset(2, 5), const Offset(20, 5), paint);
    canvas.drawLine(const Offset(5, 11), const Offset(20, 11), paint);
    canvas.drawLine(const Offset(9, 17), const Offset(20, 17), paint);
  }

  @override
  bool shouldRepaint(_MenuPainter old) => color != old.color;
}

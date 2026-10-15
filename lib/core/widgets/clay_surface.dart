import 'package:flutter/material.dart';
import '../render_mode.dart';

/// Small clay accents, with no offscreen shader or background capture.
class ClaySurface extends StatelessWidget {
  const ClaySurface({
    required this.child,
    this.selected = false,
    this.radius = 16,
    this.tint,
    this.borderColor,
    this.raised = false,
    super.key,
  });
  final Widget child;
  final bool selected;
  final double radius;
  final Color? tint;
  final Color? borderColor;

  /// Approved raised proxy-control variant; small existing clay accents stay intact.
  final bool raised;
  @override
  Widget build(BuildContext context) {
    final lightweight = lightweightRenderingOf(context);
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    final tint =
        this.tint ??
        (selected ? colors.primaryContainer : colors.surfaceContainerHigh);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: raised
              ? (dark
                    ? const [Color(0xFF51525E), Color(0xFF34353F)]
                    : const [Color(0xFFEDEBF5), Color(0xFFD8D5E3)])
              : [tint.withValues(alpha: .88), tint.withValues(alpha: .66)],
        ),
        border: Border.all(
          color:
              borderColor ??
              (raised
                  ? (dark ? const Color(0xFF5B5C6B) : const Color(0xFFC3BFD1))
                  : colors.onSurface.withValues(alpha: dark ? .08 : .06)),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(
              alpha: lightweight
                  ? (dark ? .16 : .08)
                  : (raised ? (dark ? .5 : .12) : (dark ? .13 : .07)),
            ),
            offset: lightweight
                ? const Offset(0, 2)
                : (raised ? const Offset(0, 4) : const Offset(2, 3)),
            blurRadius: lightweight ? 0 : (raised ? 10 : 7),
          ),
          BoxShadow(
            color: Colors.white.withValues(
              alpha: lightweight
                  ? (dark ? .07 : .35)
                  : (raised ? (dark ? .14 : .6) : (dark ? .05 : .30)),
            ),
            offset: lightweight
                ? const Offset(-1, -1)
                : (raised ? const Offset(-3, -3) : const Offset(-1, -1)),
            blurRadius: lightweight ? 0 : (raised ? 6 : 4),
          ),
        ],
      ),
      child: child,
    );
  }
}

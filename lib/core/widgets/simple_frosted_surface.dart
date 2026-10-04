import 'dart:ui';

import 'package:flutter/material.dart';

/// Lightweight frosted material for logs/chrome, not a refractive glass lens.
class SimpleFrostedSurface extends StatelessWidget {
  const SimpleFrostedSurface({
    required this.child,
    this.radius = 18,
    this.blur = 10,
    super.key,
  });
  final Widget child;
  final double radius, blur;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colors.surface.withValues(alpha: .64),
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(
              color: colors.outlineVariant.withValues(alpha: .35),
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}

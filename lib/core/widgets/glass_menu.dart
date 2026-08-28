import 'package:flutter/material.dart';

import 'glass_surface.dart';

class GlassMenuItem<T> {
  const GlassMenuItem({
    required this.value,
    required this.icon,
    required this.label,
    this.destructive = false,
  });

  final T value;
  final IconData icon;
  final String label;
  final bool destructive;
}

Future<T?> showGlassMenu<T>({
  required BuildContext context,
  required Offset position,
  required List<GlassMenuItem<T>> items,
}) {
  final size = MediaQuery.sizeOf(context);
  const width = 244.0;
  final estimatedHeight = items.length * 48.0 + 16;
  final left = position.dx.clamp(10.0, size.width - width - 10);
  final top = position.dy.clamp(10.0, size.height - estimatedHeight - 10);
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Theme.of(context).colorScheme.scrim.withValues(alpha: .16),
    transitionDuration: const Duration(milliseconds: 180),
    pageBuilder: (routeContext, _, _) => Stack(
      children: [
        Positioned(
          left: left,
          top: top,
          width: width,
          child: Material(
            color: Colors.transparent,
            child: GlassSurface(
              radius: 18,
              blur: 22,
              padding: const EdgeInsets.symmetric(vertical: 7),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final item in items)
                    ListTile(
                      dense: true,
                      minTileHeight: 46,
                      leading: Icon(
                        item.icon,
                        size: 20,
                        color: item.destructive
                            ? Theme.of(routeContext).colorScheme.error
                            : null,
                      ),
                      title: Text(
                        item.label,
                        style: item.destructive
                            ? TextStyle(
                                color: Theme.of(routeContext).colorScheme.error,
                              )
                            : null,
                      ),
                      onTap: () => Navigator.pop(routeContext, item.value),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    ),
    transitionBuilder: (_, animation, _, child) => FadeTransition(
      opacity: CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
      child: ScaleTransition(
        scale: Tween(begin: .94, end: 1.0).animate(
          CurvedAnimation(parent: animation, curve: Curves.easeOutBack),
        ),
        alignment: Alignment.topLeft,
        child: child,
      ),
    ),
  );
}

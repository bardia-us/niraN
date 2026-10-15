import 'package:flutter/material.dart';

import 'interactive_depth.dart';

/// The same control in all four placements and all selection states.
class NavigationDock extends StatelessWidget {
  const NavigationDock({
    required this.destinations,
    required this.selectedIndex,
    required this.onSelected,
    required this.vertical,
    super.key,
  });
  final List<NavigationDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final bool vertical;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    Widget item(int i) {
      final selected = selectedIndex == i;
      final destination = destinations[i];
      final foreground = selected ? colors.primary : colors.onSurfaceVariant;
      return Semantics(
        selected: selected,
        child: InteractiveDepth(
          radius: 20,
          tiltEnabled: false,
          child: TextButton(
            key: Key('navigation-tab-$i'),
            onPressed: () => onSelected(i),
            style: ButtonStyle(
              minimumSize: const WidgetStatePropertyAll(Size(72, 64)),
              padding: const WidgetStatePropertyAll(
                EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              ),
              foregroundColor: WidgetStatePropertyAll(foreground),
              backgroundColor: WidgetStatePropertyAll(
                selected
                    ? colors.primaryContainer.withValues(alpha: .65)
                    : Colors.transparent,
              ),
              overlayColor: WidgetStateProperty.resolveWith(
                (states) => states.contains(WidgetState.pressed)
                    ? colors.onSurface.withValues(alpha: .10)
                    : states.contains(WidgetState.hovered) ||
                          states.contains(WidgetState.focused)
                    ? colors.onSurface.withValues(alpha: .06)
                    : Colors.transparent,
              ),
              shape: const WidgetStatePropertyAll(
                RoundedRectangleBorder(
                  borderRadius: BorderRadius.all(Radius.circular(20)),
                ),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconTheme(
                  data: IconThemeData(size: 24, color: foreground),
                  child: selected
                      ? destination.selectedIcon ?? destination.icon
                      : destination.icon,
                ),
                const SizedBox(height: 4),
                Text(
                  destination.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Padding(
      key: const Key('navigation-dock'),
      padding: const EdgeInsets.all(8),
      child: vertical
          ? SizedBox(
              width: 80,
              child: Column(
                children: [
                  const SizedBox(height: 10),
                  for (var i = 0; i < destinations.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: item(i),
                    ),
                ],
              ),
            )
          : ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 64),
              child: Row(
                children: [
                  for (var i = 0; i < destinations.length; i++)
                    Expanded(child: item(i)),
                ],
              ),
            ),
    );
  }
}

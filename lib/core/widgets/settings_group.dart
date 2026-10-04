import 'package:flutter/material.dart';

/// Retained settings section with the standard accessible Flutter expansion.
class SettingsGroup extends StatelessWidget {
  const SettingsGroup({
    required this.title,
    required this.children,
    super.key,
    this.controller,
    this.initiallyExpanded = false,
    this.icon = Icons.tune_rounded,
  });

  final String title;
  final List<Widget> children;
  final ExpansibleController? controller;
  final bool initiallyExpanded;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: ExpansionTile(
      key: PageStorageKey(title),
      controller: controller,
      initiallyExpanded: initiallyExpanded,
      maintainState: true,
      expansionAnimationStyle: MediaQuery.disableAnimationsOf(context)
          ? AnimationStyle.noAnimation
          : const AnimationStyle(
              duration: Duration(milliseconds: 220),
              reverseDuration: Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              reverseCurve: Curves.easeInCubic,
            ),
      tilePadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
      childrenPadding: const EdgeInsets.only(bottom: 12),
      backgroundColor: Theme.of(
        context,
      ).colorScheme.surfaceContainerLow.withValues(alpha: .72),
      collapsedBackgroundColor: Theme.of(
        context,
      ).colorScheme.surfaceContainerLow.withValues(alpha: .72),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: Theme.of(
            context,
          ).colorScheme.outlineVariant.withValues(alpha: .38),
        ),
      ),
      collapsedShape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: Theme.of(
            context,
          ).colorScheme.outlineVariant.withValues(alpha: .38),
        ),
      ),
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: .10),
          borderRadius: BorderRadius.circular(11),
        ),
        child: Icon(
          icon,
          size: 20,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
      title: Text(
        title.toUpperCase(),
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          letterSpacing: .8,
          color: Theme.of(context).colorScheme.primary,
          fontWeight: FontWeight.w700,
        ),
      ),
      children: [RepaintBoundary(child: Column(children: children))],
    ),
  );
}

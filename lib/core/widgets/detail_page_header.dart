import 'package:flutter/material.dart';
import 'dart:ui';

import 'clay_surface.dart';
import 'interactive_depth.dart';
import '../theme/app_theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../features/vpn/app_controller.dart';
import '../render_mode.dart';

class DetailPageHeader extends ConsumerWidget implements PreferredSizeWidget {
  const DetailPageHeader({required this.title, super.key});
  final String title;
  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context, WidgetRef ref) => AppBar(
    title: Text(title),
    backgroundColor: Colors.transparent,
    surfaceTintColor: Colors.transparent,
    elevation: 0,
    scrolledUnderElevation: 0,
    flexibleSpace: ref.watch(performanceModeProvider)
        ? const LightweightHeader()
        : ClipRect(
            child: BackdropFilter(
              filter: ImageFilter.blur(
                sigmaX: NirangVisualEffects.chromeBlur(Theme.of(context), 12),
                sigmaY: NirangVisualEffects.chromeBlur(Theme.of(context), 12),
              ),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface.withValues(
                    alpha: Theme.of(context).brightness == Brightness.dark
                        ? .10
                        : .32,
                  ),
                  border: Border(
                    bottom: BorderSide(
                      color: Theme.of(
                        context,
                      ).colorScheme.outline.withValues(alpha: .12),
                    ),
                  ),
                ),
                child: const SizedBox.expand(),
              ),
            ),
          ),
    leading: Padding(
      padding: const EdgeInsets.all(8),
      child: InteractiveDepth(
        radius: 20,
        tiltEnabled: false,
        child: ClaySurface(
          radius: 20,
          child: IconButton(
            tooltip: MaterialLocalizations.of(context).backButtonTooltip,
            style: IconButton.styleFrom(shape: const CircleBorder()),
            onPressed: () => Navigator.maybePop(context),
            icon: const BackButtonIcon(),
          ),
        ),
      ),
    ),
  );
}

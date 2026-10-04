import 'package:flutter/material.dart';

import 'glass_surface.dart';
import 'animated_popup_surface.dart';
import 'snapshot_glass_route.dart';
import 'live_liquid_glass.dart';

Future<T?> showNirangDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
}) => showSnapshotGlassRoute<T>(
  context: context,
  useLiveBackdrop: liveGlassReady,
  barrierDismissible: barrierDismissible,
  captureRegion: Rect.fromCenter(
    center: MediaQuery.sizeOf(context).center(Offset.zero),
    width: 656,
    height: MediaQuery.sizeOf(context).height * .78 + 96,
  ),
  transitionDuration: MediaQuery.disableAnimationsOf(context)
      ? Duration.zero
      : const Duration(milliseconds: 140),
  pageBuilder: (routeContext, _, _) => builder(routeContext),
  // A BackdropFilter inside FadeTransition is rendered through an opacity
  // save-layer, which can expose the unfiltered backdrop on Windows. Keep the
  // glass fully painted from frame one and animate geometry only.
  transitionBuilder: (_, animation, _, child) =>
      AnimatedPopupSurface(animation: animation, child: child),
);

class NirangAlertDialog extends StatelessWidget {
  const NirangAlertDialog({
    super.key,
    this.icon,
    this.title,
    this.content,
    this.actions = const [],
    this.contentPadding = const EdgeInsets.fromLTRB(22, 14, 22, 8),
  });

  final Widget? icon;
  final Widget? title;
  final Widget? content;
  final List<Widget> actions;
  final EdgeInsetsGeometry contentPadding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final maxHeight = MediaQuery.sizeOf(context).height * .78;
    return Dialog(
      elevation: 0,
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      child: GlassSurface(
        radius: 22,
        blur: liveGlassReady ? messagesLiquidBlur : 16,
        saturation: liveGlassReady ? messagesLiquidSaturation : 1.20,
        liveLiquid: true,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 560, maxHeight: maxHeight),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (icon != null) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 20, 22, 4),
                  child: IconTheme(
                    data: IconThemeData(
                      color: theme.colorScheme.secondary,
                      size: 28,
                    ),
                    child: Center(child: icon),
                  ),
                ),
              ],
              if (title != null)
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    22,
                    icon == null ? 20 : 8,
                    22,
                    0,
                  ),
                  child: DefaultTextStyle(
                    style: theme.textTheme.headlineSmall!.copyWith(
                      color: theme.colorScheme.onSurface,
                    ),
                    child: title!,
                  ),
                ),
              if (content != null)
                Flexible(
                  child: SingleChildScrollView(
                    padding: contentPadding,
                    child: DefaultTextStyle(
                      style: theme.textTheme.bodyMedium!.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      child: content!,
                    ),
                  ),
                ),
              if (actions.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
                  child: OverflowBar(
                    alignment: MainAxisAlignment.end,
                    spacing: 8,
                    overflowSpacing: 6,
                    children: actions,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

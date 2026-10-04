import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart' as glass;

import '../../features/vpn/app_controller.dart';
import 'glass_menu_button.dart';

import 'glass_surface.dart';
import 'snapshot_glass_route.dart';
import 'live_liquid_glass.dart';

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

/// Keep the trigger in the same widget tree as the overlay. Upstream morphs the
/// *material* from this anchor; a separate faded dialog cannot do that.
class GlassActionMenu<T> extends ConsumerStatefulWidget {
  const GlassActionMenu({
    required this.items,
    required this.onSelected,
    required this.tooltip,
    this.icon = const UnequalMenuIcon(),
    super.key,
  });
  final List<GlassMenuItem<T>> items;
  final ValueChanged<T> onSelected;
  final String tooltip;
  final Widget icon;
  @override
  ConsumerState<GlassActionMenu<T>> createState() => _GlassActionMenuState<T>();
}

class _GlassActionMenuState<T> extends ConsumerState<GlassActionMenu<T>> {
  final _controller = glass.GlassMenuController();
  final _triggerFocus = FocusNode();
  final _scope = FocusScopeNode(
    debugLabel: 'niran-glass-menu',
    traversalEdgeBehavior: TraversalEdgeBehavior.parentScope,
  );
  @override
  void dispose() {
    _triggerFocus.dispose();
    _scope.dispose();
    super.dispose();
  }

  KeyEventResult _key(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.escape) {
      _controller.close();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final reduced = ref.watch(performanceModeProvider);
    if (reduced) {
      return Builder(
        builder: (buttonContext) => GlassMenuButton(
          tooltip: widget.tooltip,
          icon: widget.icon,
          onPressed: () async {
            final box = buttonContext.findRenderObject() as RenderBox;
            final value = await showGlassMenu<T>(
              context: context,
              position: box.localToGlobal(Offset(0, box.size.height)),
              items: widget.items,
            );
            if (mounted && value != null) widget.onSelected(value);
          },
        ),
      );
    }
    final theme = Theme.of(context);
    return FocusScope(
      node: _scope,
      onKeyEvent: _key,
      child: glass.GlassMenu(
        controller: _controller,
        onClose: () {
          if (!mounted) return;
          _scope.traversalEdgeBehavior = TraversalEdgeBehavior.parentScope;
          _triggerFocus.requestFocus();
        },
        autoAdjustToScreen: true,
        menuWidth: (MediaQuery.sizeOf(context).width - 20).clamp(100.0, 280.0),
        // Null lets upstream include its real padding, gaps and text scale.
        // A fixed height opts into scrolling even for a two-item menu.
        menuBorderRadius: 22,
        menuPadding: const EdgeInsets.symmetric(vertical: 8),
        settings: niranLiquidSettings(theme.brightness),
        quality: liveGlassReady
            ? glass.GlassQuality.premium
            : glass.GlassQuality.minimal,
        triggerBuilder: (context, toggle) => GlassMenuButton(
          tooltip: widget.tooltip,
          icon: widget.icon,
          focusNode: _triggerFocus,
          onPressed: () {
            _scope.traversalEdgeBehavior = TraversalEdgeBehavior.closedLoop;
            _triggerFocus.requestFocus();
            toggle();
          },
        ),
        items: [
          for (final item in widget.items)
            glass.GlassMenuItem(
              title: item.label,
              icon: Icon(item.icon),
              height: 48,
              isDestructive: item.destructive,
              titleStyle: theme.textTheme.bodyMedium?.copyWith(
                color: item.destructive
                    ? theme.colorScheme.error
                    : theme.colorScheme.onSurface,
              ),
              iconColor: item.destructive
                  ? theme.colorScheme.error
                  : theme.colorScheme.onSurface,
              onTap: () => widget.onSelected(item.value),
            ),
        ],
      ),
    );
  }
}

Future<T?> showGlassMenu<T>({
  required BuildContext context,
  required Offset position,
  required List<GlassMenuItem<T>> items,
  bool liveLiquid = true,
}) async {
  final useLiveBackdrop = liveLiquid && liveGlassReady;
  if (!context.mounted) return null;
  final size = MediaQuery.sizeOf(context);
  final width = (size.width - 20).clamp(100.0, 264.0);
  final estimatedHeight = (items.length * 48.0 + 16).clamp(
    0.0,
    size.height - 20,
  );
  final left = position.dx.clamp(10.0, size.width - width - 10);
  final top = position.dy.clamp(10.0, size.height - estimatedHeight - 10);
  return showSnapshotGlassRoute<T>(
    context: context,
    useLiveBackdrop: useLiveBackdrop,
    barrierDismissible: true,
    captureRegion: Rect.fromLTWH(left, top, width, estimatedHeight).inflate(48),
    transitionDuration: MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 180),
    pageBuilder: (routeContext, animation, _) => Stack(
      children: [
        Positioned(
          left: left,
          top: top,
          width: width,
          child: Material(
            color: Colors.transparent,
            child: GlassSurface(
              radius: 18,
              blur: useLiveBackdrop ? messagesLiquidBlur : 16,
              saturation: useLiveBackdrop ? messagesLiquidSaturation : 1.20,
              liveLiquid: liveLiquid,
              padding: const EdgeInsets.symmetric(vertical: 7),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: size.height - 20),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var index = 0; index < items.length; index++)
                        _MenuItemMotion(
                          animation: animation,
                          index: index,
                          count: items.length,
                          child: Material(
                            type: MaterialType.transparency,
                            child: ListTile(
                              dense: true,
                              minTileHeight: 46,
                              leading: Icon(
                                items[index].icon,
                                size: 20,
                                color: items[index].destructive
                                    ? Theme.of(routeContext).colorScheme.error
                                    : null,
                              ),
                              title: Text(
                                items[index].label,
                                style: items[index].destructive
                                    ? TextStyle(
                                        color: Theme.of(routeContext)
                                            .colorScheme
                                            .error,
                                      )
                                    : null,
                              ),
                              onTap: () => Navigator.pop(
                                routeContext,
                                items[index].value,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    ),
    // Keep BackdropFilter outside an opacity save-layer so the final blur is
    // present on the first visible Windows frame.
    transitionBuilder: (_, _, _, child) => child,
  );
}

class _MenuItemMotion extends StatelessWidget {
  const _MenuItemMotion({
    required this.animation,
    required this.index,
    required this.count,
    required this.child,
  });
  final Animation<double> animation;
  final int index, count;
  final Widget child;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: animation,
    child: RepaintBoundary(child: child),
    builder: (context, child) {
      final closing = animation.status == AnimationStatus.reverse;
      final start = closing ? 0.0 : index / count * .28;
      final value = Interval(
        start,
        1,
        curve: Curves.easeOutCubic,
      ).transform(animation.value);
      return IgnorePointer(
        ignoring: value < .7,
        child: Transform.translate(
          offset: Offset(0, (1 - value) * 7),
          child: Opacity(opacity: value, child: child),
        ),
      );
    },
  );
}

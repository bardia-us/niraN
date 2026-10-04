import 'package:flutter/material.dart';

/// Edit-only motion; drag targets restrict every item to its own slot group.
class HomeEditItem extends StatefulWidget {
  const HomeEditItem({
    required this.enabled,
    required this.data,
    required this.label,
    required this.child,
    this.onDrop,
    this.ignoreContent = true,
    super.key,
  });
  final bool enabled;
  final String data;
  final String label;
  final Widget child;
  final ValueChanged<String>? onDrop;
  final bool ignoreContent;
  @override
  State<HomeEditItem> createState() => _HomeEditItemState();
}

class _HomeEditItemState extends State<HomeEditItem>
    with SingleTickerProviderStateMixin {
  late final AnimationController _motion = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 150),
  );
  void sync() {
    if (widget.enabled && !MediaQuery.disableAnimationsOf(context)) {
      if (!_motion.isAnimating) _motion.repeat(reverse: true);
    } else {
      _motion.stop();
      _motion.value = .5;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    sync();
  }

  @override
  void didUpdateWidget(HomeEditItem old) {
    super.didUpdateWidget(old);
    sync();
  }

  @override
  void dispose() {
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;
    final colors = Theme.of(context).colorScheme;
    return DragTarget<String>(
      onWillAcceptWithDetails: (details) =>
          widget.onDrop != null &&
          details.data != widget.data &&
          details.data.startsWith('control:'),
      onAcceptWithDetails: (details) => widget.onDrop?.call(details.data),
      builder: (context, candidates, _) => AnimatedBuilder(
        animation: _motion,
        child: RepaintBoundary(
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: colors.primary.withValues(
                  alpha: candidates.isEmpty ? .6 : 1,
                ),
                width: candidates.isEmpty ? 1.2 : 2,
              ),
            ),
            child: LongPressDraggable<String>(
              data: widget.data,
              hitTestBehavior: HitTestBehavior.opaque,
              feedback: Material(
                color: colors.primaryContainer,
                elevation: 6,
                borderRadius: BorderRadius.circular(18),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.open_with_rounded, color: colors.primary),
                      const SizedBox(width: 8),
                      Text(
                        widget.label,
                        style: TextStyle(color: colors.onPrimaryContainer),
                      ),
                    ],
                  ),
                ),
              ),
              child: IgnorePointer(
                ignoring: widget.ignoreContent,
                child: widget.child,
              ),
            ),
          ),
        ),
        builder: (context, child) => Transform.rotate(
          angle: (_motion.value - .5) * .025,
          alignment: Alignment.center,
          child: child,
        ),
      ),
    );
  }
}

class HomeUsageDropTarget extends StatelessWidget {
  const HomeUsageDropTarget({
    required this.enabled,
    required this.onDrop,
    required this.child,
    super.key,
  });
  final bool enabled;
  final VoidCallback onDrop;
  final Widget child;
  @override
  Widget build(BuildContext context) => DragTarget<String>(
    onWillAcceptWithDetails: (details) => enabled && details.data == 'usage',
    onAcceptWithDetails: (_) => onDrop(),
    builder: (context, candidates, _) => DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: candidates.isEmpty
              ? Colors.transparent
              : Theme.of(context).colorScheme.primary,
          width: 2,
        ),
      ),
      child: child,
    ),
  );
}

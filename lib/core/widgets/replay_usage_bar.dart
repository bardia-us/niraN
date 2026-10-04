import 'package:flutter/material.dart';

/// Replays the visual fill only; the subscription's actual usage never changes.
class ReplayUsageBar extends StatefulWidget {
  const ReplayUsageBar({required this.value, super.key});
  final double value;
  @override
  State<ReplayUsageBar> createState() => _ReplayUsageBarState();
}

class _ReplayUsageBarState extends State<ReplayUsageBar>
    with SingleTickerProviderStateMixin {
  late final _motion = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 850),
    value: 1,
  );
  void _replay() {
    if (MediaQuery.disableAnimationsOf(context)) return;
    _motion.forward(from: 0);
  }

  @override
  void dispose() {
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    value: '${(widget.value * 100).round()}%',
    child: InkWell(
      onTap: _replay,
      borderRadius: BorderRadius.circular(8),
      child: AnimatedBuilder(
        animation: _motion,
        builder: (context, _) {
          final fraction = Curves.easeOutCubic.transform(_motion.value);
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: SizedBox(
              height: 8 + 4 * (1 - fraction),
              child: LinearProgressIndicator(
                value: widget.value * fraction,
                minHeight: 8,
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          );
        },
      ),
    ),
  );
}

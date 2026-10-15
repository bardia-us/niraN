import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import '../render_mode.dart';

/// Animate only the panel; never transform the route's full-screen anchor or
/// wrap a live BackdropFilter in an opacity/saveLayer transition.
class AnimatedPopupSurface extends StatelessWidget {
  const AnimatedPopupSurface({
    super.key,
    required this.animation,
    required this.child,
    this.alignment = Alignment.center,
  });
  final Animation<double> animation;
  final Widget child;
  final Alignment alignment;
  @override
  Widget build(BuildContext context) => lightweightRenderingOf(context)
      ? FadeTransition(opacity: animation, child: child)
      : GlassMaterializeTransition(
          animation: animation,
          alignment: alignment,
          scaleFrom: 1.04,
          contentSigma: 2.5,
          child: child,
        );
}

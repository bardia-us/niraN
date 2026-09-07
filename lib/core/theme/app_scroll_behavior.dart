import 'package:flutter/material.dart';

class NirangScrollBehavior extends MaterialScrollBehavior {
  const NirangScrollBehavior({required this.reducedEffects});

  final bool reducedEffects;

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) {
    final platform = getPlatform(context);
    if (platform == TargetPlatform.windows ||
        platform == TargetPlatform.linux ||
        platform == TargetPlatform.macOS) {
      return const ClampingScrollPhysics();
    }
    return BouncingScrollPhysics(
      decelerationRate: reducedEffects
          ? ScrollDecelerationRate.fast
          : ScrollDecelerationRate.normal,
      parent: const AlwaysScrollableScrollPhysics(),
    );
  }

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    final platform = getPlatform(context);
    if (reducedEffects ||
        platform == TargetPlatform.windows ||
        platform == TargetPlatform.linux ||
        platform == TargetPlatform.macOS) {
      return child;
    }
    return StretchingOverscrollIndicator(
      axisDirection: details.direction,
      child: child,
    );
  }
}

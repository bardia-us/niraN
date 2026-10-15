import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'simple_frosted_surface.dart';
import 'clay_surface.dart';

void showNiranToast(
  BuildContext context,
  String message, {
  IconData icon = Icons.check_circle_outline_rounded,
}) {
  final colors = Theme.of(context).colorScheme;
  final messenger = ScaffoldMessenger.of(context);
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      behavior: SnackBarBehavior.floating,
      width: math.min(420, MediaQuery.sizeOf(context).width - 24),
      padding: EdgeInsets.zero,
      elevation: 0,
      backgroundColor: Colors.transparent,
      duration: const Duration(milliseconds: 2600),
      content: SimpleFrostedSurface(
        radius: 16,
        color: colors.surfaceContainerHigh.withValues(alpha: .93),
        borderColor: colors.onSurface.withValues(alpha: .22),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              ClaySurface(
                radius: 11,
                selected: true,
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Icon(icon, size: 18, color: colors.primary),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  message,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: colors.onSurface),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

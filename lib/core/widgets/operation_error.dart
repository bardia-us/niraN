import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../localization/app_strings.dart';
import 'glass_dialog.dart';

bool isTunPrivilegeError(Object error) =>
    (error is PlatformException && error.code == 'tun_privilege') ||
    error.toString().contains('tun_privilege');

Future<void> showOperationError(BuildContext context, Object error) async {
  if (!context.mounted) return;
  if (isTunPrivilegeError(error)) {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => NirangAlertDialog(
        icon: const Icon(Icons.admin_panel_settings_outlined),
        title: Text(context.s('administratorRequiredTitle')),
        content: Text(context.s('administratorRequiredMessage')),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    return;
  }
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text('${context.s('operationFailed')}: ${_clean(error)}'),
    ),
  );
}

String _clean(Object error) {
  if (error is PlatformException) {
    return error.message?.trim().isNotEmpty == true
        ? error.message!.trim()
        : error.code;
  }
  return '$error';
}

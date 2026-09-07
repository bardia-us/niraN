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
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 4),
      content: Text(_userMessage(context, error)),
    ),
  );
}

String _userMessage(BuildContext context, Object error) {
  if (error is PlatformException) {
    return switch (error.code) {
      'no_server' => 'Please select a server first.',
      'not_connectable' =>
        'This entry is for information only. Please select another server.',
      'invalid_settings' =>
        error.message?.trim().isNotEmpty == true
            ? error.message!.trim()
            : 'Please check the selected settings.',
      'tun_driver' =>
        'The bundled TUN driver is unavailable. Reinstall the complete niraN package.',
      'tun_startup' =>
        'TUN could not become ready. Check its DNS, MTU and network settings.',
      'xray_start' =>
        'The connection could not start. Check the selected server and settings.',
      'subscription_refresh' =>
        'Subscription update failed. Check your connection and try again.',
      _ => '${context.s('operationFailed')}: ${_clean(error)}',
    };
  }
  return '${context.s('operationFailed')}: ${_clean(error)}';
}

String _clean(Object error) {
  if (error is PlatformException) {
    return error.message?.trim().isNotEmpty == true
        ? error.message!.trim()
        : error.code;
  }
  return '$error';
}

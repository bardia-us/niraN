import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../localization/app_strings.dart';
import '../registration/device_registration.dart';
import 'glass_dialog.dart';

bool isTunPrivilegeError(Object error) =>
    (error is PlatformException && error.code == 'tun_privilege') ||
    error.toString().contains('tun_privilege');

Future<void> showOperationError(BuildContext context, Object error) async {
  if (!context.mounted) return;
  if (isTunPrivilegeError(error)) {
    await showNirangDialog<void>(
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

String friendlyErrorMessage(BuildContext context, Object error) {
  final fa = Localizations.localeOf(context).languageCode == 'fa';
  String message(String english, String persian) => fa ? persian : english;
  if (error is TimeoutException) {
    return message(
      'The request timed out. Check your internet connection and try again.',
      'زمان درخواست تمام شد. اتصال اینترنت را بررسی و دوباره تلاش کنید.',
    );
  }
  if (error is SocketException) {
    return message(
      'The server could not be reached. Check your connection, try another network, or turn on a VPN and retry.',
      'سرور در دسترس نیست. اینترنت یا شبکهٔ دیگری را امتحان کنید؛ در صورت محدودیت، VPN را روشن کرده و دوباره تلاش کنید.',
    );
  }
  if (error is HttpException) {
    return message(
      'The server is temporarily unavailable. Please try again shortly.',
      'سرور موقتاً در دسترس نیست. کمی بعد دوباره تلاش کنید.',
    );
  }
  if (error is FormatException) {
    return message(
      'The server returned an invalid response. Update the subscription or try again later.',
      'پاسخ سرور یا Subscription معتبر نبود. اشتراک را به‌روزرسانی کنید یا بعداً دوباره تلاش کنید.',
    );
  }
  if (error is DeviceAccessException) {
    return switch (error.reason) {
      'blocked_by_administrator' => message(
        'This device has been blocked by the administrator.',
        'دسترسی این دستگاه توسط مدیر مسدود شده است.',
      ),
      'update_required' => message(
        'A newer niraN version is required to continue.',
        'برای ادامه باید niraN را به نسخهٔ جدیدتر به‌روزرسانی کنید.',
      ),
      _ => message(
        'Device verification failed. Check your connection and retry.',
        'تأیید دستگاه انجام نشد. اتصال اینترنت را بررسی و دوباره تلاش کنید.',
      ),
    };
  }
  if (error is PlatformException) {
    return switch (error.code) {
      'no_server' => message(
        'Please select a server first.',
        'ابتدا یک سرور انتخاب کنید.',
      ),
      'not_connectable' => message(
        'This entry is for information only. Please select another server.',
        'این مورد فقط اطلاع‌رسانی است؛ سرور دیگری انتخاب کنید.',
      ),
      'invalid_settings' => message(
        'Please check the selected settings.',
        'تنظیمات انتخاب‌شده را بررسی کنید.',
      ),
      'tun_driver' => message(
        'The bundled TUN driver is unavailable. Reinstall the complete niraN package.',
        'درایور TUN در دسترس نیست. بستهٔ کامل niraN را دوباره نصب کنید.',
      ),
      'tun_startup' => message(
        'TUN could not become ready. Check its DNS, MTU and network settings.',
        'TUN آماده نشد. تنظیمات DNS، MTU و شبکه را بررسی کنید.',
      ),
      'xray_start' => message(
        'The connection could not start. Check the selected server and settings.',
        'اتصال شروع نشد. سرور و تنظیمات آن را بررسی کنید.',
      ),
      'subscription_refresh' => message(
        'Subscription update failed. Check your connection and try again.',
        'به‌روزرسانی اشتراک ناموفق بود. اتصال اینترنت را بررسی و دوباره تلاش کنید.',
      ),
      _ => message(
        'The operation could not be completed. Please try again.',
        'عملیات انجام نشد. دوباره تلاش کنید.',
      ),
    };
  }
  return message(
    'The operation could not be completed. Please try again.',
    'عملیات انجام نشد. دوباره تلاش کنید.',
  );
}

String _userMessage(BuildContext context, Object error) =>
    friendlyErrorMessage(context, error);

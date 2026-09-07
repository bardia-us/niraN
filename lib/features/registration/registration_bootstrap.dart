import 'package:flutter/material.dart';

import '../../core/registration/device_registration.dart';
import '../../core/theme/app_theme.dart';
import '../../core/platform/nirang_native.dart';
import '../../platform/windows/windows_remote_access.dart';

class NiranRegistrationBootstrap extends StatefulWidget {
  NiranRegistrationBootstrap({
    required this.child,
    DeviceRegistrationCoordinator? coordinator,
    super.key,
  }) : coordinator = coordinator ?? windowsRemoteAccess;

  final Widget child;
  final DeviceRegistrationCoordinator coordinator;

  @override
  State<NiranRegistrationBootstrap> createState() =>
      _NiranRegistrationBootstrapState();
}

class _NiranRegistrationBootstrapState
    extends State<NiranRegistrationBootstrap> {
  late Future<bool> _initialization;
  bool _accepting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initialization = _verifyAccess();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<bool>(
    future: _initialization,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) {
        return _consentApp(
          const Scaffold(body: Center(child: CircularProgressIndicator())),
        );
      }
      final error = snapshot.error;
      if (_isBlocked(error)) markDeviceAccessBlocked(_errorMessage(error));
      if (snapshot.data == true) {
        return ValueListenableBuilder<String?>(
          valueListenable: deviceAccessBlock,
          child: widget.child,
          builder: (context, blocked, child) => blocked == null
              ? child!
              : _consentApp(
                  BlockedAccessScreen(onRetry: _retry, onExit: _exit),
                ),
        );
      }
      if (error != null) {
        return _consentApp(
          _isBlocked(error)
              ? BlockedAccessScreen(onRetry: _retry, onExit: _exit)
              : AccessVerificationScreen(
                  message: _errorMessage(error),
                  onRetry: _retry,
                  onExit: _exit,
                ),
        );
      }
      return _consentApp(
        RegistrationConsentScreen(
          accepting: _accepting,
          error: _error,
          onAccept: _accept,
          onExit: _exit,
        ),
      );
    },
  );

  Future<bool> _verifyAccess() async {
    final accepted = await widget.coordinator.initialize();
    if (accepted) clearDeviceAccessBlocked();
    return accepted;
  }

  void _retry() {
    setState(() {
      _error = null;
      _initialization = _retryAccess();
    });
  }

  Future<bool> _retryAccess() async {
    final coordinator = widget.coordinator;
    if (coordinator is! RemoteAccessController) return _verifyAccess();
    await (coordinator as RemoteAccessController).requireAllowed();
    clearDeviceAccessBlocked();
    return true;
  }

  Widget _consentApp(Widget home) => MaterialApp(
    title: 'niraN — Device registration',
    debugShowCheckedModeBanner: false,
    theme: AppTheme.light,
    darkTheme: AppTheme.dark,
    themeMode: ThemeMode.system,
    home: home,
  );

  Future<void> _accept() async {
    if (_accepting) return;
    setState(() {
      _accepting = true;
      _error = null;
    });
    try {
      await widget.coordinator.accept();
      if (!mounted) return;
      setState(() => _initialization = _verifyAccess());
    } on Object catch (error) {
      if (mounted) {
        if (_isBlocked(error)) {
          markDeviceAccessBlocked(_errorMessage(error));
          setState(() => _initialization = Future<bool>.error(error));
          return;
        }
        setState(() {
          _error = error is DeviceAccessException
              ? error.message
              : 'Device registration failed. Check your connection and try again.';
        });
      }
    } finally {
      if (mounted) setState(() => _accepting = false);
    }
  }

  Future<void> _exit() => widget.coordinator.exitApplication();

  static bool _isBlocked(Object? error) =>
      error is DeviceAccessException &&
      error.reason == 'blocked_by_administrator';

  static String _errorMessage(Object? error) => error is DeviceAccessException
      ? error.message
      : 'Access status could not be verified. Check your connection and try again.';
}

class BlockedAccessScreen extends StatelessWidget {
  const BlockedAccessScreen({
    required this.onRetry,
    required this.onExit,
    super.key,
  });

  final VoidCallback onRetry;
  final VoidCallback onExit;

  @override
  Widget build(BuildContext context) => _AccessMessageCard(
    icon: Icons.block_rounded,
    title: 'Access blocked',
    message:
        'دسترسی شما مسدود شده است.\n'
        'برای اطلاع از دلیل مسدود شدن می‌توانید به تلگرام سازنده مراجعه کنید.',
    actions: [
      TextButton(onPressed: onExit, child: const Text('Exit')),
      OutlinedButton(onPressed: onRetry, child: const Text('Try again')),
      FilledButton.icon(
        onPressed: () async {
          try {
            await NirangNative.openTelegram();
          } catch (_) {
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Telegram link is unavailable.')),
              );
            }
          }
        },
        icon: const Icon(Icons.send_rounded),
        label: const Text('Telegram'),
      ),
    ],
  );
}

class AccessVerificationScreen extends StatelessWidget {
  const AccessVerificationScreen({
    required this.message,
    required this.onRetry,
    required this.onExit,
    super.key,
  });

  final String message;
  final VoidCallback onRetry;
  final VoidCallback onExit;

  @override
  Widget build(BuildContext context) => _AccessMessageCard(
    icon: Icons.cloud_off_rounded,
    title: 'Access check failed',
    message: message,
    actions: [
      TextButton(onPressed: onExit, child: const Text('Exit')),
      FilledButton(onPressed: onRetry, child: const Text('Try again')),
    ],
  );
}

class _AccessMessageCard extends StatelessWidget {
  const _AccessMessageCard({
    required this.icon,
    required this.title,
    required this.message,
    required this.actions,
  });

  final IconData icon;
  final String title;
  final String message;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 48, color: theme.colorScheme.error),
                    const SizedBox(height: 16),
                    Text(title, style: theme.textTheme.headlineSmall),
                    const SizedBox(height: 12),
                    Text(
                      message,
                      textAlign: TextAlign.center,
                      textDirection: TextDirection.rtl,
                    ),
                    const SizedBox(height: 22),
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 10,
                      runSpacing: 8,
                      children: actions,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class RegistrationConsentScreen extends StatelessWidget {
  const RegistrationConsentScreen({
    required this.accepting,
    required this.error,
    required this.onAccept,
    required this.onExit,
    super.key,
  });

  final bool accepting;
  final String? error;
  final VoidCallback onAccept;
  final VoidCallback onExit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.devices_rounded,
                          size: 36,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Text(
                            'niraN device registration',
                            style: theme.textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 22),
                    const Text(
                      'Before entering niraN, this installation must be registered with the niraN server. The following information is sent over HTTPS:',
                    ),
                    const SizedBox(height: 14),
                    const _DisclosureItem(
                      'A random, persistent installation ID',
                    ),
                    const _DisclosureItem(
                      'A one-way niraN device key derived from the official Windows publisher-scoped system ID; the raw ID is never sent or stored',
                    ),
                    const _DisclosureItem(
                      'Windows Device Name (Computer Name)',
                    ),
                    const _DisclosureItem('Windows profile/display username'),
                    const _DisclosureItem('Windows version and build'),
                    const _DisclosureItem('niraN app version'),
                    const _DisclosureItem('First seen and last seen times'),
                    const SizedBox(height: 16),
                    Text(
                      'niraN does not collect your Wi-Fi/SSID, MAC address, hardware serial, files, or hardware component details. The Windows system ID is used only in memory to create the disclosed one-way device key.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'برای مدیریت دسترسی، شناسهٔ نصب و Device Key یک‌طرفهٔ مشتق‌شده از شناسهٔ رسمی و publisher-scoped ویندوز ارسال می‌شود؛ مقدار خام آن ذخیره یا ارسال نمی‌شود. Wi-Fi، MAC، سریال، فایل‌ها و جزئیات قطعات جمع‌آوری نمی‌شوند.',
                      textDirection: TextDirection.rtl,
                      style: theme.textTheme.bodyMedium,
                    ),
                    if (error case final message?) ...[
                      const SizedBox(height: 14),
                      Text(
                        message,
                        style: TextStyle(color: theme.colorScheme.error),
                      ),
                    ],
                    const SizedBox(height: 26),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: accepting ? null : onExit,
                          child: const Text('Exit'),
                        ),
                        const SizedBox(width: 12),
                        FilledButton.icon(
                          onPressed: accepting ? null : onAccept,
                          icon: accepting
                              ? const SizedBox.square(
                                  dimension: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.check_rounded),
                          label: const Text('Accept & Continue'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DisclosureItem extends StatelessWidget {
  const _DisclosureItem(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 2),
          child: Icon(Icons.check_circle_outline_rounded, size: 18),
        ),
        const SizedBox(width: 10),
        Expanded(child: Text(text)),
      ],
    ),
  );
}

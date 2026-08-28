import 'package:flutter/material.dart';

import '../../core/registration/device_registration.dart';
import '../../core/theme/app_theme.dart';
import '../../platform/windows/windows_device_registration.dart';

class NiranRegistrationBootstrap extends StatefulWidget {
  NiranRegistrationBootstrap({
    required this.child,
    DeviceRegistrationCoordinator? coordinator,
    super.key,
  }) : coordinator =
           coordinator ??
           DeviceRegistrationService(
             infoProvider: WindowsDeviceRegistrationInfoProvider(),
           );

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
    _initialization = widget.coordinator.initialize();
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
      if (snapshot.data == true) return widget.child;
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
      setState(() => _initialization = Future<bool>.value(true));
    } on Object {
      if (mounted) {
        setState(() {
          _error =
              'Registration preference could not be saved. Please try again.';
        });
      }
    } finally {
      if (mounted) setState(() => _accepting = false);
    }
  }

  Future<void> _exit() => widget.coordinator.exitApplication();
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
                      'Windows Device Name (Computer Name)',
                    ),
                    const _DisclosureItem('Windows profile/display username'),
                    const _DisclosureItem('Windows version and build'),
                    const _DisclosureItem('niraN app version'),
                    const _DisclosureItem('First seen and last seen times'),
                    const SizedBox(height: 16),
                    Text(
                      'niraN does not collect your Wi-Fi/SSID, MAC address, hardware serial, files, or a hardware fingerprint. Device Name and Windows Username are collected only as disclosed above.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'برای مدیریت نصب، شناسهٔ تصادفی نصب، نام دستگاه Windows، نام کاربری نمایشی Windows، نسخهٔ ویندوز و niraN و زمان اولین/آخرین اجرا از طریق HTTPS ارسال می‌شود. Wi-Fi، MAC، سریال سخت‌افزار، فایل‌ها و اثرانگشت سخت‌افزاری جمع‌آوری نمی‌شوند.',
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

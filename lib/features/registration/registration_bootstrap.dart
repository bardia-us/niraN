import 'package:flutter/material.dart';

import '../../core/registration/device_registration.dart';
import '../../core/theme/app_theme.dart';
import '../../core/platform/nirang_native.dart';
import '../../core/update_checker.dart';
import '../../core/windows_update_manager.dart';
import '../../platform/windows/windows_device_registration.dart';
import '../../platform/windows/windows_native_host.dart';
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
              : _isUpdateRequired(error)
              ? MandatoryWindowsUpdateScreen(
                  minimumVersion: _minimumVersion(error),
                  onRetry: _retry,
                  onExit: _exit,
                )
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
    if (accepted) {
      clearDeviceAccessBlocked();
      final coordinator = widget.coordinator;
      if (coordinator is RemoteAccessController) {
        try {
          await (coordinator as RemoteAccessController).requireAllowed();
        } on DeviceAccessException {
          rethrow;
        } on Object {
          // A temporary network/DNS/timeout failure must not create a false
          // mandatory-update lock. Cached allowed access remains usable.
        }
      }
    }
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

  static bool _isUpdateRequired(Object? error) =>
      error is DeviceAccessException && error.reason == 'update_required';

  static String _minimumVersion(Object? error) {
    final message = error is DeviceAccessException ? error.message : '';
    return RegExp(r'\d+\.\d+\.\d+').firstMatch(message)?.group(0) ?? '0.3.6';
  }

  static String _errorMessage(Object? error) => error is DeviceAccessException
      ? error.message
      : 'Access status could not be verified. Check your connection and try again.';
}

class MandatoryWindowsUpdateScreen extends StatefulWidget {
  const MandatoryWindowsUpdateScreen({
    required this.minimumVersion,
    required this.onRetry,
    required this.onExit,
    super.key,
  });

  final String minimumVersion;
  final VoidCallback onRetry;
  final VoidCallback onExit;

  @override
  State<MandatoryWindowsUpdateScreen> createState() =>
      _MandatoryWindowsUpdateScreenState();
}

class _MandatoryWindowsUpdateScreenState
    extends State<MandatoryWindowsUpdateScreen> {
  final _manager = WindowsUpdateManager.instance;
  ReleaseCheckResult? _release;
  ReleaseAsset? _asset;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  Future<void> _prepare() async {
    try {
      final info = await WindowsDeviceRegistrationInfoProvider().read();
      await _manager.initialize(info.appVersion);
      final release = await const GitHubUpdateChecker().check(info.appVersion);
      final asset = await _manager.assetFor(release);
      if (!mounted) return;
      setState(() {
        _release = release;
        _asset = asset;
        _loading = false;
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _error =
            'Could not load the verified Windows update. Check your internet connection or use the browser download.';
        _loading = false;
      });
    }
  }

  Future<void> _download() async {
    final release = _release;
    final asset = _asset;
    if (release == null || asset == null || asset.sha256 == null) return;
    try {
      await _manager.start(asset, release.latestVersion);
    } on Object {
      if (mounted) {
        setState(
          () => _error = 'The verified update download could not start.',
        );
      }
    }
  }

  Future<void> _install() async {
    try {
      final mustExit = await _manager.launch();
      if (mustExit) await MethodChannelWindowsNativeHost().exitApplication();
    } on Object {
      if (mounted) {
        setState(() => _error = 'The update installer could not be started.');
      }
    }
  }

  Future<void> _openBrowser() async {
    final uri =
        _asset?.url ?? _release?.releaseUrl ?? Uri.parse(nirangRepositoryUrl);
    await MethodChannelWindowsNativeHost().openExternalUrl(uri.toString());
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(30),
              child: AnimatedBuilder(
                animation: _manager,
                builder: (context, _) {
                  final download = _manager.snapshot;
                  final ready =
                      download.status == UpdateDownloadStatus.readyToUpdate ||
                      download.status == UpdateDownloadStatus.updateFailed;
                  final active =
                      download.status == UpdateDownloadStatus.downloading ||
                      download.status == UpdateDownloadStatus.verifying ||
                      download.status == UpdateDownloadStatus.downloaded;
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.system_update_rounded, size: 52),
                      const SizedBox(height: 16),
                      Text(
                        'Update required',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'niraN ${widget.minimumVersion} or newer is required.\n'
                        'برای ادامه، niraN را به نسخهٔ ${widget.minimumVersion} یا جدیدتر به‌روزرسانی کنید.',
                        textAlign: TextAlign.center,
                      ),
                      if (_loading) ...[
                        const SizedBox(height: 22),
                        const CircularProgressIndicator(),
                      ],
                      if (active || ready) ...[
                        const SizedBox(height: 22),
                        LinearProgressIndicator(value: download.progress),
                        const SizedBox(height: 8),
                        Text(
                          ready
                              ? 'Verified and ready to install'
                              : '${_formatMegabytes(download.received)} / ${_formatMegabytes(download.total)}',
                        ),
                      ],
                      if (_error case final error?) ...[
                        const SizedBox(height: 14),
                        Text(
                          error,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ],
                      const SizedBox(height: 24),
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 10,
                        runSpacing: 8,
                        children: [
                          TextButton(
                            onPressed: widget.onExit,
                            child: const Text('Exit'),
                          ),
                          OutlinedButton.icon(
                            onPressed: widget.onRetry,
                            icon: const Icon(Icons.refresh_rounded),
                            label: const Text('Retry policy'),
                          ),
                          OutlinedButton.icon(
                            onPressed: _release == null ? null : _openBrowser,
                            icon: const Icon(Icons.open_in_browser_rounded),
                            label: const Text('Browser'),
                          ),
                          FilledButton.icon(
                            onPressed: ready
                                ? _install
                                : active || _asset?.sha256 == null
                                ? null
                                : _download,
                            icon: Icon(
                              ready
                                  ? Icons.install_desktop_rounded
                                  : Icons.download_rounded,
                            ),
                            label: Text(
                              ready ? 'Install' : 'Download & verify',
                            ),
                          ),
                        ],
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    ),
  );

  static String _formatMegabytes(int bytes) =>
      '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
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

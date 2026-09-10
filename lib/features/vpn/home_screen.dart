import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';

import '../../core/formatters.dart';
import '../../core/localization/app_strings.dart';
import '../../core/platform/native_models.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/glass_surface.dart';
import '../../core/widgets/glass_dialog.dart';
import '../../core/widgets/country_flag_badge.dart';
import '../../core/widgets/interactive_depth.dart';
import '../../core/widgets/operation_error.dart';
import 'app_controller.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ref.watch(
      appControllerProvider.select((value) {
        final app = value.asData?.value;
        return (
          servers: app?.servers ?? const <ServerInfo>[],
          connection: app?.connection ?? const ConnectionInfo(),
          usage: app?.usage ?? const SubscriptionUsage(),
          configured: app?.subscriptionConfigured ?? false,
          error: app?.subscriptionError,
          settings: app?.settings ?? const NativeSettings(),
          logs: app?.logs ?? const <LogEntry>[],
          isPinging: app?.isPinging ?? false,
        );
      }),
    );
    final app = AppSnapshot(
      servers: view.servers,
      connection: view.connection,
      usage: view.usage,
      subscriptionConfigured: view.configured,
      subscriptionError: view.error,
      settings: view.settings,
      logs: view.logs,
      isPinging: view.isPinging,
    );
    final controller = ref.read(appControllerProvider.notifier);
    return RefreshIndicator(
      onRefresh: controller.refreshSubscription,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 24),
        children: [
          _ConnectionCard(app: app, controller: controller),
          if (app.subscriptionError != null) ...[
            const SizedBox(height: 8),
            Text(
              app.subscriptionError!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: 12),
          _SubscriptionSection(usage: app.usage),
          if (app.settings.showRecentLogsOnHome) ...[
            const SizedBox(height: 12),
            _RecentLogs(logs: app.logs),
          ],
        ],
      ),
    );
  }
}

class _ConnectionCard extends StatelessWidget {
  const _ConnectionCard({required this.app, required this.controller});

  final AppSnapshot app;
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final selected = app.selectedServer;
    final connection = app.connection;
    final statusColor = _statusColor(context, connection.state);
    final countryCode = connection.publicCountry?.trim().toUpperCase();
    final publicIp = connection.publicIp;
    final publicIpValue = publicIp == null
        ? (connection.isConnected && !connection.publicIpChecked
              ? context.s('checking')
              : '—')
        : countryCode != null && countryCode.length == 2
        ? '($countryCode) $publicIp'
        : publicIp;
    return GlassSurface(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(
                  connection.isConnected
                      ? Icons.shield_rounded
                      : Icons.shield_outlined,
                  color: statusColor,
                  size: 21,
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.s('status'),
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      context.s(connection.state),
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: statusColor,
                      ),
                    ),
                  ],
                ),
              ),
              _ConnectionAction(
                connection: connection,
                enabled: selected != null,
                controller: controller,
                settings: app.settings,
              ),
            ],
          ),
          if (connection.error?.isNotEmpty == true) ...[
            const SizedBox(height: 10),
            Text(
              connection.error!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: 12),
          _DesktopConnectionControls(
            connection: connection,
            settings: app.settings,
            controller: controller,
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 14),
            child: Divider(),
          ),
          Text(
            context.s('selectedServer').toUpperCase(),
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(letterSpacing: .75),
          ),
          const SizedBox(height: 9),
          if (selected == null)
            Text(
              app.subscriptionConfigured
                  ? context.s('emptyServers')
                  : context.s('notConfigured'),
            )
          else ...[
            Row(
              children: [
                selected.country.isEmpty &&
                        countryCodeFromRemark(selected.name) == null
                    ? Icon(
                        Icons.cloud_queue_rounded,
                        size: 26,
                        color: Theme.of(context).colorScheme.primary,
                      )
                    : CountryFlagBadge(
                        countryCode:
                            countryCodeFromRemark(selected.name) ??
                            selected.country,
                        width: 32,
                        height: 23,
                      ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        remarkWithoutCountryFlag(selected.name).isEmpty
                            ? selected.name
                            : remarkWithoutCountryFlag(selected.name),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${selected.protocol} · ${selected.transport} · ${selected.security}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _CompactMetric(
                    icon: Icons.public_rounded,
                    label: context.s('publicIp'),
                    value: publicIpValue,
                    subtitle: connection.publicCity,
                    fitValue: true,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _CompactMetric(
                    icon: Icons.network_ping_rounded,
                    label: context.s('ping'),
                    value: switch (selected.status) {
                      'testing' => context.s('testing'),
                      'timeout' => context.s('timeout'),
                      'failed' => context.s('failed'),
                      _ => selected.ping == null ? '—' : '${selected.ping} ms',
                    },
                    onTap: app.isPinging
                        ? null
                        : () => _perform(
                            context,
                            () => controller.pingServer(selected.id),
                          ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _ConnectionAction extends StatelessWidget {
  const _ConnectionAction({
    required this.connection,
    required this.enabled,
    required this.controller,
    required this.settings,
  });

  final ConnectionInfo connection;
  final bool enabled;
  final AppController controller;
  final NativeSettings settings;

  @override
  Widget build(BuildContext context) {
    if (connection.isBusy) {
      return const SizedBox.square(
        dimension: 22,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }
    if (connection.isConnected) {
      return OutlinedButton.icon(
        onPressed: () => _perform(context, controller.restartService),
        icon: const Icon(Icons.restart_alt_rounded, size: 18),
        label: Text(context.s('restartService')),
      );
    }
    return FilledButton.tonalIcon(
      onPressed: connection.canConnect
          ? () {
              if (!enabled) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    behavior: SnackBarBehavior.floating,
                    duration: Duration(seconds: 3),
                    content: Text('Please select a server first.'),
                  ),
                );
                return;
              }
              _connect(context);
            }
          : null,
      icon: const Icon(Icons.refresh_rounded, size: 19),
      label: Text(context.s('retryCore')),
    );
  }

  Future<void> _connect(BuildContext context) async {
    try {
      await controller.connect();
    } on PlatformException catch (error) {
      if (error.code != 'port_in_use') {
        if (context.mounted) _showOperationError(context, error);
        return;
      }
      if (!context.mounted) {
        return;
      }
      final action = await showDialog<String>(
        context: context,
        builder: (dialogContext) => NirangAlertDialog(
          icon: const Icon(Icons.portable_wifi_off_rounded),
          title: Text(context.s('localPortConflict')),
          content: Text(context.s('localPortConflictSummary')),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, 'cancel'),
              child: Text(context.s('cancel')),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, 'ports'),
              child: Text(context.s('changePorts')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, 'retry'),
              child: Text(context.s('retry')),
            ),
          ],
        ),
      );
      if (!context.mounted) return;
      if (action == 'retry') {
        await _connect(context);
      } else if (action == 'ports') {
        final ports = await _changePorts(context);
        if (ports == null || !context.mounted) return;
        await controller.updateSettings({
          'localSocksPort': ports.socks,
          'localHttpPort': ports.http,
        });
        if (context.mounted) await _connect(context);
      }
    } catch (error) {
      if (context.mounted) _showOperationError(context, error);
    }
  }

  Future<({int socks, int http})?> _changePorts(BuildContext context) async {
    final formKey = GlobalKey<FormState>();
    final socksController = TextEditingController(
      text: '${settings.localSocksPort}',
    );
    final httpController = TextEditingController(
      text: '${settings.localHttpPort}',
    );
    try {
      return await showDialog<({int socks, int http})>(
        context: context,
        builder: (dialogContext) => NirangAlertDialog(
          title: Text(context.s('changePorts')),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: socksController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: context.s('localSocksPort'),
                  ),
                  validator: (value) =>
                      _portError(value, httpController.text, context),
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: httpController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: context.s('localHttpPort'),
                  ),
                  validator: (value) =>
                      _portError(value, socksController.text, context),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(context.s('cancel')),
            ),
            FilledButton(
              onPressed: () {
                if (formKey.currentState?.validate() != true) return;
                Navigator.pop(dialogContext, (
                  socks: int.parse(socksController.text),
                  http: int.parse(httpController.text),
                ));
              },
              child: Text(context.s('apply')),
            ),
          ],
        ),
      );
    } finally {
      socksController.dispose();
      httpController.dispose();
    }
  }

  String? _portError(String? value, String other, BuildContext context) {
    final port = int.tryParse(value ?? '');
    final otherPort = int.tryParse(other);
    return port != null && port >= 1024 && port <= 65535 && port != otherPort
        ? null
        : context.s('invalidPort');
  }

  void _showOperationError(BuildContext context, Object error) {
    showOperationError(context, error);
  }
}

class _DesktopConnectionControls extends StatelessWidget {
  const _DesktopConnectionControls({
    required this.connection,
    required this.settings,
    required this.controller,
  });

  final ConnectionInfo connection;
  final NativeSettings settings;
  final AppController controller;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      InteractiveDepth(
        reducedEffects: settings.performanceMode,
        child: _ProxyActionButton(
          selected: settings.systemProxyState == 'niran',
          onPressed: connection.isConnected
              ? () => _runProxyAction(
                  context,
                  controller.setSystemProxy,
                  context.s('systemProxyEnabledToast'),
                )
              : null,
          icon: Icons.desktop_windows_rounded,
          label: context.s('setSystemProxy'),
        ),
      ),
      InteractiveDepth(
        reducedEffects: settings.performanceMode,
        child: _ProxyActionButton(
          selected: settings.systemProxyState == 'clear',
          onPressed: connection.isBusy
              ? null
              : () => _runProxyAction(
                  context,
                  controller.clearSystemProxy,
                  context.s('systemProxyClearedToast'),
                ),
          icon: Icons.cleaning_services_outlined,
          label: context.s('clearSystemProxy'),
        ),
      ),
      _TunSwitch(
        value: settings.isTunEnabled,
        enabled: !connection.isBusy,
        reducedEffects: settings.performanceMode,
        onChanged: (value) => _perform(
          context,
          () => controller.updateSettings({'tunEnabled': value}),
        ),
      ),
    ],
  );
}

class _ProxyActionButton extends StatelessWidget {
  const _ProxyActionButton({
    required this.selected,
    required this.onPressed,
    required this.icon,
    required this.label,
  });

  final bool selected;
  final VoidCallback? onPressed;
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return FilledButton.icon(
      style: FilledButton.styleFrom(
        backgroundColor: selected
            ? colors.primaryContainer
            : colors.surfaceContainerHighest.withValues(alpha: .5),
        foregroundColor: selected
            ? colors.onPrimaryContainer
            : colors.onSurfaceVariant,
        side: BorderSide(
          color: selected ? colors.primary : colors.outlineVariant,
          width: selected ? 1.5 : 1,
        ),
      ),
      onPressed: onPressed,
      icon: Icon(selected ? Icons.check_circle_rounded : icon, size: 18),
      label: Text(label),
    );
  }
}

class _TunSwitch extends StatelessWidget {
  const _TunSwitch({
    required this.value,
    required this.enabled,
    required this.reducedEffects,
    required this.onChanged,
  });

  final bool value;
  final bool enabled;
  final bool reducedEffects;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InteractiveDepth(
      enabled: enabled,
      reducedEffects: reducedEffects,
      child: Semantics(
        button: true,
        toggled: value,
        child: InkWell(
          onTap: enabled ? () => onChanged(!value) : null,
          borderRadius: BorderRadius.circular(99),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 210),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsetsDirectional.fromSTEB(12, 7, 7, 7),
            decoration: BoxDecoration(
              color: value
                  ? scheme.primaryContainer.withValues(alpha: .82)
                  : scheme.surfaceContainerHighest.withValues(alpha: .55),
              borderRadius: BorderRadius.circular(99),
              border: Border.all(
                color: value ? scheme.primary : scheme.outlineVariant,
                width: value ? 1.5 : 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.vpn_lock_outlined, size: 18),
                const SizedBox(width: 7),
                Text('${context.s('tunMode')}  ${value ? 'ON' : 'OFF'}'),
                const SizedBox(width: 9),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 210),
                  width: 38,
                  height: 22,
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: value
                        ? scheme.primary
                        : scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: AnimatedAlign(
                    duration: const Duration(milliseconds: 210),
                    curve: Curves.easeOutBack,
                    alignment: value
                        ? AlignmentDirectional.centerEnd
                        : AlignmentDirectional.centerStart,
                    child: Container(
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(
                        color: value ? scheme.onPrimary : scheme.outline,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RecentLogs extends StatefulWidget {
  const _RecentLogs({required this.logs});

  final List<LogEntry> logs;

  @override
  State<_RecentLogs> createState() => _RecentLogsState();
}

class _RecentLogsState extends State<_RecentLogs> {
  final _scrollController = ScrollController();
  bool _wasAtBottom = true;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(() {
      if (!_scrollController.hasClients) return;
      _wasAtBottom =
          _scrollController.position.maxScrollExtent -
              _scrollController.offset <
          24;
    });
  }

  @override
  void didUpdateWidget(covariant _RecentLogs oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.logs.length == oldWidget.logs.length || !_wasAtBottom) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final visible = widget.logs.length <= 8
        ? widget.logs
        : widget.logs.sublist(widget.logs.length - 8);
    return _Section(
      icon: Icons.notes_rounded,
      title: context.s('recentLogs'),
      child: SizedBox(
        height: 154,
        child: visible.isEmpty
            ? Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Text(context.s('noLogs')),
              )
            : ListView.separated(
                controller: _scrollController,
                padding: const EdgeInsets.fromLTRB(16, 2, 16, 14),
                itemCount: visible.length,
                separatorBuilder: (_, _) => const SizedBox(height: 5),
                itemBuilder: (context, index) {
                  final log = visible[index];
                  final color = switch (log.level) {
                    'error' => Theme.of(context).colorScheme.error,
                    'warning' => context.semanticColors.warning,
                    _ => Theme.of(context).colorScheme.primary,
                  };
                  final time =
                      '${log.time.hour.toString().padLeft(2, '0')}:'
                      '${log.time.minute.toString().padLeft(2, '0')}:'
                      '${log.time.second.toString().padLeft(2, '0')}';
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 7,
                        height: 7,
                        margin: const EdgeInsets.only(top: 6),
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 58,
                        child: Text(
                          time,
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      ),
                      Expanded(
                        child: Text(
                          log.message,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ],
                  );
                },
              ),
      ),
    );
  }
}

class _CompactMetric extends StatelessWidget {
  const _CompactMetric({
    required this.icon,
    required this.label,
    required this.value,
    this.onTap,
    this.subtitle,
    this.fitValue = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final VoidCallback? onTap;
  final String? subtitle;
  final bool fitValue;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(11),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
      decoration: BoxDecoration(
        color: Theme.of(
          context,
        ).colorScheme.surfaceContainerHighest.withValues(alpha: .45),
        borderRadius: BorderRadius.circular(11),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall,
                ),
                const SizedBox(height: 2),
                if (fitValue)
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(
                      value,
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                  )
                else
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                if (subtitle?.trim().isNotEmpty == true) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!.trim(),
                    maxLines: 1,
                    overflow: TextOverflow.fade,
                    softWrap: false,
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _SubscriptionSection extends StatelessWidget {
  const _SubscriptionSection({required this.usage});
  final SubscriptionUsage usage;

  @override
  Widget build(BuildContext context) {
    final hasUsage = usage.used != null || usage.unlimited;
    final progress =
        usage.total != null && usage.total! > 0 && usage.used != null
        ? (usage.used! / usage.total!).clamp(0.0, 1.0)
        : null;
    return _Section(
      icon: Icons.data_usage_rounded,
      title: context.s('subscriptionUsage'),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 15),
        child: !hasUsage
            ? Text(context.s('subscriptionUsageUnknown'))
            : Column(
                children: [
                  _ValueRow(
                    label: context.s('used'),
                    value: formatBytes(usage.used),
                    strong: true,
                  ),
                  if (progress != null) ...[
                    const SizedBox(height: 9),
                    LinearProgressIndicator(
                      value: progress,
                      minHeight: 6,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    const SizedBox(height: 7),
                  ],
                  _ValueRow(
                    label: context.s('remaining'),
                    value: usage.unlimited
                        ? context.s('unlimited')
                        : formatBytes(usage.remaining),
                  ),
                  if (usage.expire != null && usage.expire! > 0)
                    _ValueRow(
                      label: context.s('expires'),
                      value: formatDateTime(
                        usage.expire! * 1000,
                        dateOnly: true,
                      ),
                    ),
                  if (usage.expired)
                    _ValueRow(
                      label: context.s('status'),
                      value: context.s('expired'),
                      valueColor: Theme.of(context).colorScheme.error,
                    ),
                ],
              ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.icon,
    required this.title,
    required this.child,
  });
  final IconData icon;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => GlassSurface(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 13, 16, 11),
          child: Row(
            children: [
              Icon(
                icon,
                size: 18,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Text(
                title,
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
        child,
      ],
    ),
  );
}

class _ValueRow extends StatelessWidget {
  const _ValueRow({
    required this.label,
    required this.value,
    this.strong = false,
    this.valueColor,
  });
  final String label;
  final String value;
  final bool strong;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        Expanded(child: Text(label)),
        Text(
          value,
          style: TextStyle(
            fontWeight: strong ? FontWeight.w700 : FontWeight.w500,
            color: valueColor,
          ),
        ),
      ],
    ),
  );
}

Color _statusColor(BuildContext context, String state) => switch (state) {
  'connected' => context.semanticColors.success,
  'error' => Theme.of(context).colorScheme.error,
  'connecting' ||
  'preparing' ||
  'restarting' ||
  'switching' ||
  'reconnecting' ||
  'stopping' => context.semanticColors.warning,
  _ => Theme.of(context).colorScheme.outline,
};

Future<void> _runProxyAction(
  BuildContext context,
  Future<void> Function() operation,
  String successMessage,
) async {
  try {
    await operation();
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(successMessage)));
    }
  } catch (error) {
    if (context.mounted) await showOperationError(context, error);
  }
}

Future<void> _perform(
  BuildContext context,
  Future<void> Function() operation,
) async {
  try {
    await operation();
  } catch (error) {
    if (context.mounted) await showOperationError(context, error);
  }
}

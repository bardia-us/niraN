import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/widgets/replay_usage_bar.dart';

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
import '../../core/widgets/desktop_page_heading.dart';
import 'app_controller.dart';
import 'home_layout.dart';
import 'home_canvas.dart';
import 'home_log_panel.dart';
import '../../core/desktop_feedback.dart';
import 'traffic_panel.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  NativeSettings? _editSettings;
  bool _savingLayout = false;
  bool _resetWindowOnSave = false;
  bool get editing => _editSettings != null;
  void updateDraft(Map<String, Object?> values) {
    if (_savingLayout || _editSettings == null) return;
    setState(() => _editSettings = _editSettings!.withUpdates(values));
  }

  Future<void> saveLayout(AppController controller) async {
    final draft = _editSettings;
    if (draft == null || _savingLayout) return;
    setState(() => _savingLayout = true);
    try {
      await controller.updateSettings({
        'homeLayout': HomeLayout.fromSettings(draft).encode(),
        'showRecentLogsOnHome': draft.showRecentLogsOnHome,
      });
      if (_resetWindowOnSave) {
        await const MethodChannel('dev.niran.windows/host')
            .invokeMethod<void>('resetWindowBounds');
        _resetWindowOnSave = false;
      }
      if (mounted) setState(() => _editSettings = null);
      unawaited(
        DesktopFeedback.show(
          sound: draft.soundEffects,
          style: draft.soundStyle,
        ),
      );
    } on Object catch (error) {
      if (mounted) await showOperationError(context, error);
    } finally {
      if (mounted) setState(() => _savingLayout = false);
    }
  }

  @override
  Widget build(BuildContext context) {
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
      settings: _editSettings ?? view.settings,
      logs: view.logs,
      isPinging: view.isPinging,
    );
    final controller = ref.read(appControllerProvider.notifier);
    final layout = HomeLayout.fromSettings(app.settings);
    final labels = <String, String>{
      'status': context.s('connectionOverview'),
      'subscription': context.s('subscriptionUsage'),
      'traffic': context.s('niranTraffic'),
      'logs': context.s('recentLogs'),
      'systemProxy': context.s('setSystemProxy'),
      'clearProxy': context.s('clearSystemProxy'),
      'tun': context.s('tunMode'),
      'restart': context.s('restartService'),
    };
    return Center(
      child: ConstrainedBox(
        key: const Key('home-content'),
        constraints: const BoxConstraints(maxWidth: 1160, maxHeight: 760),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact =
                  constraints.maxWidth < 850 || constraints.maxHeight < 650;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DesktopPageHeading(
                    title: context.s('home'),
                    subtitle: editing
                        ? context.s('homeCanvasHint')
                        : compact
                        ? null
                        : context.s('connectionOverview'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (editing) ...[
                          IconButton(
                            key: const Key('reset-home-layout'),
                            color: Theme.of(context).colorScheme.error,
                            tooltip: context.s('resetLayout'),
                            onPressed: _savingLayout
                                ? null
                                : () {
                                    _resetWindowOnSave = true;
                                    updateDraft({
                                      'homeLayout': HomeLayout.defaults()
                                          .encode(),
                                      'showRecentLogsOnHome': true,
                                    });
                                  },
                            icon: const Icon(Icons.restore_rounded),
                          ),
                          TextButton(
                            key: const Key('cancel-home-edit'),
                            onPressed: _savingLayout
                                ? null
                                : () => setState(() {
                                    _editSettings = null;
                                    _resetWindowOnSave = false;
                                  }),
                            child: Text(context.s('cancelHomeEdit')),
                          ),
                          FilledButton(
                            key: const Key('save-home-layout'),
                            onPressed: _savingLayout
                                ? null
                                : () => saveLayout(controller),
                            child: Text(context.s('save')),
                          ),
                        ] else
                          InteractiveDepth(
                            radius: 99,
                            child: GlassSurface(
                              radius: 99,
                              blur: 12,
                              child: IconButton(
                                key: const Key('customize-home'),
                                tooltip: context.s('customizeHome'),
                                onPressed: () => setState(
                                  () => _editSettings = view.settings,
                                ),
                                icon: Icon(
                                  Icons.brush_rounded,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: SizedBox(
                      key: const Key('home-desktop-grid'),
                      child: HomeCanvas(
                        layout: layout,
                        editing: editing && !_savingLayout,
                        logsVisible: app.settings.showRecentLogsOnHome,
                        labels: labels,
                        onChanged: (value) =>
                            updateDraft({'homeLayout': value.encode()}),
                        onRemoveLogs: () =>
                            updateDraft({'showRecentLogsOnHome': false}),
                        children: {
                          'status': _ConnectionCard(
                            key: const Key('home-connection'),
                            app: app,
                            controller: controller,
                            compact: true,
                            editing: editing,
                            layout: layout,
                            labels: labels,
                            onLayoutChanged: (value) =>
                                updateDraft({'homeLayout': value.encode()}),
                          ),
                          'subscription': _SubscriptionSection(
                            usage: app.usage,
                          ),
                          'traffic': const TrafficPanel(),
                          'logs': HomeLogPanel(
                            logs: app.logs,
                            editing: editing,
                          ),
                        },
                      ),
                    ),
                  ),
                  if (app.subscriptionError != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        app.subscriptionError!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _ConnectionCard extends StatelessWidget {
  const _ConnectionCard({
    required this.app,
    required this.controller,
    this.compact = false,
    this.editing = false,
    required this.layout,
    required this.labels,
    required this.onLayoutChanged,
    super.key,
  });

  final AppSnapshot app;
  final AppController controller;
  final bool compact;
  final bool editing;
  final HomeLayout layout;
  final Map<String, String> labels;
  final ValueChanged<HomeLayout> onLayoutChanged;

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
      radius: 24,
      style: GlassSurfaceStyle.flat,
      padding: EdgeInsets.all(compact ? 16 : 24),
      child: _BoundedHomeContent(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 140,
              child: HomeCanvas(
                controlsOnly: true,
                heading: Row(
                  children: [
                    _ConnectionEmblem(
                      color: statusColor,
                      connected: connection.isConnected,
                      editing: editing,
                    ),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            context.s('status'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.labelMedium,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            context.s(connection.state),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: statusColor,
                                ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                layout: layout,
                editing: editing,
                logsVisible: false,
                labels: labels,
                onChanged: onLayoutChanged,
                onRemoveLogs: () {},
                children: {
                  'systemProxy': _HomeAction(
                    selected: app.settings.systemProxyState == 'niran',
                    icon: Icons.desktop_windows_rounded,
                    label: labels['systemProxy']!,
                    onPressed:
                        !editing && connection.isConnected && !connection.isBusy
                        ? () => _runProxyAction(
                            context,
                            controller.setSystemProxy,
                            context.s('systemProxyEnabledToast'),
                          )
                        : null,
                  ),
                  'clearProxy': _HomeAction(
                    selected: app.settings.systemProxyState == 'clear',
                    icon: Icons.cleaning_services_outlined,
                    label: labels['clearProxy']!,
                    onPressed: !editing && !connection.isBusy
                        ? () => _runProxyAction(
                            context,
                            controller.clearSystemProxy,
                            context.s('systemProxyClearedToast'),
                          )
                        : null,
                  ),
                  'tun': _TunControl(
                    value: app.settings.isTunEnabled,
                    enabled: !editing && !connection.isBusy,
                    onChanged: (value) => _perform(
                      context,
                      () => controller.updateSettings({'tunEnabled': value}),
                    ),
                  ),
                  'restart': _HomeAction(
                    selected: false,
                    accent: Colors.blueAccent,
                    icon: Icons.restart_alt_rounded,
                    label: labels['restart']!,
                    onPressed:
                        !editing && connection.isConnected && !connection.isBusy
                        ? () => _perform(context, controller.restartService)
                        : null,
                  ),
                },
              ),
            ),
            if (connection.error?.isNotEmpty == true) ...[
              const SizedBox(height: 8),
              Text(
                connection.error!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            if (!connection.isConnected && !connection.isBusy)
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: IgnorePointer(
                  ignoring: editing,
                  child: _ConnectionAction(
                    connection: connection,
                    enabled: selected != null,
                    controller: controller,
                    settings: app.settings,
                  ),
                ),
              ),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 14),
              child: Divider(),
            ),
            Text(
              context.s('selectedServer').toUpperCase(),
              style: Theme.of(context).textTheme.labelSmall
                  ?.copyWith(letterSpacing: .75),
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
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CountryRemarkText(
                          remark: selected.name,
                          fallbackCountry: selected.country,
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
                      onTap:
                          !editing &&
                              connection.isConnected &&
                              !connection.isBusy
                          ? () => _perform(context, controller.refreshPublicIp)
                          : null,
                      tooltip: context.s('refreshIpHint'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _CompactMetric(
                      icon: Icons.network_ping_rounded,
                      valueColor: switch (selected.status) {
                        'failed' ||
                        'timeout' => Theme.of(context).colorScheme.error,
                        'testing' => context.semanticColors.warning,
                        _ =>
                          selected.ping == null
                              ? Theme.of(context).colorScheme.outline
                              : selected.ping! < 150
                              ? context.semanticColors.success
                              : selected.ping! < 350
                              ? context.semanticColors.warning
                              : Theme.of(context).colorScheme.error,
                      },
                      label: context.s('ping'),
                      value: switch (selected.status) {
                        'testing' => context.s('testing'),
                        'timeout' => context.s('timeout'),
                        'failed' => context.s('failed'),
                        _ =>
                          selected.ping == null ? '—' : '${selected.ping} ms',
                      },
                      onTap: editing || app.isPinging
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
      final action = await showNirangDialog<String>(
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
      return await showNirangDialog<({int socks, int http})>(
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

class _HomeAction extends StatelessWidget {
  const _HomeAction({
    required this.selected,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.accent,
  });
  final bool selected;
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final Color? accent;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return InteractiveDepth(
      radius: 24,
      enabled: onPressed != null,
      child: GlassSurface(
        radius: 24,
        blur: 12,
        child: Semantics(
          button: true,
          enabled: onPressed != null,
          selected: selected,
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(24),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      selected ? Icons.check_circle_rounded : icon,
                      size: 18,
                      color: onPressed == null
                          ? colors.outline
                          : selected
                          ? colors.primary
                          : accent ?? colors.onSurface,
                    ),
                    const SizedBox(width: 7),
                    Flexible(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: onPressed == null
                              ? colors.outline
                              : selected
                              ? colors.primary
                              : accent ?? colors.onSurface,
                        ),
                      ),
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

class _TunControl extends StatelessWidget {
  const _TunControl({
    required this.value,
    required this.enabled,
    required this.onChanged,
  });
  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;
  @override
  Widget build(BuildContext context) => GlassSurface(
    radius: 24,
    blur: 12,
    child: LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 100;
        final toggle = SizedBox(
          width: 56,
          child: FittedBox(
            child: Switch.adaptive(
              value: value,
              onChanged: enabled ? onChanged : null,
            ),
          ),
        );
        if (compact) {
          return Tooltip(
            message: context.s('tunMode'),
            child: Semantics(
              label: context.s('tunMode'),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Center(child: toggle),
              ),
            ),
          );
        }
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 9),
          child: Row(
            children: [
              const Icon(Icons.vpn_lock_outlined, size: 17),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  context.s('tunMode'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ),
              toggle,
            ],
          ),
        );
      },
    ),
  );
}

class _ConnectionEmblem extends StatefulWidget {
  const _ConnectionEmblem({
    required this.color,
    required this.connected,
    required this.editing,
  });
  final Color color;
  final bool connected;
  final bool editing;
  @override
  State<_ConnectionEmblem> createState() => _ConnectionEmblemState();
}

class _ConnectionEmblemState extends State<_ConnectionEmblem>
    with SingleTickerProviderStateMixin {
  late final _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );
  void _play() {
    if (widget.editing ||
        _pulse.isAnimating ||
        MediaQuery.disableAnimationsOf(context)) {
      return;
    }
    _pulse.forward(from: 0);
  }

  @override
  void didUpdateWidget(_ConnectionEmblem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.connected && !oldWidget.connected) _play();
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
    key: const Key('home-connection-emblem'),
    onTap: widget.editing ? null : _play,
    child: AnimatedBuilder(
      animation: _pulse,
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: widget.color.withValues(alpha: .12),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Icon(
          widget.connected ? Icons.shield_rounded : Icons.shield_outlined,
          color: widget.color,
          size: 26,
        ),
      ),
      builder: (context, child) {
        final pulse = _pulse.value < .4
            ? Curves.easeOut.transform(_pulse.value / .4)
            : 1 - Curves.easeInOut.transform((_pulse.value - .4) / .6);
        return Transform.scale(scale: 1 + pulse * .08, child: child);
      },
    ),
  );
}

class _BoundedHomeContent extends StatelessWidget {
  const _BoundedHomeContent({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      // Natural content height handles wrapping without scaling typography.
      // Only this card scrolls when its contents exceed the available height.
      return SingleChildScrollView(
        primary: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: child,
        ),
      );
    },
  );
}

class _CompactMetric extends StatelessWidget {
  const _CompactMetric({
    required this.icon,
    required this.label,
    required this.value,
    this.onTap,
    this.subtitle,
    this.fitValue = false,
    this.tooltip,
    this.valueColor,
  });

  final IconData icon;
  final String label;
  final String value;
  final VoidCallback? onTap;
  final String? subtitle;
  final bool fitValue;
  final String? tooltip;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip ?? '',
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(11),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
        constraints: const BoxConstraints(minHeight: 76),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest
              .withValues(alpha: .45),
          borderRadius: BorderRadius.circular(11),
          border: Border.all(
            color: Theme.of(context).colorScheme.outline.withValues(alpha: .28),
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 18,
              color: valueColor ?? Theme.of(context).colorScheme.primary,
            ),
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
                        style: Theme.of(context).textTheme.labelLarge
                            ?.copyWith(color: valueColor),
                      ),
                    )
                  else
                    Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelLarge
                          ?.copyWith(color: valueColor),
                    ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle?.trim().isNotEmpty == true ? subtitle!.trim() : '',
                    maxLines: 1,
                    overflow: TextOverflow.fade,
                    softWrap: false,
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _SubscriptionSection extends StatelessWidget {
  const _SubscriptionSection({required this.usage});
  final SubscriptionUsage usage;

  @override
  Widget build(BuildContext context) => GlassSurface(
    radius: 24,
    style: GlassSurfaceStyle.flat,
    child: LayoutBuilder(
      builder: (context, bounds) {
        final compact = bounds.maxHeight < 140;
        final progress =
            usage.total != null && usage.total! > 0 && usage.used != null
            ? (usage.used! / usage.total!).clamp(0.0, 1.0)
            : null;
        return Padding(
          padding: EdgeInsets.symmetric(
            horizontal: 14,
            vertical: compact ? 7 : 12,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.data_usage_rounded,
                    size: 17,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      context.s('subscriptionUsage'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                ],
              ),
              SizedBox(height: compact ? 4 : 10),
              if (usage.used == null && !usage.unlimited)
                Text(
                  context.s('subscriptionUsageUnknown'),
                  maxLines: 2,
                  style: Theme.of(context).textTheme.bodySmall,
                )
              else ...[
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${context.s('used')}: ${formatBytes(usage.used)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${context.s('remaining')}: '
                        '${usage.unlimited ? context.s('unlimited') : formatBytes(usage.remaining)}',
                        textAlign: TextAlign.end,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
                if (progress != null) ReplayUsageBar(value: progress),
                if (usage.expire != null &&
                    usage.expire! > 0 &&
                    bounds.maxHeight >= 116)
                  Text(
                    '${context.s('expires')}: ${formatDateTime(usage.expire! * 1000, dateOnly: true)}',
                    maxLines: 1,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                if (usage.expired && bounds.maxHeight >= 130)
                  Text(
                    context.s('expired'),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
              ],
            ],
          ),
        );
      },
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
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(successMessage)));
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

import 'package:flutter/material.dart';

import '../../core/widgets/niran_toast.dart';

import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/localization/app_strings.dart';
import '../../core/desktop_feedback.dart';
import '../../core/platform/native_models.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/glass_dialog.dart';
import '../../core/widgets/country_flag_badge.dart';
import '../../core/widgets/glass_menu.dart';
import '../../core/widgets/glass_surface.dart';
import '../../core/widgets/live_liquid_glass.dart';
import '../../core/widgets/interactive_depth.dart';
import '../../core/widgets/operation_error.dart';
import '../vpn/app_controller.dart';
import 'server_information_screen.dart';

class ServersScreen extends ConsumerStatefulWidget {
  const ServersScreen({super.key});

  @override
  ConsumerState<ServersScreen> createState() => _ServersScreenState();
}

class _ServersScreenState extends ConsumerState<ServersScreen> {
  final Set<String> _removing = {};
  final ScrollController _scroll = ScrollController(debugLabel: 'servers');
  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final view = ref.watch(
      appControllerProvider.select((value) {
        final app = value.asData?.value;
        return (
          servers: app?.servers ?? const <ServerInfo>[],
          isPinging: app?.isPinging ?? false,
          isRefreshing: app?.isRefreshing ?? false,
          configured: app?.subscriptionConfigured ?? false,
        );
      }),
    );
    final app = AppSnapshot(
      servers: view.servers,
      isPinging: view.isPinging,
      isRefreshing: view.isRefreshing,
      subscriptionConfigured: view.configured,
    );
    final controller = ref.read(appControllerProvider.notifier);
    const headerHeight = 76.0;
    return Stack(
      children: [
        Positioned.fill(
          child: app.servers.isEmpty
              ? Padding(
                  padding: const EdgeInsets.only(top: headerHeight + 10),
                  child: _EmptyServers(app: app),
                )
              : ScrollbarTheme(
                  data: Theme.of(context).scrollbarTheme.copyWith(
                    mainAxisMargin: headerHeight + 12,
                    crossAxisMargin: 3,
                    thickness: WidgetStateProperty.resolveWith(
                      (states) =>
                          states.contains(WidgetState.hovered) ||
                              states.contains(WidgetState.dragged)
                          ? 6
                          : 3,
                    ),
                    radius: const Radius.circular(8),
                  ),
                  child: Scrollbar(
                    controller: _scroll,
                    thumbVisibility: true,
                    interactive: true,
                    child: ScrollConfiguration(
                      behavior: ScrollConfiguration.of(context)
                          .copyWith(scrollbars: false),
                      child: ReorderableListView.builder(
                        key: const PageStorageKey('servers-scroll'),
                        scrollController: _scroll,
                        scrollCacheExtent: const ScrollCacheExtent.pixels(360),
                        buildDefaultDragHandles: false,
                        itemCount: app.servers.length,
                        padding: const EdgeInsets.fromLTRB(
                          20,
                          headerHeight + 16,
                          20,
                          16,
                        ),
                        // Retain the controller's pre-removal index contract.
                        // ignore: deprecated_member_use
                        onReorder: (oldIndex, newIndex) => _perform(
                          context,
                          () => controller.reorderServers(oldIndex, newIndex),
                        ),
                        proxyDecorator: (child, index, animation) => child,
                        itemBuilder: (context, index) {
                          final server = app.servers[index];
                          final brightness = Theme.of(context).brightness;
                          return Padding(
                            key: ValueKey('${brightness.name}:${server.id}'),
                            padding: const EdgeInsets.only(bottom: 8),
                            child: TweenAnimationBuilder<double>(
                              tween: Tween(
                                begin: 1,
                                end: _removing.contains(server.id) ? 0 : 1,
                              ),
                              duration: Duration(
                                milliseconds:
                                    MediaQuery.disableAnimationsOf(context)
                                    ? 0
                                    : 180,
                              ),
                              curve: Curves.easeInOutCubic,
                              builder: (context, value, child) => ClipRect(
                                child: Align(
                                  heightFactor: value,
                                  child: IgnorePointer(
                                    ignoring: value < 1,
                                    child: Transform.scale(
                                      scale: .93 + .07 * value,
                                      child: child,
                                    ),
                                  ),
                                ),
                              ),
                              child: RepaintBoundary(
                                child: InteractiveDepth(
                                  key: ValueKey('server-depth-${server.id}'),
                                  radius: 13,
                                  enabled: false,
                                  reducedEffects: false,
                                  // Server rows use one deterministic hover lift. The
                                  // pointer-following tilt made the card visibly move a
                                  // second time after the initial hover transition.
                                  tiltEnabled: false,
                                  // Transforming the row while the handle's long-press
                                  // recognizer is active makes desktop reorder gestures
                                  // unreliable. Keep hover depth, but let the handle own
                                  // the press sequence without moving its render box.
                                  pressEnabled: false,
                                  child: ReorderableDelayedDragStartListener(
                                    key: ValueKey('server-drag-${server.id}'),
                                    index: index,
                                    child: GestureDetector(
                                      behavior: HitTestBehavior.opaque,
                                      onSecondaryTapDown: (details) =>
                                          _serverContextActions(
                                            context,
                                            controller,
                                            server,
                                            details.globalPosition,
                                          ),
                                      child: DecoratedBox(
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(
                                            13,
                                          ),
                                          border: server.selected
                                              ? Border.all(
                                                  color: Theme.of(context)
                                                      .colorScheme
                                                      .primary
                                                      .withValues(alpha: .7),
                                                  width: 1.4,
                                                )
                                              : null,
                                        ),
                                        child: GlassSurface(
                                          radius: 13,
                                          blur: 3,
                                          style: GlassSurfaceStyle.flat,
                                          overlayColor: server.selected
                                              ? Theme.of(context)
                                                    .colorScheme
                                                    .primary
                                                    .withValues(alpha: .22)
                                              : null,
                                          child: Material(
                                            type: MaterialType.transparency,
                                            child: ListTile(
                                              key: ValueKey(
                                                'server-row-${server.id}',
                                              ),
                                              splashColor: Theme.of(context)
                                                  .colorScheme
                                                  .primary
                                                  .withValues(alpha: .10),
                                              hoverColor: Colors.transparent,
                                              focusColor: Colors.transparent,
                                              leading: _SelectionIndicator(
                                                selected: server.selected,
                                                reducedEffects: false,
                                              ),
                                              title: _ServerTitle(
                                                server: server,
                                              ),
                                              subtitle: Text(
                                                '${server.protocol}  ${server.transport}',
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                              trailing: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  _Latency(server: server),
                                                  const SizedBox(width: 14),
                                                  GlassActionMenu<String>(
                                                    key: ValueKey(
                                                      'server-menu-${server.id}',
                                                    ),
                                                    tooltip: context.s(
                                                      'serverActions',
                                                    ),
                                                    icon: const Icon(
                                                      Icons.more_vert_rounded,
                                                    ),
                                                    items: _serverMenuItems(
                                                      context,
                                                    ),
                                                    onSelected: (action) =>
                                                        _handleAction(
                                                          context,
                                                          controller,
                                                          server,
                                                          action,
                                                        ),
                                                  ),
                                                ],
                                              ),
                                              onTap: () => _perform(
                                                context,
                                                () => controller.selectServer(
                                                  server.id,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
        ),
        Positioned(
          top: 6,
          left: 20,
          right: 20,
          child: RepaintBoundary(
            child: _ServersGlassHeader(
              height: headerHeight,
              serverCount: app.servers.length,
              menu: GlassActionMenu<String>(
                key: const Key('servers-menu-button'),
                tooltip: context.s('serverActions'),
                items: _pageMenuItems(context),
                onSelected: (action) =>
                    _handlePageAction(context, controller, action),
              ),
            ),
          ),
        ),
      ],
    );
  }

  List<GlassMenuItem<String>> _pageMenuItems(BuildContext context) => [
    GlassMenuItem(
      value: 'restart',
      icon: Icons.restart_alt_rounded,
      label: context.s('restartService'),
    ),
    GlassMenuItem(
      value: 'sort',
      icon: Icons.sort_rounded,
      label: context.s('sortByTestResults'),
    ),
    GlassMenuItem(
      value: 'tcp',
      icon: Icons.cable_rounded,
      label: context.s('testTcpDelays'),
    ),
    GlassMenuItem(
      value: 'real',
      icon: Icons.network_ping_rounded,
      label: context.s('testRealDelays'),
    ),
    GlassMenuItem(
      value: 'refresh',
      icon: Icons.sync_rounded,
      label: context.s('refresh'),
    ),
  ];

  Future<void> _handlePageAction(
    BuildContext context,
    AppController controller,
    String action,
  ) async {
    final app = ref.read(appControllerProvider).asData?.value;
    if (!context.mounted || app == null) return;
    final isPinging = app.isPinging;
    final isRefreshing = app.isRefreshing;
    switch (action) {
      case 'restart':
        await _perform(context, controller.restartService);
      case 'sort':
        await _perform(context, controller.sortServersByTestResults);
      case 'tcp':
        if (!isPinging) await _perform(context, controller.tcpPingAll);
      case 'real':
        if (isPinging) {
          await _perform(context, controller.cancelPing);
        } else {
          await _perform(context, controller.pingAll);
        }
      case 'refresh':
        if (!isRefreshing) {
          await _perform(context, controller.refreshSubscription);
        }
    }
  }

  List<GlassMenuItem<String>> _serverMenuItems(BuildContext context) => [
    GlassMenuItem(
      value: 'select',
      icon: Icons.check_circle_outline_rounded,
      label: context.s('select'),
    ),
    GlassMenuItem(
      value: 'ping',
      icon: Icons.network_ping_rounded,
      label: context.s('testLatency'),
    ),
    GlassMenuItem(
      value: 'tcpPing',
      icon: Icons.cable_rounded,
      label: context.s('tcpPing'),
    ),
    GlassMenuItem(
      value: 'info',
      icon: Icons.info_outline_rounded,
      label: context.s('serverInformation'),
    ),
    GlassMenuItem(
      value: 'delete',
      icon: Icons.delete_outline_rounded,
      label: context.s('delete'),
      destructive: true,
    ),
  ];

  Future<void> _serverContextActions(
    BuildContext context,
    AppController controller,
    ServerInfo server,
    Offset position,
  ) async {
    final action = await showGlassMenu<String>(
      context: context,
      position: position,
      items: [
        GlassMenuItem(
          value: 'select',
          icon: Icons.check_circle_outline_rounded,
          label: context.s('select'),
        ),
        GlassMenuItem(
          value: 'ping',
          icon: Icons.network_ping_rounded,
          label: context.s('testLatency'),
        ),
        GlassMenuItem(
          value: 'tcpPing',
          icon: Icons.cable_rounded,
          label: context.s('tcpPing'),
        ),
        GlassMenuItem(
          value: 'info',
          icon: Icons.info_outline_rounded,
          label: context.s('serverInformation'),
        ),
        GlassMenuItem(
          value: 'delete',
          icon: Icons.delete_outline_rounded,
          label: context.s('delete'),
          destructive: true,
        ),
      ],
    );
    if (action != null && context.mounted) {
      await _handleAction(context, controller, server, action);
    }
  }

  Future<void> _handleAction(
    BuildContext context,
    AppController controller,
    ServerInfo server,
    String action,
  ) async {
    switch (action) {
      case 'select':
        await _perform(context, () => controller.selectServer(server.id));
      case 'ping':
        await _perform(context, () => controller.pingServer(server.id));
      case 'tcpPing':
        await _perform(context, () async {
          final delay = await controller.tcpPingServer(server.id);
          if (context.mounted) {
            showNiranToast(
              context,
              delay > 0
                  ? '${context.s('tcpPing')}: $delay ms'
                  : '${context.s('tcpPing')}: ${context.s('timeout')}',
              icon: Icons.network_ping_rounded,
            );
          }
        });
      case 'info':
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            settings: const RouteSettings(name: '/server-information'),
            builder: (_) =>
                ServerInformationScreen(server: server, controller: controller),
          ),
        );
      case 'delete':
        final confirmed = await showNirangDialog<bool>(
          context: context,
          builder: (context) => NirangAlertDialog(
            title: Text(context.s('deleteServer')),
            content: Text('${context.s('deleteServerBody')}\n\n${server.name}'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(context.s('cancel')),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.error,
                ),
                onPressed: () => Navigator.pop(context, true),
                child: Text(context.s('delete')),
              ),
            ],
          ),
        );
        if (confirmed == true && context.mounted) {
          setState(() => _removing.add(server.id));
          if (!MediaQuery.disableAnimationsOf(context)) {
            await Future<void>.delayed(const Duration(milliseconds: 190));
          }
          if (!mounted || !context.mounted) return;
          await _perform(context, () => controller.deleteServer(server.id));
          final current = ref.read(appControllerProvider).asData?.value;
          if (mounted &&
              current != null &&
              !current.servers.any((item) => item.id == server.id)) {
            await DesktopFeedback.show(
              sound: current.settings.soundEffects,
              style: current.settings.soundStyle,
            );
          }
          if (mounted) setState(() => _removing.remove(server.id));
        }
    }
  }
}

class _ServersGlassHeader extends StatelessWidget {
  const _ServersGlassHeader({
    required this.height,
    required this.serverCount,
    required this.menu,
  });

  final double height;
  final int serverCount;
  final Widget menu;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final content = SizedBox(
      key: const Key('servers-toolbar'),
      height: height,
      child: Padding(
        padding: const EdgeInsetsDirectional.only(start: 14, end: 12),
        child: LayoutBuilder(
          builder: (context, constraints) {
            return Directionality(
              textDirection: TextDirection.ltr,
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${context.s('servers')} ($serverCount)',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Row(
                    key: const Key('servers-toolbar-actions'),
                    mainAxisSize: MainAxisSize.min,
                    children: [menu],
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
    return GlassSurface(
      radius: 22,
      blur: messagesLiquidBlur,
      saturation: messagesLiquidSaturation,
      liveLiquid: true,
      child: content,
    );
  }
}

class _ServerTitle extends StatelessWidget {
  const _ServerTitle({required this.server});

  final ServerInfo server;

  @override
  Widget build(BuildContext context) {
    return CountryRemarkText(
      remark: server.name,
      fallbackCountry: server.country,
      style: DefaultTextStyle.of(context).style.copyWith(
        fontSize: (DefaultTextStyle.of(context).style.fontSize ?? 13) + 1,
      ),
    );
  }
}

class _SelectionIndicator extends StatelessWidget {
  const _SelectionIndicator({
    required this.selected,
    required this.reducedEffects,
  });

  final bool selected;
  final bool reducedEffects;

  @override
  Widget build(BuildContext context) => AnimatedContainer(
    duration: Duration(milliseconds: reducedEffects ? 85 : 140),
    width: 22,
    height: 22,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: selected
          ? Theme.of(context).colorScheme.primary
          : Colors.transparent,
      border: Border.all(
        width: selected ? 0 : 1.5,
        color: selected
            ? Theme.of(context).colorScheme.primary
            : Theme.of(context).colorScheme.outline,
      ),
    ),
    child: selected
        ? Icon(
            Icons.check_rounded,
            size: 15,
            color: Theme.of(context).colorScheme.onPrimary,
          )
        : null,
  );
}

class _Latency extends StatelessWidget {
  const _Latency({required this.server});
  final ServerInfo server;
  @override
  Widget build(BuildContext context) {
    if (server.status == 'testing') {
      return Text(
        context.s('testing'),
        style: TextStyle(color: Theme.of(context).colorScheme.primary),
      );
    }
    if (server.status == 'timeout') {
      return Text(
        context.s('timeout'),
        style: TextStyle(color: Theme.of(context).colorScheme.error),
      );
    }
    if (server.status == 'failed') {
      return Text(
        context.s('failed'),
        style: TextStyle(color: Theme.of(context).colorScheme.error),
      );
    }
    final ping = server.ping;
    if (ping == null) return const SizedBox.shrink();
    final color = ping <= 199
        ? context.semanticColors.success
        : ping <= 349
        ? context.semanticColors.warning
        : ping <= 599
        ? (Theme.of(context).brightness == Brightness.dark
              ? const Color(0xFFF0A35A)
              : const Color(0xFFCF6B1C))
        : Theme.of(context).colorScheme.error;
    return SizedBox(
      width: 58,
      child: Text(
        '$ping ms',
        textAlign: TextAlign.end,
        style: TextStyle(color: color),
      ),
    );
  }
}

class _EmptyServers extends StatelessWidget {
  const _EmptyServers({required this.app});
  final AppSnapshot app;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.dns_outlined, size: 44),
          const SizedBox(height: 12),
          Text(
            app.subscriptionConfigured
                ? context.s('emptyServers')
                : context.s('notConfigured'),
            textAlign: TextAlign.center,
          ),
          if (!app.subscriptionConfigured) ...[
            const SizedBox(height: 8),
            Text(context.s('configureHint'), textAlign: TextAlign.center),
          ],
        ],
      ),
    ),
  );
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

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/formatters.dart';
import '../../core/localization/app_strings.dart';
import '../../core/platform/native_models.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/glass_dialog.dart';
import '../../core/widgets/country_flag_badge.dart';
import '../../core/widgets/glass_menu.dart';
import '../../core/widgets/glass_surface.dart';
import '../../core/widgets/interactive_depth.dart';
import '../../core/widgets/operation_error.dart';
import '../vpn/app_controller.dart';
import 'server_information_screen.dart';
import 'server_profile_settings_screen.dart';

class ServersScreen extends ConsumerStatefulWidget {
  const ServersScreen({super.key});

  @override
  ConsumerState<ServersScreen> createState() => _ServersScreenState();
}

class _ServersScreenState extends ConsumerState<ServersScreen> {
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
          performanceMode: app?.settings.performanceMode ?? false,
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
    const headerHeight = 64.0;
    return Stack(
      children: [
        Positioned.fill(
          child: app.servers.isEmpty
              ? Padding(
                  padding: const EdgeInsets.only(top: headerHeight + 10),
                  child: _EmptyServers(app: app),
                )
              : ReorderableListView.builder(
                  cacheExtent: 360,
                  buildDefaultDragHandles: false,
                  itemCount: app.servers.length,
                  padding: const EdgeInsets.fromLTRB(
                    8,
                    headerHeight + 16,
                    8,
                    16,
                  ),
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
                      padding: const EdgeInsets.only(bottom: 5),
                      child: RepaintBoundary(
                        child: InteractiveDepth(
                          key: ValueKey('server-depth-${server.id}'),
                          radius: 13,
                          enabled: false,
                          reducedEffects: view.performanceMode,
                          // Server rows use one deterministic hover lift. The
                          // pointer-following tilt made the card visibly move a
                          // second time after the initial hover transition.
                          tiltEnabled: false,
                          // Transforming the row while the handle's long-press
                          // recognizer is active makes desktop reorder gestures
                          // unreliable. Keep hover depth, but let the handle own
                          // the press sequence without moving its render box.
                          pressEnabled: false,
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onSecondaryTapDown: (details) =>
                                _serverContextActions(
                                  context,
                                  controller,
                                  server,
                                  details.globalPosition,
                                ),
                            child: GlassSurface(
                              radius: 13,
                              blur: 3,
                              style: GlassSurfaceStyle.flat,
                              overlayColor: server.selected
                                  ? Theme.of(context)
                                        .colorScheme
                                        .primaryContainer
                                        .withValues(alpha: .16)
                                  : null,
                              child: Material(
                                type: MaterialType.transparency,
                                child: ListTile(
                                  key: ValueKey('server-row-${server.id}'),
                                  splashColor: Theme.of(
                                    context,
                                  ).colorScheme.primary.withValues(alpha: .10),
                                  hoverColor: Colors.transparent,
                                  focusColor: Colors.transparent,
                                  leading: _SelectionIndicator(
                                    selected: server.selected,
                                    reducedEffects: view.performanceMode,
                                  ),
                                  title: _ServerTitle(server: server),
                                  subtitle: Text(
                                    '${server.protocol}  ${server.transport}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      _Latency(server: server),
                                      ReorderableDragStartListener(
                                        key: ValueKey(
                                          'server-drag-${server.id}',
                                        ),
                                        index: index,
                                        child: Tooltip(
                                          message: 'Drag to reorder',
                                          child: MouseRegion(
                                            cursor: SystemMouseCursors.grab,
                                            child: const Padding(
                                              padding: EdgeInsets.all(8),
                                              child: Icon(
                                                Icons.drag_indicator_rounded,
                                                size: 20,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                      Builder(
                                        builder: (buttonContext) => IconButton(
                                          tooltip: context.s('serverActions'),
                                          onPressed: () => _serverActions(
                                            context,
                                            controller,
                                            server,
                                            _menuPosition(buttonContext),
                                          ),
                                          icon: const Icon(
                                            Icons.more_vert_rounded,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  onTap: () => _perform(
                                    context,
                                    () => controller.selectServer(server.id),
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
        Positioned(
          top: 6,
          left: 8,
          right: 8,
          child: RepaintBoundary(
            child: _ServersGlassHeader(
              height: headerHeight,
              serverCount: app.servers.length,
              onMenu: (position) => _pageActions(
                context,
                controller,
                position,
                isPinging: app.isPinging,
                isRefreshing: app.isRefreshing,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _pageActions(
    BuildContext context,
    AppController controller,
    Offset position, {
    required bool isPinging,
    required bool isRefreshing,
  }) async {
    final action = await showGlassMenu<String>(
      context: context,
      position: position,
      items: [
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
      ],
    );
    if (!context.mounted || action == null) return;
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

  Future<void> _serverActions(
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
        if (const {'VLESS', 'TROJAN'}.contains(server.protocol.toUpperCase()))
          GlassMenuItem(
            value: 'profile',
            icon: Icons.tune_rounded,
            label: context.s('profileTlsSettings'),
          ),
        GlassMenuItem(
          value: 'delete',
          icon: Icons.delete_outline_rounded,
          label: context.s('delete'),
          destructive: true,
        ),
      ],
    );
    if (!context.mounted) return;
    if (action != null) {
      await _handleAction(context, controller, server, action);
    }
  }

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
        if (const {'VLESS', 'TROJAN'}.contains(server.protocol.toUpperCase()))
          GlassMenuItem(
            value: 'profile',
            icon: Icons.tune_rounded,
            label: context.s('profileTlsSettings'),
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
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  delay > 0
                      ? '${context.s('tcpPing')}: $delay ms'
                      : '${context.s('tcpPing')}: ${context.s('timeout')}',
                ),
              ),
            );
          }
        });
      case 'info':
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            settings: const RouteSettings(name: '/server-information'),
            builder: (_) => ServerInformationScreen(server: server),
          ),
        );
      case 'profile':
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            settings: const RouteSettings(name: '/server-profile-settings'),
            builder: (_) => ServerProfileSettingsScreen(
              server: server,
              controller: controller,
            ),
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
          await _perform(context, () => controller.deleteServer(server.id));
        }
    }
  }
}

class _ServersGlassHeader extends StatelessWidget {
  const _ServersGlassHeader({
    required this.height,
    required this.serverCount,
    required this.onMenu,
  });

  final double height;
  final int serverCount;
  final ValueChanged<Offset> onMenu;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final content = SizedBox(
      key: const Key('servers-toolbar'),
      height: height,
      child: Padding(
        padding: const EdgeInsetsDirectional.only(start: 14, end: 4),
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
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Row(
                    key: const Key('servers-toolbar-actions'),
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Builder(
                        builder: (buttonContext) => IconButton(
                          tooltip: context.s('serverActions'),
                          onPressed: () => onMenu(_menuPosition(buttonContext)),
                          icon: const Icon(Icons.more_vert_rounded),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
    return GlassSurface(radius: 16, blur: 18, child: content);
  }
}

Offset _menuPosition(BuildContext context) {
  final box = context.findRenderObject();
  if (box is! RenderBox) return Offset.zero;
  return box.localToGlobal(Offset(0, box.size.height));
}

class _ServerTitle extends StatelessWidget {
  const _ServerTitle({required this.server});

  final ServerInfo server;

  @override
  Widget build(BuildContext context) {
    final code =
        countryCodeFromRemark(server.name) ??
        (server.country.length == 2 ? server.country.toUpperCase() : null);
    final label = remarkWithoutCountryFlag(server.name);
    return Row(
      children: [
        if (code != null) ...[
          CountryFlagBadge(countryCode: code, width: 27, height: 19),
          const SizedBox(width: 9),
        ],
        Expanded(
          child: Text(
            label.isEmpty ? server.name : label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
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

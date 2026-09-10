import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/formatters.dart';
import '../../core/localization/app_strings.dart';
import '../../core/widgets/glass_dialog.dart';
import '../../core/widgets/operation_error.dart';
import '../../core/platform/native_models.dart';
import '../../core/update_checker.dart';
import '../../core/windows_update_manager.dart';
import '../vpn/app_controller.dart';

const _xrayResolutionStrategies = <String, String>{
  'AsIs': 'AsIs',
  'UseIP': 'IPv4 + IPv6',
  'UseIPv4': 'IPv4 only',
  'UseIPv6': 'IPv6 only',
  'UseIPv4v6': 'IPv4, then IPv6',
  'UseIPv6v4': 'IPv6, then IPv4',
};

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _checkingUpdates = false;
  bool _updateManagerInitialized = false;
  final ScrollController _scrollController = ScrollController();
  final ExpansibleController _updatesController = ExpansibleController();
  final GlobalKey _updateDownloadsKey = GlobalKey();
  int _handledFocusRequest = 0;

  @override
  void initState() {
    super.initState();
    WindowsUpdateManager.instance.addListener(_handleUpdateManagerFocus);
  }

  @override
  void dispose() {
    WindowsUpdateManager.instance.removeListener(_handleUpdateManagerFocus);
    _scrollController.dispose();
    super.dispose();
  }

  void _handleUpdateManagerFocus() {
    final request = WindowsUpdateManager.instance.focusRequest;
    if (request == _handledFocusRequest) return;
    _handledFocusRequest = request;
    WidgetsBinding.instance.addPostFrameCallback((_) => _revealDownloads());
  }

  Future<void> _revealDownloads() async {
    if (!mounted) return;
    _updatesController.expand();
    if (!_scrollController.hasClients) {
      await WidgetsBinding.instance.endOfFrame;
    }
    if (!mounted || !_scrollController.hasClients) return;

    // ListView builds children lazily, so the download tile may not have a
    // BuildContext yet. Walk the viewport towards it, then use its real anchor
    // for the final smooth positioning.
    _scrollController.jumpTo(_scrollController.position.minScrollExtent);
    for (var attempt = 0; attempt < 20 && mounted; attempt++) {
      await WidgetsBinding.instance.endOfFrame;
      final target = _updateDownloadsKey.currentContext;
      if (target != null && target.mounted) {
        await Scrollable.ensureVisible(
          target,
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOutCubic,
          alignment: .45,
        );
        return;
      }
      if (!_scrollController.hasClients) return;
      final position = _scrollController.position;
      final next = (position.pixels + position.viewportDimension * .8).clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      );
      if ((next - position.pixels).abs() < 1) return;
      _scrollController.jumpTo(next);
    }
  }

  @override
  Widget build(BuildContext context) {
    final view = ref.watch(
      appControllerProvider.select((value) {
        final app = value.asData?.value;
        return (
          settings: app?.settings ?? const NativeSettings(),
          lastUpdated: app?.lastUpdated ?? 0,
          isRefreshing: app?.isRefreshing ?? false,
          deletedCount: app?.deletedServerCount ?? 0,
          coreVersion: app?.coreVersion ?? 'Bundled',
          appVersion: app?.appVersion ?? '0.3.4',
        );
      }),
    );
    final app = AppSnapshot(
      settings: view.settings,
      lastUpdated: view.lastUpdated,
      isRefreshing: view.isRefreshing,
      deletedServerCount: view.deletedCount,
      coreVersion: view.coreVersion,
      appVersion: view.appVersion,
    );
    final settings = app.settings;
    final controller = ref.read(appControllerProvider.notifier);
    if (!_updateManagerInitialized && app.appVersion.isNotEmpty) {
      _updateManagerInitialized = true;
      WindowsUpdateManager.instance.initialize(app.appVersion);
    }
    return ListView(
      controller: _scrollController,
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        _SettingsGroup(
          title: context.s('tunSettings'),
          initiallyExpanded: true,
          children: [
            SwitchListTile(
              secondary: const Icon(Icons.lan_outlined),
              title: Text(context.s('enableIpv6')),
              subtitle: Text(context.s('enableIpv6Summary')),
              value: settings.enableIpv6,
              onChanged: (value) => _perform(
                context,
                () => controller.updateSettings({'enableIpv6': value}),
              ),
            ),
            SwitchListTile(
              secondary: const Icon(Icons.swap_vert_circle_outlined),
              title: Text(context.s('preferIpv6')),
              subtitle: Text(context.s('preferIpv6Summary')),
              value: settings.preferIpv6,
              onChanged: settings.enableIpv6
                  ? (value) => _perform(
                      context,
                      () => controller.updateSettings({'preferIpv6': value}),
                    )
                  : null,
            ),
            ListTile(
              leading: const Icon(Icons.router_outlined),
              title: Text(context.s('vpnDns')),
              subtitle: Text(settings.vpnDns),
              onTap: () => _editSingleValue(
                context,
                title: context.s('vpnDns'),
                initial: settings.vpnDns,
                validator: (value) => _validateIpAddress(context, value),
                onSave: (value) => controller.updateSettings({'vpnDns': value}),
              ),
            ),
          ],
        ),
        _SettingsGroup(
          title: context.s('localProxy'),
          children: [
            SwitchListTile(
              secondary: const Icon(Icons.sync_alt_rounded),
              title: Text(context.s('enableUdp')),
              subtitle: Text(context.s('enableUdpSummary')),
              value: settings.enableUdp,
              onChanged: (value) => _perform(
                context,
                () => controller.updateSettings({'enableUdp': value}),
              ),
            ),
            SwitchListTile(
              secondary: const Icon(Icons.hub_outlined),
              title: Text(context.s('allowLanConnections')),
              subtitle: Text(context.s('allowLanConnectionsSummary')),
              value: settings.allowLanConnections,
              onChanged: (value) => _perform(
                context,
                () => controller.updateSettings({'allowLanConnections': value}),
              ),
            ),
            if (settings.allowLanConnections)
              ListTile(
                leading: const Icon(Icons.my_location_rounded),
                title: Text(context.s('localListenAddress')),
                subtitle: Text(settings.localListenAddress),
                onTap: () => _editSingleValue(
                  context,
                  title: context.s('localListenAddress'),
                  initial: settings.localListenAddress,
                  validator: (value) => _validateIpAddress(context, value),
                  onSave: (value) =>
                      controller.updateSettings({'localListenAddress': value}),
                ),
              ),
            ListTile(
              leading: const Icon(Icons.electrical_services_outlined),
              title: Text(context.s('localSocksPort')),
              subtitle: Text('${settings.localSocksPort}'),
              onTap: () => _editPort(
                context,
                controller,
                key: 'localSocksPort',
                title: context.s('localSocksPort'),
                current: settings.localSocksPort,
                otherPort: settings.localHttpPort,
              ),
            ),
            ListTile(
              leading: const Icon(Icons.http_rounded),
              title: Text(context.s('localHttpPort')),
              subtitle: Text('${settings.localHttpPort}'),
              onTap: () => _editPort(
                context,
                controller,
                key: 'localHttpPort',
                title: context.s('localHttpPort'),
                current: settings.localHttpPort,
                otherPort: settings.localSocksPort,
              ),
            ),
          ],
        ),
        _SettingsGroup(
          title: context.s('delayTest'),
          children: [
            ListTile(
              leading: const Icon(Icons.travel_explore_rounded),
              title: Text(context.s('realDelayUrl')),
              subtitle: Text(
                settings.realDelayUrl,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              onTap: () => _editSingleValue(
                context,
                title: context.s('realDelayUrl'),
                initial: settings.realDelayUrl,
                validator: (value) => _validateHttpUrl(context, value),
                onSave: (value) =>
                    controller.updateSettings({'realDelayUrl': value}),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.timer_outlined),
              title: Text(context.s('realDelayTimeout')),
              subtitle: Text('${settings.realDelayTimeoutSeconds} s'),
              onTap: () => _chooseValue(
                context,
                title: context.s('realDelayTimeout'),
                current: '${settings.realDelayTimeoutSeconds}',
                values: const {
                  '5': '5 s',
                  '8': '8 s',
                  '10': '10 s',
                  '15': '15 s',
                },
                onSelected: (value) => controller.updateSettings({
                  'realDelayTimeoutSeconds': int.parse(value),
                }),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.speed_rounded),
              title: Text(context.s('realPingConcurrency')),
              subtitle: Text('${settings.realPingConcurrency}'),
              onTap: () => _chooseValue(
                context,
                title: context.s('realPingConcurrency'),
                current: '${settings.realPingConcurrency}',
                values: const {'4': '4', '8': '8', '16': '16', '32': '32'},
                onSelected: (value) => controller.updateSettings({
                  'realPingConcurrency': int.parse(value),
                }),
              ),
            ),
          ],
        ),
        _SettingsGroup(
          title: context.s('coreSettings'),
          children: [
            ListTile(
              leading: const Icon(Icons.article_outlined),
              title: Text(context.s('xrayLogLevel')),
              subtitle: Text(settings.xrayLogLevel),
              onTap: () => _chooseValue(
                context,
                title: context.s('xrayLogLevel'),
                current: settings.xrayLogLevel,
                values: const {
                  'none': 'None',
                  'error': 'Error',
                  'warning': 'Warning',
                  'info': 'Info',
                  'debug': 'Debug',
                },
                onSelected: (value) =>
                    controller.updateSettings({'xrayLogLevel': value}),
              ),
            ),
            SwitchListTile(
              secondary: const Icon(Icons.manage_search_rounded),
              title: Text(context.s('enableSniffing')),
              subtitle: Text(context.s('sniffingSummary')),
              value: settings.sniffingEnabled,
              onChanged: (value) => _perform(
                context,
                () => controller.updateSettings({'sniffingEnabled': value}),
              ),
            ),
            if (settings.sniffingEnabled)
              ListTile(
                leading: const Icon(Icons.radar_rounded),
                title: Text(context.s('sniffingType')),
                subtitle: Text(settings.sniffingType),
                onTap: () => _chooseValue(
                  context,
                  title: context.s('sniffingType'),
                  current: settings.sniffingType,
                  values: const {
                    'http,tls': 'HTTP + TLS',
                    'http,tls,quic': 'HTTP + TLS + QUIC',
                  },
                  onSelected: (value) =>
                      controller.updateSettings({'sniffingType': value}),
                ),
              ),
            SwitchListTile(
              secondary: const Icon(Icons.alt_route_rounded),
              title: Text(context.s('enableRouteOnly')),
              subtitle: Text(context.s('routeOnlySummary')),
              value: settings.routeOnly,
              onChanged: settings.sniffingEnabled
                  ? (value) => _perform(
                      context,
                      () => controller.updateSettings({'routeOnly': value}),
                    )
                  : null,
            ),
            SwitchListTile(
              secondary: const Icon(Icons.call_split_rounded),
              title: Text(context.s('enableFragment')),
              subtitle: Text(context.s('fragmentSummary')),
              value: settings.fragmentEnabled,
              onChanged: (value) => _perform(
                context,
                () => controller.updateSettings({'fragmentEnabled': value}),
              ),
            ),
            if (settings.fragmentEnabled)
              ListTile(
                leading: const Icon(Icons.tune_rounded),
                title: Text(context.s('fragmentParameters')),
                subtitle: Text(
                  '${settings.fragmentPackets} · ${settings.fragmentLength} B · '
                  '${settings.fragmentInterval} ms · max ${settings.fragmentMaxSplit}',
                ),
                onTap: () => _editFragment(context, controller, settings),
              ),
            ListTile(
              leading: const Icon(Icons.fingerprint_rounded),
              title: Text(context.s('defaultFingerprint')),
              subtitle: Text(settings.defaultFingerprint),
              onTap: () => _chooseValue(
                context,
                title: context.s('defaultFingerprint'),
                current: settings.defaultFingerprint,
                values: const {
                  'chrome': 'Chrome',
                  'firefox': 'Firefox',
                  'safari': 'Safari',
                  'ios': 'iOS',
                  'android': 'Android',
                  'edge': 'Edge',
                  '360': '360 Secure Browser',
                  'qq': 'QQ Browser',
                  'random': 'Random',
                  'randomized': 'Randomized',
                },
                onSelected: (value) =>
                    controller.updateSettings({'defaultFingerprint': value}),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.badge_outlined),
              title: Text(context.s('defaultUserAgent')),
              subtitle: Text(
                settings.defaultUserAgent.isEmpty
                    ? context.s('notSet')
                    : settings.defaultUserAgent,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              onTap: () => _editSingleValue(
                context,
                title: context.s('defaultUserAgent'),
                initial: settings.defaultUserAgent,
                onSave: (value) =>
                    controller.updateSettings({'defaultUserAgent': value}),
              ),
            ),
          ],
        ),
        _SettingsGroup(
          title: context.s('routing'),
          children: [
            ListTile(
              leading: const Icon(Icons.route_outlined),
              title: Text(context.s('routing')),
              subtitle: Text(_routingLabel(context, settings.routingMode)),
              onTap: () => _chooseRouting(context, controller, settings),
            ),
            if (settings.routingMode == 'bypassIran')
              ListTile(
                leading: const Icon(Icons.home_work_outlined),
                title: Text(context.s('domesticDns')),
                subtitle: Text(settings.domesticDns),
                onTap: () => _editSingleValue(
                  context,
                  title: context.s('domesticDns'),
                  initial: settings.domesticDns,
                  validator: (value) => _validateDnsResolvers(context, value),
                  onSave: (value) =>
                      controller.updateSettings({'domesticDns': value}),
                ),
              ),
            if (settings.routingMode == 'custom')
              ListTile(
                leading: const Icon(Icons.rule_rounded),
                title: Text(context.s('custom')),
                subtitle: Text(context.s('customRuleHint')),
                onTap: () => _editCustomRules(context, controller, settings),
              ),
          ],
        ),
        _SettingsGroup(
          title: context.s('dns'),
          children: [
            ListTile(
              leading: const Icon(Icons.public_outlined),
              title: Text(context.s('remoteDns')),
              subtitle: Text(settings.remoteDns),
              onTap: () => _editSingleValue(
                context,
                title: context.s('remoteDns'),
                initial: settings.remoteDns,
                validator: (value) => _validateDnsResolvers(context, value),
                onSave: (value) =>
                    controller.updateSettings({'remoteDns': value}),
              ),
            ),
            SwitchListTile(
              secondary: const Icon(Icons.dns_outlined),
              title: Text(context.s('directDns')),
              subtitle: Text(context.s('directDnsSummary')),
              value: settings.directDnsEnabled,
              onChanged: (value) => _perform(
                context,
                () => controller.updateSettings({'directDnsEnabled': value}),
              ),
            ),
            if (settings.directDnsEnabled)
              ListTile(
                leading: const Icon(Icons.edit_location_alt_outlined),
                title: Text(context.s('directDnsAddress')),
                subtitle: Text(settings.directDnsAddress),
                onTap: () => _editSingleValue(
                  context,
                  title: context.s('directDnsAddress'),
                  initial: settings.directDnsAddress,
                  validator: (value) => _validateDnsResolvers(context, value),
                  onSave: (value) =>
                      controller.updateSettings({'directDnsAddress': value}),
                ),
              ),
            ListTile(
              leading: const Icon(Icons.account_tree_outlined),
              title: Text(context.s('domainStrategy')),
              subtitle: Text(settings.domainStrategy),
              onTap: () => _chooseValue(
                context,
                title: context.s('domainStrategy'),
                current: settings.domainStrategy,
                values: const {
                  'AsIs': 'AsIs',
                  'IPIfNonMatch': 'IPIfNonMatch',
                  'IPOnDemand': 'IPOnDemand',
                },
                onSelected: (value) =>
                    controller.updateSettings({'domainStrategy': value}),
              ),
            ),
          ],
        ),
        _SettingsGroup(
          title: context.s('advancedSettings'),
          children: [
            ListTile(
              leading: const Icon(Icons.settings_ethernet_rounded),
              title: Text(context.s('vpnInterfaceAddress')),
              subtitle: Text(settings.vpnInterfaceAddress),
              onTap: () => _editSingleValue(
                context,
                title: context.s('vpnInterfaceAddress'),
                initial: settings.vpnInterfaceAddress,
                validator: (value) => _validateVpnAddress(context, value),
                onSave: (value) =>
                    controller.updateSettings({'vpnInterfaceAddress': value}),
              ),
            ),
            if (settings.enableIpv6)
              ListTile(
                leading: const Icon(Icons.device_hub_rounded),
                title: Text(context.s('vpnInterfaceIpv6Address')),
                subtitle: Text(settings.vpnInterfaceIpv6Address),
                onTap: () => _editSingleValue(
                  context,
                  title: context.s('vpnInterfaceIpv6Address'),
                  initial: settings.vpnInterfaceIpv6Address,
                  validator: (value) => _validateVpnIpv6Address(context, value),
                  onSave: (value) => controller.updateSettings({
                    'vpnInterfaceIpv6Address': value,
                  }),
                ),
              ),
            ListTile(
              leading: const Icon(Icons.straighten_rounded),
              title: Text(context.s('vpnMtu')),
              subtitle: Text(
                '${settings.vpnMtu} · ${context.s('vpnMtuSummary')}',
              ),
              onTap: () => _editMtu(context, controller, settings.vpnMtu),
            ),
            ListTile(
              leading: const Icon(Icons.filter_alt_outlined),
              title: Text(context.s('dnsQueryStrategy')),
              subtitle: Text(settings.dnsQueryStrategy),
              onTap: () => _chooseValue(
                context,
                title: context.s('dnsQueryStrategy'),
                current: settings.dnsQueryStrategy,
                values: const {
                  'Auto': 'Auto',
                  'UseIP': 'IPv4 + IPv6',
                  'UseIPv4': 'IPv4 only',
                  'UseIPv6': 'IPv6 only',
                  'UseSystem': 'System DNS strategy',
                },
                onSelected: (value) =>
                    controller.updateSettings({'dnsQueryStrategy': value}),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.alt_route_rounded),
              title: Text(context.s('directTargetStrategy')),
              subtitle: Text(settings.directTargetStrategy),
              onTap: () => _chooseValue(
                context,
                title: context.s('directTargetStrategy'),
                current: settings.directTargetStrategy,
                values: _xrayResolutionStrategies,
                onSelected: (value) =>
                    controller.updateSettings({'directTargetStrategy': value}),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.cloud_queue_rounded),
              title: Text(context.s('proxyTargetStrategy')),
              subtitle: Text(settings.proxyTargetStrategy),
              onTap: () => _chooseValue(
                context,
                title: context.s('proxyTargetStrategy'),
                current: settings.proxyTargetStrategy,
                values: _xrayResolutionStrategies,
                onSelected: (value) =>
                    controller.updateSettings({'proxyTargetStrategy': value}),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.cable_rounded),
              title: Text(context.s('proxyDialStrategy')),
              subtitle: Text(settings.proxyDialStrategy),
              onTap: () => _chooseValue(
                context,
                title: context.s('proxyDialStrategy'),
                current: settings.proxyDialStrategy,
                values: const {'Auto': 'Auto', ..._xrayResolutionStrategies},
                onSelected: (value) =>
                    controller.updateSettings({'proxyDialStrategy': value}),
              ),
            ),
            SwitchListTile(
              secondary: const Icon(Icons.swap_horiz_rounded),
              title: Text(context.s('happyEyeballs')),
              subtitle: Text(context.s('happyEyeballsSummary')),
              value: settings.happyEyeballs,
              onChanged: settings.enableIpv6
                  ? (value) => _perform(
                      context,
                      () => controller.updateSettings({'happyEyeballs': value}),
                    )
                  : null,
            ),
            SwitchListTile(
              secondary: const Icon(Icons.speed_outlined),
              title: Text(context.s('blockQuic')),
              subtitle: Text(context.s('blockQuicSummary')),
              value: settings.blockQuic,
              onChanged: (value) => _perform(
                context,
                () => controller.updateSettings({'blockQuic': value}),
              ),
            ),
            SwitchListTile(
              secondary: const Icon(Icons.merge_type_rounded),
              title: Text(context.s('mux')),
              subtitle: Text(context.s('muxSummary')),
              value: settings.muxEnabled,
              onChanged: (value) => _perform(
                context,
                () => controller.updateSettings({'muxEnabled': value}),
              ),
            ),
            if (settings.muxEnabled)
              ListTile(
                leading: const Icon(Icons.numbers_rounded),
                title: Text(context.s('muxConcurrency')),
                subtitle: Text('${settings.muxConcurrency}'),
                onTap: () => _chooseValue(
                  context,
                  title: context.s('muxConcurrency'),
                  current: '${settings.muxConcurrency}',
                  values: const {
                    '1': '1',
                    '4': '4',
                    '8': '8',
                    '16': '16',
                    '32': '32',
                  },
                  onSelected: (value) => controller.updateSettings({
                    'muxConcurrency': int.parse(value),
                  }),
                ),
              ),
          ],
        ),
        _SettingsGroup(
          title: context.s('subscriptionUpdate'),
          children: [
            ListTile(
              leading: const Icon(Icons.sync_rounded),
              title: Text(context.s('refresh')),
              subtitle: Text(
                '${context.s('lastUpdated')}: ${formatDateTime(app.lastUpdated)}',
              ),
              trailing: app.isRefreshing
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.chevron_right_rounded),
              onTap: app.isRefreshing
                  ? null
                  : () => _perform(context, controller.refreshSubscription),
            ),
            ListTile(
              enabled: app.deletedServerCount > 0,
              leading: const Icon(Icons.restore_from_trash_outlined),
              title: Text(context.s('restoreDeletedServers')),
              subtitle: Text(
                app.deletedServerCount == 0
                    ? context.s('noDeletedServers')
                    : '${app.deletedServerCount} ${context.s('deletedServersCount')}',
              ),
              onTap: app.deletedServerCount == 0
                  ? null
                  : () => _perform(context, () async {
                      await controller.restoreDeletedServers();
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(context.s('serversRestored'))),
                        );
                      }
                    }),
            ),
            SwitchListTile(
              secondary: const Icon(Icons.update_rounded),
              title: Text(context.s('autoUpdate')),
              value: settings.autoUpdate,
              onChanged: (value) => _perform(
                context,
                () => controller.updateSettings({'autoUpdate': value}),
              ),
            ),
            ListTile(
              enabled: settings.autoUpdate,
              leading: const Icon(Icons.schedule_rounded),
              title: Text(context.s('updateInterval')),
              subtitle: Text(context.s('hours${settings.updateIntervalHours}')),
              onTap: !settings.autoUpdate
                  ? null
                  : () => _chooseValue(
                      context,
                      title: context.s('updateInterval'),
                      current: '${settings.updateIntervalHours}',
                      values: {
                        '6': context.s('hours6'),
                        '12': context.s('hours12'),
                        '24': context.s('hours24'),
                      },
                      onSelected: (value) => controller.updateSettings({
                        'updateIntervalHours': int.parse(value),
                      }),
                    ),
            ),
          ],
        ),
        _SettingsGroup(
          title: context.s('appearance'),
          children: [
            ListTile(
              leading: const Icon(Icons.contrast_rounded),
              title: Text(context.s('theme')),
              subtitle: Text(context.s(settings.themeMode)),
              onTap: () => _chooseValue(
                context,
                title: context.s('theme'),
                current: settings.themeMode,
                values: {
                  'system': context.s('system'),
                  'light': context.s('light'),
                  'dark': context.s('dark'),
                },
                onSelected: (value) =>
                    controller.updateSettings({'themeMode': value}),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.language_rounded),
              title: Text(context.s('language')),
              subtitle: Text(
                settings.language == 'fa'
                    ? context.s('persian')
                    : context.s('english'),
              ),
              onTap: () => _chooseValue(
                context,
                title: context.s('language'),
                current: settings.language,
                values: {
                  'en': context.s('english'),
                  'fa': context.s('persian'),
                },
                onSelected: (value) =>
                    controller.updateSettings({'language': value}),
              ),
            ),
            SwitchListTile(
              secondary: const Icon(Icons.bolt_rounded),
              title: Text(context.s('performanceMode')),
              subtitle: Text(context.s('performanceModeSummary')),
              value: settings.performanceMode,
              onChanged: (value) => _perform(
                context,
                () => controller.updateSettings({
                  'performanceMode': value,
                  'performanceModePrompted': true,
                }),
              ),
            ),
            SwitchListTile(
              secondary: const Icon(Icons.notes_rounded),
              title: Text(context.s('showRecentLogsOnHome')),
              subtitle: Text(context.s('showRecentLogsOnHomeSummary')),
              value: settings.showRecentLogsOnHome,
              onChanged: (value) => _perform(
                context,
                () =>
                    controller.updateSettings({'showRecentLogsOnHome': value}),
              ),
            ),
            SwitchListTile(
              secondary: const Icon(Icons.login_rounded),
              title: Text(context.s('startWithWindows')),
              subtitle: Text(context.s('startWithWindowsSummary')),
              value: settings.startWithWindows,
              onChanged: (value) => _perform(
                context,
                () => controller.updateSettings({'startWithWindows': value}),
              ),
            ),
          ],
        ),
        _SettingsGroup(
          title: context.s('updates'),
          controller: _updatesController,
          children: [
            ListTile(
              leading: const Icon(Icons.system_update_alt_rounded),
              title: Text(context.s('checkForUpdates')),
              subtitle: Text(
                '${context.s('currentVersion')}: ${app.appVersion}',
              ),
              trailing: _checkingUpdates
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.chevron_right_rounded),
              onTap: _checkingUpdates
                  ? null
                  : () => _checkForUpdates(context, controller, app.appVersion),
            ),
            KeyedSubtree(
              key: _updateDownloadsKey,
              child: _UpdateDownloadTile(controller: controller),
            ),
          ],
        ),
        _SettingsGroup(
          title: context.s('settings'),
          children: [
            ListTile(
              leading: const Icon(Icons.public_rounded),
              title: Text(context.s('ipProvider')),
              subtitle: Text(
                settings.ipCheckUrl,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              onTap: () => _editSingleValue(
                context,
                title: context.s('ipProvider'),
                initial: settings.ipCheckUrl,
                validator: (value) => _validateHttps(context, value),
                onSave: (value) =>
                    controller.updateSettings({'ipCheckUrl': value}),
              ),
            ),
            ListTile(
              enabled: settings.telegramUrlConfigured,
              leading: const Icon(Icons.send_outlined),
              title: Text(context.s('telegram')),
              subtitle: Text(
                settings.telegramContact.isEmpty
                    ? context.s('telegramSubtitle')
                    : '${settings.telegramContact} · ${context.s('telegramSubtitle')}',
              ),
              trailing: const Icon(Icons.open_in_new_rounded, size: 19),
              onTap: () => _perform(context, controller.openTelegram),
            ),
            ListTile(
              leading: const Icon(Icons.info_outline_rounded),
              title: Text(context.s('about')),
              subtitle: Text('niraN ${app.appVersion}'),
              onTap: () => _showAbout(context, app.coreVersion, app.appVersion),
            ),
            ListTile(
              leading: const Icon(Icons.settings_backup_restore_rounded),
              title: Text(context.s('resetSettings')),
              onTap: () => _confirmResetSettings(context, controller),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Text(
            context.s('applyNextConnection'),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    );
  }

  Future<void> _confirmResetSettings(
    BuildContext context,
    AppController controller,
  ) async {
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => NirangAlertDialog(
        icon: const Icon(Icons.settings_backup_restore_rounded),
        title: Text(context.s('resetSettings')),
        content: Text(context.s('resetSettingsBody')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(context.s('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(context.s('resetSettings')),
          ),
        ],
      ),
    );
    if (accepted != true || !context.mounted) return;
    await _perform(context, controller.resetSettings);
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.s('settingsReset'))));
    }
  }

  Future<void> _chooseRouting(
    BuildContext context,
    AppController controller,
    NativeSettings settings,
  ) async {
    await _chooseValue(
      context,
      title: context.s('routing'),
      current: settings.routingMode,
      values: {
        'global': context.s('global'),
        'bypassIran': context.s('bypassIran'),
        'custom': context.s('custom'),
      },
      descriptions: {
        'global': context.s('globalRoutingHint'),
        'bypassIran': context.s('bypassIranHint'),
        'custom': context.s('customRuleHint'),
      },
      onSelected: (value) => controller.updateSettings({'routingMode': value}),
    );
  }

  Future<void> _checkForUpdates(
    BuildContext context,
    AppController controller,
    String currentVersion,
  ) async {
    setState(() => _checkingUpdates = true);
    try {
      final release = await const GitHubUpdateChecker().check(currentVersion);
      if (!context.mounted) return;
      if (!release.updateAvailable) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(context.s('upToDate'))));
        return;
      }
      final updateManager = WindowsUpdateManager.instance;
      final updateAsset = await updateManager.assetFor(release);
      if (!context.mounted) return;
      final action = await showDialog<String>(
        context: context,
        builder: (dialogContext) => NirangAlertDialog(
          icon: const Icon(Icons.new_releases_outlined),
          title: Text(context.s('newVersionAvailable')),
          content: Text('${release.latestVersion}'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, 'browser'),
              child: const Text('Download with browser'),
            ),
            FilledButton(
              onPressed: updateAsset?.sha256 == null
                  ? null
                  : () => Navigator.pop(dialogContext, 'inside'),
              child: const Text('Download in niraN'),
            ),
          ],
        ),
      );
      if (action == 'inside' && updateAsset != null) {
        await updateManager.start(updateAsset, release.latestVersion);
        updateManager.requestManagerFocus();
      } else if (action == 'browser' && context.mounted) {
        await _perform(
          context,
          () => controller.openExternalUrl(
            updateAsset?.url ?? release.releaseUrl,
          ),
        );
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(context.s('updateCheckFailed'))));
      }
    } finally {
      if (mounted) setState(() => _checkingUpdates = false);
    }
  }

  Future<void> _editCustomRules(
    BuildContext context,
    AppController controller,
    NativeSettings settings,
  ) async {
    final result = await showDialog<({String domains, String ips})>(
      context: context,
      builder: (_) => _CustomRulesDialog(
        domains: settings.customDomains,
        ips: settings.customIps,
      ),
    );
    if (context.mounted && result != null) {
      await _perform(
        context,
        () => controller.updateSettings({
          'customDomains': result.domains,
          'customIps': result.ips,
        }),
      );
    }
  }

  Future<void> _editSingleValue(
    BuildContext context, {
    required String title,
    required String initial,
    required Future<void> Function(String value) onSave,
    String? Function(String value)? validator,
  }) async {
    final value = await _promptSingleValue(
      context,
      title: title,
      initial: initial,
      validator: validator,
    );
    if (value != null && context.mounted) {
      await _perform(context, () => onSave(value));
    }
  }

  Future<String?> _promptSingleValue(
    BuildContext context, {
    required String title,
    required String initial,
    TextInputType keyboardType = TextInputType.url,
    String? Function(String value)? validator,
  }) async {
    return showDialog<String>(
      context: context,
      builder: (_) => _TextValueDialog(
        title: title,
        initial: initial,
        keyboardType: keyboardType,
        validator: validator,
      ),
    );
  }

  Future<void> _editMtu(
    BuildContext context,
    AppController controller,
    int current,
  ) async {
    final value = await _promptSingleValue(
      context,
      title: context.s('vpnMtu'),
      initial: '$current',
      keyboardType: TextInputType.number,
      validator: (value) {
        final mtu = int.tryParse(value);
        return mtu != null && mtu >= 1280 && mtu <= 9000
            ? null
            : context.s('vpnMtuSummary');
      },
    );
    if (!context.mounted || value == null) return;
    final mtu = int.parse(value);
    await _perform(context, () => controller.updateSettings({'vpnMtu': mtu}));
  }

  Future<void> _editFragment(
    BuildContext context,
    AppController controller,
    NativeSettings settings,
  ) async {
    final packets = TextEditingController(text: settings.fragmentPackets);
    final length = TextEditingController(text: settings.fragmentLength);
    final interval = TextEditingController(text: settings.fragmentInterval);
    final maxSplit = TextEditingController(text: settings.fragmentMaxSplit);
    final formKey = GlobalKey<FormState>();
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => NirangAlertDialog(
        title: Text(context.s('fragmentParameters')),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: packets,
                decoration: InputDecoration(
                  labelText: context.s('fragmentPackets'),
                ),
                validator: (value) =>
                    (value?.trim() == 'tlshello' ||
                        _validFragmentRange(value, minimum: 1))
                    ? null
                    : context.s('invalidValue'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: length,
                decoration: InputDecoration(
                  labelText: context.s('fragmentLength'),
                  suffixText: 'bytes',
                ),
                validator: (value) => _validFragmentRange(value, minimum: 1)
                    ? null
                    : context.s('invalidValue'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: interval,
                decoration: InputDecoration(
                  labelText: context.s('fragmentInterval'),
                  suffixText: 'ms',
                ),
                validator: (value) => _validFragmentRange(value, minimum: 0)
                    ? null
                    : context.s('invalidValue'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: maxSplit,
                decoration: InputDecoration(
                  labelText: context.s('fragmentMaxSplit'),
                  hintText: '0 or 1-4',
                ),
                validator: (value) =>
                    _validFragmentRange(value, minimum: 0, allowSingle: true)
                    ? null
                    : context.s('invalidValue'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(context.s('cancel')),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState?.validate() == true) {
                Navigator.pop(dialogContext, true);
              }
            },
            child: Text(context.s('save')),
          ),
        ],
      ),
    );
    if (accepted == true && context.mounted) {
      await _perform(
        context,
        () => controller.updateSettings({
          'fragmentPackets': packets.text.trim(),
          'fragmentLength': length.text.trim(),
          'fragmentInterval': interval.text.trim(),
          'fragmentMaxSplit': maxSplit.text.trim(),
        }),
      );
    }
    packets.dispose();
    length.dispose();
    interval.dispose();
    maxSplit.dispose();
  }

  Future<void> _editPort(
    BuildContext context,
    AppController controller, {
    required String key,
    required String title,
    required int current,
    required int otherPort,
  }) async {
    final value = await _promptSingleValue(
      context,
      title: title,
      initial: '$current',
      keyboardType: TextInputType.number,
      validator: (value) {
        final port = int.tryParse(value);
        return port != null &&
                port >= 1024 &&
                port <= 65535 &&
                port != otherPort
            ? null
            : context.s('invalidPort');
      },
    );
    if (!context.mounted || value == null) return;
    await _perform(
      context,
      () => controller.updateSettings({key: int.parse(value)}),
    );
  }

  Future<void> _chooseValue(
    BuildContext context, {
    required String title,
    required String current,
    required Map<String, String> values,
    required Future<void> Function(String value) onSelected,
    Map<String, String>? descriptions,
  }) async {
    final selected = await _pickValue(
      context,
      title: title,
      current: current,
      values: values,
      descriptions: descriptions,
    );
    if (selected != null && selected != current && context.mounted) {
      await _perform(context, () => onSelected(selected));
    }
  }

  Future<String?> _pickValue(
    BuildContext context, {
    required String title,
    required String current,
    required Map<String, String> values,
    Map<String, String>? descriptions,
  }) async {
    var temporary = current;
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => NirangAlertDialog(
          title: Text(title),
          contentPadding: const EdgeInsets.fromLTRB(8, 12, 8, 0),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final entry in values.entries)
                ListTile(
                  leading: Icon(
                    entry.key == temporary
                        ? Icons.radio_button_checked_rounded
                        : Icons.radio_button_unchecked_rounded,
                    color: entry.key == temporary
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.outline,
                  ),
                  title: Text(entry.value),
                  subtitle: descriptions?[entry.key] == null
                      ? null
                      : Text(descriptions![entry.key]!),
                  onTap: () => setDialogState(() => temporary = entry.key),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(context.s('cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, temporary),
              child: Text(context.s('apply')),
            ),
          ],
        ),
      ),
    );
  }

  void _showAbout(
    BuildContext context,
    String coreVersion,
    String appVersion,
  ) => showAboutDialog(
    context: context,
    applicationName: 'niraN',
    applicationVersion: appVersion,
    applicationIcon: ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Image.asset(
        'assets/branding/nirang-logo-concept.png',
        width: 54,
        height: 54,
        cacheWidth: 108,
        cacheHeight: 108,
      ),
    ),
    children: [
      const SizedBox(height: 8),
      Text('${context.s('coreVersion')}: $coreVersion'),
      Text('${context.s('packageName')}: dev.nirang.client'),
    ],
  );
}

class _TextValueDialog extends StatefulWidget {
  const _TextValueDialog({
    required this.title,
    required this.initial,
    required this.keyboardType,
    this.validator,
  });

  final String title;
  final String initial;
  final TextInputType keyboardType;
  final String? Function(String value)? validator;

  @override
  State<_TextValueDialog> createState() => _TextValueDialogState();
}

class _TextValueDialogState extends State<_TextValueDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initial);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => NirangAlertDialog(
    title: Text(widget.title),
    content: Form(
      key: _formKey,
      child: TextFormField(
        controller: _controller,
        autocorrect: false,
        keyboardType: widget.keyboardType,
        validator: (raw) {
          final value = raw?.trim() ?? '';
          if (value.isEmpty) return context.s('requiredValue');
          return widget.validator?.call(value);
        },
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(context.s('cancel')),
      ),
      FilledButton(
        onPressed: () {
          if (_formKey.currentState?.validate() != true) return;
          Navigator.pop(context, _controller.text.trim());
        },
        child: Text(context.s('save')),
      ),
    ],
  );
}

class _CustomRulesDialog extends StatefulWidget {
  const _CustomRulesDialog({required this.domains, required this.ips});

  final String domains;
  final String ips;

  @override
  State<_CustomRulesDialog> createState() => _CustomRulesDialogState();
}

class _CustomRulesDialogState extends State<_CustomRulesDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _domains;
  late final TextEditingController _ips;

  @override
  void initState() {
    super.initState();
    _domains = TextEditingController(text: widget.domains);
    _ips = TextEditingController(text: widget.ips);
  }

  @override
  void dispose() {
    _domains.dispose();
    _ips.dispose();
    super.dispose();
  }

  String? _validateDomains(String? value) {
    final text = value ?? '';
    if (!_validRuleText(text)) return context.s('invalidRules');
    return _splitDomainRules(text).every(_isValidDomainRule)
        ? null
        : context.s('invalidRules');
  }

  String? _validateIps(String? value) {
    final text = value ?? '';
    if (!_validRuleText(text)) return context.s('invalidRules');
    return _splitRules(text).every(_isValidIpRule)
        ? null
        : context.s('invalidRules');
  }

  @override
  Widget build(BuildContext context) => NirangAlertDialog(
    title: Text(context.s('custom')),
    content: Form(
      key: _formKey,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _domains,
              maxLines: 4,
              validator: _validateDomains,
              decoration: InputDecoration(
                labelText: context.s('customDomains'),
                hintText: 'domain:example.com, full:api.example.com',
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _ips,
              maxLines: 4,
              validator: _validateIps,
              decoration: InputDecoration(
                labelText: context.s('customIps'),
                hintText: '1.2.3.4, 10.0.0.0/8, 2001:db8::/32',
              ),
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(context.s('cancel')),
      ),
      FilledButton(
        onPressed: () {
          if (_formKey.currentState?.validate() != true) return;
          Navigator.pop(context, (
            domains: _domains.text.trim(),
            ips: _ips.text.trim(),
          ));
        },
        child: Text(context.s('save')),
      ),
    ],
  );
}

class _SettingsGroup extends StatelessWidget {
  const _SettingsGroup({
    required this.title,
    required this.children,
    this.controller,
    this.initiallyExpanded = false,
  });

  final String title;
  final List<Widget> children;
  final ExpansibleController? controller;
  final bool initiallyExpanded;

  @override
  Widget build(BuildContext context) => ExpansionTile(
    key: PageStorageKey(title),
    controller: controller,
    initiallyExpanded: initiallyExpanded,
    maintainState: true,
    tilePadding: const EdgeInsets.symmetric(horizontal: 16),
    childrenPadding: const EdgeInsets.only(bottom: 6),
    shape: Border(
      bottom: BorderSide(
        color: Theme.of(
          context,
        ).colorScheme.outlineVariant.withValues(alpha: .45),
      ),
    ),
    collapsedShape: Border(
      bottom: BorderSide(
        color: Theme.of(
          context,
        ).colorScheme.outlineVariant.withValues(alpha: .30),
      ),
    ),
    title: Text(
      title.toUpperCase(),
      style: Theme.of(context).textTheme.labelMedium?.copyWith(
        letterSpacing: .8,
        color: Theme.of(context).colorScheme.primary,
        fontWeight: FontWeight.w700,
      ),
    ),
    children: children,
  );
}

String _routingLabel(BuildContext context, String value) => switch (value) {
  'bypassIran' => context.s('bypassIran'),
  'custom' => context.s('custom'),
  _ => context.s('global'),
};

List<String> _splitRules(String value) => value
    .split(RegExp(r'[,\n]'))
    .map((entry) => entry.trim())
    .where((entry) => entry.isNotEmpty)
    .toList(growable: false);

List<String> _splitDomainRules(String value) => value
    .split('\n')
    .expand((line) {
      final trimmed = line.trim();
      return trimmed.toLowerCase().startsWith('regexp:')
          ? [trimmed]
          : trimmed.split(',');
    })
    .map((entry) => entry.trim())
    .where((entry) => entry.isNotEmpty)
    .toList(growable: false);

bool _validRuleText(String value) =>
    value.length <= 16384 &&
    !value.contains('\u0000') &&
    !value.runes.any(
      (code) => code < 32 && code != 9 && code != 10 && code != 13,
    );

bool _validFragmentRange(
  String? raw, {
  required int minimum,
  bool allowSingle = false,
}) {
  final value = raw?.trim() ?? '';
  final match = RegExp(
    allowSingle ? r'^(\d+)(?:-(\d+))?$' : r'^(\d+)-(\d+)$',
  ).firstMatch(value);
  if (match == null) return false;
  final from = int.tryParse(match.group(1) ?? '');
  final to = int.tryParse(match.group(2) ?? match.group(1) ?? '');
  return from != null && to != null && from >= minimum && to >= from;
}

class _UpdateDownloadTile extends StatelessWidget {
  const _UpdateDownloadTile({required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: WindowsUpdateManager.instance,
    builder: (context, _) {
      final manager = WindowsUpdateManager.instance;
      final value = manager.snapshot;
      if (value.status == UpdateDownloadStatus.idle) {
        return const SizedBox.shrink();
      }
      final received = formatBytes(value.received);
      final total = value.total > 0 ? formatBytes(value.total) : 'Unknown';
      return ListTile(
        leading: Icon(switch (value.status) {
          UpdateDownloadStatus.readyToUpdate ||
          UpdateDownloadStatus.updateCompleted => Icons.download_done_rounded,
          UpdateDownloadStatus.failed ||
          UpdateDownloadStatus.updateFailed => Icons.error_outline_rounded,
          UpdateDownloadStatus.paused => Icons.pause_circle_outline_rounded,
          UpdateDownloadStatus.cancelled => Icons.cancel_outlined,
          UpdateDownloadStatus.downloaded ||
          UpdateDownloadStatus.verifying => Icons.verified_outlined,
          UpdateDownloadStatus.closingApp ||
          UpdateDownloadStatus.extracting ||
          UpdateDownloadStatus.replacingFiles ||
          UpdateDownloadStatus.renamingFolder ||
          UpdateDownloadStatus.restarting => Icons.system_update_alt_rounded,
          _ => Icons.downloading_rounded,
        }),
        title: Text('${context.s('updateDownload')} · ${value.version}'),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value.error ??
                  '${_downloadStatusLabel(context, value.status)} · $received / $total',
            ),
            if (value.status == UpdateDownloadStatus.downloading ||
                value.status == UpdateDownloadStatus.downloaded ||
                value.status == UpdateDownloadStatus.verifying)
              LinearProgressIndicator(value: value.progress),
          ],
        ),
        trailing: Wrap(
          spacing: 2,
          children: [
            if (value.status == UpdateDownloadStatus.downloading)
              IconButton(
                tooltip: 'Pause',
                onPressed: manager.pause,
                icon: const Icon(Icons.pause_circle_outline_rounded),
              ),
            if (value.status == UpdateDownloadStatus.downloading)
              IconButton(
                tooltip: context.s('cancelDownload'),
                onPressed: manager.cancel,
                icon: const Icon(Icons.cancel_outlined),
              ),
            if (value.status == UpdateDownloadStatus.paused ||
                value.status == UpdateDownloadStatus.cancelled ||
                value.status == UpdateDownloadStatus.failed)
              IconButton(
                tooltip: context.s('resumeDownload'),
                onPressed: manager.resume,
                icon: const Icon(Icons.play_arrow_rounded),
              ),
            if (value.status == UpdateDownloadStatus.readyToUpdate ||
                value.status == UpdateDownloadStatus.updateFailed)
              IconButton(
                tooltip: context.s('installUpdate'),
                onPressed: () => _perform(context, () async {
                  final mustExit = await manager.launch();
                  if (mustExit) await controller.exitApplication();
                }),
                icon: const Icon(Icons.install_desktop_rounded),
              ),
            if (value.status != UpdateDownloadStatus.downloading &&
                value.status != UpdateDownloadStatus.downloaded &&
                value.status != UpdateDownloadStatus.verifying &&
                !manager.isInstalling) ...[
              IconButton(
                tooltip: context.s('openDownloadFolder'),
                onPressed: () => _perform(context, manager.openFolder),
                icon: const Icon(Icons.folder_open_rounded),
              ),
              IconButton(
                tooltip: context.s('delete'),
                onPressed: manager.delete,
                icon: const Icon(Icons.delete_outline_rounded),
              ),
            ],
          ],
        ),
      );
    },
  );
}

String _downloadStatusLabel(
  BuildContext context,
  UpdateDownloadStatus status,
) => switch (status) {
  UpdateDownloadStatus.downloading => context.s('downloading'),
  UpdateDownloadStatus.paused => context.s('paused'),
  UpdateDownloadStatus.cancelled => context.s('cancelled'),
  UpdateDownloadStatus.downloaded => context.s('downloaded'),
  UpdateDownloadStatus.verifying => context.s('verifying'),
  UpdateDownloadStatus.readyToUpdate => context.s('readyToUpdate'),
  UpdateDownloadStatus.closingApp => context.s('closingApp'),
  UpdateDownloadStatus.extracting => context.s('extracting'),
  UpdateDownloadStatus.replacingFiles => context.s('replacingFiles'),
  UpdateDownloadStatus.renamingFolder => context.s('renamingFolder'),
  UpdateDownloadStatus.restarting => context.s('restartingApp'),
  UpdateDownloadStatus.updateCompleted => context.s('completed'),
  UpdateDownloadStatus.updateFailed => context.s('updateFailed'),
  UpdateDownloadStatus.failed => context.s('failed'),
  UpdateDownloadStatus.idle => '',
};

final _hostnameRule = RegExp(
  r'^(?=.{1,253}$)([A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.)*[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?$',
);

bool _isValidDomainRule(String rule) {
  if (rule.length > 512) return false;
  final separator = rule.indexOf(':');
  if (separator < 0) {
    return !rule.contains(RegExp(r'\s')) && _hostnameRule.hasMatch(rule);
  }
  final prefix = rule.substring(0, separator).toLowerCase();
  final body = rule.substring(separator + 1);
  if (prefix == 'regexp') return body.isNotEmpty;
  return !body.contains(RegExp(r'\s')) &&
      (prefix == 'domain' || prefix == 'full') &&
      _hostnameRule.hasMatch(body);
}

bool _isValidIpRule(String rule) {
  final parts = rule.split('/');
  if (parts.length > 2 || !_isIpAddress(parts.first)) return false;
  if (parts.length == 1) return true;
  final prefix = int.tryParse(parts.last);
  final maxPrefix = parts.first.contains(':') ? 128 : 32;
  return prefix != null && prefix >= 0 && prefix <= maxPrefix;
}

bool _isIpAddress(String value) {
  if (value.length > 253 || value.contains(RegExp(r'\s'))) {
    return false;
  }
  final ipv4Parts = value.split('.');
  final isIpv4 =
      ipv4Parts.length == 4 &&
      ipv4Parts.every((part) {
        final number = int.tryParse(part);
        return number != null && number >= 0 && number <= 255;
      });
  final isIpv6 =
      value.contains(':') &&
      RegExp(r'^[0-9a-fA-F:]+$').hasMatch(value) &&
      value.split(':').length >= 3;
  return isIpv4 || isIpv6;
}

String? _validateIpAddress(BuildContext context, String value) =>
    _isIpAddress(value) ? null : context.s('invalidDns');

String? _validateVpnAddress(BuildContext context, String value) {
  final parts = value.split('/');
  if (parts.length != 2 || !_isIpAddress(parts.first)) {
    return context.s('invalidVpnAddress');
  }
  final octets = parts.first.split('.').map(int.tryParse).toList();
  final prefix = int.tryParse(parts.last);
  if (octets.length != 4 || octets.any((value) => value == null)) {
    return context.s('invalidVpnAddress');
  }
  final first = octets[0]!;
  final second = octets[1]!;
  final isPrivate =
      first == 10 ||
      (first == 172 && second >= 16 && second <= 31) ||
      (first == 192 && second == 168);
  return isPrivate && prefix != null && prefix >= 16 && prefix <= 30
      ? null
      : context.s('invalidVpnAddress');
}

String? _validateVpnIpv6Address(BuildContext context, String value) {
  final parts = value.trim().split('/');
  final prefix = parts.length == 2 ? int.tryParse(parts.last) : null;
  final address = parts.length == 2 ? parts.first : '';
  return _isIpAddress(address) &&
          address.contains(':') &&
          prefix != null &&
          prefix >= 1 &&
          prefix <= 126
      ? null
      : context.s('invalidVpnIpv6Address');
}

String? _validateDnsResolvers(BuildContext context, String value) {
  final resolvers = value
      .split(RegExp(r'[,\n]'))
      .map((entry) => entry.trim())
      .where((entry) => entry.isNotEmpty)
      .toList();
  if (resolvers.isEmpty || resolvers.length > 8) return context.s('invalidDns');
  const schemes = {'https', 'https+local', 'quic+local', 'tcp', 'tcp+local'};
  final hostname = RegExp(
    r'^(?=.{1,253}$)([A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.)*[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?$',
  );
  for (final resolver in resolvers) {
    if (_isIpAddress(resolver) || hostname.hasMatch(resolver)) continue;
    final uri = Uri.tryParse(resolver);
    if (uri == null || !schemes.contains(uri.scheme) || uri.host.isEmpty) {
      return context.s('invalidDns');
    }
  }
  return null;
}

String? _validateHttps(BuildContext context, String value) {
  final uri = Uri.tryParse(value);
  return uri != null && uri.scheme == 'https' && uri.host.isNotEmpty
      ? null
      : context.s('invalidHttps');
}

String? _validateHttpUrl(BuildContext context, String value) {
  final uri = Uri.tryParse(value.trim());
  return uri != null &&
          const {'http', 'https'}.contains(uri.scheme) &&
          uri.host.isNotEmpty
      ? null
      : context.s('invalidUrl');
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

import 'package:flutter/material.dart';

import '../../core/localization/app_strings.dart';
import '../../core/platform/native_models.dart';
import '../../core/widgets/country_flag_badge.dart';
import '../vpn/app_controller.dart';
import 'server_profile_settings_screen.dart';
import '../../core/widgets/detail_page_header.dart';
import '../../core/widgets/clay_surface.dart';
import '../../core/widgets/interactive_depth.dart';

class ServerInformationScreen extends StatelessWidget {
  const ServerInformationScreen({
    required this.server,
    this.controller,
    super.key,
  });

  final ServerInfo server;
  final AppController? controller;

  @override
  Widget build(BuildContext context) => Scaffold(
    extendBodyBehindAppBar: true,
    appBar: DetailPageHeader(title: context.s('serverInformation')),
    body: ListView(
      padding: EdgeInsets.fromLTRB(
        16,
        kToolbarHeight + MediaQuery.paddingOf(context).top + 8,
        16,
        24,
      ),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CountryRemarkText(
                        remark: server.name,
                        fallbackCountry: server.country,
                        maxLines: 2,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${server.protocol} · ${server.transport} · ${server.security}',
                      ),
                    ],
                  ),
                ),
                if (server.selected) ...[
                  const SizedBox(width: 12),
                  _SelectedProfileBadge(label: context.s('selected')),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        _InfoSection(
          title: context.s('generalInformation'),
          children: [
            _InfoRow(label: context.s('name'), value: server.name),
            _InfoRow(label: context.s('protocol'), value: server.protocol),
            _InfoRow(label: context.s('transport'), value: server.transport),
            _InfoRow(label: context.s('security'), value: server.security),
            _InfoRow(
              label: context.s('country'),
              value: server.country.isEmpty
                  ? context.s('unknown')
                  : server.country,
            ),
            _InfoRow(
              label: context.s('port'),
              value: server.port > 0 ? '${server.port}' : '—',
            ),
            if (server.sni.isNotEmpty)
              _InfoRow(label: 'SNI', value: server.sni, ltr: true),
            _InfoRow(
              label: context.s('ping'),
              value: server.ping == null
                  ? context.s('neverTested')
                  : '${server.ping} ms',
            ),
            _InfoRow(
              label: context.s('status'),
              value: context.s(server.status),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (controller != null &&
            const {
              'tls',
              'reality',
            }.contains(server.security.trim().toLowerCase()) &&
            const {
              'VLESS',
              'TROJAN',
            }.contains(server.protocol.toUpperCase())) ...[
          _InfoSection(
            title: context.s('profileTlsSettings'),
            children: [
              ServerProfileSettingsScreen(
                server: server,
                controller: controller!,
                embedded: true,
              ),
            ],
          ),
          const SizedBox(height: 12),
        ],
        _InfoSection(
          title: context.s('protectedCredentials'),
          subtitle: context.s('credentialsProtected'),
          children: [
            if (server.credentialMasked.isNotEmpty)
              _InfoRow(
                label: server.credentialLabel == 'Password'
                    ? context.s('password')
                    : 'UUID',
                value: server.credentialMasked,
                ltr: true,
              ),
            if (server.realityPublicKeyMasked.isNotEmpty)
              _InfoRow(
                label: context.s('realityPublicKey'),
                value: server.realityPublicKeyMasked,
                ltr: true,
              ),
            if (server.shortIdMasked.isNotEmpty)
              _InfoRow(
                label: context.s('shortId'),
                value: server.shortIdMasked,
                ltr: true,
              ),
          ],
        ),
      ],
    ),
  );
}

class _SelectedProfileBadge extends StatefulWidget {
  const _SelectedProfileBadge({required this.label});
  final String label;
  @override
  State<_SelectedProfileBadge> createState() => _SelectedProfileBadgeState();
}

class _SelectedProfileBadgeState extends State<_SelectedProfileBadge>
    with SingleTickerProviderStateMixin {
  late final _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 460),
  );
  late final _scale = TweenSequence<double>([
    TweenSequenceItem(
      tween: Tween(
        begin: 1.0,
        end: 1.055,
      ).chain(CurveTween(curve: Curves.easeOutCubic)),
      weight: 35,
    ),
    TweenSequenceItem(
      tween: Tween(
        begin: 1.055,
        end: 1.0,
      ).chain(CurveTween(curve: Curves.easeOutCubic)),
      weight: 65,
    ),
  ]).animate(_pulse);
  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _scale,
    builder: (context, child) =>
        Transform.scale(scale: _scale.value, child: child),
    child: InteractiveDepth(
      radius: 20,
      tiltEnabled: false,
      child: ClaySurface(
        radius: 20,
        selected: true,
        child: TextButton.icon(
          onPressed: () {
            if (!MediaQuery.disableAnimationsOf(context)) {
              _pulse.forward(from: 0);
            }
          },
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            overlayColor: Colors.transparent,
          ),
          icon: const Icon(Icons.check_circle_rounded, size: 18),
          label: Text(widget.label),
        ),
      ),
    ),
  );
}

class _InfoSection extends StatelessWidget {
  const _InfoSection({
    required this.title,
    required this.children,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 3),
            Text(subtitle!, style: Theme.of(context).textTheme.bodySmall),
          ],
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    ),
  );
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value, this.ltr = false});

  final String label;
  final String value;
  final bool ltr;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(label, style: Theme.of(context).textTheme.bodySmall),
        ),
        const SizedBox(width: 16),
        Flexible(
          child: Directionality(
            textDirection: ltr ? TextDirection.ltr : Directionality.of(context),
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ),
      ],
    ),
  );
}

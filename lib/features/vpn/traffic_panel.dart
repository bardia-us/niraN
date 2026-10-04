import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/formatters.dart';
import '../../core/localization/app_strings.dart';
import '../../core/widgets/glass_surface.dart';
import 'app_controller.dart';

/// Only this small panel listens to the two-second counter stream.
class TrafficPanel extends ConsumerWidget {
  const TrafficPanel({super.key});
  int? sum(int? up, int? down) =>
      up == null && down == null ? null : (up ?? 0) + (down ?? 0);
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final traffic = ref.watch(
      appControllerProvider.select((app) => app.asData?.value.traffic),
    );
    final colors = Theme.of(context).colorScheme;
    final up = traffic?.uploadBytesPerSecond;
    final down = traffic?.downloadBytesPerSecond;
    return GlassSurface(
      style: GlassSurfaceStyle.flat,
      radius: 24,
      padding: const EdgeInsets.all(14),
      child: SingleChildScrollView(
        primary: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(
                  Icons.stacked_line_chart_rounded,
                  color: colors.primary,
                  size: 18,
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    context.s('niranTraffic'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _Rate(
                    icon: Icons.arrow_upward_rounded,
                    color: Colors.orange.shade700,
                    value: up == null ? '—' : '${formatBytes(up.round())}/s',
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _Rate(
                    icon: Icons.arrow_downward_rounded,
                    color: Colors.teal.shade600,
                    value: down == null
                        ? '—'
                        : '${formatBytes(down.round())}/s',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 9),
            _TrafficRow(
              label: context.s('configToday'),
              value: formatBytes(
                sum(traffic?.todayUpload, traffic?.todayDownload),
              ),
            ),
            _TrafficRow(
              label: context.s('configTrackedTotal'),
              value: formatBytes(
                sum(traffic?.lifetimeUpload, traffic?.lifetimeDownload),
              ),
            ),
            _TrafficRow(
              label: context.s('allConfigsToday'),
              value: formatBytes(
                sum(
                  traffic?.aggregateTodayUpload,
                  traffic?.aggregateTodayDownload,
                ),
              ),
            ),
            const SizedBox(height: 6),
            Tooltip(
              message: context.s('trafficScopeHint'),
              child: Text(
                context.s(
                  traffic?.lifetimeDownload != null &&
                          traffic?.todayDownload == null
                      ? 'trafficDayUnknownHint'
                      : traffic?.unavailableReason == 'disconnected'
                      ? 'trafficIdleHint'
                      : traffic?.available == true
                      ? 'trafficMidnightHint'
                      : 'trafficUnavailableHint',
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Rate extends StatelessWidget {
  const _Rate({required this.icon, required this.color, required this.value});
  final IconData icon;
  final Color color;
  final String value;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, size: 16, color: color),
      const SizedBox(width: 3),
      Expanded(
        child: Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.labelLarge,
        ),
      ),
    ],
  );
}

class _TrafficRow extends StatelessWidget {
  const _TrafficRow({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      children: [
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        const SizedBox(width: 6),
        Text(value, style: Theme.of(context).textTheme.labelLarge),
      ],
    ),
  );
}

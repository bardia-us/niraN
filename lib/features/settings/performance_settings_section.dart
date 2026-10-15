import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/localization/app_strings.dart';
import '../../core/widgets/glass_dialog.dart';
import '../../core/widgets/operation_error.dart';
import '../../core/widgets/settings_group.dart';
import '../vpn/app_controller.dart';

class PerformanceSettingsSection extends ConsumerStatefulWidget {
  const PerformanceSettingsSection({super.key});
  @override
  ConsumerState<PerformanceSettingsSection> createState() =>
      _PerformanceSettingsSectionState();
}

class _PerformanceSettingsSectionState
    extends ConsumerState<PerformanceSettingsSection> {
  bool _busy = false;
  Future<void> _change(bool value) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final confirmed = await showNirangDialog<bool>(
        context: context,
        builder: (context) => NirangAlertDialog(
          icon: const Icon(Icons.restart_alt_rounded),
          title: Text(context.s('performanceMode')),
          content: Text(
            context.s(
              value ? 'performanceEnableConfirm' : 'performanceDisableConfirm',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(context.s('cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(context.s('applyRestart')),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
      final controller = ref.read(appControllerProvider.notifier);
      await controller.updateSettings({'performanceMode': value});
      // Persist first. The effective boot provider intentionally stays frozen.
      await controller.restartApplication();
    } catch (error) {
      if (mounted) await showOperationError(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final requested = ref.watch(
      appControllerProvider.select(
        (app) => app.asData?.value.settings.performanceMode ?? false,
      ),
    );
    final effective = ref.watch(performanceModeProvider);
    return SettingsGroup(
      title: context.s('performanceRecovery'),
      icon: Icons.speed_rounded,
      initiallyExpanded: true,
      children: [
        SwitchListTile(
          key: const Key('performance-mode-switch'),
          value: requested,
          onChanged: _busy ? null : _change,
          secondary: IconButton(
            icon: const Icon(Icons.error_outline_rounded),
            tooltip: context.s('performanceMode'),
            onPressed: _busy
                ? null
                : () => showNirangDialog<void>(
                    context: context,
                    builder: (context) => NirangAlertDialog(
                      title: Text(context.s('performanceMode')),
                      content: Text(context.s('performanceDetails')),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: Text(context.s('close')),
                        ),
                      ],
                    ),
                  ),
          ),
          title: Text(context.s('performanceMode')),
          subtitle: Text(
            context.s(
              requested != effective
                  ? 'performanceRestartPending'
                  : 'performanceLightSummary',
            ),
          ),
        ),
      ],
    );
  }
}

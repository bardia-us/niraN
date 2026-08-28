import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';

import '../../core/diagnostics.dart';
import '../../core/localization/app_strings.dart';
import '../../core/platform/native_models.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/glass_dialog.dart';
import '../logs/logs_screen.dart';
import '../servers/servers_screen.dart';
import '../settings/settings_screen.dart';
import 'app_controller.dart';
import 'home_screen.dart';

class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  int _index = 0;
  bool _reminderQueued = false;
  bool _performancePromptQueued = false;

  @override
  void initState() {
    super.initState();
    NirangDiagnostics.currentFeature = 'home';
  }

  @override
  Widget build(BuildContext context) {
    final shellState = ref.watch(
      appControllerProvider.select(
        (value) => (
          ready: value.asData != null,
          loading: value.isLoading,
          error: value.hasError ? '${value.error}' : null,
          performanceMode:
              value.asData?.value.settings.performanceMode ?? false,
        ),
      ),
    );
    ref.listen(appControllerProvider, (_, next) {
      next.whenData((app) {
        if (!_performancePromptQueued &&
            !app.settings.performanceModePrompted) {
          _performancePromptQueued = true;
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => _showPerformanceModePrompt(),
          );
          return;
        }
        if (!_reminderQueued &&
            app.settings.performanceModePrompted &&
            app.telegramEligible &&
            !app.connection.isBusy &&
            !app.isPinging) {
          _reminderQueued = true;
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => _showTelegramReminder(),
          );
        }
      });
    });

    if (!shellState.ready && shellState.loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (!shellState.ready) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline_rounded, size: 42),
                const SizedBox(height: 12),
                Text(
                  '${context.s('operationFailed')}\n${shellState.error ?? context.s('unknown')}',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () => ref.invalidate(appControllerProvider),
                  icon: const Icon(Icons.refresh_rounded),
                  label: Text(context.s('refresh')),
                ),
              ],
            ),
          ),
        ),
      );
    }

    const pages = [
      HomeScreen(),
      ServersScreen(),
      SettingsScreen(),
      LogsScreen(),
    ];
    final theme = Theme.of(context);
    final reducedEffects = shellState.performanceMode;
    void selectDestination(int value) {
      NirangDiagnostics.currentFeature = const [
        'home',
        'servers',
        'settings',
        'logs',
      ][value];
      setState(() => _index = value);
      if (value == 3) {
        ref.read(appControllerProvider.notifier).refreshLogs();
      }
    }

    final destinations = [
      NavigationDestination(
        icon: const Icon(Icons.home_outlined),
        selectedIcon: const Icon(Icons.home_rounded),
        label: context.s('home'),
      ),
      NavigationDestination(
        icon: const Icon(Icons.dns_outlined),
        selectedIcon: const Icon(Icons.dns_rounded),
        label: context.s('servers'),
      ),
      NavigationDestination(
        icon: const Icon(Icons.settings_outlined),
        selectedIcon: const Icon(Icons.settings_rounded),
        label: context.s('settings'),
      ),
      NavigationDestination(
        icon: const Icon(Icons.article_outlined),
        selectedIcon: const Icon(Icons.article_rounded),
        label: context.s('logs'),
      ),
    ];
    final navigationBar = NavigationBar(
      backgroundColor: NirangVisualEffects.chromeColor(
        theme,
        reducedEffects: reducedEffects,
        darkAlpha: .68,
      ),
      selectedIndex: _index,
      onDestinationSelected: selectDestination,
      destinations: destinations,
    );
    final controller = ref.read(appControllerProvider.notifier);
    final connection = ref.watch(
      appControllerProvider.select(
        (value) => value.asData?.value.connection ?? const ConnectionInfo(),
      ),
    );
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyR, control: true): () {
          if (connection.isConnected && !connection.isBusy) {
            unawaited(controller.restartService());
          }
        },
        const SingleActivator(LogicalKeyboardKey.f5): () {
          unawaited(controller.refreshSubscription());
        },
      },
      child: Focus(
        autofocus: true,
        child: DecoratedBox(
          decoration: NirangVisualEffects.shellBackground(
            theme,
            reducedEffects: reducedEffects,
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final desktopLayout = constraints.maxWidth >= 900;
              final body = IndexedStack(index: _index, children: pages);
              return Scaffold(
                backgroundColor: Colors.transparent,
                appBar: AppBar(
                  backgroundColor: NirangVisualEffects.chromeColor(
                    theme,
                    reducedEffects: reducedEffects,
                    darkAlpha: .58,
                  ),
                  flexibleSpace: reducedEffects
                      ? null
                      : ClipRect(
                          child: BackdropFilter(
                            filter: ImageFilter.blur(
                              sigmaX: NirangVisualEffects.chromeBlur(theme, 12),
                              sigmaY: NirangVisualEffects.chromeBlur(theme, 12),
                            ),
                            child: const SizedBox.expand(),
                          ),
                        ),
                  title: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(7),
                        child: Image.asset(
                          'assets/branding/nirang-logo-concept.png',
                          width: 30,
                          height: 30,
                          cacheWidth: 60,
                          cacheHeight: 60,
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Text('niraN'),
                    ],
                  ),
                ),
                body: desktopLayout
                    ? Row(
                        children: [
                          NavigationRail(
                            selectedIndex: _index,
                            onDestinationSelected: selectDestination,
                            labelType: NavigationRailLabelType.all,
                            groupAlignment: -.65,
                            backgroundColor: NirangVisualEffects.chromeColor(
                              theme,
                              reducedEffects: reducedEffects,
                              darkAlpha: .56,
                            ),
                            destinations: [
                              for (final destination in destinations)
                                NavigationRailDestination(
                                  icon: destination.icon,
                                  selectedIcon: destination.selectedIcon,
                                  label: Text(destination.label),
                                ),
                            ],
                          ),
                          VerticalDivider(
                            width: 1,
                            color: theme.colorScheme.outlineVariant,
                          ),
                          Expanded(
                            child: Center(
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: 1240,
                                ),
                                child: body,
                              ),
                            ),
                          ),
                        ],
                      )
                    : body,
                bottomNavigationBar: desktopLayout
                    ? null
                    : reducedEffects
                    ? navigationBar
                    : ClipRect(
                        child: BackdropFilter(
                          filter: ImageFilter.blur(
                            sigmaX: NirangVisualEffects.chromeBlur(theme, 14),
                            sigmaY: NirangVisualEffects.chromeBlur(theme, 14),
                          ),
                          child: navigationBar,
                        ),
                      ),
              );
            },
          ),
        ),
      ),
    );
  }

  Future<void> _showPerformanceModePrompt() async {
    if (!mounted) return;
    final enable = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => NirangAlertDialog(
        icon: const Icon(Icons.bolt_rounded),
        title: Text(context.s('performanceMode')),
        content: Text(context.s('performanceModeDialogBody')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(context.s('keepFullEffects')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(context.s('enable')),
          ),
        ],
      ),
    );
    if (!mounted || enable == null) return;
    await ref.read(appControllerProvider.notifier).updateSettings({
      'performanceMode': enable,
      'performanceModePrompted': true,
    });
  }

  Future<void> _showTelegramReminder() async {
    if (!mounted) return;
    var never = false;
    final decision = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => NirangAlertDialog(
          icon: const Icon(Icons.campaign_outlined),
          title: Text(context.s('joinTelegramTitle')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(context.s('joinTelegramBody')),
              CheckboxListTile(
                value: never,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                onChanged: (value) =>
                    setDialogState(() => never = value ?? false),
                title: Text(context.s('dontShowAgain')),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, 'later'),
              child: Text(context.s('later')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, 'join'),
              child: Text(context.s('joinTelegram')),
            ),
          ],
        ),
      ),
    );
    if (!mounted || decision == null) return;
    final controller = ref.read(appControllerProvider.notifier);
    if (decision == 'join') {
      await controller.openTelegram();
    }
    await controller.recordTelegramDecision(never ? 'never' : 'later');
  }
}

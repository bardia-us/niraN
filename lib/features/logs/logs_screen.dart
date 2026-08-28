import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';

import '../../core/formatters.dart';
import '../../core/localization/app_strings.dart';
import '../../core/widgets/glass_dialog.dart';
import '../../core/platform/native_models.dart';
import '../../core/theme/app_theme.dart';
import '../vpn/app_controller.dart';

class LogsScreen extends ConsumerStatefulWidget {
  const LogsScreen({super.key});

  @override
  ConsumerState<LogsScreen> createState() => _LogsScreenState();
}

class _LogsScreenState extends ConsumerState<LogsScreen> {
  final _scrollController = ScrollController();
  bool _atBottom = true;
  int? _selectedIndex;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(() {
      if (!_scrollController.hasClients) return;
      _atBottom =
          _scrollController.position.maxScrollExtent -
              _scrollController.offset <
          32;
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final logs = ref.watch(
      appControllerProvider.select(
        (value) => value.asData?.value.logs ?? const <LogEntry>[],
      ),
    );
    ref.listen(
      appControllerProvider.select(
        (value) => value.asData?.value.logs.length ?? 0,
      ),
      (previous, next) {
        if (previous == next || !_atBottom) return;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || !_scrollController.hasClients) return;
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
          );
        });
      },
    );
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 8, 8),
          child: Row(
            children: [
              Text(
                context.s('logs'),
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const Spacer(),
              TextButton.icon(
                onPressed:
                    _selectedIndex == null || _selectedIndex! >= logs.length
                    ? null
                    : () async {
                        final log = logs[_selectedIndex!];
                        await Clipboard.setData(
                          ClipboardData(
                            text:
                                '${formatDateTime(log.time.millisecondsSinceEpoch)} '
                                '[${log.level.toUpperCase()}] ${log.message}',
                          ),
                        );
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(context.s('logCopied'))),
                          );
                        }
                      },
                icon: const Icon(Icons.copy_rounded, size: 17),
                label: Text(context.s('copy')),
              ),
              IconButton(
                tooltip: context.s('refresh'),
                onPressed: ref.read(appControllerProvider.notifier).refreshLogs,
                icon: const Icon(Icons.refresh_rounded),
              ),
              IconButton(
                tooltip: context.s('clear'),
                onPressed: logs.isEmpty
                    ? null
                    : () => _confirmClear(context, ref),
                icon: const Icon(Icons.delete_outline_rounded),
              ),
            ],
          ),
        ),
        const Divider(),
        Expanded(
          child: logs.isEmpty
              ? Center(child: Text(context.s('noLogs')))
              : ListView.separated(
                  controller: _scrollController,
                  cacheExtent: 420,
                  itemCount: logs.length,
                  separatorBuilder: (_, _) => const Divider(indent: 50),
                  itemBuilder: (context, index) {
                    final log = logs[index];
                    final color = switch (log.level) {
                      'error' => Theme.of(context).colorScheme.error,
                      'warning' => context.semanticColors.warning,
                      _ => Theme.of(context).colorScheme.primary,
                    };
                    return ListTile(
                      selected: _selectedIndex == index,
                      selectedTileColor: Theme.of(
                        context,
                      ).colorScheme.primaryContainer.withValues(alpha: .25),
                      onTap: () => setState(() => _selectedIndex = index),
                      leading: Icon(Icons.circle, size: 9, color: color),
                      title: Text(
                        log.message,
                        maxLines: 5,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        formatDateTime(log.time.millisecondsSinceEpoch),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Future<void> _confirmClear(BuildContext context, WidgetRef ref) async {
    final clear = await showDialog<bool>(
      context: context,
      builder: (context) => NirangAlertDialog(
        title: Text(context.s('clearLogs')),
        content: Text(context.s('clearLogsBody')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.s('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.s('clear')),
          ),
        ],
      ),
    );
    if (clear == true) {
      try {
        await ref.read(appControllerProvider.notifier).clearLogs();
      } catch (error) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${context.s('operationFailed')}: $error')),
          );
        }
      }
    }
  }
}

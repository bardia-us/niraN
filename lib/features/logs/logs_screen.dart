import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';

import '../../core/formatters.dart';
import '../../core/localization/app_strings.dart';
import '../../core/widgets/glass_dialog.dart';
import '../../core/widgets/simple_frosted_surface.dart';
import '../../core/widgets/niran_toast.dart';
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
  bool _hasSelection = false;
  bool _pointerDown = false;
  List<LogEntry> _displayedLogs = const [];

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

  void _resumePendingLogs() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _pointerDown || _hasSelection) return;
      setState(() {});
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted ||
            !_atBottom ||
            _pointerDown ||
            _hasSelection ||
            !_scrollController.hasClients) {
          return;
        }
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
        );
      });
    });
  }

  void _releasePointer() {
    _pointerDown = false;
    _resumePendingLogs();
  }

  @override
  Widget build(BuildContext context) {
    final incoming = ref.watch(
      appControllerProvider.select(
        (value) => value.asData?.value.logs ?? const <LogEntry>[],
      ),
    );
    // A growing log must not invalidate a selection while the user copies it.
    if (!_hasSelection && !_pointerDown) _displayedLogs = incoming;
    final logs = _displayedLogs;
    ref.listen(
      appControllerProvider.select(
        (value) => value.asData?.value.logs.length ?? 0,
      ),
      (previous, next) {
        if (previous == next || !_atBottom || _hasSelection || _pointerDown) {
          return;
        }
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
        SimpleFrostedSurface(
          radius: 0,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(26, 14, 20, 18),
            child: Row(
              children: [
                Text(
                  context.s('logs'),
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: -.4,
                  ),
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
                            showNiranToast(context, context.s('logCopied'));
                          }
                        },
                  icon: const Icon(Icons.copy_rounded, size: 17),
                  label: Text(context.s('copy')),
                ),
                IconButton(
                  tooltip: context.s('refresh'),
                  onPressed: ref
                      .read(appControllerProvider.notifier)
                      .refreshLogs,
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
        ),
        const Divider(),
        Expanded(
          child: logs.isEmpty
              ? Center(child: Text(context.s('noLogs')))
              : ClipRect(
                  child: Listener(
                    onPointerDown: (_) => _pointerDown = true,
                    onPointerUp: (_) => _releasePointer(),
                    onPointerCancel: (_) => _releasePointer(),
                    child: SelectionArea(
                      onSelectionChanged: (selection) {
                        final selected =
                            selection?.plainText.isNotEmpty ?? false;
                        if (selected != _hasSelection) {
                          setState(() => _hasSelection = selected);
                          if (!selected) _resumePendingLogs();
                        }
                      },
                      contextMenuBuilder: (context, region) =>
                          AdaptiveTextSelectionToolbar.buttonItems(
                            anchors: region.contextMenuAnchors,
                            buttonItems: region.contextMenuButtonItems,
                          ),
                      child: ListView.separated(
                        controller: _scrollController,
                        scrollCacheExtent: const ScrollCacheExtent.pixels(420),
                        itemCount: logs.length,
                        separatorBuilder: (_, _) => const Divider(indent: 50),
                        itemBuilder: (context, index) {
                          final log = logs[index];
                          final color = switch (log.level) {
                            'error' => Theme.of(context).colorScheme.error,
                            'warning' => context.semanticColors.warning,
                            _ => Theme.of(context).colorScheme.primary,
                          };
                          return Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 2,
                            ),
                            child: Material(
                              type: MaterialType.transparency,
                              borderRadius: BorderRadius.circular(10),
                              clipBehavior: Clip.antiAlias,
                              child: ListTile(
                                selected: _selectedIndex == index,
                                selectedTileColor: Theme.of(context)
                                    .colorScheme
                                    .primaryContainer
                                    .withValues(alpha: .25),
                                onTap: () =>
                                    setState(() => _selectedIndex = index),
                                leading: Icon(
                                  Icons.circle,
                                  size: 9,
                                  color: color,
                                ),
                                title: Text(
                                  log.message,
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(height: 1.45),
                                ),
                                subtitle: Text(
                                  formatDateTime(
                                    log.time.millisecondsSinceEpoch,
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
      ],
    );
  }

  Future<void> _confirmClear(BuildContext context, WidgetRef ref) async {
    final clear = await showNirangDialog<bool>(
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

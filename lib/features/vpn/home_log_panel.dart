import 'package:flutter/material.dart';

import '../../core/localization/app_strings.dart';
import '../../core/platform/native_models.dart';
import '../../core/widgets/simple_frosted_surface.dart';

class HomeLogPanel extends StatefulWidget {
  const HomeLogPanel({required this.logs, this.editing = false, super.key});

  final List<LogEntry> logs;
  final bool editing;

  @override
  State<HomeLogPanel> createState() => _HomeLogPanelState();
}

class _HomeLogPanelState extends State<HomeLogPanel> {
  final _scroll = ScrollController();
  bool _autoScroll = true;
  bool _pointerDown = false;
  bool _hasSelection = false;
  bool _followPending = false;
  LogEntry? _lastLog;
  int _logCount = 0;
  List<LogEntry> _visibleLogs = const [];
  bool _logsPending = false;

  @override
  void initState() {
    super.initState();
    _rememberLogs();
    _refreshVisibleLogs();
    _followLatest();
  }

  void _rememberLogs() {
    _logCount = widget.logs.length;
    _lastLog = widget.logs.lastOrNull;
  }

  @override
  void didUpdateWidget(covariant HomeLogPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    final changed =
        _logCount != widget.logs.length ||
        !identical(_lastLog, widget.logs.lastOrNull);
    _rememberLogs();
    if (changed) {
      if (_pointerDown || _hasSelection) {
        // Keep the selected offsets attached to the same log text even when
        // the latest-hundred window advances while logs are arriving.
        _logsPending = true;
      } else {
        _refreshVisibleLogs();
      }
      if (_autoScroll) _followLatest();
    }
  }

  void _refreshVisibleLogs() {
    _visibleLogs = widget.logs
        .skip((widget.logs.length - 100).clamp(0, widget.logs.length))
        .toList(growable: false);
    _logsPending = false;
  }

  void _releaseSelection() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _pointerDown || _hasSelection) return;
      if (_logsPending) setState(_refreshVisibleLogs);
      if (_followPending) _followLatest();
    });
  }

  void _followLatest() {
    _followPending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          !_autoScroll ||
          !_followPending ||
          _pointerDown ||
          _hasSelection ||
          !_scroll.hasClients) {
        return;
      }
      _followPending = false;
      _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final spans = <InlineSpan>[];
    for (final log in _visibleLogs) {
      if (spans.isNotEmpty) spans.add(const TextSpan(text: '\n'));
      final time = [
        log.time.hour,
        log.time.minute,
        log.time.second,
      ].map((part) => part.toString().padLeft(2, '0')).join(':');
      spans.add(TextSpan(text: '$time  ', style: theme.textTheme.labelSmall));
      spans.add(
        TextSpan(
          text: log.message,
          style: theme.textTheme.bodySmall?.copyWith(
            color: log.level == 'error' ? colors.error : null,
          ),
        ),
      );
    }
    return SimpleFrostedSurface(
      radius: 24,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(14, 8, widget.editing ? 36 : 8, 6),
            child: Row(
              textDirection: TextDirection.ltr,
              children: [
                Icon(Icons.notes_rounded, size: 18, color: colors.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    context.s('recentLogs'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                IconButton(
                  key: const Key('home-log-autoscroll'),
                  tooltip: context.s(
                    _autoScroll ? 'autoScrollOn' : 'autoScrollOff',
                  ),
                  isSelected: _autoScroll,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(
                    width: 28,
                    height: 28,
                  ),
                  iconSize: 17,
                  style: IconButton.styleFrom(
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  color: _autoScroll ? colors.primary : colors.onSurfaceVariant,
                  icon: const Icon(Icons.vertical_align_bottom_rounded),
                  onPressed: () {
                    setState(() => _autoScroll = !_autoScroll);
                    if (_autoScroll) _followLatest();
                  },
                ),
              ],
            ),
          ),
          Expanded(
            child: spans.isEmpty
                ? Center(
                    child: Text(
                      context.s('noLogs'),
                      style: theme.textTheme.bodySmall,
                    ),
                  )
                : Listener(
                    onPointerDown: (_) => _pointerDown = true,
                    onPointerUp: (_) {
                      _pointerDown = false;
                      _releaseSelection();
                    },
                    onPointerCancel: (_) {
                      _pointerDown = false;
                      _releaseSelection();
                    },
                    child: SelectionArea(
                      onSelectionChanged: (selection) {
                        _hasSelection =
                            selection?.plainText.isNotEmpty ?? false;
                        if (!_hasSelection) _releaseSelection();
                      },
                      contextMenuBuilder: (context, region) =>
                          AdaptiveTextSelectionToolbar.buttonItems(
                            anchors: region.contextMenuAnchors,
                            buttonItems: [
                              for (final item in region.contextMenuButtonItems)
                                item.type == ContextMenuButtonType.copy
                                    ? item.copyWith(label: context.s('copy'))
                                    : item,
                            ],
                          ),
                      child: Scrollbar(
                        controller: _scroll,
                        child: SingleChildScrollView(
                          key: const Key('home-log-scroll'),
                          controller: _scroll,
                          padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                          child: Text.rich(
                            TextSpan(children: spans),
                            key: const Key('home-log-text'),
                            textDirection: TextDirection.ltr,
                            style: theme.textTheme.bodySmall?.copyWith(
                              height: 1.6,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

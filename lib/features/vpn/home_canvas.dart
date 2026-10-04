import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import '../../core/localization/app_strings.dart';
import 'home_layout.dart';

enum _ResizeAxis { both, width, height }

/// A bounded, physical-coordinate canvas. Drafts never mutate settings here.
class HomeCanvas extends StatefulWidget {
  const HomeCanvas({
    super.key,
    required this.layout,
    required this.editing,
    required this.logsVisible,
    required this.children,
    required this.labels,
    required this.onChanged,
    required this.onRemoveLogs,
    this.controlsOnly = false,
    this.heading,
  });
  final HomeLayout layout;
  final bool editing;
  final bool logsVisible;
  final Map<String, Widget> children;
  final Map<String, String> labels;
  final ValueChanged<HomeLayout> onChanged;
  final VoidCallback onRemoveLogs;
  final bool controlsOnly;
  final Widget? heading;
  @override
  State<HomeCanvas> createState() => _HomeCanvasState();
}

class _HomeCanvasState extends State<HomeCanvas>
    with SingleTickerProviderStateMixin {
  late final _wiggle = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 440),
  );
  String? _active;
  final _stationaryBackdrop = BackdropKey();
  final _dragBackdrop = BackdropKey();
  bool _resizing = false;
  _ResizeAxis _resizeAxis = _ResizeAxis.both;
  double? _guideX;
  double? _guideY;
  Offset _delta = Offset.zero;
  HomeLayout? _candidate;
  Size _size = Size.zero;
  bool _viewportChanged = false;
  int get _rows =>
      widget.controlsOnly ? HomeLayout.controlRows : HomeLayout.rows;
  List<String> get _ids =>
      widget.controlsOnly ? HomeLayout.controlIds : HomeLayout.surfaceIds;

  void _sync() {
    if (widget.editing && !MediaQuery.disableAnimationsOf(context)) {
      if (!_wiggle.isAnimating) _wiggle.repeat(reverse: true);
    } else {
      _wiggle.stop();
      _wiggle.value = .5;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(HomeCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
    if (!widget.editing) {
      _active = null;
      _candidate = null;
      _delta = Offset.zero;
      _guideX = null;
      _guideY = null;
    }
  }

  @override
  void dispose() {
    _wiggle.dispose();
    super.dispose();
  }

  void _start(
    String id, {
    bool resize = false,
    _ResizeAxis axis = _ResizeAxis.both,
  }) {
    setState(() {
      _active = id;
      _resizing = resize;
      _resizeAxis = axis;
      _delta = Offset.zero;
      _candidate = widget.layout;
      _guideX = null;
      _guideY = null;
    });
  }

  void _move(DragUpdateDetails details) {
    final id = _active;
    if (id == null || _size.isEmpty) return;
    setState(() {
      _delta += _resizing && _resizeAxis == _ResizeAxis.width
          ? Offset(details.delta.dx, 0)
          : _resizing && _resizeAxis == _ResizeAxis.height
          ? Offset(0, details.delta.dy)
          : details.delta;
      _guideX = null;
      _guideY = null;
      final original = widget.layout[id];
      final rawDx = _delta.dx * HomeLayout.columns / _size.width;
      final rawDy = _delta.dy * _rows / _size.height;
      final dx = rawDx.round();
      final dy = rawDy.round();
      if (_resizing) {
        _candidate = widget.layout.resize(
          id,
          original.width + dx,
          original.height + dy,
          logsVisible: widget.logsVisible,
        );
      } else {
        final x = (original.x + dx).clamp(
          0,
          HomeLayout.columns - original.width,
        );
        final y = (original.y + dy).clamp(0, _rows - original.height);
        _candidate = widget.layout.move(
          id,
          x,
          y,
          logsVisible: widget.logsVisible,
        );
        // A card drop snaps to the collided card's anchor, independent of the
        // pointer's grab offset. Invalid/multi-card swaps remain rejected.
        final intended = original.copyWith(x: x, y: y);
        final hits = widget.layout.placements.entries
            .where(
              (entry) =>
                  entry.key != id &&
                  _ids.contains(entry.key) &&
                  (widget.logsVisible || entry.key != 'logs') &&
                  intended.overlaps(entry.value),
            )
            .toList();
        if (hits.length == 1) {
          final hit = hits.single.value;
          _candidate =
              widget.layout.move(
                id,
                hit.x,
                hit.y,
                logsVisible: widget.logsVisible,
              ) ??
              _candidate;
        } else if (hits.isEmpty && !HardwareKeyboard.instance.isAltPressed) {
          _alignMove(
            id,
            x,
            y,
            (original.x + rawDx)
                .clamp(0, HomeLayout.columns - original.width)
                .toDouble(),
            (original.y + rawDy).clamp(0, _rows - original.height).toDouble(),
          );
        }
      }
    });
  }

  void _end({bool cancelled = false}) {
    final accepted = cancelled ? null : _candidate;
    setState(() {
      _active = null;
      _candidate = null;
      _delta = Offset.zero;
      _guideX = null;
      _guideY = null;
    });
    if (accepted != null) widget.onChanged(accepted);
  }

  /// Assist within eight logical pixels, not a percentage of the viewport.
  /// Only a valid placement snaps; Alt bypasses assistance for fine placement.
  void _alignMove(String id, int x, int y, double rawX, double rawY) {
    final item = widget.layout[id];
    final peers = _ids.where(
      (other) => other != id && (widget.logsVisible || other != 'logs'),
    );
    final xs = <({int value, double guide})>[];
    final ys = <({int value, double guide})>[];
    void offer(
      List<({int value, double guide})> values,
      int value,
      double intended,
      double cellSize,
      int maximum,
      double guide,
    ) {
      if (value >= 0 &&
          value <= maximum &&
          (value - intended).abs() * cellSize <= 8 &&
          !values.any((entry) => entry.value == value)) {
        values.add((value: value, guide: guide));
      }
    }

    final cellW = _size.width / HomeLayout.columns;
    final cellH = _size.height / _rows;
    for (final other in peers) {
      final peer = widget.layout[other];
      final rect = _rect(peer);
      offer(
        xs,
        peer.x,
        rawX,
        cellW,
        HomeLayout.columns - item.width,
        rect.left,
      );
      offer(
        xs,
        peer.right - item.width,
        rawX,
        cellW,
        HomeLayout.columns - item.width,
        rect.right,
      );
      offer(
        xs,
        (peer.x + (peer.width - item.width) / 2).round(),
        rawX,
        cellW,
        HomeLayout.columns - item.width,
        rect.center.dx,
      );
      offer(ys, peer.y, rawY, cellH, _rows - item.height, rect.top);
      offer(
        ys,
        peer.bottom - item.height,
        rawY,
        cellH,
        _rows - item.height,
        rect.bottom,
      );
      offer(
        ys,
        (peer.y + (peer.height - item.height) / 2).round(),
        rawY,
        cellH,
        _rows - item.height,
        rect.center.dy,
      );
    }
    xs.sort((a, b) => (a.value - rawX).abs().compareTo((b.value - rawX).abs()));
    ys.sort((a, b) => (a.value - rawY).abs().compareTo((b.value - rawY).abs()));
    // Try both axes, then each axis alone. Rejected alignment must never swap
    // an otherwise non-overlapping card or turn a valid free move invalid.
    for (final sx in [...xs, (value: x, guide: double.nan)]) {
      for (final sy in [...ys, (value: y, guide: double.nan)]) {
        final aligned = item.copyWith(x: sx.value, y: sy.value);
        if (peers.any((other) => aligned.overlaps(widget.layout[other]))) {
          continue;
        }
        final candidate = widget.layout.move(
          id,
          sx.value,
          sy.value,
          logsVisible: widget.logsVisible,
        );
        if (candidate == null) continue;
        _candidate = candidate;
        _guideX = sx.guide.isNaN ? null : sx.guide;
        _guideY = sy.guide.isNaN ? null : sy.guide;
        return;
      }
    }
  }

  Rect _rect(HomePlacement item) => Rect.fromLTWH(
    item.x * _size.width / HomeLayout.columns,
    item.y * _size.height / _rows,
    item.width * _size.width / HomeLayout.columns,
    item.height * _size.height / _rows,
  ).deflate(4);

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      _viewportChanged = _size != constraints.biggest;
      _size = constraints.biggest;
      final colors = Theme.of(context).colorScheme;
      final ids = _ids
          .where((id) => widget.logsVisible || id != 'logs')
          .toList();
      if (_active != null) {
        ids.remove(_active);
        ids.add(_active!);
      }
      return Stack(
        key: Key(widget.controlsOnly ? 'home-control-canvas' : 'home-canvas'),
        clipBehavior: Clip.hardEdge,
        children: [
          if (widget.heading != null)
            Positioned(
              left: 4,
              top: 4,
              width: _size.width * 80 / HomeLayout.columns - 8,
              height: _size.height * 16 / _rows - 8,
              child: widget.heading!,
            ),
          if (widget.editing)
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _CanvasGrid(
                    colors.primary.withValues(alpha: .09),
                    rows: _rows,
                  ),
                ),
              ),
            ),
          if (_active != null && _candidate != null)
            Positioned.fromRect(
              rect: _rect(_candidate![_active!]),
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: colors.primary.withValues(alpha: .10),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: colors.primary.withValues(alpha: .6),
                      width: 1.2,
                    ),
                  ),
                ),
              ),
            ),
          for (final id in ids) _tile(context, id),
          if (_guideX != null)
            Positioned(
              left: _guideX,
              top: 0,
              bottom: 0,
              width: 1,
              child: IgnorePointer(
                child: ColoredBox(
                  key: const Key('home-align-vertical'),
                  color: colors.primary.withValues(alpha: .65),
                ),
              ),
            ),
          if (_guideY != null)
            Positioned(
              top: _guideY,
              left: 0,
              right: 0,
              height: 1,
              child: IgnorePointer(
                child: ColoredBox(
                  key: const Key('home-align-horizontal'),
                  color: colors.primary.withValues(alpha: .65),
                ),
              ),
            ),
        ],
      );
    },
  );

  Widget _axisHandle(BuildContext context, String id, _ResizeAxis axis) {
    final horizontal = axis == _ResizeAxis.width;
    return Semantics(
      label: '${context.s('resizeHomeCard')}: ${widget.labels[id]}',
      child: MouseRegion(
        cursor: horizontal
            ? SystemMouseCursors.resizeLeftRight
            : SystemMouseCursors.resizeUpDown,
        child: GestureDetector(
          dragStartBehavior: DragStartBehavior.down,
          behavior: HitTestBehavior.opaque,
          onPanStart: (_) => _start(id, resize: true, axis: axis),
          onPanUpdate: _move,
          onPanEnd: (_) => _end(),
          onPanCancel: () => _end(cancelled: true),
          child: SizedBox(
            key: Key('resize-${horizontal ? 'width' : 'height'}-home-$id'),
            width: horizontal ? 18 : 30,
            height: horizontal ? 30 : 18,
            child: Center(
              child: Container(
                width: horizontal ? 3 : 18,
                height: horizontal ? 18 : 3,
                decoration: BoxDecoration(
                  color: Theme.of(
                    context,
                  ).colorScheme.primary.withValues(alpha: .45),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _tile(BuildContext context, String id) {
    final originalRect = _rect(
      (id == _active ? widget.layout : _candidate ?? widget.layout)[id],
    );
    var rect = originalRect;
    final active = id == _active;
    if (active) {
      if (_resizing) {
        rect = Rect.fromLTWH(
          rect.left,
          rect.top,
          _resizeAxis == _ResizeAxis.height
              ? rect.width
              : (rect.width + _delta.dx).clamp(80, _size.width - rect.left),
          _resizeAxis == _ResizeAxis.width
              ? rect.height
              : (rect.height + _delta.dy).clamp(36, _size.height - rect.top),
        );
      } else {
        final aligned = _candidate == null ? null : _rect(_candidate![id]);
        rect = Rect.fromLTWH(
          _guideX != null && aligned != null
              ? aligned.left
              : (rect.left + _delta.dx).clamp(4, _size.width - rect.width - 4),
          _guideY != null && aligned != null
              ? aligned.top
              : (rect.top + _delta.dy).clamp(4, _size.height - rect.height - 4),
          rect.width,
          rect.height,
        );
      }
    }
    final colors = Theme.of(context).colorScheme;
    // Merge non-overlapping tile backdrops into one engine pass. The active
    // drag has its own input because it may cover another card temporarily.
    final content = BackdropGroup(
      backdropKey: active ? _dragBackdrop : _stationaryBackdrop,
      child: RepaintBoundary(child: widget.children[id]!),
    );
    return AnimatedPositioned.fromRect(
      key: ValueKey('canvas-position-$id'),
      rect: rect,
      duration:
          active || _viewportChanged || MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      child: SizedBox.expand(
        key: Key('home-tile-$id'),
        child: AnimatedBuilder(
          animation: _wiggle,
          child: Stack(
            fit: StackFit.expand,
            children: [
              GestureDetector(
                dragStartBehavior: DragStartBehavior.down,
                behavior: HitTestBehavior.opaque,
                onPanStart: widget.editing ? (_) => _start(id) : null,
                onPanUpdate: widget.editing ? _move : null,
                onPanEnd: widget.editing ? (_) => _end() : null,
                onPanCancel: widget.editing
                    ? () => _end(cancelled: true)
                    : null,
                child: MouseRegion(
                  cursor: widget.editing
                      ? (active
                            ? SystemMouseCursors.grabbing
                            : SystemMouseCursors.grab)
                      : MouseCursor.defer,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(24),
                      border: widget.editing && active
                          ? Border.all(
                              color: active && _candidate == null
                                  ? colors.error
                                  : colors.primary.withValues(alpha: .55),
                              width: 1.2,
                            )
                          : null,
                    ),
                    child: IgnorePointer(
                      ignoring: widget.editing && id != 'status',
                      child: content,
                    ),
                  ),
                ),
              ),
              if (widget.editing && id == 'logs')
                Positioned(
                  right: 3,
                  top: 3,
                  child: Tooltip(
                    message: context.s('removeFromHome'),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Color.alphaBlend(
                              colors.error.withValues(alpha: .06),
                              colors.surface,
                            ),
                            Color.alphaBlend(
                              colors.error.withValues(alpha: .16),
                              colors.surface,
                            ),
                          ],
                        ),
                        border: Border.all(
                          color: colors.error.withValues(alpha: .24),
                          width: .7,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: colors.shadow.withValues(alpha: .12),
                            blurRadius: 5,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: IconButton(
                        key: const Key('remove-home-logs'),
                        visualDensity: VisualDensity.compact,
                        constraints: const BoxConstraints.tightFor(
                          width: 28,
                          height: 28,
                        ),
                        padding: EdgeInsets.zero,
                        onPressed: widget.onRemoveLogs,
                        icon: Icon(
                          Icons.close_rounded,
                          size: 18,
                          color: colors.error,
                        ),
                      ),
                    ),
                  ),
                ),
              if (widget.editing)
                Positioned(
                  right: 0,
                  top: (rect.height - 30) / 2,
                  child: _axisHandle(context, id, _ResizeAxis.width),
                ),
              if (widget.editing)
                Positioned(
                  bottom: 0,
                  left: (rect.width - 30) / 2,
                  child: _axisHandle(context, id, _ResizeAxis.height),
                ),
              if (widget.editing)
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Semantics(
                    label:
                        '${context.s('resizeHomeCard')}: ${widget.labels[id]}',
                    child: MouseRegion(
                      cursor: SystemMouseCursors.resizeUpLeftDownRight,
                      child: GestureDetector(
                        dragStartBehavior: DragStartBehavior.down,
                        behavior: HitTestBehavior.opaque,
                        onPanStart: (_) => _start(id, resize: true),
                        onPanUpdate: _move,
                        onPanEnd: (_) => _end(),
                        onPanCancel: () => _end(cancelled: true),
                        child: SizedBox(
                          key: Key('resize-home-$id'),
                          width: (rect.width / 3).clamp(1, 26),
                          height: (rect.height / 3).clamp(1, 26),
                          child: Align(
                            alignment: Alignment.bottomRight,
                            child: Icon(
                              Icons.south_east_rounded,
                              size: 15,
                              color: colors.primary,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          // Launcher-style, restrained tilt instead of the distracting lateral
          // sway. One shared ticker; no blur is animated or read back here.
          builder: (context, child) => Transform.rotate(
            angle: widget.editing && !active
                ? (_wiggle.value - .5) * (widget.controlsOnly ? .016 : .003)
                : 0,
            child: child,
          ),
        ),
      ),
    );
  }
}

class _CanvasGrid extends CustomPainter {
  const _CanvasGrid(this.color, {required this.rows});
  final Color color;
  final int rows;
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    for (var x = 4; x < HomeLayout.columns; x += 4) {
      for (var y = 4; y < rows; y += 4) {
        canvas.drawCircle(
          Offset(x * size.width / HomeLayout.columns, y * size.height / rows),
          .8,
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_CanvasGrid oldDelegate) =>
      oldDelegate.color != color || oldDelegate.rows != rows;
}

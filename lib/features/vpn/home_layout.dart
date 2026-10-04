import 'dart:convert';

import '../../core/platform/native_models.dart';

/// Immutable grid bounds, measured in cells rather than viewport pixels.
final class HomePlacement {
  const HomePlacement({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  final int x;
  final int y;
  final int width;
  final int height;
  int get right => x + width;
  int get bottom => y + height;

  HomePlacement copyWith({int? x, int? y, int? width, int? height}) =>
      HomePlacement(
        x: x ?? this.x,
        y: y ?? this.y,
        width: width ?? this.width,
        height: height ?? this.height,
      );

  bool overlaps(HomePlacement other) =>
      x < other.right &&
      right > other.x &&
      y < other.bottom &&
      bottom > other.y;

  Map<String, int> toMap() => {
    'x': x,
    'y': y,
    'width': width,
    'height': height,
  };
}

/// One atomic Home draft. Rejected edits return null and never mutate it.
final class HomeLayout {
  HomeLayout._(Map<String, HomePlacement> placements)
    : placements = Map.unmodifiable(placements);

  // Fine-grained positions, with a separate local coordinate space for the
  // connection controls. A control can never leave its owning status card.
  static const columns = 120;
  static const rows = 120;
  static const controlRows = 32;
  // A fixed heading is part of the control board, not a separate row below it.
  static const _heading = HomePlacement(x: 0, y: 0, width: 80, height: 16);
  static const surfaceIds = ['status', 'subscription', 'traffic', 'logs'];
  static const controlIds = ['systemProxy', 'clearProxy', 'tun', 'restart'];
  static const itemIds = [
    'status',
    'subscription',
    'traffic',
    'logs',
    'systemProxy',
    'clearProxy',
    'tun',
    'restart',
  ];
  static const _minimums = <String, (int, int)>{
    'status': (52, 66),
    'subscription': (28, 22),
    'traffic': (28, 36),
    'logs': (32, 18),
    'systemProxy': (28, 10),
    'clearProxy': (28, 10),
    'tun': (28, 10),
    'restart': (28, 10),
  };

  final Map<String, HomePlacement> placements;
  HomePlacement operator [](String id) => placements[id]!;

  factory HomeLayout.defaults() => HomeLayout._({
    'status': const HomePlacement(x: 0, y: 0, width: 76, height: 84),
    'subscription': const HomePlacement(x: 78, y: 0, width: 42, height: 28),
    'traffic': const HomePlacement(x: 78, y: 32, width: 42, height: 44),
    'logs': const HomePlacement(x: 0, y: 88, width: 76, height: 32),
    'systemProxy': const HomePlacement(x: 0, y: 18, width: 37, height: 14),
    'clearProxy': const HomePlacement(x: 40, y: 18, width: 37, height: 14),
    'tun': const HomePlacement(x: 80, y: 18, width: 40, height: 14),
    'restart': const HomePlacement(x: 82, y: 0, width: 38, height: 14),
  });

  factory HomeLayout.fromSettings(NativeSettings settings) {
    final saved = tryDecode(
      settings.homeLayout,
      logsVisible: settings.showRecentLogsOnHome,
    );
    if (saved != null) return saved;
    final migrated = {...HomeLayout.defaults().placements};
    if (settings.homeUsageSide == 'left') {
      for (final id in const ['subscription', 'traffic']) {
        migrated[id] = migrated[id]!.copyWith(x: 0);
      }
      for (final id in const ['status', 'logs']) {
        migrated[id] = migrated[id]!.copyWith(x: 44);
      }
    }
    final order = settings.orderedHomeControls;
    for (var i = 0; i < order.length; i++) {
      migrated[order[i]] = migrated[order[i]]!.copyWith(
        x: i * 40,
        width: i == 2 ? 40 : 37,
      );
    }
    return HomeLayout._(migrated);
  }

  static HomeLayout? tryDecode(String encoded, {bool logsVisible = true}) {
    try {
      final data = jsonDecode(encoded);
      if (data is! Map || !const [1, 2, 3, 4].contains(data['version'])) {
        return null;
      }
      final saved = data['placements'];
      if (saved is! Map || saved.length != itemIds.length) return null;
      final placements = <String, HomePlacement>{};
      for (final id in itemIds) {
        final bounds = saved[id];
        if (bounds is! Map ||
            !const [
              'x',
              'y',
              'width',
              'height',
            ].every((key) => bounds[key] is int)) {
          return null;
        }
        placements[id] = HomePlacement(
          x: bounds['x'] as int,
          y: bounds['y'] as int,
          width: bounds['width'] as int,
          height: bounds['height'] as int,
        );
      }
      final layout = HomeLayout._(placements);
      if (data['version'] == 1) {
        // Validate the old 24-cell, all-independent layout before migrating.
        // The larger connection card owns its controls now; incompatible old
        // outer layouts return to standard rather than silently overlapping.
        if (placements.values.any(
          (p) =>
              p.x < 0 ||
              p.y < 0 ||
              p.width < 1 ||
              p.height < 1 ||
              p.right > 24 ||
              p.bottom > 24,
        )) {
          return null;
        }
        final active = itemIds
            .where((id) => logsVisible || id != 'logs')
            .toList();
        for (var i = 0; i < active.length; i++) {
          for (var j = i + 1; j < active.length; j++) {
            if (layout[active[i]].overlaps(layout[active[j]])) return null;
          }
        }
        final migrated = {...HomeLayout.defaults().placements};
        for (final id in surfaceIds) {
          final p = layout[id];
          migrated[id] = HomePlacement(
            x: p.x * 5,
            y: p.y * 5,
            width: p.width * 5,
            height: p.height * 5,
          );
        }
        final candidate = HomeLayout._(migrated);
        return candidate._isValid(logsVisible: logsVisible)
            ? candidate
            : HomeLayout.defaults();
      }
      if (!layout._isValid(
        logsVisible: logsVisible,
        reserveHeading: data['version'] == 4,
      )) {
        return null;
      }
      if (data['version'] != 4 &&
          controlIds.any((id) => layout[id].overlaps(_heading))) {
        // Old controls used the same coordinates below the heading. Preserve
        // outer custom cards but migrate incompatible inner controls together.
        for (final id in controlIds) {
          placements[id] = HomeLayout.defaults()[id];
        }
      }
      if (data['version'] == 2) {
        // Upgrade only the old factory surface arrangement, never a manual
        // resize/move. v3 makes this a one-time migration rather than undoing
        // a later deliberate resize back to the old width.
        final standard = HomeLayout.defaults();
        final isPreviousStandard = surfaceIds.every((id) {
          final expected = id == 'logs'
              ? standard[id].copyWith(width: 68)
              : standard[id];
          final actual = layout[id];
          return actual.x == expected.x &&
              actual.y == expected.y &&
              actual.width == expected.width &&
              actual.height == expected.height;
        });
        if (isPreviousStandard) {
          return HomeLayout._({...placements, 'logs': standard['logs']});
        }
      }
      return HomeLayout._(placements);
    } on FormatException {
      return null;
    }
  }

  String encode() => jsonEncode({
    'version': 4,
    'placements': {for (final id in itemIds) id: this[id].toMap()},
  });

  HomeLayout? move(String id, int x, int y, {bool logsVisible = true}) {
    final current = placements[id];
    if (current == null) return null;
    final domain = controlIds.contains(id) ? controlIds : surfaceIds;
    final maxRows = controlIds.contains(id) ? controlRows : rows;
    final target = current.copyWith(x: x, y: y);
    if (x < 0 || y < 0 || x >= columns || y >= maxRows) return null;
    final active = placements.entries
        .where(
          (entry) =>
              domain.contains(entry.key) &&
              entry.key != id &&
              (logsVisible || entry.key != 'logs'),
        )
        .toList();
    final originMatches = active
        .where((entry) => entry.value.x == x && entry.value.y == y)
        .toList();
    final collisions = originMatches.length == 1
        ? originMatches
        : active.where((entry) => target.overlaps(entry.value)).toList();
    if (collisions.length > 1) return null;
    final draft = {...placements, id: target};
    if (collisions.isNotEmpty) {
      final other = collisions.single;
      draft[other.key] = other.value.copyWith(x: current.x, y: current.y);
    }
    final result = HomeLayout._(draft);
    final packUnequal =
        collisions.length == 1 &&
        current.x == collisions.single.value.x &&
        current.height != collisions.single.value.height;
    if (result._isValid(logsVisible: logsVisible) && !packUnequal) {
      return result;
    }
    if (collisions.isEmpty) return null;
    final other = collisions.single;
    // Unequal cards in one row/column exchange order within the same union,
    // retaining the empty gap and both original sizes.
    if (current.x == other.value.x) {
      final first = current.y < other.value.y ? current : other.value;
      final second = identical(first, current) ? other.value : current;
      final gap = second.y - first.bottom;
      draft[id] = current.copyWith(
        x: current.x,
        y: identical(first, current)
            ? first.y + other.value.height + gap
            : first.y,
      );
      draft[other.key] = other.value.copyWith(
        y: identical(first, current) ? first.y : first.y + current.height + gap,
      );
    } else if (current.y == other.value.y) {
      final first = current.x < other.value.x ? current : other.value;
      final second = identical(first, current) ? other.value : current;
      final gap = second.x - first.right;
      draft[id] = current.copyWith(
        x: identical(first, current)
            ? first.x + other.value.width + gap
            : first.x,
        y: current.y,
      );
      draft[other.key] = other.value.copyWith(
        x: identical(first, current) ? first.x : first.x + current.width + gap,
      );
    } else {
      return null;
    }
    final packed = HomeLayout._(draft);
    return packed._isValid(logsVisible: logsVisible) ? packed : null;
  }

  HomeLayout? resize(
    String id,
    int width,
    int height, {
    bool logsVisible = true,
  }) {
    final current = placements[id];
    if (current == null) return null;
    final result = HomeLayout._({
      ...placements,
      id: current.copyWith(width: width, height: height),
    });
    return result._isValid(logsVisible: logsVisible) ? result : null;
  }

  /// Restoring a hidden panel never places it over an active control.
  HomeLayout? restoreLogs() {
    if (_isValid()) return this;
    final logs = this['logs'];
    for (var y = 0; y <= rows - logs.height; y++) {
      for (var x = 0; x <= columns - logs.width; x++) {
        final result = HomeLayout._({
          ...placements,
          'logs': logs.copyWith(x: x, y: y),
        });
        if (result._isValid()) return result;
      }
    }
    return null;
  }

  static bool _inBounds(String id, HomePlacement item) {
    final minimum = _minimums[id]!;
    return item.x >= 0 &&
        item.y >= 0 &&
        item.width >= minimum.$1 &&
        item.height >= minimum.$2 &&
        item.right <= columns &&
        item.bottom <= (controlIds.contains(id) ? controlRows : rows);
  }

  bool _isValid({bool logsVisible = true, bool reserveHeading = true}) {
    for (final id in itemIds) {
      if (!_inBounds(id, this[id])) return false;
      if (reserveHeading &&
          controlIds.contains(id) &&
          this[id].overlaps(_heading)) {
        return false;
      }
    }
    final active = itemIds.where((id) => logsVisible || id != 'logs').toList();
    for (var i = 0; i < active.length; i++) {
      for (var j = i + 1; j < active.length; j++) {
        if (controlIds.contains(active[i]) == controlIds.contains(active[j]) &&
            this[active[i]].overlaps(this[active[j]])) {
          return false;
        }
      }
    }
    return true;
  }
}

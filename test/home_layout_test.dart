import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:niran/core/platform/native_models.dart';
import 'package:niran/features/vpn/home_layout.dart';

void main() {
  test(
    'v1 detached controls migrate inside status without losing other preferences',
    () {
      final old = jsonEncode({
        'version': 1,
        'placements': {
          'status': {'x': 0, 'y': 0, 'width': 15, 'height': 10},
          'subscription': {'x': 16, 'y': 0, 'width': 8, 'height': 7},
          'traffic': {'x': 16, 'y': 8, 'width': 8, 'height': 13},
          'logs': {'x': 0, 'y': 11, 'width': 15, 'height': 10},
          'systemProxy': {'x': 0, 'y': 22, 'width': 4, 'height': 2},
          'clearProxy': {'x': 5, 'y': 22, 'width': 4, 'height': 2},
          'tun': {'x': 10, 'y': 22, 'width': 4, 'height': 2},
          'restart': {'x': 15, 'y': 22, 'width': 4, 'height': 2},
        },
      });
      final settings = NativeSettings(
        homeLayout: old,
        themeMode: 'dark',
        soundEffects: false,
      );
      final migrated = HomeLayout.fromSettings(settings);
      expect(migrated['status'].height, greaterThan(60));
      expect(migrated['tun'].bottom, lessThanOrEqualTo(32));
      expect(HomeLayout.tryDecode(migrated.encode()), isNotNull);
      expect(settings.soundEffects, isFalse);
      expect(settings.themeMode, 'dark');
    },
  );

  test(
    'control placement supports small moves but never escapes its domain',
    () {
      final layout = HomeLayout.defaults();
      final moved = layout.move('systemProxy', 1, 18)!;
      expect(moved['systemProxy'].x, 1);
      expect(moved['systemProxy'].y, 18);
      expect(moved.move('systemProxy', 1, 23), isNull);
      expect(moved['status'].y, 0);
    },
  );
  test('a saved layout restores independent positions and bounded sizes', () {
    final draft = HomeLayout.defaults().move('subscription', 78, 1)!;
    final resized = draft.resize('status', 72, 68)!;
    final restored = HomeLayout.tryDecode(resized.encode())!;
    expect(restored['subscription'].y, 1);
    expect(restored['status'].width, 72);
    expect(restored['status'].height, 68);
    expect(restored.placements.keys, hasLength(8));
    expect((jsonDecode(restored.encode()) as Map)['version'], 4);
    expect(HomeLayout.defaults()['subscription'].y, 0);
  });

  test(
    'moving a card swaps one collision while preserving different sizes',
    () {
      final layout = HomeLayout.defaults().resize('logs', 68, 30)!;
      final swapped = layout.move('status', 0, 36)!;
      expect(swapped['status'].y, 34);
      expect(swapped['status'].height, 84);
      expect(swapped['logs'].y, 0);
      expect(swapped['logs'].width, 68);
      expect(swapped['logs'].height, 30);
    },
  );

  test('invalid movement and resize reject without mutating the draft', () {
    final layout = HomeLayout.defaults();
    final original = layout.encode();
    expect(layout.move('status', -1, 0), isNull);
    expect(layout.move('status', 10, 0), isNull);
    expect(layout.move('logs', 0, 95), isNull);
    expect(layout.resize('status', 80, 72), isNull);
    expect(layout.resize('logs', 32, 17), isNull);
    expect(layout.resize('traffic', 45, 44), isNull);
    expect(layout.encode(), original);
  });

  test(
    'unequal stacked cards swap inside their shared column with the gap',
    () {
      final swapped = HomeLayout.defaults().move('subscription', 78, 32)!;
      expect(swapped['traffic'].y, 0);
      expect(swapped['traffic'].height, 44);
      expect(swapped['subscription'].y, 48);
      expect(swapped['subscription'].height, 28);
      expect(HomeLayout.tryDecode(swapped.encode()), isNotNull);
      final back = swapped.move('traffic', 78, 48)!;
      expect(back['subscription'].y, 0);
      expect(back['traffic'].y, 32);
    },
  );

  test('unequal adjacent controls swap inside their shared row', () {
    final narrow = HomeLayout.defaults()
        .resize('systemProxy', 30, 14)!
        .resize('clearProxy', 35, 14)!;
    final swapped = narrow.move('systemProxy', 40, 18)!;
    expect(swapped['clearProxy'].x, 0);
    expect(swapped['clearProxy'].width, 35);
    expect(swapped['systemProxy'].x, 40);
    expect(swapped['systemProxy'].width, 30);
    expect(
      HomeLayout.tryDecode(swapped.encode(), logsVisible: false),
      isNotNull,
    );
  });

  test('hidden logs free their space and restore to an available slot', () {
    final layout = HomeLayout.defaults()
        .resize('logs', 32, 18)!
        .move('subscription', 0, 88, logsVisible: false)!;
    expect(layout['logs'].y, 88);
    expect(HomeLayout.tryDecode(layout.encode()), isNull);
    expect(
      HomeLayout.tryDecode(layout.encode(), logsVisible: false),
      isNotNull,
    );
    final restored = layout.restoreLogs()!;
    expect(restored['logs'].overlaps(restored['subscription']), isFalse);
    expect(HomeLayout.tryDecode(restored.encode()), isNotNull);
  });

  test('damaged saved layouts fall back without resetting other settings', () {
    final valid = jsonDecode(HomeLayout.defaults().encode()) as Map;
    for (final encoded in [
      '{',
      jsonEncode({...valid, 'version': 5}),
      jsonEncode({...valid, 'placements': {}}),
      _damaged(valid, 'status', 'x', -1),
      _damaged(valid, 'status', 'x', 0.5),
      _damaged(valid, 'logs', 'y', 0),
      _damaged(valid, 'traffic', 'width', 130),
    ]) {
      expect(HomeLayout.tryDecode(encoded), isNull);
      final settings = NativeSettings.fromMap({
        'homeLayout': encoded,
        'themeMode': 'dark',
        'localSocksPort': 12345,
        'soundEffects': false,
      });
      expect(HomeLayout.fromSettings(settings)['status'].x, 0);
      expect(settings.themeMode, 'dark');
      expect(settings.localSocksPort, 12345);
      expect(settings.soundEffects, isFalse);
    }
  });

  test('legacy left-side usage and action order migrate together', () {
    final layout = HomeLayout.fromSettings(
      const NativeSettings(
        homeUsageSide: 'left',
        homeControlOrder: 'tun,systemProxy,clearProxy',
      ),
    );
    expect(layout['subscription'].x, 0);
    expect(layout['traffic'].x, 0);
    expect(layout['status'].x, 44);
    expect(layout['logs'].x, 44);
    expect(layout['tun'].x, 0);
    expect(layout['systemProxy'].x, 40);
    expect(layout['clearProxy'].x, 80);
    expect(layout['restart'].x, 82);
    expect(HomeLayout.tryDecode(layout.encode()), isNotNull);
  });

  test(
    'NativeSettings keeps sound choice and layout through partial updates',
    () {
      final encoded = HomeLayout.defaults().encode();
      final settings = NativeSettings.fromMap({
        'homeLayout': encoded,
        'soundStyle': 'classic',
        'soundEffects': false,
      });
      final changed = settings.withUpdates({'themeMode': 'dark'});
      expect(changed.homeLayout, encoded);
      expect(changed.soundStyle, 'classic');
      expect(changed.soundEffects, isFalse);
      expect(const NativeSettings().soundStyle, 'notification');
      expect(
        NativeSettings.fromMap({'soundStyle': 'broken'}).soundStyle,
        'notification',
      );
      expect(
        changed.withUpdates({'soundStyle': 'notification'}).soundStyle,
        'notification',
      );
    },
  );
}

String _damaged(Map valid, String id, String key, Object value) {
  final data = jsonDecode(jsonEncode(valid)) as Map;
  ((data['placements'] as Map)[id] as Map)[key] = value;
  return jsonEncode(data);
}

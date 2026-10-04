import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:niran/features/vpn/home_layout.dart';

void main() {
  const old =
      '{"version":2,"placements":{"status":{"x":0,"y":0,"width":76,"height":84},"subscription":{"x":78,"y":0,"width":42,"height":28},"traffic":{"x":78,"y":32,"width":42,"height":44},"logs":{"x":0,"y":88,"width":68,"height":32},"systemProxy":{"x":0,"y":0,"width":37,"height":14},"clearProxy":{"x":40,"y":0,"width":37,"height":14},"tun":{"x":80,"y":0,"width":40,"height":14},"restart":{"x":0,"y":18,"width":42,"height":14}}}';
  test('standard logs widen to status without gaining height', () {
    final layout = HomeLayout.defaults();
    expect(layout['logs'].right, layout['status'].right);
    expect(layout['logs'].height, 32);
  });
  test(
    'previous standard layout widens logs and moves controls clear of heading',
    () {
      final saved = jsonDecode(old) as Map<String, dynamic>;
      saved['placements']['restart']['x'] = 1;
      final migrated = HomeLayout.tryDecode(jsonEncode(saved))!;
      expect(migrated['logs'].width, 76);
      expect(migrated['logs'].height, 32);
      expect(migrated['restart'].x, 82);
      expect(migrated['restart'].y, 0);
      expect(migrated['systemProxy'].y, 18);
      expect(migrated['status'].width, 76);
      expect(migrated['traffic'].x, 78);
      final customized = migrated.resize('logs', 68, 32)!;
      expect(HomeLayout.tryDecode(customized.encode())!['logs'].width, 68);
    },
  );
  test(
    'existing manually sized logs do not get overwritten during migration',
    () {
      final saved = jsonDecode(old) as Map<String, dynamic>;
      saved['placements']['logs']['width'] = 60;
      final restored = HomeLayout.tryDecode(jsonEncode(saved))!;
      expect(restored['logs'].width, 60);
      expect(restored['logs'].height, 32);
    },
  );
}

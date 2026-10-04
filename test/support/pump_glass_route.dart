import 'package:flutter_test/flutter_test.dart';
import 'package:niran/core/widgets/snapshot_glass.dart';

/// Load the shared engine future outside a per-test FakeAsync zone so that it
/// can complete before that zone is disposed by a later widget test.
Future<void> warmGlassRouteTests() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  expect(await warmSnapshotGlass(), isNotNull);
}

/// Route creation waits for shader loading, a painted frame and GPU readback.
/// Fake-clock settling alone cannot drive those real engine futures.
Future<void> pumpGlassRoute(
  WidgetTester tester,
  Finder expected, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  final deadline = Stopwatch()..start();
  do {
    // Native spring menus need fake time to advance too; waiting only on
    // real shader futures leaves their morph at progress zero indefinitely.
    await tester.pump(const Duration(milliseconds: 16));
    if (expected.evaluate().isNotEmpty) {
      await tester.pumpAndSettle();
      return;
    }
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
  } while (deadline.elapsed < timeout);
  throw TestFailure('Timed out waiting for captured-glass route: $expected');
}

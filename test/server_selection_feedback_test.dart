import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niran/core/platform/native_models.dart';
import 'package:niran/features/vpn/app_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('dev.niran.windows/host');
  final delivered = <MethodCall>[];
  Completer<bool>? feedbackGate;

  setUp(() {
    delivered.clear();
    feedbackGate = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          delivered.add(call);
          return feedbackGate == null ? true : await feedbackGate!.future;
        });
  });
  tearDown(() {
    if (feedbackGate != null && !feedbackGate!.isCompleted) {
      feedbackGate!.complete(true);
    }
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  for (final (style, waveLength) in [
    ('notification', 3572),
    ('classic', 5336),
  ]) {
    testWidgets('$style selection cue precedes a pending server switch', (
      tester,
    ) async {
      final selection = Completer<List<dynamic>>();
      final container = await _fixture(selection, soundStyle: style);
      var finished = false;
      final request = container
          .read(appControllerProvider.notifier)
          .selectServer('fr')
          .whenComplete(() => finished = true);
      await tester.pump();

      expect(finished, false);
      expect(
        container.read(appControllerProvider).requireValue.selectedServer?.id,
        'fr',
      );
      expect(delivered, hasLength(1));
      expect(delivered.single.method, 'showDesktopFeedback');
      final arguments = delivered.single.arguments as Map;
      expect(arguments['sound'], isA<Uint8List>());
      expect((arguments['sound'] as Uint8List).length, waveLength);
      expect(arguments['notification'], false);

      selection.complete(_selectedServers('fr'));
      await request;
      await tester.pump();
      expect(finished, true);
      expect(delivered, hasLength(1));
    });
  }

  testWidgets('muting selection sound stays silent during and after switch', (
    tester,
  ) async {
    final selection = Completer<List<dynamic>>();
    final container = await _fixture(selection, soundEffects: false);
    final request = container
        .read(appControllerProvider.notifier)
        .selectServer('fr');
    await tester.pump();
    expect(delivered, isEmpty);
    selection.complete(_selectedServers('fr'));
    await request;
    await tester.pump();
    expect(delivered, isEmpty);
  });

  testWidgets('reselecting the active server stays silent', (tester) async {
    final selection = Completer<List<dynamic>>();
    final container = await _fixture(selection);
    final request = container
        .read(appControllerProvider.notifier)
        .selectServer('de');
    await tester.pump();
    expect(delivered, isEmpty);
    selection.complete(_selectedServers('de'));
    await request;
    await tester.pump();
    expect(delivered, isEmpty);
  });

  testWidgets('overlapping connected selections do not replay feedback', (
    tester,
  ) async {
    final selection = Completer<List<dynamic>>();
    final requestedIds = <String>[];
    final container = await _fixture(selection, requestedIds: requestedIds);
    final controller = container.read(appControllerProvider.notifier);
    final first = controller.selectServer('fr');
    final duplicate = controller.selectServer('de');
    await tester.pump();
    expect(requestedIds, ['fr']);
    expect(delivered, hasLength(1));
    expect(
      container.read(appControllerProvider).requireValue.selectedServer?.id,
      'fr',
    );
    selection.complete(_selectedServers('fr'));
    await Future.wait([first, duplicate]);
    await tester.pump();
    expect(delivered, hasLength(1));
  });

  testWidgets('failed switch rolls selection back without a second cue', (
    tester,
  ) async {
    final selection = Completer<List<dynamic>>();
    final container = await _fixture(selection);
    final request = container
        .read(appControllerProvider.notifier)
        .selectServer('fr');
    final failure = expectLater(request, throwsA(isA<PlatformException>()));
    await tester.pump();
    final feedbackWhileSwitching = List<MethodCall>.of(delivered);
    selection.completeError(PlatformException(code: 'connection_failed'));
    await failure;
    await tester.pump();
    expect(feedbackWhileSwitching, hasLength(1));
    expect(
      container.read(appControllerProvider).requireValue.selectedServer?.id,
      'de',
    );
    expect(delivered, hasLength(1));
  });

  testWidgets('slow optional audio never blocks server switching', (
    tester,
  ) async {
    feedbackGate = Completer<bool>();
    final selection = Completer<List<dynamic>>();
    final container = await _fixture(selection);
    var finished = false;
    final request = container
        .read(appControllerProvider.notifier)
        .selectServer('fr')
        .whenComplete(() => finished = true);
    await tester.pump();
    expect(delivered, hasLength(1));
    selection.complete(_selectedServers('fr'));
    await tester.pump();
    expect(finished, true);
    expect(feedbackGate!.isCompleted, false);
    await request;
    feedbackGate!.complete(true);
    await tester.pump();
  });

  testWidgets('an unknown server does not emit a selection cue', (
    tester,
  ) async {
    final selection = Completer<List<dynamic>>();
    final container = await _fixture(selection);
    final request = container
        .read(appControllerProvider.notifier)
        .selectServer('missing');
    final failure = expectLater(request, throwsA(isA<PlatformException>()));
    await tester.pump();
    final feedbackWhileSwitching = List<MethodCall>.of(delivered);
    selection.completeError(PlatformException(code: 'not_found'));
    await failure;
    await tester.pump();
    expect(feedbackWhileSwitching, isEmpty);
    expect(delivered, isEmpty);
    expect(
      container.read(appControllerProvider).requireValue.selectedServer?.id,
      'de',
    );
  });
}

Future<ProviderContainer> _fixture(
  Completer<List<dynamic>> selection, {
  bool soundEffects = true,
  String soundStyle = 'notification',
  List<String>? requestedIds,
}) async {
  final container = ProviderContainer(
    overrides: [
      appControllerProvider.overrideWith(
        () => _SnapshotController(
          selectServerOperation: (id) {
            requestedIds?.add(id);
            return selection.future;
          },
          settings: NativeSettings(
            soundEffects: soundEffects,
            soundStyle: soundStyle,
          ),
        ),
      ),
    ],
  );
  addTearDown(() {
    if (!selection.isCompleted) selection.complete(_selectedServers('fr'));
    container.dispose();
  });
  await container.read(appControllerProvider.future);
  return container;
}

class _SnapshotController extends AppController {
  _SnapshotController({
    required super.selectServerOperation,
    required this.settings,
  });

  final NativeSettings settings;

  @override
  Future<AppSnapshot> build() async => AppSnapshot(
    servers: const [_germany, _france],
    connection: const ConnectionInfo(state: 'connected', serverId: 'de'),
    settings: settings,
  );
}

List<dynamic> _selectedServers(String id) => [
  for (final (serverId, name, country) in [
    ('de', 'Germany', 'DE'),
    ('fr', 'France', 'FR'),
  ])
    {
      'id': serverId,
      'name': name,
      'country': country,
      'protocol': 'VLESS',
      'transport': 'TCP',
      'security': 'TLS',
      'port': 443,
      'selected': serverId == id,
      'status': 'idle',
    },
];

const _germany = ServerInfo(
  id: 'de',
  name: 'Germany',
  country: 'DE',
  protocol: 'VLESS',
  transport: 'TCP',
  security: 'TLS',
  port: 443,
  selected: true,
  status: 'idle',
);
const _france = ServerInfo(
  id: 'fr',
  name: 'France',
  country: 'FR',
  protocol: 'VLESS',
  transport: 'TCP',
  security: 'TLS',
  port: 443,
  selected: false,
  status: 'idle',
);

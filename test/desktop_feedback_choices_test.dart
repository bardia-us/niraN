import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niran/core/desktop_feedback.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'default sound delivers the embedded soft pop at moderate gain',
    () async {
      final delivered = await _feedback();
      final sound = (delivered!.arguments as Map)['sound'] as Uint8List;
      expect(sound, orderedEquals(DesktopFeedback.softCue()));
      expect(sound.length, lessThan(4500));
      _expectModerate(sound, minimumPeak: 1500, maximumRms: 1500);
    },
  );
  test(
    'classic retains the earlier simple cue and differs from the pop',
    () async {
      final classic = (await _feedback(style: 'classic'))!.arguments as Map;
      final notification =
          (await _feedback(style: 'notification'))!.arguments as Map;
      final classicBytes = classic['sound'] as Uint8List;
      expect(classicBytes, isNot(notification['sound']));
      expect(classicBytes.length, 5336);
      final samples = _pcm(classicBytes);
      expect(samples[200], -341);
      expect(samples.map((v) => v.abs()).reduce(math.max), 1423);
      _expectModerate(classicBytes, minimumPeak: 1000, maximumRms: 1000);
    },
  );
  test('muting both outputs skips the native feedback call', () async {
    expect(await _feedback(sound: false), isNull);
  });
  test(
    'both styles preserve notification delivery when audio is muted',
    () async {
      for (final style in ['notification', 'classic']) {
        final delivered = await _feedback(
          style: style,
          sound: false,
          notification: true,
        );
        expect(delivered!.method, 'showDesktopFeedback');
        expect((delivered.arguments as Map)['notification'], true);
        expect((delivered.arguments as Map).containsKey('sound'), false);
      }
    },
  );
  test('native failures remain optional for both styles', () async {
    const channel = MethodChannel('dev.niran.windows/host');
    for (final style in ['notification', 'classic']) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async {
            throw PlatformException(code: 'audio_unavailable');
          });
      try {
        await expectLater(DesktopFeedback.show(style: style), completes);
      } finally {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      }
    }
  });
  test('unsupported native hosts do not fail the action', () async {
    const channel = MethodChannel('dev.niran.windows/host');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          channel,
          (_) async => throw MissingPluginException(),
        );
    try {
      await expectLater(DesktopFeedback.show(style: 'classic'), completes);
    } finally {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    }
  });
}

Future<MethodCall?> _feedback({
  String style = 'notification',
  bool sound = true,
  bool notification = false,
}) async {
  MethodCall? delivered;
  const channel = MethodChannel('dev.niran.windows/host');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (call) async {
        delivered = call;
        return true;
      });
  try {
    await DesktopFeedback.show(
      style: style,
      sound: sound,
      notification: notification,
    );
    return delivered;
  } finally {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  }
}

List<int> _pcm(Uint8List bytes) {
  final data = ByteData.sublistView(bytes);
  var offset = 12;
  while (ascii.decode(bytes.sublist(offset, offset + 4)) != 'data') {
    final size = data.getUint32(offset + 4, Endian.little);
    offset += 8 + size + size % 2;
  }
  final size = data.getUint32(offset + 4, Endian.little);
  return List.generate(
    size ~/ 2,
    (i) => data.getInt16(offset + 8 + i * 2, Endian.little),
  );
}

void _expectModerate(
  Uint8List bytes, {
  required int minimumPeak,
  required double maximumRms,
}) {
  final header = ByteData.sublistView(bytes);
  expect(ascii.decode(bytes.sublist(0, 4)), 'RIFF');
  expect(ascii.decode(bytes.sublist(8, 12)), 'WAVE');
  expect(header.getUint32(4, Endian.little), bytes.length - 8);
  expect(header.getUint16(20, Endian.little), 1);
  expect(header.getUint16(34, Endian.little), 16);
  final samples = _pcm(bytes);
  final peak = samples.map((v) => v.abs()).reduce(math.max);
  final rms = math.sqrt(
    samples.fold<double>(0, (sum, v) => sum + v * v) / samples.length,
  );
  final mean = samples.fold<double>(0, (sum, v) => sum + v) / samples.length;
  expect(peak, greaterThan(minimumPeak));
  expect(peak, lessThan(12000));
  expect(rms, lessThan(maximumRms));
  expect(rms, greaterThan(200));
  expect(mean.abs(), lessThan(20));
  expect(samples.first, 0);
  expect(samples.last, 0);
}

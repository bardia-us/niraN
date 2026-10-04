import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niran/core/desktop_feedback.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('soft cue is short mono PCM with quiet attack and release', () {
    final bytes = DesktopFeedback.softCue();
    final header = ByteData.sublistView(bytes);
    expect(ascii.decode(bytes.sublist(0, 4)), 'RIFF');
    expect(ascii.decode(bytes.sublist(8, 12)), 'WAVE');
    expect(header.getUint16(22, Endian.little), 1);
    expect(header.getUint16(34, Endian.little), 16);
    expect(header.getUint32(24, Endian.little), 22050);
    expect(bytes.length, lessThan(7000));
    expect(header.getInt16(44, Endian.little), 0);
    expect(header.getInt16(bytes.length - 2, Endian.little).abs(), lessThan(8));
  });
  test(
    'muting feedback omits audio without suppressing notification',
    () async {
      MethodCall? delivered;
      const channel = MethodChannel('dev.niran.windows/host');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            delivered = call;
            return true;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      await DesktopFeedback.show(
        message: 'TUN enabled',
        notification: true,
        sound: false,
      );
      expect(delivered?.method, 'showDesktopFeedback');
      expect((delivered?.arguments as Map)['notification'], true);
      expect((delivered?.arguments as Map)['sound'], isNull);
    },
  );
}

import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niran/core/desktop_feedback.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'missing assets cannot silence the embedded pop or lose notification',
    () async {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      const channel = MethodChannel('dev.niran.windows/host');
      MethodCall? delivered;
      messenger.setMockMessageHandler('flutter/assets', (_) async => null);
      messenger.setMockMethodCallHandler(channel, (call) async {
        delivered = call;
        return true;
      });
      addTearDown(() {
        messenger.setMockMessageHandler('flutter/assets', null);
        messenger.setMockMethodCallHandler(channel, null);
      });

      await DesktopFeedback.show(notification: true, message: 'Ready');

      final arguments = delivered!.arguments as Map;
      expect(arguments['notification'], true);
      expect(arguments['message'], 'Ready');
      expect(arguments['sound'], isA<Uint8List>());
      final wave = arguments['sound'] as Uint8List;
      expect(wave.length, lessThan(4500));
      final data = ByteData.sublistView(wave);
      expect(data.getUint32(24, Endian.little), 22050);
      expect(wave, orderedEquals(DesktopFeedback.softCue()));
    },
  );
}

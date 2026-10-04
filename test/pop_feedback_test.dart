import 'dart:typed_data';
import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:niran/core/desktop_feedback.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'default feedback is a short quiet pop, not the long notification',
    () async {
      final bytes = await DesktopFeedback.cueForStyle('notification');
      final data = ByteData.sublistView(bytes);
      final rate = data.getUint32(24, Endian.little);
      final channels = data.getUint16(22, Endian.little);
      final duration = (bytes.length - 44) / (2 * channels * rate);
      expect(duration, inInclusiveRange(.05, .10));
      expect(channels, 1);
      final samples = List.generate(
        (bytes.length - 44) ~/ 2,
        (i) => data.getInt16(44 + 2 * i, Endian.little),
      );
      final peak = samples.map((s) => s.abs()).reduce(math.max);
      final rms = math.sqrt(
        samples.fold<double>(0, (sum, s) => sum + s * s) / samples.length,
      );
      expect(peak, inInclusiveRange(1500, 5500));
      expect(rms, inInclusiveRange(200, 1500));
      expect(samples.first, 0);
      expect(samples.last, 0);
      expect(
        samples.take(samples.length ~/ 3).map((s) => s.abs()).reduce(math.max),
        greaterThan(peak * .9),
      );
    },
  );
}

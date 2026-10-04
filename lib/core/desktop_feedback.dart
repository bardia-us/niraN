import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/services.dart';

/// Optional local PCM feedback; never a dependency of a core operation.
abstract final class DesktopFeedback {
  static const _channel = MethodChannel('dev.niran.windows/host');
  static final _classic = classicCue();
  static final _pop = softCue();

  /// Retain the explicit Classic preference; no external audio asset is needed.
  static Uint8List classicCue() {
    final bytes = _wave(2646);
    final data = ByteData.sublistView(bytes);
    const rate = 22050;
    const samples = 2646;
    for (var i = 0; i < samples; i++) {
      final t = i / rate;
      final envelope =
          math.sin(math.pi * i / (samples - 1)) * math.exp(-t * 24);
      final tone =
          (math.sin(2 * math.pi * 620 * t) +
              .35 * math.sin(2 * math.pi * 930 * t)) *
          envelope;
      data.setInt16(
        44 + i * 2,
        (tone * 3200).round().clamp(-32768, 32767),
        Endian.little,
      );
    }
    return bytes;
  }

  // Keep the persisted 'notification' identifier compatible with older builds.
  static Future<Uint8List> cueForStyle(String style) async =>
      style == 'classic' ? _classic : _pop;

  static Uint8List _wave(int samples) {
    const rate = 22050;
    final data = ByteData(44 + samples * 2);
    final bytes = data.buffer.asUint8List();
    bytes.setRange(0, 4, ascii.encode('RIFF'));
    data.setUint32(4, bytes.length - 8, Endian.little);
    bytes.setRange(8, 16, ascii.encode('WAVEfmt '));
    data.setUint32(16, 16, Endian.little);
    data.setUint16(20, 1, Endian.little);
    data.setUint16(22, 1, Endian.little);
    data.setUint32(24, rate, Endian.little);
    data.setUint32(28, rate * 2, Endian.little);
    data.setUint16(32, 2, Endian.little);
    data.setUint16(34, 16, Endian.little);
    bytes.setRange(36, 40, ascii.encode('data'));
    data.setUint32(40, samples * 2, Endian.little);
    return bytes;
  }

  static Uint8List softCue() {
    const rate = 22050;
    const samples =
        1764; // 80 ms: rounded pop, not a long ringing notification.
    final bytes = _wave(samples);
    final data = ByteData.sublistView(bytes);
    for (var i = 0; i < samples; i++) {
      final t = i / rate;
      final attack = math.sin(math.pi / 2 * (t / .004).clamp(0, 1));
      final tail = ((samples - 1 - i) / (rate * .018)).clamp(0.0, 1.0);
      final envelope = attack * attack * math.exp(-t * 52) * tail * tail;
      // A low, falling fundamental without bright harmonics avoids a sharp beep.
      final phase =
          2 * math.pi * (170 * t + 200 / 65 * (1 - math.exp(-65 * t)));
      data.setInt16(
        44 + i * 2,
        (math.sin(phase) * envelope * 5000).round(),
        Endian.little,
      );
    }
    return bytes;
  }

  static Future<void> show({
    String message = '',
    bool notification = false,
    bool sound = true,
    String style = 'notification',
  }) async {
    if (!notification && !sound) return;
    Uint8List? cue;
    if (sound) cue = await cueForStyle(style);
    try {
      await _channel.invokeMethod<bool>('showDesktopFeedback', {
        'message': message,
        'notification': notification,
        'sound': ?cue,
      });
    } on PlatformException catch (_) {
      // A failed optional sound/notification cannot invalidate a VPN action.
    } on MissingPluginException catch (_) {
      // Unsupported hosts are silent.
    }
  }
}

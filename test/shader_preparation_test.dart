import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:niran/core/widgets/shader_preparation.dart';

void main() {
  test(
    'late preparation cannot replace a settled fallback or block a menu',
    () async {
      final loader = Completer<bool>();
      final preparation = ShaderPreparation(
        () => loader.future,
        timeout: Duration.zero,
      );
      expect(await preparation.prepare(), isFalse);
      loader.complete(true);
      await Future<void>.delayed(Duration.zero);
      expect(preparation.ready, isFalse);
      expect(await preparation.prepare(), isFalse);
    },
  );
  test(
    'loaded programs settle once and stay ready without loading on each menu',
    () async {
      var calls = 0;
      final preparation = ShaderPreparation(() async {
        calls++;
        return true;
      });
      expect(await preparation.prepare(), isTrue);
      expect(await preparation.prepare(), isTrue);
      expect(preparation.ready, isTrue);
      expect(calls, 1);
    },
  );
  test(
    'loading failure settles to fallback instead of throwing on menu open',
    () async {
      final preparation = ShaderPreparation(
        () async => throw StateError('unavailable'),
      );
      expect(await preparation.prepare(), isFalse);
      expect(preparation.ready, isFalse);
    },
  );
}

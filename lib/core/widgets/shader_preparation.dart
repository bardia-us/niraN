import 'dart:async';

/// Settle once before UI startup. A late loader cannot switch a fallback
/// session to an unannounced live renderer or stall subsequent menu opens.
final class ShaderPreparation {
  ShaderPreparation(this._load, {this.timeout = const Duration(seconds: 2)});
  final Future<bool> Function() _load;
  final Duration timeout;
  Future<bool>? _pending;
  bool ready = false;
  Future<bool> prepare() => _pending ??= _settle();
  Future<bool> _settle() async {
    try {
      ready = await Future<bool>.sync(_load)
          .then((value) => value, onError: (Object _, StackTrace _) => false)
          .timeout(timeout, onTimeout: () => false);
    } on Object {
      ready = false;
    }
    return ready;
  }
}

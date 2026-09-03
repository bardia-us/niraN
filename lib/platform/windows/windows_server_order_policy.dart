import 'windows_server_record.dart';

/// Keeps a user-defined order without turning the cached subscription into a
/// second source of truth. Only records present in the refreshed subscription
/// are returned.
final class WindowsServerOrderPolicy {
  const WindowsServerOrderPolicy();

  List<WindowsServerRecord> reconcile({
    required List<String> preferredIds,
    required List<WindowsServerRecord> previous,
    required List<WindowsServerRecord> refreshed,
  }) {
    if (preferredIds.isEmpty || refreshed.isEmpty) return List.of(refreshed);
    final unused = List<WindowsServerRecord>.of(refreshed);
    final result = <WindowsServerRecord>[];
    final oldById = {for (final item in previous) item.id: item};
    for (final oldId in preferredIds) {
      final exact = unused.indexWhere((item) => item.id == oldId);
      if (exact >= 0) {
        result.add(unused.removeAt(exact));
        continue;
      }
      final old = oldById[oldId];
      if (old == null) continue;
      final matches = unused.where((item) => _sameEndpoint(old, item)).toList();
      if (matches.length == 1) {
        result.add(matches.single);
        unused.remove(matches.single);
      }
    }
    // New subscription entries retain their source order and are never
    // allowed to shuffle already matched entries.
    result.addAll(unused);
    return result;
  }

  bool _sameEndpoint(WindowsServerRecord a, WindowsServerRecord b) =>
      a.protocol.toLowerCase() == b.protocol.toLowerCase() &&
      a.address.toLowerCase() == b.address.toLowerCase() &&
      a.port == b.port &&
      a.credential == b.credential;
}

import 'dart:convert';
import 'dart:io';

const nirangRepositoryUrl = 'https://github.com/bardia-us/niraN';
const nirangLatestReleaseApi =
    'https://api.github.com/repos/bardia-us/niraN/releases/latest';

class SemanticVersion implements Comparable<SemanticVersion> {
  const SemanticVersion(this.major, this.minor, this.patch);

  factory SemanticVersion.parse(String value) {
    final match = RegExp(
      r'^v?(\d+)\.(\d+)\.(\d+)(?:[-+].*)?$',
      caseSensitive: false,
    ).firstMatch(value.trim());
    if (match == null) throw const FormatException('Invalid release version');
    return SemanticVersion(
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
      int.parse(match.group(3)!),
    );
  }

  @override
  int compareTo(SemanticVersion other) {
    final majorResult = major.compareTo(other.major);
    if (majorResult != 0) return majorResult;
    final minorResult = minor.compareTo(other.minor);
    if (minorResult != 0) return minorResult;
    return patch.compareTo(other.patch);
  }

  final int major;
  final int minor;
  final int patch;

  @override
  String toString() => '$major.$minor.$patch';
}

class ReleaseCheckResult {
  const ReleaseCheckResult({
    required this.latestVersion,
    required this.releaseUrl,
    required this.updateAvailable,
    this.windowsAsset,
  });

  final SemanticVersion latestVersion;
  final Uri releaseUrl;
  final bool updateAvailable;
  final ReleaseAsset? windowsAsset;
}

class ReleaseAsset {
  const ReleaseAsset({
    required this.name,
    required this.url,
    required this.size,
    this.sha256,
  });
  final String name;
  final Uri url;
  final int size;
  final String? sha256;
}

class GitHubUpdateChecker {
  const GitHubUpdateChecker();

  Future<ReleaseCheckResult> check(String currentVersion) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final request = await client.getUrl(Uri.parse(nirangLatestReleaseApi));
      request.headers
        ..set(HttpHeaders.acceptHeader, 'application/vnd.github+json')
        ..set(HttpHeaders.userAgentHeader, 'niraN-update-checker/0.3.4');
      final response = await request.close().timeout(
        const Duration(seconds: 10),
      );
      if (response.statusCode != HttpStatus.ok) {
        throw const HttpException('GitHub release check failed');
      }
      final payload = jsonDecode(
        await utf8.decoder
            .bind(response)
            .join()
            .timeout(const Duration(seconds: 10)),
      );
      if (payload is! Map<String, dynamic>) {
        throw const FormatException('Invalid GitHub response');
      }
      final latest = SemanticVersion.parse('${payload['tag_name'] ?? ''}');
      final releaseUrl = Uri.tryParse('${payload['html_url'] ?? ''}');
      if (releaseUrl == null ||
          releaseUrl.scheme != 'https' ||
          releaseUrl.host != 'github.com' ||
          !releaseUrl.path.startsWith('/bardia-us/niraN/releases/')) {
        throw const FormatException('Invalid release URL');
      }
      ReleaseAsset? windowsAsset;
      final assets = payload['assets'];
      if (assets is List) {
        final candidates = <ReleaseAsset>[];
        for (final value in assets.whereType<Map>()) {
          final name = '${value['name'] ?? ''}';
          final lower = name.toLowerCase();
          if (!lower.contains('windows') ||
              !lower.contains('x64') ||
              !(lower.endsWith('.zip') ||
                  lower.endsWith('.exe') ||
                  lower.endsWith('.msix'))) {
            continue;
          }
          final url = Uri.tryParse('${value['browser_download_url'] ?? ''}');
          if (url == null ||
              url.scheme != 'https' ||
              !const {
                'github.com',
                'objects.githubusercontent.com',
              }.contains(url.host)) {
            continue;
          }
          final rawDigest = '${value['digest'] ?? ''}';
          final digest = RegExp(
            r'^sha256:([0-9a-fA-F]{64})$',
          ).firstMatch(rawDigest)?.group(1)?.toLowerCase();
          candidates.add(
            ReleaseAsset(
              name: name,
              url: url,
              size: (value['size'] as num?)?.toInt() ?? 0,
              sha256: digest,
            ),
          );
        }
        candidates.sort(
          (left, right) =>
              _assetPriority(left.name).compareTo(_assetPriority(right.name)),
        );
        windowsAsset = candidates.firstOrNull;
      }
      return ReleaseCheckResult(
        latestVersion: latest,
        releaseUrl: releaseUrl,
        updateAvailable:
            latest.compareTo(SemanticVersion.parse(currentVersion)) > 0,
        windowsAsset: windowsAsset,
      );
    } finally {
      client.close(force: true);
    }
  }

  static int _assetPriority(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.zip')) return 0;
    if (lower.endsWith('.exe')) return 1;
    return 2;
  }
}

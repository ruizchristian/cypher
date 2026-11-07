import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

// The only file in the app that opens network connections (the guard script
// enforces this). It talks to GitHub alone: the release list, then the APK.
// No account data, codes or settings are ever sent; the requests carry nothing
// but the repository name.

/// Where releases are published. CI attaches the signed APK to each release.
const updateRepository = 'ruizchristian/cypher';

/// The APK name CI gives every build: `CypherAuth-<version>-<build>.apk`. The
/// build number is the Android versionCode, which decides whether Android
/// treats the file as an upgrade.
final _apkName = RegExp(r'^CypherAuth-([0-9A-Za-z.+\-]+)-(\d+)\.apk$');

/// A published build that may be newer than the installed one.
final class AvailableUpdate {
  const AvailableUpdate({
    required this.version,
    required this.build,
    required this.downloadUrl,
    required this.sizeBytes,
    this.sha256,
  });

  final String version;
  final int build;
  final Uri downloadUrl;
  final int sizeBytes;

  /// Lower-case hex digest GitHub computed on upload, when it recorded one.
  final String? sha256;
}

/// Picks the newest installable APK out of a `GET /releases` response.
///
/// Pre-releases count: CypherAuth ships as pre-releases until 1.0 is final,
/// and those are the builds people install. Drafts never do. Returns null when
/// no release has an APK yet (CI attaches it minutes after publishing).
AvailableUpdate? parseReleases(List<Object?> releases) {
  AvailableUpdate? best;
  for (final release in releases) {
    if (release is! Map || release['draft'] == true) continue;
    final candidate = _apkOf(release);
    if (candidate != null && (best == null || candidate.build > best.build)) {
      best = candidate;
    }
  }
  return best;
}

AvailableUpdate? _apkOf(Map<Object?, Object?> release) {
  final assets = release['assets'];
  if (assets is! List) return null;

  AvailableUpdate? best;
  for (final asset in assets) {
    if (asset is! Map) continue;
    final match = _apkName.firstMatch('${asset['name']}');
    final url = Uri.tryParse('${asset['browser_download_url']}');
    final size = asset['size'];
    // An upload still in flight is listed with another state.
    final state = asset['state'];
    if (match == null ||
        url == null ||
        url.scheme != 'https' ||
        size is! int ||
        size <= 0 ||
        (state != null && state != 'uploaded')) {
      continue;
    }
    final digest = '${asset['digest']}';
    final candidate = AvailableUpdate(
      version: match.group(1)!,
      build: int.parse(match.group(2)!),
      downloadUrl: url,
      sizeBytes: size,
      sha256: digest.startsWith('sha256:')
          ? digest.substring(7).toLowerCase()
          : null,
    );
    if (best == null || candidate.build > best.build) best = candidate;
  }
  return best;
}

/// A download that finished but is not the file the release describes.
final class CorruptDownloadException implements Exception {
  const CorruptDownloadException();
}

abstract interface class UpdateSource {
  /// The newest published build, or null when there is none with an APK.
  Future<AvailableUpdate?> latest();

  /// Streams the APK into [destination], reporting bytes received so far,
  /// and verifies its size and digest.
  Future<void> download(
    AvailableUpdate update,
    File destination,
    void Function(int received) onProgress,
  );
}

final class GitHubUpdateSource implements UpdateSource {
  const GitHubUpdateSource({this.repository = updateRepository});

  final String repository;

  static const _requestTimeout = Duration(seconds: 20);

  /// Gap between two chunks before a stalled download is abandoned. Generous,
  /// because a phone on a weak signal pauses for seconds and recovers.
  static const _stallTimeout = Duration(seconds: 30);

  HttpClient _client() => HttpClient()
    ..connectionTimeout = const Duration(seconds: 15)
    ..userAgent = 'CypherAuth-updater';

  @override
  Future<AvailableUpdate?> latest() async {
    final client = _client();
    try {
      final request = await client
          .getUrl(
            Uri.https('api.github.com', '/repos/$repository/releases', {
              'per_page': '10',
            }),
          )
          .timeout(_requestTimeout);
      request.headers.set(
        HttpHeaders.acceptHeader,
        'application/vnd.github+json',
      );
      final response = await request.close().timeout(_requestTimeout);
      if (response.statusCode != HttpStatus.ok) {
        await response.drain<void>();
        throw HttpException('Release lookup failed (${response.statusCode})');
      }
      final body = await response
          .transform(utf8.decoder)
          .join()
          .timeout(_requestTimeout);
      final json = jsonDecode(body);
      return json is List ? parseReleases(json) : null;
    } finally {
      client.close(force: true);
    }
  }

  @override
  Future<void> download(
    AvailableUpdate update,
    File destination,
    void Function(int received) onProgress,
  ) async {
    final client = _client();
    final sink = destination.openWrite();
    final digest = _DigestSink();
    final hasher = sha256.startChunkedConversion(digest);
    var received = 0;

    try {
      // The asset URL redirects to GitHub's CDN; HttpClient follows it.
      final request = await client
          .getUrl(update.downloadUrl)
          .timeout(_requestTimeout);
      final response = await request.close().timeout(_requestTimeout);
      if (response.statusCode != HttpStatus.ok) {
        await response.drain<void>();
        throw HttpException('Download failed (${response.statusCode})');
      }
      await for (final chunk in response.timeout(_stallTimeout)) {
        sink.add(chunk);
        hasher.add(chunk);
        received += chunk.length;
        // A server sending more than the release lists is not this file.
        if (received > update.sizeBytes) throw const CorruptDownloadException();
        onProgress(received);
      }
    } finally {
      await sink.close();
      client.close(force: true);
    }

    hasher.close();
    // Android refuses an APK not signed with CypherAuth's key no matter what,
    // which is the real protection. Checking here turns a truncated or
    // swapped file into a clear "try again" before the installer opens.
    final expected = update.sha256;
    if (received != update.sizeBytes ||
        (expected != null && digest.value.toString() != expected)) {
      throw const CorruptDownloadException();
    }
  }
}

final class _DigestSink implements Sink<Digest> {
  late Digest value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}

/// User-facing text for in-app updates, kept in one place for localization.
abstract final class UpdateStrings {
  static const String section = 'Updates';
  static const String checkFailed = "Couldn't check for updates right now.";
  static const String downloadFailed =
      "Couldn't download the update. Check your connection and try again.";
  static const String installerFailed = "Couldn't open the installer.";
  static const String allowInstalls =
      'Allow CypherAuth to install apps, then come back to finish the update.';

  static const String available = 'Update available';
  static const String downloading = 'Downloading update';
  static const String ready = 'Update ready';
  static const String install = 'Install';
  static const String later = 'Not now';

  static String availableDetail(String version, int bytes) =>
      'CypherAuth $version · ${megabytes(bytes)}';
  static String downloadingDetail(double? progress, int bytes) =>
      '${((progress ?? 0) * 100).round()}% of ${megabytes(bytes)}';
  static String readyDetail(String version) =>
      'CypherAuth $version is downloaded.';
  static const String keepsAccounts =
      'Your accounts and PIN are kept when it installs.';

  static const String unsupported =
      'In-app updates work only in release builds on Android.';
  static String installedVersion(String version, int build) =>
      'Installed: $version ($build)';
  static String availableVersion(String version, int build) =>
      'Available: $version ($build)';
  static const String upToDate = 'CypherAuth is up to date.';
  static String lastChecked(DateTime at) {
    String two(int n) => n.toString().padLeft(2, '0');
    return 'Last checked ${two(at.hour)}:${two(at.minute)}';
  }

  static const String checkNow = 'Check for updates';
  static const String checking = 'Checking…';
  static String downloadAndInstall(int bytes) =>
      'Download and install (${megabytes(bytes)})';
  static const String installUpdate = 'Install update';
  static const String networkNote =
      'Updates are the only thing CypherAuth uses the internet for: it asks '
      'GitHub for the latest release and downloads it. Nothing about your '
      'accounts is ever sent.';

  static String megabytes(int bytes) =>
      '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

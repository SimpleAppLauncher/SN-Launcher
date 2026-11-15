import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'platform_bridge.dart';
import 'settings_store.dart';
import 'update_feed.dart';

/// The release list the updater reads.
///
/// The whole list, not `/releases/latest`: everything this project published
/// from 0.2.0 onwards is a pre-release, and `/releases/latest` answers with
/// v0.1.3.
const String _releasesUrl =
    'https://api.github.com/repos/SimpleAppLauncher/SN-Launcher/releases';

/// The package name of the Google Play Store.
const String _playStore = 'com.android.vending';

/// How long one check is good for.
const Duration _checkInterval = Duration(hours: 24);

/// The name a download is written under while it is in progress, and the name
/// it is renamed to once it is whole.
const String _partName = 'update.apk.part';
const String _apkName = 'update.apk';

/// What the updater is doing.
///
/// Every state here is something that happened. There is no state that means
/// "probably fine", and no state that is entered on the way to another one:
/// a failed check is `failed` with the reason, never `upToDate`.
enum UpdateStatus {
  /// Nothing has been checked yet.
  idle,

  /// A check is running.
  checking,

  /// The published release is the one this build is.
  upToDate,

  /// The published release is older than this build.
  publishedReleaseIsOlder,

  /// A newer build exists and can be fetched.
  available,

  /// The build is being downloaded.
  downloading,

  /// The build is downloaded and has passed its checks.
  readyToInstall,

  /// The build has been handed to Android's installer.
  installing,

  /// The last thing that happened did not work.
  failed,

  /// This build came from somewhere that owns its own updates.
  notFromHere,
}

/// Where the release list comes from.
abstract interface class UpdateFeed {
  /// The body of the release list.
  Future<String> fetch();
}

/// How a build is fetched.
abstract interface class UpdateDownloader {
  /// Writes the file at [url] to [target], reporting the progress.
  Future<void> download(
    String url,
    File target, {
    required void Function(int received, int total) onProgress,
  });
}

/// How a build is installed.
///
/// The seam a Play-Store implementation would slot into: nothing above this
/// line knows how the file reaches the device.
abstract interface class UpdateInstaller {
  /// Hands [apk] to the installer.
  Future<InstallOutcome> install(File apk);
}

/// Finds, fetches and installs this app's own newer build.
///
/// The service owns the state machine and nothing else. The feed, the
/// downloader, the installer and the platform are all injected, so the whole
/// thing can be tested without a network and without a device.
class UpdateService extends ChangeNotifier {
  /// The service, with the real pieces behind it.
  factory UpdateService({
    PlatformBridge? platform,
    UpdateFeed? feed,
    UpdateDownloader? downloader,
    UpdateInstaller? installer,
    SettingsStore? settings,
  }) {
    final bridge = platform ?? const PlatformBridge();
    return UpdateService._(
      bridge,
      feed ?? const _HttpFeed(),
      downloader ?? const _HttpDownloader(),
      installer ?? _PlatformInstaller(bridge),
      settings,
    );
  }

  UpdateService._(
    this._platform,
    this._feed,
    this._downloader,
    this._installer,
    this._settings,
  );

  final PlatformBridge _platform;
  final UpdateFeed _feed;
  final UpdateDownloader _downloader;
  final UpdateInstaller _installer;
  final SettingsStore? _settings;

  UpdateStatus _status = UpdateStatus.idle;
  bool _needsInstallPermission = false;
  String _message = 'Never checked.';
  UpdateRelease? _release;
  UpdateAsset? _asset;
  File? _downloaded;
  double _progress = 0;
  AppInfo? _appInfo;

  /// What the updater is doing.
  UpdateStatus get status => _status;

  /// The sentence to show the user.
  ///
  /// It says what happened, not what was wished for: a check that failed says
  /// why it failed, and never says the app is up to date.
  String get message => _message;

  /// The release on offer, when there is one.
  UpdateRelease? get release => _release;

  /// How far the download has got, 0 to 1.
  double get progress => _progress;

  /// The verified APK, when there is one ready to install.
  File? get downloaded => _downloaded;

  /// Whether this build can update itself at all.
  ///
  /// True once the platform has described the build. A desktop never gets
  /// that far, and says so by staying false.
  bool get supported => _appInfo != null;

  /// Whether the user has asked for pre-release builds.
  bool get preReleasesEnabled =>
      _settings?.get(SettingKeys.updatePreReleases) == 'true';

  /// Switches the pre-releases on or off, and remembers it.
  void setPreReleasesEnabled(bool value) {
    final store = _settings;
    if (store != null) {
      unawaited(
        store.put(SettingKeys.updatePreReleases, value ? 'true' : 'false'),
      );
    }
    notifyListeners();
  }

  /// Looks for a newer build.
  ///
  /// [force] skips the once-a-day rule. The startup path calls it without
  /// [force] and the Settings button with it: a button that does nothing for
  /// a day is a broken button.
  Future<void> check({bool force = false}) async {
    await _settings?.load();

    if (!force && _checkedRecently()) {
      // The stamp is younger than a day, so there is nothing to say that was
      // not said already. The state is left alone: it is not wrong, and
      // overwriting it would throw away a result the user is reading.
      if (_status == UpdateStatus.idle) {
        _message = 'Checked recently — try again later.';
        notifyListeners();
      }
      return;
    }

    _set(UpdateStatus.checking, 'Checking…');

    final info = await _platform.appInfo();
    _appInfo = info;
    if (info == null) {
      // A platform with no package manager: a desktop build.
      _fail('Could not read this build’s version.');
      await _stamp();
      return;
    }

    if (info.installer == _playStore) {
      // The Play Store owns this build's updates, and a sideloaded APK cannot
      // replace a Play-installed one. Saying so now is better than fetching
      // ten megabytes that cannot be installed.
      _set(
        UpdateStatus.notFromHere,
        'This build was installed from the Play Store; updates come from there.',
      );
      await _stamp();
      return;
    }

    final String body;
    try {
      body = await _feed.fetch();
    } catch (e) {
      _fail('Could not check for updates: ${_reasonOf(e)}');
      await _stamp();
      return;
    }

    final releases = parseReleases(body);
    if (releases.isEmpty) {
      // A body that is not a release list: a rate limit, a captive portal, a
      // truncated answer. Reading that as "nothing new" would be a claim
      // nothing backs.
      _fail('Could not read the release list from GitHub.');
      await _stamp();
      return;
    }

    _offer(releases, info);
    await _stamp();
  }

  /// Fetches the build on offer and checks it.
  ///
  /// Nothing is fetched until the user asks for it: the connection may be
  /// metered and the file is ten megabytes.
  Future<void> download() async {
    final release = _release;
    final asset = _asset;
    if (release == null || asset == null) {
      _fail('There is no update to download.');
      return;
    }

    final info = await _appInfoOrRead();
    if (info == null) {
      _fail('Could not read this build’s version.');
      return;
    }
    if (info.filesDir.isEmpty) {
      _fail('Could not find this build’s files directory.');
      return;
    }

    final part = File('${info.filesDir}/$_partName');
    final target = File('${info.filesDir}/$_apkName');

    _progress = 0;
    _set(UpdateStatus.downloading, 'Downloading ${release.version}…');

    try {
      final directory = Directory(info.filesDir);
      if (!await directory.exists()) await directory.create(recursive: true);
      await _downloader.download(
        asset.url,
        part,
        onProgress: (received, total) {
          _progress =
              total > 0 ? (received / total).clamp(0.0, 1.0).toDouble() : 0.0;
          notifyListeners();
        },
      );
      // The file is whole only once it has been renamed, so a half-written
      // download is never something the installer can be handed.
      if (await target.exists()) await target.delete();
      await part.rename(target.path);
    } catch (e) {
      // A download that failed leaves nothing behind: a half-written file in
      // the app's own directory is rubbish, and the next download would find
      // it and think it was the last one.
      await _delete(part);
      await _delete(target);
      _progress = 0;
      _fail('Could not download the update: ${_reasonOf(e)}');
      return;
    }

    final verification = await _platform.verifyUpdate(target.path);
    if (!verification.ok) {
      // A file that failed its checks is not kept. It is not an update, and
      // leaving it on disk is leaving rubbish in the app's own directory.
      await _delete(target);
      _progress = 0;
      _fail(
        verification.reason.isEmpty
            ? 'The download did not pass its checks.'
            : verification.reason,
      );
      return;
    }

    _downloaded = target;
    _progress = 1;
    _set(UpdateStatus.readyToInstall, 'Ready to install ${release.version}.');
  }

  /// Hands the downloaded build to Android's installer.
  Future<void> install() async {
    final file = _downloaded;
    if (_status != UpdateStatus.readyToInstall || file == null) {
      // Nothing has been downloaded and checked. The state that says so is
      // left alone: it is telling the truth, and overwriting it would hide
      // the offer the user is reading.
      return;
    }

    // The platform is asked again rather than the answer being remembered:
    // the installer of a build is the one thing the updater must not get
    // wrong, and asking costs nothing.
    final info = await _platform.appInfo();
    if (info != null) _appInfo = info;
    if (info != null && info.installer == _playStore) {
      _set(
        UpdateStatus.notFromHere,
        'This build was installed from the Play Store; updates come from there.',
      );
      return;
    }

    _set(UpdateStatus.installing, 'Handing the update to Android…');

    final outcome = await _installer.install(file);
    if (!outcome.started) {
      _needsInstallPermission = outcome.needsPermission;
      _fail(
        outcome.reason.isEmpty
            ? 'Android did not start the installer.'
            : outcome.reason,
      );
      return;
    }
    _needsInstallPermission = false;
    _set(UpdateStatus.installing, 'Handed to Android’s installer.');
  }

  /// Whether the last refusal was the one the user can fix.
  ///
  /// Android asks each app separately for permission to install packages from
  /// outside the store. Until that is granted, no update can be installed, and
  /// the only thing that can change it is a screen in Settings — so this is
  /// what the settings page offers instead of a dead end.
  bool get needsInstallPermission => _needsInstallPermission;

  /// Opens that screen.
  Future<void> openInstallSettings() async {
    await _platform.openInstallSettings();
  }

  /// Picks the release to offer, and says what was found.
  void _offer(List<UpdateRelease> releases, AppInfo info) {
    final installed = info.versionName;

    final preReleases = releases.where(_isPreRelease).toList();
    final stable = releases.where((r) => !_isPreRelease(r)).toList();
    // The releases this build would be offered: the pre-releases only when
    // the user has asked for them.
    final considered = preReleasesEnabled ? releases : stable;

    final candidates = considered
        .where((r) => isNewerVersion(r.version, installed))
        .toList();

    if (candidates.isNotEmpty) {
      // A stable release is preferred over a pre-release of the same age.
      final stableCandidates =
          candidates.where((r) => !_isPreRelease(r)).toList();
      final chosen = _newest(
        stableCandidates.isNotEmpty ? stableCandidates : candidates,
      )!;
      _release = chosen;
      _asset = assetFor(
        chosen,
        applicationId: info.applicationId,
        abi: info.abi,
      );
      if (_asset == null) {
        // The release exists; the file for this variant and this ABI does
        // not. Offering one anyway would offer a file that cannot run.
        _fail('There is no build for this device yet.');
        return;
      }
      _set(
        UpdateStatus.available,
        _isPreRelease(chosen)
            ? '${chosen.version} is available as a pre-release.'
            : '${chosen.version} is available to install.',
      );
      return;
    }

    // Nothing newer that this build would be offered. The newest pre-release
    // is still worth mentioning: the user can ask for it.
    final pending = preReleasesEnabled
        ? null
        : preReleases
              .where((r) => isNewerVersion(r.version, installed))
              .firstOrNull;
    final note = pending == null
        ? ''
        : ' ${pending.version} is available as a pre-release. '
            'Turn pre-releases on to install it.';

    // The published release is the one GitHub listed first: the most recent
    // publication there is.
    final published = considered.isEmpty ? null : considered.first;
    if (published != null &&
        isNewerVersion(installed, published.version)) {
      // The published release is older than the build that is running. This
      // is not "up to date": the published thing is behind.
      _set(
        UpdateStatus.publishedReleaseIsOlder,
        'The published release is ${published.version}. '
        'This build is $installed.$note',
      );
      return;
    }

    _set(UpdateStatus.upToDate, '$installed is the latest build.$note');
  }

  /// The release with the highest version, or null for an empty list.
  ///
  /// Ties keep the one GitHub listed first: the list is published newest
  /// first, and `0.4.0-rc2` and `0.4.0-rc3` compare as the same triple.
  UpdateRelease? _newest(List<UpdateRelease> releases) {
    UpdateRelease? best;
    for (final release in releases) {
      final current = best;
      if (current == null || isNewerVersion(release.version, current.version)) {
        best = release;
      }
    }
    return best;
  }

  /// Whether a release is a pre-release.
  ///
  /// GitHub's own flag, or a version with a suffix. Either one is enough: a
  /// release GitHub calls a pre-release must not be offered as a stable one,
  /// and a version carrying `-rc1` is one whatever the flag says.
  bool _isPreRelease(UpdateRelease release) =>
      release.prerelease || isPreReleaseVersion(release.version);

  /// The app's own details, read once and remembered.
  Future<AppInfo?> _appInfoOrRead() async {
    final cached = _appInfo;
    if (cached != null) return cached;
    final info = await _platform.appInfo();
    _appInfo = info;
    return info;
  }

  /// Whether the last check was less than a day ago.
  bool _checkedRecently() {
    final raw = _settings?.get(SettingKeys.lastUpdateCheck);
    if (raw == null) return false;
    final stamp = int.tryParse(raw);
    if (stamp == null) return false;
    // A stamp from the future — the device's clock moved — still counts as
    // recent, because as far as this device is concerned it just happened.
    return DateTime.now().millisecondsSinceEpoch - stamp <
        _checkInterval.inMilliseconds;
  }

  /// Writes the stamp that keeps the app to one check a day.
  Future<void> _stamp() async {
    final store = _settings;
    if (store == null) return;
    await store.put(
      SettingKeys.lastUpdateCheck,
      DateTime.now().millisecondsSinceEpoch.toString(),
    );
  }

  void _set(UpdateStatus status, String message) {
    _status = status;
    _message = message;
    notifyListeners();
  }

  void _fail(String reason) => _set(UpdateStatus.failed, reason);

  /// Deletes a file, and does not mind if it is already gone.
  Future<void> _delete(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {
      // A file that will not delete is a nuisance, not a failure of the
      // update: the download has already failed, and saying so twice helps
      // nobody.
    }
  }
}

/// The reason in a failure, in words the user can read.
String _reasonOf(Object error) {
  if (error is HttpException) return error.message;
  if (error is SocketException) return error.message;
  return error.toString();
}

/// The release list, over HTTP.
class _HttpFeed implements UpdateFeed {
  const _HttpFeed();

  @override
  Future<String> fetch() async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10)
      ..idleTimeout = const Duration(seconds: 20);
    try {
      final request = await client.getUrl(Uri.parse(_releasesUrl));
      // GitHub refuses a request that carries no User-Agent.
      request.headers.set(HttpHeaders.userAgentHeader, 'SN-Launcher');
      request.headers.set(
        HttpHeaders.acceptHeader,
        'application/vnd.github+json',
      );
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        await response.drain<void>();
        throw HttpException(
          'GitHub answered ${response.statusCode}.',
          uri: request.uri,
        );
      }
      return await response.transform(utf8.decoder).join();
    } finally {
      client.close(force: true);
    }
  }
}

/// The download, over HTTP.
class _HttpDownloader implements UpdateDownloader {
  const _HttpDownloader();

  @override
  Future<void> download(
    String url,
    File target, {
    required void Function(int received, int total) onProgress,
  }) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15)
      ..idleTimeout = const Duration(seconds: 30);
    IOSink? sink;
    try {
      final request = await client.getUrl(Uri.parse(url));
      request.headers.set(HttpHeaders.userAgentHeader, 'SN-Launcher');
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        await response.drain<void>();
        throw HttpException(
          'The server answered ${response.statusCode}.',
          uri: request.uri,
        );
      }
      final total = response.contentLength;
      sink = target.openWrite();
      var received = 0;
      await for (final chunk in response) {
        received += chunk.length;
        sink.add(chunk);
        onProgress(received, total);
      }
      await sink.flush();
      await sink.close();
      sink = null;
    } finally {
      await sink?.close();
      client.close(force: true);
    }
  }
}

/// The installer, through the platform bridge.
class _PlatformInstaller implements UpdateInstaller {
  const _PlatformInstaller(this._platform);

  final PlatformBridge _platform;

  @override
  Future<InstallOutcome> install(File apk) async {
    final outcome = await _platform.installUpdate(apk.path);
    return outcome ??
        const InstallOutcome(
          started: false,
          reason: 'Android did not start the installer.',
        );
  }
}

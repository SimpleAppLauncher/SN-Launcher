import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sn_launcher/src/services/platform_bridge.dart';
import 'package:sn_launcher/src/services/settings_store.dart';
import 'package:sn_launcher/src/services/update_service.dart';

/// The application id of the reduced build.
const String _appId = 'dev.snlauncher.snlauncher';

/// The ABI of the device the fixtures are written for.
const String _abi = 'arm64-v8a';

/// The package name of the Play Store.
const String _playStore = 'com.android.vending';

/// One release, as GitHub would send it.
///
/// [assetVersion] is the version in the asset's file name. It is separate from
/// the tag because a release can be tagged one thing and published with a
/// build of another — which is exactly the case the asset matcher refuses.
Map<String, Object?> _release({
  required String tag,
  bool prerelease = false,
  String? assetVersion,
  String abi = _abi,
  String applicationId = _appId,
}) {
  final assets = <Map<String, Object?>>[];
  if (assetVersion != null) {
    final prefix = applicationId == 'dev.snlauncher.snlauncher.ef'
        ? 'SN-Launcher-ef-'
        : 'SN-Launcher-';
    final name = '$prefix$assetVersion-$abi.apk';
    assets.add({
      'name': name,
      'browser_download_url': 'https://example.invalid/$name',
      'size': 10485760,
    });
  }
  return {
    'tag_name': tag,
    'name': tag,
    'prerelease': prerelease,
    'body': 'What changed in $tag.',
    'assets': assets,
  };
}

/// A release list, as the feed would send it.
String _payload(List<Map<String, Object?>> releases) => jsonEncode(releases);

/// A platform that answers the way a phone would.
class _FakePlatform extends PlatformBridge {
  _FakePlatform({this.info});

  /// What the platform says about this build. Null on a platform that cannot
  /// say — a desktop, or an Android whose native side is not there.
  AppInfo? info;

  /// What the platform says about a downloaded APK.
  UpdateVerification verification = const UpdateVerification(ok: true, reason: '');

  /// What the platform says when it is asked to install an APK.
  InstallOutcome? installOutcome = const InstallOutcome(started: true, reason: '');

  int appInfoCalls = 0;
  int verifyCalls = 0;
  int installCalls = 0;

  /// The path the last verified file had.
  String? verifiedPath;

  /// The path the last install was given.
  String? installedPath;

  @override
  Future<AppInfo?> appInfo() async {
    appInfoCalls++;
    return info;
  }

  @override
  Future<UpdateVerification> verifyUpdate(String path) async {
    verifyCalls++;
    verifiedPath = path;
    return verification;
  }

  @override
  Future<InstallOutcome?> installUpdate(String path) async {
    installCalls++;
    installedPath = path;
    return installOutcome;
  }
}

/// A feed that answers with a fixed body, or fails.
class _FakeFeed implements UpdateFeed {
  _FakeFeed({this.body = ''});

  String body;

  /// The failure the feed throws, when it is meant to fail.
  Object? error;

  /// How many times the feed was asked.
  int calls = 0;

  @override
  Future<String> fetch() async {
    calls++;
    final failure = error;
    if (failure != null) throw failure;
    return body;
  }
}

/// A downloader that writes bytes to the file it is given.
class _FakeDownloader implements UpdateDownloader {
  _FakeDownloader();

  /// The failure the download throws, when it is meant to fail.
  Object? error;

  int calls = 0;
  String? url;
  File? target;

  @override
  Future<void> download(
    String url,
    File target, {
    required void Function(int received, int total) onProgress,
  }) async {
    calls++;
    this.url = url;
    this.target = target;
    // The bytes are written before the failure, so the service has something
    // half-written to clean up — which is what a full disk leaves behind.
    await target.writeAsBytes(const [1, 2, 3, 4]);
    onProgress(4, 4);
    final failure = error;
    if (failure != null) throw failure;
  }
}

/// An installer that records the file it was given.
class _FakeInstaller implements UpdateInstaller {
  _FakeInstaller();

  InstallOutcome outcome = const InstallOutcome(started: true, reason: '');

  int calls = 0;
  File? received;

  @override
  Future<InstallOutcome> install(File apk) async {
    calls++;
    received = apk;
    return outcome;
  }
}

/// The build this app says it is.
AppInfo _appInfo({
  String version = '0.3.0',
  String installer = '',
  String filesDir = '',
  String applicationId = _appId,
  String abi = _abi,
}) {
  return AppInfo(
    versionName: version,
    versionCode: 11001,
    applicationId: applicationId,
    abi: abi,
    installer: installer,
    canInstallPackages: true,
    filesDir: filesDir,
  );
}

void main() {
  // The settings store reaches for a platform channel, and the channel needs
  // a binding even when the native side is not there.
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  late Directory filesDir;
  late SettingsStore settings;
  late _FakePlatform platform;
  late _FakeFeed feed;
  late _FakeDownloader downloader;
  late _FakeInstaller installer;
  late UpdateService service;

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('sn_update_service');
    filesDir = Directory('${tmp.path}/files')..createSync();
    settings = SettingsStore(fallbackPath: '${tmp.path}/settings.json');
    await settings.load();
    platform = _FakePlatform(info: _appInfo(filesDir: filesDir.path));
    feed = _FakeFeed(body: _payload([_release(tag: 'v0.4.0', assetVersion: '0.4.0')]));
    downloader = _FakeDownloader();
    installer = _FakeInstaller();
    service = UpdateService(
      platform: platform,
      feed: feed,
      downloader: downloader,
      installer: installer,
      settings: settings,
    );
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  group('before anything has been checked', () {
    test('a service that has never checked says so', () {
      expect(service.status, UpdateStatus.idle);
      expect(service.message, 'Never checked.');
    });

    test('the service is not supported until the platform describes the build',
        () async {
      expect(service.supported, isFalse);

      await service.check();

      expect(service.supported, isTrue);
    });
  });

  group('checking for an update', () {
    test('a newer release is offered', () async {
      await service.check();

      expect(service.status, UpdateStatus.available);
      expect(service.release?.version, '0.4.0');
      expect(service.message, contains('0.4.0'));
    });

    test('the same version leaves the service up to date', () async {
      feed.body = _payload([
        _release(tag: 'v0.3.0', assetVersion: '0.3.0'),
      ]);

      await service.check();

      expect(service.status, UpdateStatus.upToDate);
      expect(service.message, contains('0.3.0'));
      expect(service.message, contains('latest'));
    });

    test('an older published release has a state of its own', () async {
      feed.body = _payload([
        _release(tag: 'v0.1.3', assetVersion: '0.1.3'),
      ]);

      await service.check();

      expect(service.status, UpdateStatus.publishedReleaseIsOlder);
      expect(service.message, contains('0.1.3'));
      expect(service.message, contains('0.3.0'));
      // It must never read as "up to date": the published release is older
      // than this build, and saying otherwise would be a lie.
      expect(service.message.toLowerCase(), isNot(contains('up to date')));
      expect(service.message, isNot(contains('latest')));
    });

    test('a feed that throws fails with the reason', () async {
      feed.error = Exception('GitHub is unreachable');

      await service.check();

      expect(service.status, UpdateStatus.failed);
      expect(service.message, contains('GitHub is unreachable'));
      expect(service.message.toLowerCase(), isNot(contains('up to date')));
      expect(service.message, isNot(contains('latest')));
    });

    test('a release with no build for this device says so', () async {
      // The release exists; the file for this ABI and this variant does not.
      feed.body = _payload([
        _release(tag: 'v0.4.0', assetVersion: '0.4.0', abi: 'armeabi-v7a'),
      ]);

      await service.check();

      expect(service.status, UpdateStatus.failed);
      expect(service.message, contains('no build for this device'));
      expect(service.downloaded, isNull);
    });

    test('an empty release list is not an up-to-date', () async {
      // GitHub answers a rate-limited request with a body that is not a
      // release list. Reading that as "nothing new" would be a claim the app
      // has no evidence for.
      feed.body = '{"message":"API rate limit exceeded"}';

      await service.check();

      expect(service.status, UpdateStatus.failed);
      expect(service.message, isNot(contains('up to date')));
      expect(service.message, isNot(contains('latest')));
    });

    test('a published version that cannot be read is not offered', () async {
      // A tag that is not a version. It is not evidence of a newer build, so
      // nothing is offered — but nothing has failed either, so this is not a
      // failure.
      feed.body = _payload([
        _release(tag: 'vnot-a-version'),
      ]);

      await service.check();

      expect(service.release, isNull);
      expect(service.downloaded, isNull);
      expect(service.status, UpdateStatus.upToDate);
    });

    test('the check never downloads anything', () async {
      await service.check();

      expect(downloader.calls, 0);
    });

    test('a build installed by the Play Store is refused before the feed is '
        'read', () async {
      platform.info = _appInfo(filesDir: filesDir.path, installer: _playStore);

      await service.check();

      expect(service.status, UpdateStatus.notFromHere);
      expect(service.message, contains('Play Store'));
      expect(feed.calls, 0);
    });

    test('a platform that cannot describe the build fails', () async {
      // The desktop case: there is no Android package manager to ask.
      platform.info = null;

      await service.check();

      expect(service.status, UpdateStatus.failed);
      expect(service.supported, isFalse);
      expect(service.message, isNot(contains('up to date')));
    });
  });

  group('pre-releases', () {
    test('a pre-release is not offered while pre-releases are off', () async {
      feed.body = _payload([
        _release(tag: 'v0.4.0-rc1', prerelease: true, assetVersion: '0.4.0-rc1'),
        _release(tag: 'v0.3.0', assetVersion: '0.3.0'),
      ]);

      await service.check();

      expect(service.status, UpdateStatus.upToDate);
      expect(service.message, contains('0.4.0-rc1'));
      expect(service.message, contains('pre-release'));
      expect(service.release, isNull);
    });

    test('a pre-release is offered when the user has asked for one', () async {
      feed.body = _payload([
        _release(tag: 'v0.4.0-rc1', prerelease: true, assetVersion: '0.4.0-rc1'),
        _release(tag: 'v0.3.0', assetVersion: '0.3.0'),
      ]);
      service.setPreReleasesEnabled(true);

      await service.check();

      expect(service.status, UpdateStatus.available);
      expect(service.release?.version, '0.4.0-rc1');
      expect(service.message, contains('pre-release'));
    });

    test('the pre-release switch is remembered', () async {
      expect(service.preReleasesEnabled, isFalse);

      service.setPreReleasesEnabled(true);

      expect(service.preReleasesEnabled, isTrue);
      expect(settings.get(SettingKeys.updatePreReleases), 'true');

      service.setPreReleasesEnabled(false);

      expect(service.preReleasesEnabled, isFalse);
      expect(settings.get(SettingKeys.updatePreReleases), 'false');
    });
  });

  group('the 24-hour stamp', () {
    test('a check made moments ago is not repeated', () async {
      await settings.put(
        SettingKeys.lastUpdateCheck,
        DateTime.now().millisecondsSinceEpoch.toString(),
      );

      await service.check();

      expect(feed.calls, 0);
      expect(service.status, UpdateStatus.idle);
      expect(service.message, 'Checked recently — try again later.');
    });

    test('a forced check ignores the stamp', () async {
      await settings.put(
        SettingKeys.lastUpdateCheck,
        DateTime.now().millisecondsSinceEpoch.toString(),
      );

      await service.check(force: true);

      expect(feed.calls, 1);
      expect(service.status, UpdateStatus.available);
    });

    test('a check writes the stamp', () async {
      expect(settings.get(SettingKeys.lastUpdateCheck), isNull);

      await service.check();

      expect(settings.get(SettingKeys.lastUpdateCheck), isNotNull);
    });
  });

  group('downloading', () {
    test('the download ends ready to install', () async {
      await service.check();

      final seen = <UpdateStatus>[];
      service.addListener(() => seen.add(service.status));

      await service.download();

      expect(seen, contains(UpdateStatus.downloading));
      expect(service.status, UpdateStatus.readyToInstall);
      expect(service.progress, 1);
      expect(service.downloaded, isNotNull);
    });

    test('the download is written to the files directory and renamed',
        () async {
      await service.check();

      await service.download();

      expect(downloader.target?.path, endsWith('update.apk.part'));
      expect(
        File('${filesDir.path}/update.apk').existsSync(),
        isTrue,
      );
      expect(platform.verifiedPath, '${filesDir.path}/update.apk');
    });

    test('a download that fails leaves nothing behind', () async {
      await service.check();
      downloader.error = Exception('No space left on device');

      await service.download();

      expect(service.status, UpdateStatus.failed);
      expect(service.message, contains('No space left on device'));
      expect(service.downloaded, isNull);
      expect(
        filesDir.listSync(),
        isEmpty,
      );
    });

    test('a download that fails its checks is deleted', () async {
      await service.check();
      platform.verification = const UpdateVerification(
        ok: false,
        reason: 'The download was signed with a different key.',
      );

      await service.download();

      expect(service.status, UpdateStatus.failed);
      expect(service.message, contains('different key'));
      expect(service.downloaded, isNull);
      expect(filesDir.listSync(), isEmpty);
    });
  });

  group('installing', () {
    test('the installer is given the verified file', () async {
      await service.check();
      await service.download();

      await service.install();

      expect(installer.calls, 1);
      expect(installer.received?.path, service.downloaded?.path);
      expect(service.status, UpdateStatus.installing);
    });

    test('a build installed by the Play Store is refused', () async {
      await service.check();
      await service.download();
      platform.info = _appInfo(filesDir: filesDir.path, installer: _playStore);

      await service.install();

      expect(service.status, UpdateStatus.notFromHere);
      expect(service.message, contains('Play Store'));
      expect(installer.calls, 0);
    });

    test('an install the platform refuses says why', () async {
      await service.check();
      await service.download();
      installer.outcome = const InstallOutcome(
        started: false,
        reason: 'SN-Launcher needs permission to install updates',
      );

      await service.install();

      expect(service.status, UpdateStatus.failed);
      expect(service.message, contains('permission to install updates'));
    });

    test('installing without a download does nothing', () async {
      await service.check();

      await service.install();

      expect(installer.calls, 0);
      expect(service.status, UpdateStatus.available);
    });
  });
}

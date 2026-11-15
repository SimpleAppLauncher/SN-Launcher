import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sn_launcher/src/services/platform_bridge.dart';
import 'package:sn_launcher/src/services/update_service.dart';
import 'package:sn_launcher/src/theme/ambient_palette.dart';
import 'package:sn_launcher/src/theme/nest_metrics.dart';
import 'package:sn_launcher/src/theme/nest_type.dart';
import 'package:sn_launcher/src/widgets/update_section.dart';

/// What the update section says, in every state it can be in.
///
/// The section is the only place the user finds out what the updater did, so
/// what it says is the feature. Two rules are checked in every state: it must
/// not say "up to date" unless the updater really is up to date, and it must
/// not say anything at all that the updater did not do.
///
/// The service is driven through its own API rather than having its state
/// poked, so the section is tested against a service that really got there.
const _appId = 'dev.snlauncher.snlauncher';
const _abi = 'arm64-v8a';

String _releaseJson(
  String tag, {
  bool prerelease = false,
  bool withAsset = true,
}) {
  final version = tag.replaceFirst('v', '');
  // A list, because that is what the releases endpoint returns.
  return jsonEncode([
    {
      'tag_name': tag,
      'name': tag,
      'prerelease': prerelease,
      'body': 'What changed in $tag.',
      'assets': withAsset
          ? [
              {
                'name': 'SN-Launcher-$version-$_abi.apk',
                'browser_download_url': 'https://example.invalid/$tag.apk',
                'size': 10485760,
                'digest': 'sha256:${'0' * 64}',
              },
            ]
          : <Object?>[],
    },
  ]);
}

class _FakePlatform extends PlatformBridge {
  _FakePlatform({this.info});

  AppInfo? info;

  /// How many times the app was sent to the screen where the install
  /// permission is granted.
  int installSettingsCalls = 0;

  @override
  Future<AppInfo?> appInfo() async => info;

  @override
  Future<UpdateVerification> verifyUpdate(String path) async =>
      const UpdateVerification(ok: true, reason: '');

  @override
  Future<InstallOutcome?> installUpdate(String path) async =>
      const InstallOutcome(started: true, reason: '');

  @override
  Future<bool> openInstallSettings() async {
    installSettingsCalls++;
    return true;
  }
}

class _FakeFeed implements UpdateFeed {
  String body = '';
  Object? error;

  /// Held open so a check can be observed while it is running.
  Completer<void>? gate;

  @override
  Future<String> fetch() async {
    await gate?.future;
    final failure = error;
    if (failure != null) throw failure;
    return body;
  }
}

class _FakeDownloader implements UpdateDownloader {
  _FakeDownloader();

  /// Held open so the download can be observed while it is running.
  ///
  /// It is opened *before* anything is written, so a download that is left
  /// hanging never leaves a half-written file behind.
  Completer<void>? gate;

  @override
  Future<void> download(
    String url,
    File target, {
    required void Function(int received, int total) onProgress,
  }) async {
    await gate?.future;
    await target.writeAsBytes(const [1, 2, 3, 4]);
    onProgress(2, 4);
    onProgress(4, 4);
  }
}

class _FakeInstaller implements UpdateInstaller {
  @override
  Future<InstallOutcome> install(File apk) async =>
      const InstallOutcome(started: true, reason: '');
}

/// An installer that refuses the way Android does when the app has not been
/// granted permission to install packages from outside the store.
class _RefusingInstaller implements UpdateInstaller {
  @override
  Future<InstallOutcome> install(File apk) async => const InstallOutcome(
        started: false,
        reason: 'SN-Launcher needs permission to install updates.',
        needsPermission: true,
      );
}

AppInfo _info({
  String version = '0.3.0',
  String installer = '',
  String filesDir = '',
}) => AppInfo(
      versionName: version,
      versionCode: 11001,
      applicationId: _appId,
      abi: _abi,
      installer: installer,
      canInstallPackages: true,
      filesDir: filesDir,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;

  setUp(() {
    // Each test gets its own directory: the downloaded file has a fixed
    // name, and two test files running at once would fight over it.
    tmp = Directory.systemTemp.createTempSync('sn_update_section');
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  /// A service driven into the state the test wants.
  Future<UpdateService> serviceIn(
    WidgetTester tester,
    UpdateStatus want, {
    String version = '0.3.0',
    String installer = '',
  }) async {
    final platform = _FakePlatform(
      info: _info(
        version: version,
        installer: installer,
        filesDir: tmp.path,
      ),
    );
    final feed = _FakeFeed();
    final downloader = _FakeDownloader();
    final service = UpdateService(
      platform: platform,
      feed: feed,
      downloader: downloader,
      installer: _FakeInstaller(),
    );

    switch (want) {
      case UpdateStatus.idle:
        break;
      case UpdateStatus.checking:
        // A feed that never answers, so the service is caught mid-check.
        feed.gate = Completer<void>();
        unawaited(service.check());
        break;
      case UpdateStatus.upToDate:
        feed.body = _releaseJson('v$version');
        await service.check();
        break;
      case UpdateStatus.publishedReleaseIsOlder:
        feed.body = _releaseJson('v0.1.3');
        await service.check();
        break;
      case UpdateStatus.available:
        feed.body = _releaseJson('v0.4.0');
        await service.check();
        break;
      case UpdateStatus.downloading:
        feed.body = _releaseJson('v0.4.0');
        await service.check();
        downloader.gate = Completer<void>();
        unawaited(service.download());
        break;
      case UpdateStatus.readyToInstall:
        feed.body = _releaseJson('v0.4.0');
        await service.check();
        // The download writes to the disk, and a widget test runs in a zone
        // where the disk does not move. runAsync is the way out.
        await tester.runAsync(() => service.download());
        break;
      case UpdateStatus.failed:
        feed.error = Exception('GitHub is unreachable');
        await service.check();
        break;
      case UpdateStatus.installing:
        feed.body = _releaseJson('v0.4.0');
        await service.check();
        await tester.runAsync(() async {
          await service.download();
          await service.install();
        });
        break;
      case UpdateStatus.notFromHere:
        feed.body = _releaseJson('v0.4.0');
        await service.check();
        break;
    }
    return service;
  }

  /// The section, rendered.
  Future<void> show(WidgetTester tester, UpdateService service) async {
    final metrics = NestMetrics.forSize(const Size(1024, 600));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: UpdateSection(
              updates: service,
              metrics: metrics,
              type: NestType(metrics),
              palette: AmbientPalette.of(NestTheme.night),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  String textOf(WidgetTester tester) => tester
      .widgetList<Text>(find.byType(Text))
      .map((t) => t.data ?? '')
      .join(' | ');

  testWidgets('nothing has been checked yet, and it says so', (tester) async {
    final service = await serviceIn(tester, UpdateStatus.idle);
    await show(tester, service);

    expect(textOf(tester), contains('Never checked'));
  });

  testWidgets('a check in progress says it is checking', (tester) async {
    final service = await serviceIn(tester, UpdateStatus.checking);
    await show(tester, service);

    expect(textOf(tester), contains('Checking'));
  });

  testWidgets('the latest build says which version is latest',
      (tester) async {
    final service = await serviceIn(tester, UpdateStatus.upToDate);
    await show(tester, service);

    expect(textOf(tester), contains('0.3.0'));
    expect(textOf(tester), contains('latest'));
  });

  testWidgets('a published release that is older says both versions',
      (tester) async {
    final service = await serviceIn(tester, UpdateStatus.publishedReleaseIsOlder);
    await show(tester, service);

    final text = textOf(tester);
    expect(text, contains('0.1.3'));
    expect(text, contains('0.3.0'));
    expect(text, isNot(contains('latest')));
  });

  testWidgets('an available update offers to install it', (tester) async {
    final service = await serviceIn(tester, UpdateStatus.available);
    await show(tester, service);

    expect(textOf(tester), contains('0.4.0'));
    expect(find.text('Download and install'), findsOneWidget);
  });

  testWidgets('a download in progress shows progress', (tester) async {
    final service = await serviceIn(tester, UpdateStatus.downloading);
    await show(tester, service);

    expect(textOf(tester), contains('Downloading'));
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
  });

  testWidgets('a checked download offers to install it', (tester) async {
    final service = await serviceIn(tester, UpdateStatus.readyToInstall);
    await show(tester, service);

    expect(find.text('Install'), findsOneWidget);
  });

  testWidgets('a failure says why', (tester) async {
    final service = await serviceIn(tester, UpdateStatus.failed);
    await show(tester, service);

    expect(textOf(tester), contains('GitHub is unreachable'));
  });

  testWidgets('a Play Store build says the Play Store has the updates',
      (tester) async {
    final service = await serviceIn(
      tester,
      UpdateStatus.notFromHere,
      installer: 'com.android.vending',
    );
    await show(tester, service);

    expect(textOf(tester), contains('Play Store'));
  });

  testWidgets('no state but the up-to-date one claims to be up to date',
      (tester) async {
    for (final status in UpdateStatus.values) {
      final service = await serviceIn(tester, status);
      await show(tester, service);
      final text = textOf(tester);
      if (status == UpdateStatus.upToDate) {
        expect(text.toLowerCase(), contains('latest'));
      } else {
        expect(
          text.toLowerCase(),
          isNot(contains('up to date')),
          reason: 'the $status state claimed to be up to date',
        );
      }
    }
  });

  testWidgets('there is a way to ask for a check', (tester) async {
    final service = await serviceIn(tester, UpdateStatus.idle);
    await show(tester, service);

    expect(find.text('Check for updates'), findsOneWidget);
  });

  testWidgets('the pre-release switch is offered', (tester) async {
    final service = await serviceIn(tester, UpdateStatus.idle);
    await show(tester, service);

    expect(find.text('Pre-release builds'), findsOneWidget);
  });

  testWidgets('an install Android will not allow offers the way to fix it',
      (tester) async {
    // The message "SN-Launcher needs permission to install updates" is only
    // useful if the user can act on it. Without a button to open that screen
    // the card is a dead end.
    final platform = _FakePlatform(
      info: _info(version: '0.3.0', filesDir: tmp.path),
    );
    final feed = _FakeFeed();
    final downloader = _FakeDownloader();
    final service = UpdateService(
      platform: platform,
      feed: feed,
      downloader: downloader,
      installer: _RefusingInstaller(),
    );
    feed.body = _releaseJson('v0.4.0');
    await service.check();
    await tester.runAsync(() => service.download());
    await service.install();

    await show(tester, service);

    expect(find.text('Open settings'), findsOneWidget);
    await tester.tap(find.text('Open settings'));
    await tester.pump();
    expect(platform.installSettingsCalls, 1);
  });
}

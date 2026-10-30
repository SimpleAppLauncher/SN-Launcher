import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sn_launcher/src/services/device_media_watcher.dart';
import 'package:sn_launcher/src/services/playback_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel(DeviceMediaWatcher.channelName);
  var granted = false;
  var commandAccepted = false;
  final commands = <String>[];
  Map<String, Object?>? session;

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    granted = false;
    commandAccepted = false;
    commands.clear();
    session = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          switch (call.method) {
            case 'hasPermission':
              return granted;
            case 'sessions':
              return session;
            case 'command':
              final action = (call.arguments as Map)['action'] as String? ?? '';
              commands.add(action);
              return commandAccepted;
            case 'openSettings':
              return true;
          }
          return null;
        });
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('desktop has no media-session registry and says so', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    final watcher = DeviceMediaWatcher(channel: channel);
    addTearDown(watcher.dispose);

    expect(watcher.supported, isFalse);
    await watcher.probe();
    expect(watcher.hasPermission, isFalse);
    expect(watcher.session, isNull);
    expect(watcher.explanation, 'Now playing is only available on Android.');
  });

  test(
    'without notification access it does not pretend to see a session',
    () async {
      final watcher = DeviceMediaWatcher(channel: channel);
      addTearDown(watcher.dispose);

      expect(watcher.supported, isTrue);
      await watcher.probe();

      expect(watcher.hasPermission, isFalse);
      expect(watcher.session, isNull);
      expect(watcher.explanation, contains('Allow notification access'));
    },
  );

  test('granted access adopts the other app session', () async {
    granted = true;
    session = {
      'package': 'com.spotify.music',
      'title': 'Nightcall',
      'artist': 'Kavinsky',
      'album': '',
      'artworkPath': '',
      'playing': true,
      'positionMs': 1000,
      'durationMs': 200000,
    };
    final watcher = DeviceMediaWatcher(channel: channel);
    addTearDown(watcher.dispose);

    await watcher.probe();

    expect(watcher.hasPermission, isTrue);
    expect(watcher.session?.title, 'Nightcall');
    expect(watcher.session?.artist, 'Kavinsky');
    expect(watcher.session?.playing, isTrue);
    expect(watcher.explanation, isEmpty);
  });

  test('a session that stops playing keeps its paused state', () async {
    granted = true;
    session = {
      'package': 'com.google.android.apps.youtube.music',
      'title': 'Nightcall',
      'artist': 'Kavinsky',
      'album': '',
      'artworkPath': '',
      'playing': false,
      'positionMs': 1000,
      'durationMs': 200000,
    };
    final watcher = DeviceMediaWatcher(channel: channel);
    addTearDown(watcher.dispose);

    await watcher.probe();

    expect(watcher.session?.playing, isFalse);
    expect(watcher.session?.title, 'Nightcall');
  });

  test(
    'transport actions are adopted only when the other app offers them',
    () async {
      granted = true;
      session = {
        'package': 'com.spotify.music',
        'title': 'Nightcall',
        'artist': 'Kavinsky',
        'album': '',
        'artworkPath': '',
        'playing': true,
        'positionMs': 1000,
        'durationMs': 200000,
        'canPlay': true,
        'canPause': true,
        'canNext': true,
        'canPrevious': false,
      };
      final watcher = DeviceMediaWatcher(channel: channel);
      addTearDown(watcher.dispose);

      await watcher.probe();

      expect(watcher.session?.canPlay, isTrue);
      expect(watcher.session?.canPause, isTrue);
      expect(watcher.session?.canNext, isTrue);
      expect(watcher.session?.canPrevious, isFalse);
    },
  );

  test(
    'a transport command reaches the session and refreshes its state',
    () async {
      granted = true;
      commandAccepted = true;
      session = {
        'package': 'com.spotify.music',
        'title': 'Nightcall',
        'artist': 'Kavinsky',
        'album': '',
        'artworkPath': '',
        'playing': true,
        'positionMs': 1000,
        'durationMs': 200000,
        'canPlay': true,
        'canPause': true,
        'canNext': true,
        'canPrevious': true,
      };
      final watcher = DeviceMediaWatcher(channel: channel);
      addTearDown(watcher.dispose);
      await watcher.probe();

      final accepted = await watcher.command('next');

      expect(accepted, isTrue);
      expect(commands, ['next']);
      expect(watcher.session?.title, 'Nightcall');
    },
  );

  test('a command is never sent when there is no adopted session', () async {
    granted = true;
    commandAccepted = true;
    final watcher = DeviceMediaWatcher(channel: channel);
    addTearDown(watcher.dispose);
    await watcher.probe();

    expect(await watcher.command('pause'), isFalse);
    expect(commands, isEmpty);
  });

  test('PlaybackService forwards external transport to the watcher', () async {
    granted = true;
    commandAccepted = true;
    session = {
      'package': 'com.spotify.music',
      'title': 'Nightcall',
      'artist': 'Kavinsky',
      'album': '',
      'artworkPath': '',
      'playing': true,
      'positionMs': 1000,
      'durationMs': 200000,
      'canPlay': true,
      'canPause': true,
      'canNext': true,
      'canPrevious': true,
    };
    final watcher = DeviceMediaWatcher(channel: channel);
    addTearDown(watcher.dispose);
    await watcher.probe();
    final playback = PlaybackService();
    addTearDown(playback.dispose);
    playback.attach(watcher);

    await playback.pause();
    await playback.next();
    await playback.previous();
    await playback.resume();

    expect(commands, ['pause', 'next', 'previous', 'play']);
  });
}

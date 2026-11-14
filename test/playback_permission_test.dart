import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sn_launcher/src/services/permission_service.dart';
import 'package:sn_launcher/src/services/playback_service.dart';

/// A permission service that records what it was asked for.
class _FakePermissions extends PermissionService {
  _FakePermissions(this.current);

  final PermissionState current;
  final List<AppPermission> asked = [];

  @override
  PermissionState state(AppPermission permission) => current;

  @override
  Future<bool> request(AppPermission permission) async {
    asked.add(permission);
    return true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel(PlaybackService.channelName);

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'available') return true;
      if (call.method == 'play') {
        return <String, Object?>{
          'playing': true,
          'position': 0,
          'duration': 1000,
          'canPlay': true,
          'canPause': true,
          'canNext': true,
          'canPrevious': true,
          'track': <String, Object?>{
            'url': 'https://example.invalid/song.mp3',
            'title': 'Song',
            'artist': 'Artist',
            'album': 'Album',
            'duration': 1000,
          },
        };
      }
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('starting music asks for the notification permission', () async {
    // Android 13+ drops the media notification without POST_NOTIFICATIONS,
    // and the lock-screen controls go with it. The permission was declared
    // in the manifest and never asked for, so the notification was silently
    // missing on every modern phone.
    final permissions = _FakePermissions(PermissionState.denied);
    final playback = PlaybackService(
      channel: channel,
      permissions: permissions,
    );
    addTearDown(playback.dispose);

    await playback.play(
      Track(
        url: 'https://example.invalid/song.mp3',
        title: 'Song',
        artist: 'Artist',
        album: 'Album',
        duration: const Duration(seconds: 1),
      ),
    );

    expect(permissions.asked, contains(AppPermission.notifications));
  });

  test('music does not ask again when it is already allowed', () async {
    final permissions = _FakePermissions(PermissionState.allowed);
    final playback = PlaybackService(
      channel: channel,
      permissions: permissions,
    );
    addTearDown(playback.dispose);

    await playback.play(
      Track(
        url: 'https://example.invalid/song.mp3',
        title: 'Song',
        artist: 'Artist',
        album: 'Album',
        duration: const Duration(seconds: 1),
      ),
    );

    expect(permissions.asked, isEmpty);
  });

  test('a build without the permission asks for nothing', () async {
    // The reduced build has no music player, so it does not declare the
    // permission and there is nothing to ask for.
    final permissions = _FakePermissions(PermissionState.notInThisBuild);
    final playback = PlaybackService(
      channel: channel,
      permissions: permissions,
    );
    addTearDown(playback.dispose);

    await playback.play(
      Track(
        url: 'https://example.invalid/song.mp3',
        title: 'Song',
        artist: 'Artist',
        album: 'Album',
        duration: const Duration(seconds: 1),
      ),
    );

    expect(permissions.asked, isEmpty);
  });
}

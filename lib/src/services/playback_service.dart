import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// One thing to play.
@immutable
class Track {
  const Track({
    required this.url,
    this.title = '',
    this.artist = '',
    this.album = '',
    this.artworkUrl = '',
    this.duration,
    this.isLive = false,
  });

  /// A direct audio stream. Not a YouTube page, not a share link — an actual
  /// media URL the platform can decode.
  ///
  /// [url] is the contract with [PlaybackService.play]. Anything that is not a
  /// media URL will not play, and the service will report an error rather than
  /// quietly doing nothing.
  final String url;
  final String title;
  final String artist;
  final String album;
  final String artworkUrl;
  final Duration? duration;

  /// Live streams have no end, so a progress bar is a lie. The player hides it
  /// rather than sitting at 99% forever pretending.
  final bool isLive;

  Map<String, Object?> toChannel() => {
        'url': url,
        'title': title,
        'artist': artist,
        'album': album,
        'artworkUrl': artworkUrl,
        'durationMs': duration?.inMilliseconds ?? 0,
        'isLive': isLive,
      };

  @override
  bool operator ==(Object other) =>
      other is Track &&
      other.url == url &&
      other.title == title &&
      other.artist == artist;

  @override
  int get hashCode => Object.hash(url, title, artist);
}

/// What the player is doing right now.
@immutable
class PlaybackState {
  const PlaybackState({
    this.playing = false,
    this.loading = false,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.track,
    this.error = '',
  });

  final bool playing;
  final bool loading;
  final Duration position;
  final Duration duration;
  final Track? track;

  /// Why playback stopped, if it did.
  ///
  /// Surfaced rather than swallowed. A player that silently fails looks
  /// identical to one that is working, which is the failure mode this whole
  /// project keeps running into.
  final String error;

  bool get hasTrack => track != null;

  /// 0..1, or null when there is nothing meaningful to show.
  ///
  /// Null for a live stream, because a live stream has no progress and
  /// pretending otherwise is worse than showing nothing.
  double? get progress {
    if (loading) return null;
    if (track?.isLive ?? false) return null;
    if (duration.inMilliseconds <= 0) return null;
    return (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0);
  }
}

/// Controls the native player.
///
/// This talks to [PlaybackService] over a method channel. It is not a Flutter
/// audio plugin and does not try to be: the point is that playback continues
/// when the app is closed and the screen is off, and that only happens with an
/// Android foreground service and a real `MediaSession`.
///
/// Nothing here knows where audio comes from. It plays what it is handed, which
/// keeps the licensing decision on the Dart side where it can be tested.
class PlaybackService extends ChangeNotifier {
  PlaybackService({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel(channelName);

  @visibleForTesting
  static const channelName = 'dev.snlauncher/playback';

  final MethodChannel _channel;

  /// Whether the platform has a playback service at all.
  ///
  /// False on the reduced build's desktop targets and in tests. Callers should
  /// check before showing controls that cannot work — a button that does
  /// nothing is worse than no button.
  bool _available = false;
  bool get available => _available;

  PlaybackState _state = const PlaybackState();
  PlaybackState get state => _state;

  Future<void> probe() async {
    _available = await _invoke<bool>('available') ?? false;
    if (_available) _update(await _invoke<Map>('state'));
    notifyListeners();
  }

  /// Plays [track], optionally as part of a [queue].
  Future<void> play(Track track, {List<Track>? queue, int index = 0}) async {
    if (!_available) await probe();
    if (!_available) {
      _emitError('This build has no audio player');
      return;
    }
    final result = await _invoke<Map>('play', {
      'track': track.toChannel(),
      'queue': (queue ?? [track]).map((t) => t.toChannel()).toList(),
      'index': index,
    });
    if (result == null) {
      _emitError('The player did not accept that track');
      return;
    }
    _update(result);
  }

  Future<void> resume() async => _update(await _invoke<Map>('resume'));
  Future<void> pause() async => _update(await _invoke<Map>('pause'));
  Future<void> stop() async => _update(await _invoke<Map>('stop'));

  Future<void> seek(Duration to) async => _update(await _invoke<Map>(
        'seek',
        {'positionMs': to.inMilliseconds},
      ));

  Future<void> next() async => _update(await _invoke<Map>('next'));
  Future<void> previous() async => _update(await _invoke<Map>('previous'));

  /// Called by the platform when the user presses a headset button, so the
  /// launcher controls follow the system rather than fighting it.
  @visibleForTesting
  void handleExternalCommand(String action) {
    switch (action) {
      case 'play':
        resume();
      case 'pause':
        pause();
      case 'next':
        next();
      case 'previous':
        previous();
    }
  }

  Future<T?> _invoke<T>(String method, [Map<String, Object?>? args]) async {
    try {
      return await _channel.invokeMethod<T>(method, args);
    } on MissingPluginException {
      _available = false;
      return null;
    } on PlatformException catch (e) {
      _emitError(e.message ?? 'Playback failed');
      return null;
    }
  }

  void _emitError(String message) {
    _state = PlaybackState(error: message);
    notifyListeners();
  }

  void _update(Map? raw) {
    if (raw == null) return;
    final trackRaw = raw['track'];
    _state = PlaybackState(
      playing: raw['playing'] == true,
      loading: raw['loading'] == true,
      position: Duration(milliseconds: _ms(raw['positionMs'])),
      duration: Duration(milliseconds: _ms(raw['durationMs'])),
      track: trackRaw is Map
          ? Track(
              url: trackRaw['url'] as String? ?? '',
              title: trackRaw['title'] as String? ?? '',
              artist: trackRaw['artist'] as String? ?? '',
              album: trackRaw['album'] as String? ?? '',
              artworkUrl: trackRaw['artworkUrl'] as String? ?? '',
              isLive: trackRaw['isLive'] == true,
            )
          : null,
      error: raw['error'] as String? ?? '',
    );
    notifyListeners();
  }

  static int _ms(Object? v) => v is int ? v : (v is num ? v.toInt() : 0);
}

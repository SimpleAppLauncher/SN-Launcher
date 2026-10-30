import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'device_media_watcher.dart';

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

  /// True when this track was adopted from another app's media session.
  ///
  /// The audio belongs to SoundCloud/Spotify/podcasts, not to this process.
  /// Transport commands are forwarded to that app's `MediaController`; they
  /// must never be sent to our own player just because it shares a UI.
  bool get isExternal => url.startsWith('external:');

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
    this.canPlay = true,
    this.canPause = true,
    this.canNext = true,
    this.canPrevious = true,
  });

  final bool playing;
  final bool loading;
  final Duration position;
  final Duration duration;
  final Track? track;

  /// Which transport commands are actually advertised by the session.
  ///
  /// Our own player can always be told to play, pause, and skip, so these
  /// default to true. An adopted session is different: Spotify may offer
  /// next but a podcast player may not, and drawing the button anyway would
  /// claim a capability the other app never published.
  final bool canPlay;
  final bool canPause;
  final bool canNext;
  final bool canPrevious;

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

  /// Presents another app's session as the current track.
  ///
  /// This is what makes the card appear when something is playing in Spotify
  /// or SoundCloud rather than in this app. The card already knows how to show
  /// a track and a transport; it just needed to be told about one it did not
  /// start. Called by [DeviceMediaWatcher] on every change.
  void adoptExternalSession(ExternalSession session) {
    final ours = _state.track;
    // Our own player wins if it is actually playing something; an external
    // session must not stomp on our own playback. An *adopted* external track
    // is not "ours", though: refusing to replace it here is what made a new
    // song invisible until the launcher was restarted.
    if (ours != null && !ours.isExternal && _state.playing) return;
    _state = PlaybackState(
      playing: session.playing,
      loading: false,
      position: session.position,
      duration: session.duration,
      canPlay: session.canPlay,
      canPause: session.canPause,
      canNext: session.canNext,
      canPrevious: session.canPrevious,
      track: Track(
        url: 'external:${session.package}',
        title: session.title,
        artist: session.artist,
        album: session.album,
      ),
    );
    notifyListeners();
  }

  /// Clears the adopted track when the other app stops.
  void clearExternalSession() {
    if (_state.track?.url.startsWith('external:') ?? false) {
      _state = const PlaybackState();
      notifyListeners();
    }
  }

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

  Future<void> resume() async {
    if (_isExternal) {
      await _controlExternal('play');
      return;
    }
    _update(await _invoke<Map>('resume'));
  }

  Future<void> pause() async {
    if (_isExternal) {
      await _controlExternal('pause');
      return;
    }
    _update(await _invoke<Map>('pause'));
  }

  Future<void> stop() async => _update(await _invoke<Map>('stop'));

  Future<void> seek(Duration to) async =>
      _update(await _invoke<Map>('seek', {'positionMs': to.inMilliseconds}));

  Future<void> next() async {
    if (_isExternal) {
      await _controlExternal('next');
      return;
    }
    _update(await _invoke<Map>('next'));
  }

  Future<void> previous() async {
    if (_isExternal) {
      await _controlExternal('previous');
      return;
    }
    _update(await _invoke<Map>('previous'));
  }

  bool get _isExternal => _state.track?.isExternal ?? false;

  /// Sends a transport command to the app that actually owns the audio.
  ///
  /// Nothing here goes through our own native player. A MediaController is
  /// the system's own write side for somebody else's session, so the command
  /// lands on Spotify or the podcast app exactly as the lock-screen button
  /// would. The watcher refreshes after the command so the strip follows the
  /// other app rather than guessing that it obeyed.
  Future<void> _controlExternal(String action) async {
    final watcher = _watcher;
    if (watcher == null) return;
    await watcher.command(action);
  }

  /// Called by the platform when the user presses a headset button, so the
  /// launcher controls follow the system rather than fighting it.
  /// Wires this player to a watcher, so anything playing anywhere on the device
  /// reaches the card.
  void attach(DeviceMediaWatcher watcher) {
    _watcher = watcher;
    watcher.addListener(_onWatchedSession);
    // Adopt whatever is already playing, rather than waiting for the next
    // change — the common case is that music was already going when the app
    // started, and the card should be there immediately.
    _onWatchedSession();
  }

  DeviceMediaWatcher? _watcher;

  void _onWatchedSession() {
    final watcher = _watcher;
    if (watcher == null) return;
    final session = watcher.session;
    if (session == null) {
      clearExternalSession();
      return;
    }
    adoptExternalSession(session);
  }

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

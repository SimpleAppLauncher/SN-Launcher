import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Whatever is playing on this device, whoever is playing it.
///
/// This is the piece that makes the card show up when you start something in
/// SoundCloud or Spotify. It does not play anything and it does not own the
/// audio — Android publishes every active media session through
/// `MediaSessionManager`, and this reads them.
///
/// **The permission is real and is the user's to grant.** Reading another app's
/// media session requires this app to be a notification listener, which is a
/// toggle in Settings. [hasPermission] reports the truth rather than assuming,
/// because the user can revoke it at any moment and a launcher that kept
/// showing a track after access was pulled would be lying about the device.
class DeviceMediaWatcher extends ChangeNotifier {
  DeviceMediaWatcher({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(channelName) {
    _channel.setMethodCallHandler(_onCall);
  }

  @visibleForTesting
  static const channelName = 'dev.snlauncher/sessions';

  final MethodChannel _channel;
  Timer? _poll;
  Duration _every = const Duration(milliseconds: 400);

  bool _hasPermission = false;
  bool get hasPermission => _hasPermission;

  ExternalSession? _session;
  ExternalSession? get session => _session;

  /// Media sessions are an Android API. Desktop and Tizen have no equivalent,
  /// so the launcher must not render a permission card that can never work.
  bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Why the sessions are not available, in words a person can act on.
  String get explanation {
    if (!supported) return 'Now playing is only available on Android.';
    if (_hasPermission) return '';
    return 'Allow notification access so the launcher can see what is playing.';
  }

  Future<void> probe() async {
    if (!supported) {
      _hasPermission = false;
      _session = null;
      stopPolling();
      notifyListeners();
      return;
    }
    _hasPermission = await _invoke<bool>('hasPermission') ?? false;
    notifyListeners();
    if (_hasPermission) {
      _ensurePolling();
      // Await the first read so a caller that awaits probe() also sees the
      // session. Polling still runs unawaited after this.
      await refresh();
    } else {
      // Do not keep a timer running when the answer is "no". The permission
      // can be granted later; the resumed lifecycle callback probes again.
      stopPolling();
      if (_session != null) {
        _session = null;
        notifyListeners();
      }
    }
  }

  /// Sends a play/pause/skip command to the session currently being shown.
  ///
  /// The native side owns the MediaController; this only names the action.
  /// Returns false when there is no session, notification access was pulled,
  /// or the other app does not advertise that transport action. A false is
  /// deliberately not turned into a fake optimistic state: the card keeps
  /// showing what the other app last reported.
  Future<bool> command(String action) async {
    if (!supported || _session == null) return false;
    final accepted = await _invoke<bool>('command', {'action': action});
    if (accepted == true) await refresh();
    return accepted == true;
  }

  /// Sends the user to the notification-access settings page.
  Future<void> requestAccess() async {
    if (!supported) return;
    try {
      await _channel.invokeMethod('openSettings');
    } on PlatformException catch (e) {
      debugPrint('DeviceMediaWatcher: could not open settings — ${e.message}');
    } on MissingPluginException {
      // Desktop or a test host. Nothing to grant.
    }
  }

  /// Starts polling.
  ///
  /// `MediaSessionManager` has no change callback — there is no way to be told
  /// when a session appears — so this is a timer. It is deliberately slow: the
  /// only thing being kept honest is whether a card is showing, and polling
  /// every 400 ms on a weak device to change a few glyphs is not a trade worth
  /// making.
  ///
  /// The timer is only created after the permission check succeeds. Polling a
  /// service that will answer `SecurityException` forever is wasted work on
  /// the hardware this targets.
  void startPolling({Duration every = const Duration(milliseconds: 400)}) {
    _every = every;
    stopPolling();
    unawaited(probe());
  }

  void _ensurePolling() {
    if (!supported || !_hasPermission || _poll != null) return;
    _poll = Timer.periodic(_every, (_) => unawaited(refresh()));
  }

  void stopPolling() {
    _poll?.cancel();
    _poll = null;
  }

  Future<void> refresh() async {
    if (!supported) {
      _apply(null);
      return;
    }
    final raw = await _invoke<Map>('sessions');
    _apply(raw);
  }

  Future<void> _onCall(MethodCall call) async {
    if (call.method != 'sessionChanged') return;
    _apply(call.arguments as Map?);
  }

  void _apply(Map? raw) {
    if (raw == null || raw.isEmpty) {
      if (_session == null) return;
      _session = null;
      notifyListeners();
      return;
    }
    // Only notify when something actually changed.
    //
    // This polls every 400 ms, and the position field changes on every poll,
    // so "notify only when the session changed" has to mean "changed in a way
    // the card can see" — the track, whether it is playing, or which transport
    // the other app now offers. The position is deliberately not compared,
    // because comparing it would notify on every single poll, which is the
    // thing being fixed.
    final next = ExternalSession(
      package: raw['package'] as String? ?? '',
      title: raw['title'] as String? ?? '',
      artist: raw['artist'] as String? ?? '',
      album: raw['album'] as String? ?? '',
      artworkPath: raw['artworkPath'] as String? ?? '',
      playing: raw['playing'] == true,
      position: Duration(milliseconds: _ms(raw['positionMs'])),
      duration: Duration(milliseconds: _ms(raw['durationMs'])),
      canPlay: raw['canPlay'] == true,
      canPause: raw['canPause'] == true,
      canNext: raw['canNext'] == true,
      canPrevious: raw['canPrevious'] == true,
    );
    final previous = _session;
    if (previous != null &&
        previous.package == next.package &&
        previous.title == next.title &&
        previous.artist == next.artist &&
        previous.album == next.album &&
        previous.playing == next.playing &&
        previous.duration == next.duration &&
        previous.canPlay == next.canPlay &&
        previous.canPause == next.canPause &&
        previous.canNext == next.canNext &&
        previous.canPrevious == next.canPrevious) {
      // The same track, still playing. Update the position without waking
      // anyone up.
      _session = next;
      return;
    }
    // The permission can be revoked while the app is running; the native side
    // starts sending nulls, and a stale card must not outlive it.
    _hasPermission = true;
    _session = next;
    notifyListeners();
  }

  Future<T?> _invoke<T>(String method, [Map<String, Object?>? args]) async {
    try {
      return await _channel.invokeMethod<T>(method, args);
    } on MissingPluginException {
      _hasPermission = false;
      return null;
    } on PlatformException {
      return null;
    }
  }

  static int _ms(Object? v) => v is int ? v : (v is num ? v.toInt() : 0);

  /// Whether the path is one this process can actually read.
  ///
  /// Album art is written by the native side into the app's own cache, so it
  /// should always be readable — but a path from anywhere else is treated as
  /// absent rather than handed to an image decoder that will throw.
  bool get hasArtwork =>
      _session != null &&
      _session!.artworkPath.isNotEmpty &&
      File(_session!.artworkPath).existsSync();

  @override
  void dispose() {
    stopPolling();
    _channel.setMethodCallHandler(null);
    super.dispose();
  }
}

/// One media session belonging to some other app.
@immutable
class ExternalSession {
  const ExternalSession({
    required this.package,
    required this.title,
    required this.artist,
    required this.album,
    required this.artworkPath,
    required this.playing,
    required this.position,
    required this.duration,
    this.canPlay = false,
    this.canPause = false,
    this.canNext = false,
    this.canPrevious = false,
  });

  /// Which app it is, e.g. `com.soundcloud.android`.
  final String package;
  final String title;
  final String artist;
  final String album;
  final String artworkPath;
  final bool playing;
  final Duration position;
  final Duration duration;

  /// Transport actions the owning app actually advertised.
  ///
  /// Defaults are false because an old reader or a test fixture that does not
  /// mention them has not proved that the action exists. The UI can then
  /// leave the button out instead of offering a command that does nothing.
  final bool canPlay;
  final bool canPause;
  final bool canNext;
  final bool canPrevious;

  /// 0..1, or null when there is nothing honest to show.
  ///
  /// Null for a live stream, which reports no duration, and null while
  /// buffering. A bar that sits at 0% because it does not know is not a
  /// progress bar.
  double? get progress {
    if (duration.inMilliseconds <= 0) return null;
    return (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0);
  }

  /// Builds a session from a plain JSON reading.
  ///
  /// So the desktop bridge and the Android media-session watcher produce the
  /// same thing, and the card does not have to know which one it is looking
  /// at. The file contract and the platform API are two routes to one place.
  factory ExternalSession.fromReading(Map<String, Object?> reading) {
    final position = (reading['positionMs'] as num?)?.toInt() ?? 0;
    final duration = (reading['durationMs'] as num?)?.toInt() ?? 0;
    return ExternalSession(
      package: reading['source'] as String? ?? 'external',
      title: reading['title'] as String? ?? '',
      artist: reading['artist'] as String? ?? '',
      album: reading['album'] as String? ?? '',
      artworkPath: reading['artworkPath'] as String? ?? '',
      playing: reading['playing'] == true,
      position: Duration(milliseconds: position),
      duration: Duration(milliseconds: duration),
      canPlay: reading['canPlay'] == true,
      canPause: reading['canPause'] == true,
      canNext: reading['canNext'] == true,
      canPrevious: reading['canPrevious'] == true,
    );
  }

  /// A short label for which app this is.
  String get appLabel => package.split('.').last;
}

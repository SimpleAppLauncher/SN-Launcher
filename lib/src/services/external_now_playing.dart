import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// Now-playing information from *another* application on this machine.
///
/// This is the desktop counterpart to the Android media-session watcher, and it
/// exists for one specific reason: there is another launcher in this project —
/// **NCS-SMLauncher** — which is a Python application, and which cannot publish
/// an Android `MediaSession` because it is not an Android application. So the
/// two cannot talk through the platform.
///
/// They talk through a file instead.
///
/// ## The contract
///
/// Any application on the machine may write a JSON object to the path below,
/// and SN-Launcher will pick it up and show it on the now-playing card.
///
/// ```json
/// {
///   "title":      "Some track",
///   "artist":     "Some artist",
///   "album":      "Some album",
///   "positionMs": 61500,
///   "durationMs": 240000,
///   "playing":    true,
///   "source":     "NCS-SMLauncher"
/// }
/// ```
///
/// Every field except `title` is optional. A file that is missing, unreadable,
/// malformed, or older than [staleAfter] is treated as "nothing is playing" —
/// never as a crash and never as a half-drawn card.
///
/// ## Where the file goes
///
/// 1. `$SN_LAUNCHER_NOW_PLAYING`, if set. This is the explicit contract and
///    the one to use when the other application needs a specific path.
/// 2. Otherwise `$XDG_CACHE_HOME/sn_launcher/now_playing.json`, or
///    `~/.cache/sn_launcher/now_playing.json` on Linux.
/// 3. Otherwise `~/Library/Caches/sn_launcher/now_playing.json` on macOS.
///
/// The writer should write atomically — write to a temporary file and rename
/// over the target — because a half-written file is a JSON parse error, and
/// the reader treats that as "nothing is playing".
///
/// **This is deliberately not implemented on Android.** There the platform
/// already has the right mechanism, `MediaSession`, and using it means the
/// card also shows music from Spotify, YouTube Music and anything else that
/// publishes a session, rather than only from applications that know about
/// this file.
class ExternalNowPlaying extends ChangeNotifier {
  ExternalNowPlaying({String? path, this.pollInterval = const Duration(seconds: 1)})
      : _path = path ?? defaultPath();

  /// Where the file is read from.
  final String _path;

  /// How often it is read.
  ///
  /// A second, because the position has to move and the card has to look
  /// alive. It is a local file read, not a network call, so it costs almost
  /// nothing — and it stops entirely when the file has not changed.
  final Duration pollInterval;

  String get path => _path;

  Map<String, Object?>? _reading;
  Timer? _timer;
  bool _disposed = false;

  Map<String, Object?>? get reading => _reading;

  /// The track, or null when nothing is playing.
  Map<String, Object?>? get track {
    final r = _reading;
    if (r == null) return null;
    final title = r['title'];
    if (title is! String || title.isEmpty) return null;
    return r;
  }

  /// The default location of the file.
  static String defaultPath() {
    final override = Platform.environment['SN_LAUNCHER_NOW_PLAYING'];
    if (override != null && override.isNotEmpty) return override;

    if (Platform.isMacOS) {
      final home = Platform.environment['HOME'] ?? '';
      return '$home/Library/Caches/sn_launcher/now_playing.json';
    }
    if (Platform.isLinux) {
      final cache = Platform.environment['XDG_CACHE_HOME'];
      final base = (cache != null && cache.isNotEmpty)
          ? cache
          : '${Platform.environment['HOME'] ?? ''}/.cache';
      return '$base/sn_launcher/now_playing.json';
    }
    // Android and anything else: the temp directory, which is where the
    // Android media-session watcher does not need to be.
    return '${Directory.systemTemp.path}/sn_launcher_now_playing.json';
  }

  /// How old a file may be and still be believed.
  ///
  /// An application that crashes without clearing its file would otherwise
  /// leave a card on screen showing a track that stopped playing hours ago.
  static const Duration staleAfter = Duration(seconds: 15);

  /// Starts watching.
  void start() {
    stop();
    _poll();
    _timer = Timer.periodic(pollInterval, (_) => _poll());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  /// Reads the file now, rather than waiting for the next tick.
  ///
  /// For tests, and for anything that wants to refresh on demand.
  @visibleForTesting
  void pollNow() => _poll();

  void _poll() {
    if (_disposed) return;
    Map<String, Object?>? next;
    try {
      final file = File(_path);
      if (!file.existsSync()) {
        next = null;
      } else {
        final stat = file.statSync();
        final age = DateTime.now().difference(stat.modified);
        if (age > staleAfter) {
          // Too old to believe. The other app is gone or stalled.
          next = null;
        } else {
          final raw = file.readAsStringSync();
          final decoded = jsonDecode(raw);
          next = decoded is Map ? Map<String, Object?>.from(decoded) : null;
        }
      }
    } catch (_) {
      // Missing, unreadable, malformed, or a race with the writer renaming
      // the file over ours. All of those mean "nothing to show".
      next = null;
    }

    // Only wake the UI when something actually changed, or when the position
    // moved enough to matter. A poll that notifies every second rebuilds the
    // card sixty times a minute for no reason.
    final changed = !_sameReading(next, _reading);
    if (changed) {
      _reading = next;
      if (!_disposed) notifyListeners();
    }
  }

  /// Whether two readings are the same for the purposes of the UI.
  static bool _sameReading(Map<String, Object?>? a, Map<String, Object?>? b) {
    if (a == null || b == null) return a == b;
    for (final key in const ['title', 'artist', 'album', 'playing', 'source']) {
      if (a[key] != b[key]) return false;
    }
    // The position is allowed to move, but not by a whole second at a time —
    // a card that redraws every second is a card that never rests.
    final ap = (a['positionMs'] as num?)?.toInt() ?? 0;
    final bp = (b['positionMs'] as num?)?.toInt() ?? 0;
    return (ap - bp).abs() < 1000;
  }

  @override
  void dispose() {
    _disposed = true;
    stop();
    super.dispose();
  }
}

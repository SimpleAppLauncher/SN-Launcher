import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// One track, as NCS-SMLauncher describes it over the wire.
///
/// Every field except [title] is allowed to be empty, because the other side is
/// somebody else's application and a missing album is not an error — it is an
/// album nobody tagged.
@immutable
class NcsTrack {
  const NcsTrack({
    this.id = '',
    required this.title,
    this.artist = '',
    this.album = '',
    this.artwork = '',
    this.duration = Duration.zero,
  });

  /// Stable identifier, used to ask the player to play *this* one.
  final String id;

  final String title;
  final String artist;
  final String album;

  /// Either an absolute URL or a path on the same server, `/art/7.jpg`.
  final String artwork;

  final Duration duration;

  /// Whether this is a placeholder rather than a track.
  bool get isEmpty => title.isEmpty;

  static NcsTrack? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final title = raw['title'];
    if (title is! String || title.isEmpty) return null;
    return NcsTrack(
      id: raw['id']?.toString() ?? '',
      title: title,
      artist: raw['artist']?.toString() ?? '',
      album: raw['album']?.toString() ?? '',
      artwork: raw['artwork']?.toString() ?? '',
      duration: Duration(
        milliseconds: (raw['durationMs'] as num?)?.toInt() ?? 0,
      ),
    );
  }

  /// The artwork URL resolved against the server, or null when there is none.
  ///
  /// The server may send `/art/7.jpg`, which is a path and not a URL — resolving
  /// it here rather than on the server means a player behind a reverse proxy
  /// still works, because the path is relative to wherever we actually reached
  /// it.
  String? artworkUrl(String baseUrl) {
    if (artwork.isEmpty) return null;
    if (artwork.startsWith('http://') || artwork.startsWith('https://')) {
      return artwork;
    }
    return '$baseUrl${artwork.startsWith('/') ? '' : '/'}$artwork';
  }

  Map<String, Object?> toJson() => {
    if (id.isNotEmpty) 'id': id,
    'title': title,
    if (artist.isNotEmpty) 'artist': artist,
    if (album.isNotEmpty) 'album': album,
    if (artwork.isNotEmpty) 'artwork': artwork,
    if (duration > Duration.zero) 'durationMs': duration.inMilliseconds,
  };
}

/// What the player is doing right now.
@immutable
class NcsSnapshot {
  const NcsSnapshot({
    required this.playing,
    required this.current,
    required this.position,
    required this.volume,
    required this.queue,
    required this.receivedAt,
    this.serverName = '',
  });

  final bool playing;
  final NcsTrack? current;
  final Duration position;
  final double volume;
  final List<NcsTrack> queue;

  /// When this reading arrived.
  ///
  /// The position is a still photograph taken at that instant; between polls
  /// the UI has to work out where playback actually is, or the progress bar
  /// jumps two seconds at a time.
  final DateTime receivedAt;

  /// What the other end calls itself, for the "Playing on …" line.
  final String serverName;

  Duration get duration => current?.duration ?? Duration.zero;

  /// Where playback is now, assuming it has been running since [receivedAt].
  Duration positionAt(DateTime now) {
    if (!playing) return position;
    final elapsed = now.difference(receivedAt);
    final moved = position + (elapsed.isNegative ? Duration.zero : elapsed);
    final total = duration;
    if (total > Duration.zero && moved > total) return total;
    return moved;
  }

  static NcsSnapshot? fromJson(Map<String, Object?> json, DateTime now) {
    final current = NcsTrack.fromJson(json['track'] ?? json['current']);
    final queue = <NcsTrack>[];
    final rawQueue = json['queue'];
    if (rawQueue is List) {
      for (final entry in rawQueue) {
        final track = NcsTrack.fromJson(entry);
        if (track != null) queue.add(track);
      }
    }
    return NcsSnapshot(
      playing: json['playing'] == true,
      current: current,
      position: Duration(
        milliseconds: (json['positionMs'] as num?)?.toInt() ?? 0,
      ),
      volume: (json['volume'] as num?)?.toDouble() ?? 1.0,
      queue: queue,
      receivedAt: now,
      serverName: json['server']?.toString() ?? '',
    );
  }
}

/// A client for the playback protocol NCS-SMLauncher exposes.
///
/// This is a *remote control*, not a player. The decoding, the library and the
/// audio all live in the other application; this side draws them and sends
/// button presses back. That is deliberate — it means the launcher can be
/// replaced or restarted without stopping the music, which is the whole
/// advantage a wall panel is supposed to have over a phone.
///
/// The protocol is HTTP:
///
///   GET  /state      the snapshot
///   POST /control    {"action": "play", "value": 0.5, "id": "..."}
///   GET  /browse     optional, the library
///
/// `GET /events` exists in the proposal as an SSE stream, but the client polls
/// `/state` instead. A poll every two seconds is indistinguishable from a push
/// on a wall display, and it survives a server that only implements half the
/// contract — which, while the other side is being rewritten, is the likely
/// case.
class NcsClient extends ChangeNotifier {
  NcsClient({
    String baseUrl = '',
    Duration pollInterval = const Duration(seconds: 2),
  }) : _baseUrl = _normalise(baseUrl),
       _interval = pollInterval;

  /// The address the player is at, or an empty string when it is not set.
  ///
  /// Empty is a real state, not a misconfiguration: a launcher that has never
  /// been pointed at a player should say so, not fail at something.
  String _baseUrl;

  final Duration _interval;

  HttpClient? _http;
  Timer? _timer;
  bool _polling = false;
  bool _disposed = false;

  NcsSnapshot? _snapshot;
  bool _connected = false;
  String _error = '';

  String get baseUrl => _baseUrl;
  bool get configured => _baseUrl.isNotEmpty;
  bool get connected => _connected;
  NcsSnapshot? get snapshot => _snapshot;

  /// Why the last poll failed, or an empty string.
  String get error => _error;

  /// Where the player calls itself home. Shown in the connect sheet.
  static String get exampleAddress => 'http://192.168.1.20:8737';

  /// Turns whatever the user typed into a URL, or returns an empty string.
  ///
  /// A host and a port are what people type — `192.168.1.20:8737` — and a bare
  /// hostname is what mDNS gives you. Both are accepted; neither is guessed at.
  static String _normalise(String raw) {
    var value = raw.trim();
    if (value.isEmpty) return '';
    if (!value.contains('://')) value = 'http://$value';
    while (value.endsWith('/')) {
      value = value.substring(0, value.length - 1);
    }
    return value;
  }

  /// Points the client somewhere new and starts over.
  Future<void> configure(String baseUrl) async {
    final next = _normalise(baseUrl);
    if (next == _baseUrl) return;
    _baseUrl = next;
    _snapshot = null;
    _connected = false;
    _error = '';
    notifyListeners();
    if (next.isEmpty) {
      stop();
      return;
    }
    await refresh();
  }

  /// Starts polling. Safe to call twice.
  void start() {
    if (_disposed || !configured) return;
    _timer?.cancel();
    _timer = Timer.periodic(_interval, (_) => unawaited(refresh()));
    unawaited(refresh());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  /// Reads the state once.
  Future<void> refresh() async {
    if (_disposed || !configured || _polling) return;
    _polling = true;
    try {
      final json = await _getJson('/state');
      if (_disposed) return;
      if (json == null) {
        // _getJson has already said why — a 500, a timeout, a parse error.
        // Replacing that with "no player at" would throw away the one detail
        // that tells the user what to fix.
        if (_error.isEmpty) _fail(_unreachable());
        return;
      }
      final next = NcsSnapshot.fromJson(json, DateTime.now());
      if (next == null) {
        _fail('The player sent a state with no track in it');
        return;
      }
      _snapshot = next;
      _connected = true;
      _error = '';
      // Always notify, even when the track is the same: the position moved,
      // and the progress bar has to move with it.
      notifyListeners();
    } finally {
      _polling = false;
    }
  }

  /// The library, if the server offers one.
  ///
  /// Returns an empty list rather than throwing when it does not: `/browse` is
  /// optional in the protocol, and a server that only implements playback is
  /// still a working player.
  Future<List<NcsTrack>> browse() async {
    if (!configured) return const [];
    final json = await _getJson('/browse', quiet: true);
    if (json == null) return const [];
    final raw = json['tracks'] ?? json['albums'] ?? json['items'];
    if (raw is! List) return const [];
    return [for (final entry in raw) ?NcsTrack.fromJson(entry)];
  }

  /// Sends a transport command.
  ///
  /// The method does not throw when the player is unreachable — the button
  /// press is simply lost, and the next poll tells the truth about what is
  /// happening. A transport button that shows an error dialog is worse than
  /// one that does nothing, because the user is across the room.
  Future<void> control(String action, {double? value, String? id}) async {
    if (!configured) return;
    try {
      final payload = <String, Object?>{'action': action};
      if (value != null) payload['value'] = value;
      if (id != null && id.isNotEmpty) payload['id'] = id;
      await _post('/control', payload);
      // Do not wait for the next tick: the button should feel connected.
      unawaited(refresh());
    } catch (_) {
      // Ignored on purpose. See above.
    }
  }

  /// [quiet] is for the optional endpoints.
  ///
  /// A 404 on `/browse` means the server never implemented a library, not that
  /// the player has gone away. Reporting it through [_fail] would turn a
  /// working player into a "not connected" page the moment the feed asked for
  /// a library it was never going to get.
  Future<Map<String, Object?>?> _getJson(
    String path, {
    bool quiet = false,
  }) async {
    try {
      final request = await _client.getUrl(Uri.parse('$_baseUrl$path'));
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final response = await request.close().timeout(
        const Duration(seconds: 4),
      );
      if (response.statusCode != 200) {
        await response.drain<void>();
        if (!quiet) _fail('The player answered ${response.statusCode}');
        return null;
      }
      final body = await response.transform(utf8.decoder).join();
      final decoded = jsonDecode(body);
      if (decoded is! Map) return null;
      return Map<String, Object?>.from(decoded);
    } on SocketException {
      if (!quiet) _fail(_unreachable());
      return null;
    } on TimeoutException {
      if (!quiet) _fail('The player did not answer');
      return null;
    } on FormatException {
      if (!quiet) _fail('The player sent something that is not JSON');
      return null;
    } catch (e) {
      if (!quiet) _fail('Could not reach the player');
      return null;
    }
  }

  Future<void> _post(String path, Map<String, Object?> body) async {
    final request = await _client.postUrl(Uri.parse('$_baseUrl$path'));
    request.headers.contentType = ContentType.json;
    request.write(jsonEncode(body));
    final response = await request.close().timeout(const Duration(seconds: 4));
    await response.drain<void>();
  }

  HttpClient get _client => _http ??= HttpClient()
    ..connectionTimeout = const Duration(seconds: 3)
    ..idleTimeout = const Duration(seconds: 10);

  String _unreachable() {
    final host = Uri.tryParse(_baseUrl)?.authority ?? _baseUrl;
    return 'No player at $host';
  }

  void _fail(String message) {
    final changed = _connected || message != _error;
    _connected = false;
    _error = message;
    if (changed && !_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    stop();
    _http?.close(force: true);
    _http = null;
    super.dispose();
  }
}

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sn_launcher/src/services/ncs_client.dart';
import 'package:sn_launcher/src/widgets/ncs_music_page.dart'
    show formatDuration;

/// The client that talks to NCS-SMLauncher.
///
/// The point of these tests is that the other side is somebody else's program.
/// It can return a 500, it can be switched off, it can send a track with no
/// artist and a queue full of holes. None of that may become an exception in
/// the launcher, because a wall panel in a kitchen cannot show a stack trace.
void main() {
  // flutter_test installs HTTP overrides that answer every request with a
  // canned image, which would make a loopback server unreachable and every
  // test here pass for the wrong reason.
  setUpAll(() => HttpOverrides.global = null);

  group('a track', () {
    test('needs a title', () {
      expect(NcsTrack.fromJson({'artist': 'x'}), isNull);
      expect(NcsTrack.fromJson({'title': ''}), isNull);
      expect(NcsTrack.fromJson('not a map'), isNull);
      expect(NcsTrack.fromJson(null), isNull);
    });

    test('fills in what is missing', () {
      final track = NcsTrack.fromJson({'title': 'One'})!;
      expect(track.artist, '');
      expect(track.album, '');
      expect(track.artwork, '');
      expect(track.duration, Duration.zero);
    });

    test('resolves artwork relative to the server it came from', () {
      const relative = NcsTrack(title: 'One', artwork: '/art/7.jpg');
      expect(
        relative.artworkUrl('http://10.0.0.2:8737'),
        'http://10.0.0.2:8737/art/7.jpg',
      );

      // A server that already gave an absolute URL — a reverse proxy, or a CDN
      // — must not have its host replaced.
      const absolute = NcsTrack(
        title: 'One',
        artwork: 'https://cdn.example/7.jpg',
      );
      expect(
        absolute.artworkUrl('http://10.0.0.2:8737'),
        'https://cdn.example/7.jpg',
      );

      expect(const NcsTrack(title: 'One').artworkUrl('http://x'), isNull);
    });
  });

  group('the position between polls', () {
    final received = DateTime(2026, 10, 23, 12);

    NcsSnapshot snapshot({required bool playing, required Duration position}) =>
        NcsSnapshot(
          playing: playing,
          current: const NcsTrack(title: 'One', duration: Duration(minutes: 4)),
          position: position,
          volume: 1,
          queue: const [],
          receivedAt: received,
        );

    test('moves while playing', () {
      final s = snapshot(playing: true, position: const Duration(seconds: 10));
      expect(
        s.positionAt(received.add(const Duration(seconds: 3))),
        const Duration(seconds: 13),
      );
    });

    test('stays still while paused', () {
      final s = snapshot(playing: false, position: const Duration(seconds: 10));
      expect(
        s.positionAt(received.add(const Duration(seconds: 30))),
        const Duration(seconds: 10),
      );
    });

    test('does not run past the end of the track', () {
      final s = snapshot(playing: true, position: const Duration(seconds: 235));
      expect(
        s.positionAt(received.add(const Duration(minutes: 5))),
        const Duration(minutes: 4),
      );
    });
  });

  group('durations', () {
    test('are written the way a player writes them', () {
      expect(formatDuration(Duration.zero), '0:00');
      expect(formatDuration(const Duration(seconds: 7)), '0:07');
      expect(formatDuration(const Duration(minutes: 3, seconds: 7)), '3:07');
      expect(
        formatDuration(const Duration(hours: 1, minutes: 2, seconds: 7)),
        '1:02:07',
      );
    });
  });

  group('without an address', () {
    test('is a state, not a failure', () async {
      final client = NcsClient();
      addTearDown(client.dispose);
      await client.refresh();
      expect(client.configured, isFalse);
      expect(client.connected, isFalse);
      expect(client.error, isEmpty);
    });

    test('accepts a host and port without a scheme', () async {
      final client = NcsClient();
      addTearDown(client.dispose);
      // Nothing listens on this port; what matters is the address the client
      // decided on, and that it failed quietly rather than throwing.
      await client.configure('192.168.1.20:8737/');
      expect(client.baseUrl, 'http://192.168.1.20:8737');
    });
  });

  group('against a real server', () {
    late FakePlayer player;

    setUp(() async => player = await FakePlayer.start());
    tearDown(() async => player.stop());

    test('reads the state', () async {
      final client = NcsClient(baseUrl: player.url);
      addTearDown(client.dispose);

      await client.refresh();

      expect(client.connected, isTrue);
      expect(client.error, isEmpty);
      expect(client.snapshot?.current?.title, 'Everything In Its Right Place');
      expect(client.snapshot?.current?.artist, 'Radiohead');
      expect(client.snapshot?.playing, isTrue);
      expect(client.snapshot?.serverName, 'NCS-SMLauncher');
      expect(client.snapshot?.queue, hasLength(5));
    });

    test('sends a bare transport command', () async {
      final client = NcsClient(baseUrl: player.url);
      addTearDown(client.dispose);
      await client.refresh();

      await client.control('pause');

      expect(player.controls.single, {'action': 'pause'});
      // Chunked would be -1 here. The mock player (and any server that only
      // reads Content-Length) would then parse an empty body and answer 400.
      expect(player.lastControlLength, greaterThan(0));
    });

    test('sends the track it was asked to play', () async {
      final client = NcsClient(baseUrl: player.url);
      addTearDown(client.dispose);
      await client.refresh();

      await client.control('play', id: 'track-42');

      expect(player.controls.single, {'action': 'play', 'id': 'track-42'});
    });

    test('sends a value with a seek', () async {
      final client = NcsClient(baseUrl: player.url);
      addTearDown(client.dispose);
      await client.refresh();

      await client.control('seek', value: 61500);

      expect(player.controls.single, {'action': 'seek', 'value': 61500.0});
    });

    test('reads the library when there is one', () async {
      final client = NcsClient(baseUrl: player.url);
      addTearDown(client.dispose);

      final library = await client.browse();

      expect(library.map((t) => t.title), ['Kid A', 'Amnesiac']);
    });

    test('a server with no library is still a working player', () async {
      final client = NcsClient(baseUrl: player.url);
      addTearDown(client.dispose);
      await client.refresh();
      expect(client.connected, isTrue);
      player.hasLibrary = false;

      expect(await client.browse(), isEmpty);
      // The 404 was on an endpoint the protocol calls optional. It must not
      // take the player from "connected" to "no player at" while the music
      // is playing.
      expect(client.connected, isTrue);
      expect(client.error, isEmpty);
    });

    test('an error is reported, not thrown', () async {
      final client = NcsClient(baseUrl: player.url);
      addTearDown(client.dispose);
      player.stateStatus = 500;

      await client.refresh();

      expect(client.connected, isFalse);
      expect(client.error, contains('500'));
    });

    test('a player that has gone away is reported, not thrown', () async {
      final port = player.port;
      await player.stop();

      final client = NcsClient(baseUrl: 'http://127.0.0.1:$port');
      addTearDown(client.dispose);

      await client.refresh();

      expect(client.connected, isFalse);
      expect(client.error, contains('No player at'));
    });

    test('a malformed state does not crash the launcher', () async {
      final client = NcsClient(baseUrl: player.url);
      addTearDown(client.dispose);
      player.malformed = true;

      await client.refresh();

      expect(client.connected, isFalse);
      expect(client.error, isNotEmpty);
    });

    test('a refresh during a poll waits for that poll', () async {
      // The Connect button asks for a refresh while the two-second timer may
      // already have one in flight. Returning immediately there made the button
      // read `connected` before the answer landed, and the tablet showed
      // "No player at ..." underneath a header that was about to say connected.
      player.stateDelay = const Duration(milliseconds: 120);
      final client = NcsClient(baseUrl: player.url);
      addTearDown(client.dispose);

      await Future.wait([client.refresh(), client.refresh()]);

      expect(client.connected, isTrue);
      expect(player.stateRequests, 1);
    });
  });
}

/// A stand-in for NCS-SMLauncher, on a real socket.
///
/// Not a mock: it is an HTTP server, and the client reaches it over a loopback
/// address exactly as it will reach the real player over the network. A fake
/// that answers method calls would pass while the JSON shape was wrong.
class FakePlayer {
  FakePlayer._(this._server) : url = 'http://127.0.0.1:${_server.port}';

  final HttpServer _server;
  final String url;
  final List<Map<String, Object?>> controls = [];

  bool hasLibrary = true;
  bool malformed = false;
  int stateStatus = 200;

  /// How long `/state` waits before answering.
  Duration stateDelay = Duration.zero;

  /// How many times the client asked for the state.
  int stateRequests = 0;

  /// The Content-Length the last control arrived with. -1 means the client
  /// chunked it, which this kind of server would read as an empty body.
  int lastControlLength = -1;

  /// One transparent pixel, so `/art/...` answers with a decodable image.
  static final List<int> _pixel = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk'
    'YPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
  );

  int get port => _server.port;

  static Future<FakePlayer> start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final player = FakePlayer._(server);
    server.listen(player._handle);
    return player;
  }

  Map<String, Object?> get _state => {
    'playing': true,
    'server': 'NCS-SMLauncher',
    'positionMs': 61000,
    'durationMs': 240000,
    'volume': 0.8,
    'track': {
      'id': 'track-1',
      'title': 'Everything In Its Right Place',
      'artist': 'Radiohead',
      'album': 'Kid A',
      'durationMs': 240000,
      'artwork': '/art/track-1.png',
    },
    'queue': [
      {
        'id': 'track-2',
        'title': 'Kid A',
        'artist': 'Radiohead',
        'artwork': '/art/track-2.png',
        'durationMs': 250000,
      },
      {
        'id': 'track-3',
        'title': 'The National Anthem',
        'artist': 'Radiohead',
        'artwork': '/art/track-3.png',
        'durationMs': 320000,
      },
      {
        'id': 'track-4',
        'title': 'How to Disappear Completely',
        'artist': 'Radiohead',
        'durationMs': 356000,
      },
      {
        'id': 'track-5',
        'title': 'Treefingers',
        'artist': 'Radiohead',
        'durationMs': 222000,
      },
      {
        'id': 'track-6',
        'title': 'Optimistic',
        'artist': 'Radiohead',
        'durationMs': 316000,
      },
    ],
  };

  Future<void> _handle(HttpRequest request) async {
    final path = request.uri.path;
    if (request.method == 'GET' && path == '/state') {
      stateRequests++;
      if (stateDelay > Duration.zero) await Future<void>.delayed(stateDelay);
      if (malformed) {
        request.response.write('{this is not json');
        await request.response.close();
        return;
      }
      request.response.statusCode = stateStatus;
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode(_state));
      await request.response.close();
      return;
    }
    if (request.method == 'POST' && path == '/control') {
      // A server that only reads Content-Length must still see the body.
      lastControlLength = request.contentLength;
      final body = await utf8.decoder.bind(request).join();
      controls.add(Map<String, Object?>.from(jsonDecode(body) as Map));
      request.response.statusCode = 204;
      await request.response.close();
      return;
    }
    if (request.method == 'GET' && path.startsWith('/art/')) {
      request.response.headers.contentType = ContentType('image', 'png');
      request.response.add(_pixel);
      await request.response.close();
      return;
    }
    if (request.method == 'GET' && path == '/browse' && hasLibrary) {
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({
          'tracks': [
            {'id': 'a', 'title': 'Kid A', 'artist': 'Radiohead'},
            {'id': 'b', 'title': 'Amnesiac', 'artist': 'Radiohead'},
          ],
        }),
      );
      await request.response.close();
      return;
    }
    request.response.statusCode = 404;
    await request.response.close();
  }

  Future<void> stop() async {
    await _server.close(force: true);
  }
}

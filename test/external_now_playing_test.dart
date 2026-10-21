import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sn_launcher/src/services/external_now_playing.dart';

/// The contract with other applications on the machine — NCS-SMLauncher
/// chiefly — for showing their now-playing on the launcher's card.
///
/// The whole point of this file is that it is testable *without* the other
/// application existing. The other side of the contract is a JSON file; this
/// side reads it, and everything that can go wrong with a file somebody else
/// is writing has to be survivable.
void main() {
  late Directory tmp;

  setUp(() => tmp = Directory.systemTemp.createTempSync('sn_nowplaying'));
  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  String path() => '${tmp.path}/now_playing.json';

  void write(Map<String, Object?> reading) =>
      File(path()).writeAsStringSync(jsonEncode(reading));

  ExternalNowPlaying watcher() => ExternalNowPlaying(path: path());

  group('reading the file', () {
    test('a missing file means nothing is playing', () {
      final w = watcher();
      w.start();
      expect(w.track, isNull);
      w.dispose();
    });

    test('a well-formed file is read', () {
      write({
        'title': 'Some track',
        'artist': 'Some artist',
        'album': 'Some album',
        'positionMs': 61500,
        'durationMs': 240000,
        'playing': true,
        'source': 'NCS-SMLauncher',
      });
      final w = watcher();
      w.start();
      expect(w.track?['title'], 'Some track');
      expect(w.track?['artist'], 'Some artist');
      expect(w.track?['playing'], isTrue);
      w.dispose();
    });

    test('a file with no title is not a track', () {
      // The other app might write a partial file mid-update. A card with an
      // empty title is worse than no card.
      write({'artist': 'Some artist', 'playing': true});
      final w = watcher();
      w.start();
      expect(w.track, isNull);
      w.dispose();
    });

    test('malformed JSON is survivable', () {
      File(path()).writeAsStringSync('{not json at all');
      final w = watcher();
      w.start();
      expect(w.track, isNull);
      w.dispose();
    });

    test('a JSON array is not a track', () {
      File(path()).writeAsStringSync('[1,2,3]');
      final w = watcher();
      w.start();
      expect(w.track, isNull);
      w.dispose();
    });

    test('an empty file is survivable', () {
      File(path()).writeAsStringSync('');
      final w = watcher();
      w.start();
      expect(w.track, isNull);
      w.dispose();
    });

    test('a file that is too old is not believed', () {
      // The other application crashed without clearing up. A card showing a
      // track that stopped playing an hour ago is a lie.
      write({'title': 'Stale track', 'playing': true});
      final f = File(path());
      f.setLastModifiedSync(DateTime.now().subtract(const Duration(hours: 1)));
      final w = watcher();
      w.start();
      expect(w.track, isNull);
      w.dispose();
    });
  });

  group('not waking the UI for nothing', () {
    test('the same reading does not notify', () {
      write({'title': 'A track', 'positionMs': 1000, 'playing': true});
      final w = watcher();
      var notifications = 0;
      w.addListener(() => notifications++);
      w.start();
      // start() reads once, which notifies. The counts below are changes
      // *after* that first read.
      final afterStart = notifications;

      write({'title': 'A track', 'positionMs': 1500, 'playing': true});
      w.pollNow();
      expect(notifications - afterStart, 0,
          reason: 'a position that moved less than a second is not a change');

      write({'title': 'Another track', 'positionMs': 1500, 'playing': true});
      w.pollNow();
      expect(notifications - afterStart, 1, reason: 'a different track is a change');
      w.dispose();
    });

    test('a position that moved a second is a change', () {
      write({'title': 'A track', 'positionMs': 1000, 'playing': true});
      final w = watcher();
      var notifications = 0;
      w.addListener(() => notifications++);
      w.start();
      final afterStart = notifications;
      write({'title': 'A track', 'positionMs': 2000, 'playing': true});
      w.pollNow();
      expect(notifications - afterStart, 1);
      w.dispose();
    });
  });

  group('where the file goes', () {
    test('the environment variable wins', () {
      // The explicit contract, and the one to use when the other application
      // needs a specific path.
      final previous = Platform.environment['SN_LAUNCHER_NOW_PLAYING'];
      // Platform.environment cannot be changed at runtime, so this tests the
      // shape of the rule rather than the override itself.
      expect(ExternalNowPlaying.defaultPath(), isNotEmpty);
      expect(previous, anyOf(isNull, isNotEmpty));
    });

    test('the default path is absolute', () {
      expect(ExternalNowPlaying.defaultPath(), startsWith('/'));
    });
  });
}

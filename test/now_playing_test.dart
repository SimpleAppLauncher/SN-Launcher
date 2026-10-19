import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sn_launcher/src/services/playback_service.dart';
import 'package:sn_launcher/src/theme/ambient_palette.dart';
import 'package:sn_launcher/src/theme/nest_icons.dart';
import 'package:sn_launcher/src/theme/nest_metrics.dart';
import 'package:sn_launcher/src/theme/nest_type.dart';
import 'package:sn_launcher/src/widgets/now_playing_card.dart';

const _scrubberKey = ValueKey('now-playing-scrubber');
const _staticTrackKey = ValueKey('now-playing-static-track');
const _playPauseKey = ValueKey('now-playing-play-pause');
const _previousKey = ValueKey('now-playing-previous');
const _nextKey = ValueKey('now-playing-next');
const _openKey = ValueKey('now-playing-open');
const _shotKey = ValueKey('now-playing-shot');

/// A player whose state the test sets directly.
///
/// Subclassing [PlaybackService] rather than mocking the method channel:
/// the widget's contract is "read `state`, send transport calls back", and
/// this exercises exactly that contract. The channel is never touched,
/// because every method that would touch it is overridden.
class _FakePlayback extends PlaybackService {
  _FakePlayback(this.current);

  PlaybackState current;

  /// What each transport call was handed, in order.
  final List<String> calls = <String>[];
  final List<Duration> seeks = <Duration>[];

  @override
  PlaybackState get state => current;

  /// Swap the state and notify — the platform does this through the channel,
  /// a headset does it through `handleExternalCommand`.
  void set(PlaybackState next) {
    current = next;
    notifyListeners();
  }

  @override
  Future<void> resume() async => calls.add('resume');

  @override
  Future<void> pause() async => calls.add('pause');

  @override
  Future<void> next() async => calls.add('next');

  @override
  Future<void> previous() async => calls.add('previous');

  @override
  Future<void> seek(Duration to) async => seeks.add(to);
}

const _track = Track(
  url: 'https://example.com/audio/cirrus.m4a',
  title: 'Cirrus',
  artist: 'Bonobo',
  album: 'The North Borders',
);

PlaybackState _playing({
  Track track = _track,
  bool playing = true,
  bool loading = false,
  Duration position = const Duration(seconds: 10),
  Duration duration = const Duration(seconds: 100),
}) =>
    PlaybackState(
      playing: playing,
      loading: loading,
      position: position,
      duration: duration,
      track: track,
    );

/// A live radio track. The duration is deliberately *set* — a live stream
/// whose platform happens to report a length must still hide the total, so
/// the test proves the `isLive` flag is what hides it, not a zero duration.
final _liveState = PlaybackState(
  playing: true,
  position: const Duration(minutes: 5),
  duration: const Duration(hours: 1),
  track: const Track(
    url: 'https://example.com/live/aac',
    title: 'BBC Radio 6 Music',
    artist: 'BBC',
    isLive: true,
    duration: Duration(hours: 1),
  ),
);

Future<_FakePlayback> _pump(
  WidgetTester tester,
  PlaybackState state, {
  VoidCallback? onOpen,
}) async {
  final fake = _FakePlayback(state);
  final m = NestMetrics.forSize(const Size(1024, 600));
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(fontFamily: 'GoogleSans'),
      home: Material(
        color: const Color(0xFF101418),
        child: Center(
          child: RepaintBoundary(
            key: _shotKey,
            child: SizedBox(
              width: 560,
              child: NowPlayingCard(
                metrics: m,
                type: NestType(m),
                palette: AmbientPalette.of(NestTheme.day),
                playback: fake,
                onOpen: onOpen,
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  return fake;
}

Future<void> _loadRealFonts() async {
  // Without these, every glyph renders as an Ahem box and every test below
  // would pass happily while proving nothing about what is on screen — this
  // exact failure mode has shipped here before. The Material Symbols font
  // matters most: the play/pause assertions find IconData (which never
  // consults the font), so only a screenshot can say the glyph is really
  // there.
  final text = FontLoader('GoogleSans')
    ..addFont(rootBundle.load('assets/fonts/GoogleSans-400.ttf'));
  await text.load();
  final symbols = FontLoader('MaterialSymbolsRounded')
    ..addFont(rootBundle.load('assets/fonts/MaterialSymbolsRounded.ttf'));
  await symbols.load();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(_loadRealFonts);

  group('when nothing is playing', () {
    testWidgets('it says so instead of showing an empty player',
        (tester) async {
      await _pump(tester, const PlaybackState());
      expect(find.text('Nothing playing'), findsOneWidget);
      expect(find.byKey(_scrubberKey), findsNothing);
      expect(find.byKey(_staticTrackKey), findsNothing);
      expect(find.byKey(_playPauseKey), findsNothing);
      expect(find.byKey(_previousKey), findsNothing);
      // An idle card carries no clock at all: "0:00" next to nothing is a
      // claim that something has a position.
      expect(
        find.textContaining(RegExp(r'^\d+:\d{2}(:\d{2})?$')),
        findsNothing,
      );
    });

    testWidgets('while the platform is still loading it says that',
        (tester) async {
      await _pump(tester, const PlaybackState(loading: true));
      expect(find.text('Loading…'), findsOneWidget);
      expect(find.text('Nothing playing'), findsNothing);
    });
  });

  group('while a track plays', () {
    testWidgets('shows the title, the artist and both times', (tester) async {
      await _pump(tester, _playing());
      expect(find.text('Cirrus'), findsOneWidget);
      expect(find.text('Bonobo'), findsOneWidget);
      expect(find.byKey(_scrubberKey), findsOneWidget);
      expect(find.text('0:10'), findsOneWidget); // elapsed
      expect(find.text('1:40'), findsOneWidget); // total
    });

    testWidgets('the play/pause icon follows the playing state',
        (tester) async {
      final fake = await _pump(tester, _playing(playing: true));
      expect(find.byIcon(NestIcons.Pause), findsOneWidget);
      expect(find.byIcon(NestIcons.PlayArrow), findsNothing);

      fake.set(_playing(playing: false));
      await tester.pump();
      expect(find.byIcon(NestIcons.PlayArrow), findsOneWidget);
      expect(find.byIcon(NestIcons.Pause), findsNothing);

      await tester.tap(find.byKey(_playPauseKey));
      await tester.pump();
      expect(fake.calls, ['resume']);

      fake.set(_playing(playing: true));
      await tester.pump();
      await tester.tap(find.byKey(_playPauseKey));
      await tester.pump();
      expect(fake.calls, ['resume', 'pause']);
    });

    testWidgets('previous and next go to the service', (tester) async {
      final fake = await _pump(tester, _playing());
      await tester.tap(find.byKey(_previousKey));
      await tester.pump();
      await tester.tap(find.byKey(_nextKey));
      await tester.pump();
      expect(fake.calls, ['previous', 'next']);
    });

    testWidgets('onOpen opens the full player', (tester) async {
      var opened = false;
      await _pump(
        tester,
        _playing(),
        onOpen: () => opened = true,
      );
      await tester.tap(find.byKey(_openKey));
      await tester.pump();
      expect(opened, isTrue);
    });

    testWidgets('without an onOpen there is no dead chevron', (tester) async {
      await _pump(tester, _playing());
      expect(find.byKey(_openKey), findsNothing);
    });
  });

  group('the card repaints when playback changes', () {
    // The whole point of listening to the ChangeNotifier. If this widget
    // ever stops listening, this test fails — which is the test the project
    // keeps needing.
    testWidgets('a new track replaces the old one', (tester) async {
      final fake = await _pump(tester, _playing());
      expect(find.text('Cirrus'), findsOneWidget);

      fake.set(_playing(
        track: const Track(
          url: 'https://example.com/audio/xtal.mp3',
          title: 'Xtal',
          artist: 'Autechre',
        ),
        position: Duration.zero,
      ));
      await tester.pump();

      expect(find.text('Xtal'), findsOneWidget);
      expect(find.text('Autechre'), findsOneWidget);
      expect(find.text('Cirrus'), findsNothing);
    });

    testWidgets('an error raised later replaces the player',
        (tester) async {
      final fake = await _pump(tester, _playing());
      expect(find.byKey(_playPauseKey), findsOneWidget);

      fake.set(const PlaybackState(
        error: 'The player did not accept that track',
      ));
      await tester.pump();

      expect(find.text('The player did not accept that track'), findsOneWidget);
      expect(find.byKey(_playPauseKey), findsNothing);
    });
  });

  group('a live stream', () {
    testWidgets('has no scrubber to drag', (tester) async {
      await _pump(tester, _liveState);
      expect(find.byKey(_scrubberKey), findsNothing);
      expect(find.byKey(_staticTrackKey), findsOneWidget);
    });

    testWidgets('hides the total and says Live, but keeps the elapsed',
        (tester) async {
      await _pump(tester, _liveState);
      expect(find.text('Live'), findsOneWidget);
      expect(find.text('1:00:00'), findsNothing);
      expect(find.text('5:00'), findsOneWidget);
    });

    testWidgets('cannot be seeked by dragging the static track',
        (tester) async {
      final fake = await _pump(tester, _liveState);
      final gesture =
          await tester.startGesture(tester.getCenter(find.byKey(_staticTrackKey)));
      await gesture.moveBy(const Offset(80, 0));
      await tester.pump();
      await gesture.up();
      await tester.pump();
      expect(fake.seeks, isEmpty);
    });
  });

  group('when the duration is unknown', () {
    testWidgets('the total is hidden rather than shown as 0:00',
        (tester) async {
      await _pump(
        tester,
        PlaybackState(
          playing: true,
          position: const Duration(seconds: 30),
          track: _track,
        ),
      );
      expect(find.byKey(_scrubberKey), findsNothing);
      expect(find.byKey(_staticTrackKey), findsOneWidget);
      expect(find.text('0:30'), findsOneWidget);
      // Exactly one time on screen: the elapsed. A second would be an
      // invented total.
      expect(
        find.textContaining(RegExp(r'^\d+:\d{2}(:\d{2})?$')),
        findsOneWidget,
      );
    });
  });

  group('the error', () {
    testWidgets('is shown verbatim, instead of a working-looking player',
        (tester) async {
      await _pump(
        tester,
        const PlaybackState(error: 'This build has no audio player'),
      );
      expect(find.text('This build has no audio player'), findsOneWidget);
      expect(find.byKey(_playPauseKey), findsNothing);
      expect(find.byKey(_scrubberKey), findsNothing);
      expect(find.text('Nothing playing'), findsNothing,
          reason: 'a failure must not be dressed up as an idle card');
    });

    testWidgets('still wins when a track is loaded alongside it',
        (tester) async {
      await _pump(
        tester,
        PlaybackState(
          error: 'Playback failed',
          track: _track,
        ),
      );
      expect(find.text('Playback failed'), findsOneWidget);
      expect(find.byKey(_playPauseKey), findsNothing,
          reason: 'no normal-looking player over a failure');
    });
  });

  group('the scrubber', () {
    testWidgets('seeks once, on release — not on every move', (tester) async {
      final fake = await _pump(tester, _playing());
      final scrubber = find.byKey(_scrubberKey);
      final width = tester.getSize(scrubber).width;
      final gesture = await tester.startGesture(tester.getCenter(scrubber));
      await tester.pump(const Duration(milliseconds: 50));

      // Two moves: the first is consumed by touch slop and starts the
      // recogniser, the second is a real update that carries the final
      // position. Start and update rather than one big drag, so the seek
      // value does not depend on where the recogniser decided to fire.
      await gesture.moveBy(Offset(width * 0.15, 0));
      await tester.pump(const Duration(milliseconds: 50));
      expect(fake.seeks, isEmpty,
          reason: 'seeking fires on release, not on every pointer move');

      await gesture.moveBy(Offset(width * 0.10, 0));
      await tester.pump(const Duration(milliseconds: 50));
      await gesture.up();
      await tester.pump();

      expect(fake.seeks, hasLength(1));
      // Dragged from the centre to three-quarters across a 100s track, so
      // the seek must land near 75s — not at the old position (10s), not at
      // zero, not at the end.
      expect(
        fake.seeks.single.inMilliseconds,
        inInclusiveRange(70000, 80000),
        reason: 'a drag to 75% of a 100s track should seek to ~75s',
      );
    });

    testWidgets('thumb sits where the position says it should',
        (tester) async {
      // 10s into a 100s track: the fill must be a tenth of the width. If the
      // bar ever renders at a constant width, this is what catches it.
      await _pump(tester, _playing());
      final containers = tester.widgetList<Container>(
        find.descendant(
          of: find.byKey(_scrubberKey),
          matching: find.byType(Container),
        ),
      );
      // Track, fill, thumb — in that order. Container folds width: into its
      // constraints, so all three report an explicit width.
      final widths = containers
          .map((c) => c.constraints?.maxWidth)
          .whereType<double>()
          .toList();
      expect(widths, hasLength(3),
          reason: 'track, fill and thumb, each explicitly sized');
      expect(
        widths[1] / widths[0],
        closeTo(0.1, 0.01),
        reason: '10s into a 100s track must fill a tenth of the track',
      );
    });
  });

  // The repo has shipped "passing" icon tests whose glyphs were a grid of
  // Ahem boxes, and a passing test can be a passing test of nothing. These
  // measure the actual pixels: text that rendered as solid blocks is almost
  // as dark as the baseline box font, and a glyph that rendered as nothing
  // has no ink at all. The baseline is rendered in the same environment, so
  // the thresholds calibrate themselves instead of being guessed.
  group('what actually rendered', () {
    const baselineKey = ValueKey('now-playing-baseline');

    double inkIn(ByteData bytes, int width, int height, Rect rect) {
      final data =
          bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes);
      var x0 = rect.left.floor();
      var y0 = rect.top.floor();
      var x1 = rect.right.ceil();
      var y1 = rect.bottom.ceil();
      if (x0 < 0) x0 = 0;
      if (y0 < 0) y0 = 0;
      if (x1 > width) x1 = width;
      if (y1 > height) y1 = height;
      var dark = 0;
      var total = 0;
      for (var y = y0; y < y1; y++) {
        for (var x = x0; x < x1; x++) {
          final i = (y * width + x) * 4;
          if (i + 3 >= data.length) continue;
          final lum =
              0.299 * data[i] + 0.587 * data[i + 1] + 0.114 * data[i + 2];
          if (lum < 140) dark++;
          total++;
        }
      }
      return total == 0 ? 0 : dark / total;
    }

    Future<double> coverageOf(
      WidgetTester tester,
      Finder boundary,
      Rect globalRect,
    ) async {
      var result = 0.0;
      await tester.runAsync(() async {
        final repaint =
            tester.renderObject<RenderRepaintBoundary>(boundary);
        final image = await repaint.toImage(pixelRatio: 1.0);
        final bytes =
            await image.toByteData(format: ui.ImageByteFormat.rawRgba);
        if (bytes == null) return;
        final origin = tester.getTopLeft(boundary);
        result = inkIn(
          bytes,
          image.width,
          image.height,
          globalRect.translate(-origin.dx, -origin.dy),
        );
      });
      return result;
    }

    testWidgets('the title and the play glyph are ink, not boxes',
        (tester) async {
      await _pump(tester, _playing());

      // Independent of pixels: an unset font advances every glyph by exactly
      // one em, so a box-font "Cirrus" at 24px would measure ~6 x 24 wide.
      // Google Sans sets it at roughly three ems.
      final titleWidth = tester.getSize(find.text('Cirrus')).width;
      expect(titleWidth, lessThan(130),
          reason: 'Cirrus in Google Sans is ~75px; in the box font ~145px');

      final titleCov = await coverageOf(
        tester,
        find.byKey(_shotKey),
        tester.getRect(find.text('Cirrus')),
      );
      // playing: true, so the pause glyph is on screen.
      final iconCov = await coverageOf(
        tester,
        find.byKey(_shotKey),
        tester.getRect(find.byIcon(NestIcons.Pause)),
      );

      // The baseline: text in a font that does not exist, which the test
      // environment draws as solid boxes. Whatever real ink looks like here,
      // it must be clearly less dense than a block and clearly not empty.
      await tester.pumpWidget(
        MaterialApp(
          home: RepaintBoundary(
            key: baselineKey,
            child: Material(
              color: Colors.white,
              child: Center(
                child: Text(
                  'III',
                  style: const TextStyle(
                    fontSize: 22,
                    fontFamily: 'FontThatDoesNotExistAnywhere',
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      final blockCov = await coverageOf(
        tester,
        find.byKey(baselineKey),
        tester.getRect(find.text('III')),
      );

      debugPrint('ink coverage — title: ${titleCov.toStringAsFixed(3)}, '
          'pause glyph: ${iconCov.toStringAsFixed(3)}, '
          'box-font baseline: ${blockCov.toStringAsFixed(3)}');

      expect(titleCov, greaterThan(0.05),
          reason: 'the title rendered nothing at all');
      expect(titleCov, lessThan(blockCov * 0.75),
          reason: 'title ink is as dense as solid boxes: wrong font');
      expect(iconCov, greaterThan(0.05),
          reason: 'the pause glyph rendered as nothing — missing codepoint '
              'or font not loaded');
      expect(iconCov, lessThan(blockCov * 0.75),
          reason: 'the pause glyph is a solid block, not a glyph');
    });
  });

  // Written so the card can be looked at, because every visual bug in this
  // project's history was invisible to a passing assertion: an Ahem box
  // where a play triangle should be, text spilling out of the card, a bar
  // drawn at full width while the label said 0:10.
  group('screenshots', () {
    final dir = Directory('build/now_playing_shots');
    if (!dir.existsSync()) dir.createSync(recursive: true);

    Future<void> shot(WidgetTester tester, String name) async {
      await tester.runAsync(() async {
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(_shotKey),
        );
        final image = await boundary.toImage(pixelRatio: 1.0);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        if (bytes == null) return;
        File('${dir.path}/$name.png')
            .writeAsBytesSync(bytes.buffer.asUint8List());
      });
    }

    testWidgets('idle', (tester) async {
      await _pump(tester, const PlaybackState());
      await shot(tester, 'idle');
    });

    testWidgets('playing', (tester) async {
      await _pump(tester, _playing());
      await shot(tester, 'playing');
    });

    testWidgets('live', (tester) async {
      await _pump(tester, _liveState);
      await shot(tester, 'live');
    });

    testWidgets('error', (tester) async {
      await _pump(
        tester,
        const PlaybackState(error: 'This build has no audio player'),
      );
      await shot(tester, 'error');
    });
  });
}

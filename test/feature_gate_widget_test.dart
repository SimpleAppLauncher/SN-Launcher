import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sn_launcher/src/screens/nest_shell.dart';
import 'package:sn_launcher/src/services/assistant_service.dart';
import 'package:sn_launcher/src/services/clock_service.dart';
import 'package:sn_launcher/src/services/feature_flags.dart';
import 'package:sn_launcher/src/services/settings_store.dart';
import 'package:sn_launcher/src/services/todo_service.dart';
import 'package:sn_launcher/src/services/weather_service.dart';
import 'package:sn_launcher/src/state/shell_controller.dart';
import 'package:sn_launcher/src/theme/ambient_palette.dart';
import 'package:sn_launcher/src/theme/nest_icons.dart';
import 'package:sn_launcher/src/theme/nest_metrics.dart';
import 'package:sn_launcher/src/widgets/assistant_lightbar.dart';

/// The point of these: [feature_flags_test.dart] proves the *config files* are
/// right, which is not the same thing as proving the *GUI* honours them. A flag
/// that parses and is then never read is a plausible, silent failure — and one
/// already happened here, with `quickSettings`, which was declared in both
/// JSON files and gated nowhere.
///
/// So: render the real shell with each shipped config and assert on what is
/// actually on screen.
FeatureFlags efFlags() =>
    FeatureFlags.parse(File('assets/features.ef.json').readAsStringSync(), 'ef');

FeatureFlags reducedFlags() => FeatureFlags.parse(
  File('assets/features.json').readAsStringSync(),
  'reduced',
);

const _size = Size(1280, 800);

class _Harness extends StatefulWidget {
  const _Harness({
    required this.controller,
    required this.clock,
    required this.weather,
    required this.assistant,
    required this.todo,
  });

  final ShellController controller;
  final ClockService clock;
  final WeatherService weather;

  /// A real AssistantService, not a stub. The lightbar gate reads
  /// `assist != null`, so passing null here would make "absent in the reduced
  /// build" pass for entirely the wrong reason.
  final AssistantService assistant;

  /// Same reasoning. The to-do card is only rendered when the service is
  /// present, so a harness without one would quietly not render it.
  final TodoService todo;

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> with TickerProviderStateMixin {
  @override
  void dispose() {
    widget.controller.dispose();
    widget.clock.dispose();
    widget.weather.dispose();
    widget.assistant.dispose();
    widget.todo.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData(fontFamily: 'GoogleSans'),
    home: Material(
      color: const Color(0xFF000000),
      child: NestShell(
        controller: widget.controller,
        clock: widget.clock,
        weather: widget.weather,
        assistant: widget.assistant,
        todo: widget.todo,
        animateDecorations: false,
      ),
    ),
  );
}

Future<_Harness> _pump(
  WidgetTester tester, {
  required ShellPage page,
}) async {
  final clock = ClockService(showSeconds: true, autoTick: false);
  final weather = WeatherService();
  // Constructed but never asked to listen: constructing touches no platform
  // channel, and _startListening is never invoked in these tests.
  final assistant = AssistantService();
  // A real service, backed by a throwaway file. If the shell is handed a null
  // service the to-do card is silently not rendered, and a test that does not
  // supply one proves nothing about the card being there.
  final todo = TodoService(SettingsStore(
    fallbackPath: '${Directory.systemTemp.path}/sn_gate_test.json',
  ));
  final controller = ShellController(
    metrics: NestMetrics.forSize(_size),
    vsync: tester,
  );
  controller.setPaletteForTest(AmbientPalette.at(12));
  controller.setSheetForTest(0);
  controller.goToPage(page);
  clock.overrideForTesting(DateTime(2022, 5, 26, 12, 0, 0));

  await tester.pumpWidget(
    _Harness(
      controller: controller,
      clock: clock,
      weather: weather,
      assistant: assistant,
      todo: todo,
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  return _Harness(
    controller: controller,
    clock: clock,
    weather: weather,
    assistant: assistant,
    todo: todo,
  );
}

void main() {
  final ef = efFlags();
  final reduced = reducedFlags();

  tearDown(() {
    // Leave the static as the reduced build, so one test cannot hand another
    // a configuration it did not set up.
    FeatureFlags.forTesting = reduced;
  });


  group('the carousel gesture', () {
    // The shell accumulated the drag distance itself — `DragEndDetails` has the
    // velocity but not how far the finger travelled — and it passed the
    // distance as zero, so only a fast flick could change the page. A slow
    // drag across the screen did nothing at all.
    testWidgets('a slow drag changes the page', (tester) async {
      FeatureFlags.forTesting = ef;
      final harness = await _pump(tester, page: ShellPage.home);
      expect(harness.controller.page, ShellPage.home);

      // A slow drag: `timedDrag` moves the pointer in steps over a duration
      // rather than flinging it, so the gesture ends with no velocity. That is
      // the case that used to do nothing.
      // Slow enough that the velocity is under the flick threshold:
      // 400px over 2s is 200px/s, and a flick is anything over 260. A faster
      // drag would still be a flick and the test would pass even with the
      // distance thrown away.
      await tester.timedDrag(
        find.byType(NestShell),
        const Offset(-400, 0),
        const Duration(milliseconds: 2000),
        frequency: 60.0,
      );
      await tester.pump(const Duration(milliseconds: 400));

      expect(
        harness.controller.page,
        isNot(ShellPage.home),
        reason: 'a 400px drag is well past the 18% threshold',
      );
    });

    testWidgets('a small drag does not change the page', (tester) async {
      FeatureFlags.forTesting = ef;
      final harness = await _pump(tester, page: ShellPage.home);
      await tester.timedDrag(
        find.byType(NestShell),
        const Offset(-40, 0),
        const Duration(milliseconds: 600),
        frequency: 60.0,
      );
      await tester.pump(const Duration(milliseconds: 400));
      expect(harness.controller.page, ShellPage.home);
    });

    testWidgets('the left arrow key goes to the next page', (tester) async {
      // These two were the wrong way round: LEFT went back and RIGHT went
      // forward, so a D-pad or an Android TV remote paged the wrong way.
      FeatureFlags.forTesting = ef;
      final harness = await _pump(tester, page: ShellPage.home);
      expect(harness.controller.page, ShellPage.home);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump(const Duration(milliseconds: 400));
      expect(
        harness.controller.page,
        ShellPage.digest,
        reason: 'left is the next page, because the first page is left-most',
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump(const Duration(milliseconds: 400));
      expect(harness.controller.page, ShellPage.home);
    });
  });

  group('the settings gear', () {
    testWidgets('is on screen in the ef build', (tester) async {
      FeatureFlags.forTesting = ef;
      await _pump(tester, page: ShellPage.home);
      expect(find.byIcon(NestIcons.Settings), findsOneWidget);
    });

    testWidgets('is on screen in the reduced build too', (tester) async {
      // This is the capability the user asked to keep in both.
      FeatureFlags.forTesting = reduced;
      await _pump(tester, page: ShellPage.home);
      expect(find.byIcon(NestIcons.Settings), findsOneWidget);
    });

    testWidgets('disappears when the feature is off', (tester) async {
      // Neither shipped config has settings off, so the two tests above cannot
      // tell whether this gate works at all — deleting it would change nothing
      // and they would both still pass. This third configuration is what makes
      // the gate real.
      FeatureFlags.forTesting = FeatureFlags.parse('{"features":{}}', 'none');
      await _pump(tester, page: ShellPage.home);
      expect(find.byIcon(NestIcons.Settings), findsNothing);
    });
  });

  group('the assistant lightbar', () {
    testWidgets('is on screen in the ef build', (tester) async {
      FeatureFlags.forTesting = ef;
      await _pump(tester, page: ShellPage.home);
      expect(find.byType(AssistantLightbar), findsOneWidget);
    });

    testWidgets('is absent in the reduced build', (tester) async {
      // The rule this repo is built on: never show an affordance for something
      // this build cannot do. A reduced build with a listening bar that does
      // nothing is the same lie as the old four-dot orb.
      FeatureFlags.forTesting = reduced;
      await _pump(tester, page: ShellPage.home);
      expect(find.byType(AssistantLightbar), findsNothing);
    });
  });

  group('the digest page', () {
    testWidgets('renders cards in the ef build', (tester) async {
      FeatureFlags.forTesting = ef;
      await _pump(tester, page: ShellPage.digest);
      expect(find.textContaining('Good'), findsOneWidget);
      expect(find.text('Theme'), findsOneWidget);
      expect(find.text('Calendar'), findsOneWidget);
      expect(find.text('Music'), findsOneWidget);
    });

    testWidgets('the weather is not a card on the digest page', (tester) async {
      // It has a page of its own now. A card squeezed beside four others
      // showed a temperature and two words.
      FeatureFlags.forTesting = ef;
      await _pump(tester, page: ShellPage.digest);
      expect(find.text('Weather'), findsNothing);
    });

    testWidgets('shows a calendar and nothing else in the reduced build', (tester) async {
      // The reduced build is a launcher with a calendar. The greeting and the
      // Calendar card must be there; every other card must not, because a
      // card with a dead control is the same lie as a dead button.
      //
      // Asserted on the greeting as well as the cards. The cards are
      // individually gated, so checking only their absence would pass even if
      // the page-level gate were deleted — the row would be empty either way.
      FeatureFlags.forTesting = reduced;
      await _pump(tester, page: ShellPage.digest);
      expect(find.textContaining('Good'), findsOneWidget);
      expect(find.text('Calendar'), findsOneWidget);
      // The date the events belong to. The card used to show a time and a
      // title and nothing else, so "Nothing else today" never said which day
      // "today" was.
      //
      // At least one, not exactly one: the shell keeps the home page alive in
      // the carousel, and the clock block there shows the same date.
      expect(find.text('Thu, May 26'), findsWidgets);
      expect(find.text('Weather'), findsNothing);
      expect(find.text('Music'), findsNothing);
      expect(find.text('Photos'), findsNothing);
      expect(find.text('Theme'), findsNothing);
      expect(find.text('Weather'), findsNothing);
    });

    testWidgets('is unreachable at all when the digest page is off', (tester) async {
      // A build with calendar on but digestPage off is the shape that made the
      // reduced build look broken on hardware: a calendar rendering on a page
      // nobody can reach. Both flags have to travel together.
      FeatureFlags.forTesting = FeatureFlags.parse(
        '{"features":{"calendar":true}}',
        'orphan',
      );
      await _pump(tester, page: ShellPage.digest);
      expect(find.textContaining('Good'), findsNothing);
      expect(find.text('Calendar'), findsNothing);
    });
  });

  group('the home page is unaffected by any of it', () {
    // The ef build must look exactly like the current app — that was the
    // point of shipping it with no GUI change, so the test on real hardware
    // would be about whether it runs, not about how it looks.
    for (final entry in {'ef': ef, 'reduced': reduced}.entries) {
      testWidgets('${entry.key} build renders the clock', (tester) async {
        FeatureFlags.forTesting = entry.value;
        await _pump(tester, page: ShellPage.home);
        expect(find.text('12:00'), findsOneWidget);
        expect(find.byType(AssistantLightbar), entry.key == 'ef' ? findsOneWidget : findsNothing);
      });
    }
  });
}
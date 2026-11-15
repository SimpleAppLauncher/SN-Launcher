import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sn_launcher/src/models/nest_action.dart';
import 'package:sn_launcher/src/screens/nest_shell.dart';
import 'package:sn_launcher/src/services/assistant_service.dart';
import 'package:sn_launcher/src/services/clock_service.dart';
import 'package:sn_launcher/src/services/feature_flags.dart';
import 'package:sn_launcher/src/services/speech_to_text.dart';
import 'package:sn_launcher/src/services/weather_service.dart';
import 'package:sn_launcher/src/state/shell_controller.dart';
import 'package:sn_launcher/src/theme/ambient_palette.dart';
import 'package:sn_launcher/src/theme/nest_icons.dart';
import 'package:sn_launcher/src/theme/nest_metrics.dart';
import 'package:sn_launcher/src/widgets/voice_widgets.dart';

/// The controls that live in the shell rather than in a page — the settings
/// gear, the listening lightbar, the microphone button and the timer chip —
/// have to be *above* the page carousel.
///
/// They were below it. On the home page the photograph is opaque and covers
/// the screen, so all four were invisible there. Worse, the photograph's
/// crossfade is a `FadeTransition`, and a fade absorbs taps: the home page
/// swallowed every touch, which is why the settings gear did not open the
/// settings from the home screen and the microphone button did nothing.
///
/// Found by looking at a screenshot taken on a phone, which is the only way
/// it could have been found: no test asserted that the gear was reachable.
class _SilentSpeech extends SpeechToText {
  @override
  Future<String?> listenOnce({int timeoutMs = 8000}) =>
      Completer<String?>().future;
}

const _size = Size(1280, 800);

FeatureFlags _reducedFlags() => FeatureFlags.parse(
  File('assets/features.json').readAsStringSync(),
  'reduced',
);

/// The index of [widget] in the shell's own stack.
int _indexOfChild(List<Widget> children, Widget widget) =>
    children.indexWhere((c) => identical(c, widget));

Future<AssistantService> _pumpShell(
  WidgetTester tester, {
  required AssistantService assistant,
}) async {
  FeatureFlags.forTesting = _reducedFlags();

  final clock = ClockService(showSeconds: false, autoTick: false);
  final weather = WeatherService();
  final controller = ShellController(
    metrics: NestMetrics.forSize(_size),
    vsync: tester,
  );
  controller.setPaletteForTest(AmbientPalette.at(12));
  controller.setSheetForTest(0);
  controller.goToPage(ShellPage.home);
  clock.overrideForTesting(DateTime(2022, 5, 26, 12, 0, 0));

  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Material(
        color: const Color(0xFF000000),
        child: NestShell(
          controller: controller,
          clock: clock,
          weather: weather,
          assistant: assistant,
          animateDecorations: false,
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  addTearDown(() {
    controller.dispose();
    clock.dispose();
    weather.dispose();
  });
  return assistant;
}

void main() {
  testWidgets('the microphone button is painted above the page', (tester) async {
    final assistant = AssistantService(stt: _SilentSpeech());
    addTearDown(assistant.dispose);
    await _pumpShell(tester, assistant: assistant);

    final mic = find.byType(MicButton);
    expect(mic, findsOneWidget);

    // The shell's own stack: the one the overlays and the carousel are
    // children of. It is the only stack above the microphone button.
    final stack = tester.widget<Stack>(
      find.ancestor(of: mic, matching: find.byType(Stack)).first,
    );
    final children = stack.children;

    final micIndex = _indexOfChild(
      children,
      tester.widget<Positioned>(
        find.ancestor(of: mic, matching: find.byType(Positioned)).first,
      ),
    );
    // The carousel is the one plain stack among the shell's children; the
    // overlays are all Positioned.
    final carouselIndex = children.indexWhere((c) => c is Stack);

    expect(
      micIndex,
      greaterThan(carouselIndex),
      reason: 'the microphone button is painted under the page, so the '
          'photograph covers it and swallows the tap',
    );
  });

  testWidgets('the settings gear is painted above the page', (tester) async {
    final assistant = AssistantService(stt: _SilentSpeech());
    addTearDown(assistant.dispose);
    await _pumpShell(tester, assistant: assistant);

    final gear = find.byIcon(NestIcons.Settings);
    expect(gear, findsOneWidget);

    final stack = tester.widget<Stack>(
      find.ancestor(of: gear, matching: find.byType(Stack)).first,
    );
    final children = stack.children;

    final gearIndex = _indexOfChild(
      children,
      tester.widget<Positioned>(
        find.ancestor(of: gear, matching: find.byType(Positioned)).first,
      ),
    );
    final carouselIndex = children.indexWhere((c) => c is Stack);

    expect(
      gearIndex,
      greaterThan(carouselIndex),
      reason: 'the settings gear is painted under the page, so on the home '
          'screen — where the photograph covers everything — the gear could '
          'not be seen or tapped',
    );
  });

  testWidgets('tapping the microphone button starts listening', (tester) async {
    final assistant = AssistantService(stt: _SilentSpeech());
    addTearDown(assistant.dispose);
    await _pumpShell(tester, assistant: assistant);

    expect(find.byType(MicButton), findsOneWidget);
    expect(assistant.activity, AssistActivity.idle);

    await tester.tap(find.byType(MicButton));
    await tester.pump();

    expect(
      assistant.activity,
      AssistActivity.listening,
      reason: 'the tap never reached the button: the photograph was painted '
          'over it and absorbed the touch',
    );
  });
}

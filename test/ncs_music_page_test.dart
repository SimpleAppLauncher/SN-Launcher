import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sn_launcher/src/services/ncs_client.dart';
import 'package:sn_launcher/src/theme/nest_icons.dart';
import 'package:sn_launcher/src/theme/nest_metrics.dart';
import 'package:sn_launcher/src/theme/nest_type.dart';
import 'package:sn_launcher/src/widgets/ncs_music_page.dart';

import 'ncs_client_test.dart' show FakePlayer;

/// What the music page puts on the screen.
///
/// These assert on rendered text rather than on the client's fields, because
/// the lesson this project keeps relearning is that a passing test on the
/// bookkeeping can hide a page that draws nothing.
///
/// The page is pumped with `isCurrent: false`. That is not a shortcut: the page
/// deliberately starts polling and loads its library only while it is the page
/// on screen, and a widget test runs on a fake clock on which a real socket
/// never completes. Saying "not the visible page" is what makes the test able
/// to assert on rendering at all. The polling itself is covered in
/// `ncs_client_test.dart`, against a real server.
void main() {
  setUpAll(() => HttpOverrides.global = null);

  const surface = Size(800, 1340);

  // The server is started in `setUp` and not inside a `testWidgets` body. A
  // test body runs on a fake clock, and a server whose request handler was
  // registered on that clock never answers: the client connects, sends, and
  // waits for a reply that is queued behind a timer that is not running.
  // `setUp` runs on the real one.
  late FakePlayer player;
  setUp(() async => player = await FakePlayer.start());
  tearDown(() async => player.stop());

  Future<void> pumpPage(
    WidgetTester tester,
    NcsClient client, {
    bool current = false,
  }) async {
    tester.view.physicalSize = surface;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final metrics = NestMetrics.forSize(surface);
    await tester.pumpWidget(
      MaterialApp(
        home: NcsMusicPage(
          client: client,
          metrics: metrics,
          type: NestType(metrics),
          isCurrent: current,
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> finish(WidgetTester tester, NcsClient client) async {
    client.stop();
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    client.dispose();
  }

  testWidgets('says how to connect when no player is set', (tester) async {
    final client = NcsClient();
    await pumpPage(tester, client, current: true);

    expect(find.text('Connect NCS-SMLauncher'), findsOneWidget);
    expect(find.text('Music'), findsOneWidget);
    expect(find.text('Not connected'), findsOneWidget);
    // The field is there, and it is a real text field — the assertion that
    // caught the page being built without a Material ancestor.
    expect(find.byType(TextField), findsOneWidget);

    await finish(tester, client);
  });

  testWidgets('draws the track, the feed and the mini player', (tester) async {
    final client = NcsClient(baseUrl: player.url);
    await tester.runAsync(() async => client.refresh());
    expect(client.connected, isTrue);

    await pumpPage(tester, client);

    expect(find.text('Music'), findsOneWidget);
    // The chip names the player rather than saying "connected", so a glance
    // tells you *which* box in the house is playing.
    expect(find.text('NCS-SMLauncher'), findsOneWidget);

    expect(find.text('Quick picks'), findsOneWidget);
    expect(find.text('Up next'), findsOneWidget);

    // The mini player is the current track, not a queue entry.
    expect(find.text('Everything In Its Right Place'), findsOneWidget);
    expect(find.text('Kid A'), findsWidgets);

    await finish(tester, client);
  });

  testWidgets('the transport buttons are wired', (tester) async {
    final client = NcsClient(baseUrl: player.url);
    await tester.runAsync(() async => client.refresh());

    await pumpPage(tester, client);

    for (final icon in [NestIcons.Pause, NestIcons.SkipNext]) {
      final button = tester.widget<IconButton>(
        find
            .ancestor(
              of: find.byIcon(icon).first,
              matching: find.byType(IconButton),
            )
            .first,
      );
      expect(button.onPressed, isNotNull, reason: '$icon is a dead button');
    }

    await finish(tester, client);
  });

  testWidgets('an unreachable player says so and keeps the field', (
    tester,
  ) async {
    final client = NcsClient(baseUrl: 'http://127.0.0.1:1');
    await tester.runAsync(() async => client.refresh());
    expect(client.connected, isFalse);

    await pumpPage(tester, client);

    expect(find.text('Connect NCS-SMLauncher'), findsOneWidget);
    expect(find.textContaining('No player at'), findsOneWidget);
    // The address it tried is still in the field, so a typo is one edit away
    // from working rather than a page you have to start over.
    expect(find.text('http://127.0.0.1:1'), findsOneWidget);

    await finish(tester, client);
  });
}

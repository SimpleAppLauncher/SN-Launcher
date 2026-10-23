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

  // The Samsung's real shape, landscape. Not a round number picked for the
  // test: the page had a 3-column grid and a caption that overflowed at this
  // size, and a portrait surface hid both.
  const surface = Size(1340, 800);

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

    // The mini player is the current track, not a queue entry.
    expect(find.text('Everything In Its Right Place'), findsOneWidget);
    expect(find.text('Kid A'), findsWidgets);

    // "Up next" is below the fold on a landscape tablet, so scroll to it the
    // way the user has to. A sliver that is off screen is not built, and the
    // finder would report a section that is there as missing.
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -700));
    await tester.pump();
    expect(find.text('Up next'), findsOneWidget);

    await finish(tester, client);
  });

  testWidgets('the mini player asks for the current track cover', (
    tester,
  ) async {
    final client = NcsClient(baseUrl: player.url);
    await tester.runAsync(() async => client.refresh());

    await pumpPage(tester, client);

    final covers = tester
        .widgetList<Image>(find.byType(Image))
        .map((image) => image.image)
        .whereType<NetworkImage>()
        .map((provider) => provider.url)
        .toList();

    // The grid draws the queue; only the mini player can ask for the track that
    // is playing. If its URL is missing, the strip is showing the placeholder
    // while the server has a cover for it — which is exactly what the tablet
    // showed while the grid's covers loaded.
    expect(covers, contains('${player.url}/art/track-1.png'));

    await finish(tester, client);
  });

  testWidgets('the wide player keeps the volume on screen', (tester) async {
    final client = NcsClient(baseUrl: player.url);
    await tester.runAsync(() async => client.refresh());

    await pumpPage(tester, client);
    await tester.tap(find.text('Everything In Its Right Place'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    // On the 1340x800 panel the stacked layout put the volume row below the
    // fold, so the one control with no other way to reach it had to be hunted
    // for by scrolling. The wide layout puts the cover beside the controls.
    final slider = tester.getRect(find.byType(Slider).last);
    expect(slider.top, greaterThanOrEqualTo(0));
    expect(slider.bottom, lessThanOrEqualTo(800));

    await finish(tester, client);
  });

  testWidgets('the connect card fits above the keyboard', (tester) async {
    final client = NcsClient();
    await pumpPage(tester, client, current: true);

    // The Samsung keyboard takes the lower 340 px of the 800 px panel. The card
    // has to drop its decoration and put the Connect button above that line; it
    // used to sit behind the keys, reachable only by dismissing the keyboard.
    tester.view.viewInsets = const FakeViewPadding(bottom: 340);
    addTearDown(tester.view.resetViewInsets);
    await tester.pump();
    await tester.pump();

    final button = tester.getRect(find.widgetWithText(FilledButton, 'Connect'));
    expect(button.bottom, lessThanOrEqualTo(800 - 340));

    // The explanation is what gets dropped to make room.
    expect(find.textContaining('this screen is the remote'), findsNothing);

    await finish(tester, client);
  });

  testWidgets('a missed poll keeps the feed and says reconnecting', (
    tester,
  ) async {
    final client = NcsClient(baseUrl: player.url);
    await tester.runAsync(() async => client.refresh());
    expect(client.connected, isTrue);

    await tester.runAsync(() async {
      await player.stop();
      await client.refresh();
    });
    expect(client.connected, isFalse);
    expect(client.snapshot, isNotNull);

    await pumpPage(tester, client);

    // One dropped packet used to replace the whole feed with the connect card
    // while the mini player carried on underneath it.
    expect(find.text('Reconnecting…'), findsOneWidget);
    expect(find.text('Quick picks'), findsOneWidget);
    expect(find.text('Connect NCS-SMLauncher'), findsNothing);
    expect(find.text('Everything In Its Right Place'), findsOneWidget);

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

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sn_launcher/src/screens/nest_shell.dart';
import 'package:sn_launcher/src/services/feature_flags.dart';
import 'package:sn_launcher/src/state/shell_controller.dart';
import 'package:sn_launcher/src/theme/nest_metrics.dart';

/// The weather page exists in one build and not the other.
///
/// The carousel indexes into the *available* pages rather than into the enum,
/// because a build without the weather page must not have a hole in the middle
/// of a swipe. That is easy to get wrong and it shows up as a blank page.
void main() {
  // The controller builds animation controllers, which need the binding.
  TestWidgetsFlutterBinding.ensureInitialized();

  final ef = FeatureFlags.parse(
    '{"features":{"settings":true,"quickSettings":true,"digestPage":true,'
        '"calendar":true,"todo":true,"weather":true}}',
    'ef',
  );
  final reduced = FeatureFlags.parse(
    '{"features":{"settings":true,"quickSettings":true,"digestPage":true,'
        '"calendar":true,"todo":true,"weather":false}}',
    'reduced',
  );

  tearDown(() => FeatureFlags.forTesting = reduced);

  ShellController controller() => ShellController(
    metrics: NestMetrics.forSize(const Size(1280, 800)),
    vsync: const TestVSync(),
  );

  group('the available pages', () {
    test('the ef build has the weather page as its third', () {
      FeatureFlags.forTesting = ef;
      final c = controller();
      addTearDown(c.dispose);
      final pages = c.availablePages;
      expect(pages[0], ShellPage.home);
      expect(pages[1], ShellPage.digest);
      expect(pages[2], ShellPage.weather);
    });

    test('the reduced build does not have it, and has no hole', () {
      FeatureFlags.forTesting = reduced;
      final c = controller();
      addTearDown(c.dispose);
      final pages = c.availablePages;
      expect(pages, isNot(contains(ShellPage.weather)));
      // No hole: the page after the digest is the next one that exists, and
      // the indices are still contiguous.
      expect(pages.indexOf(ShellPage.digest), 1);
      expect(
        pages.asMap().keys.toList(),
        List.generate(pages.length, (i) => i),
      );
    });

    test('the shipped reduced build is exactly home and digest', () {
      // The normal build must have no Home control stop and no blank stop for
      // the `discover` sheet sentinel. This is the whole carousel, not a
      // subset check: a subset check would still pass with a blank page added.
      FeatureFlags.forTesting = FeatureFlags.parse(
        File('assets/features.json').readAsStringSync(),
        'reduced',
      );
      final c = controller();
      addTearDown(c.dispose);
      expect(
        c.availablePages,
        [ShellPage.home, ShellPage.digest],
        reason: 'normal build must not expose Home control or a blank page',
      );
    });

    test('navigating to a page this build does not have is refused', () {
      FeatureFlags.forTesting = reduced;
      final c = controller();
      addTearDown(c.dispose);
      c.goToPage(ShellPage.weather);
      expect(c.page, isNot(ShellPage.weather));
    });

    test('navigating to the weather page works in the ef build', () {
      FeatureFlags.forTesting = ef;
      final c = controller();
      addTearDown(c.dispose);
      c.goToPage(ShellPage.weather);
      expect(c.page, ShellPage.weather);
    });

    test('a swipe cannot land on a page this build does not have', () {
      FeatureFlags.forTesting = reduced;
      final c = controller();
      addTearDown(c.dispose);
      c.goToPage(ShellPage.digest);
      // Flick left, hard, twice: the carousel should move on to the next page
      // that exists rather than into the gap.
      c.onHorizontalDragEnd(-900, -400, 1000);
      c.onHorizontalDragEnd(-900, -400, 1000);
      expect(c.page, isNot(ShellPage.weather));
    });
  });

  group('the digest page cards', () {
    // A card row that scrolls eats the horizontal drag, so a swipe that should
    // change page instead scrolls the cards — and the user can never reach the
    // page after the digest page. That is exactly what happened: the weather
    // page was unreachable because the card row swallowed the gesture.
    //
    // So the cards share the width equally, and they only scroll if an equal
    // share would be narrower than the floor.
    const floor = 150.0;
    const gap = 14.0;
    // 1340 physical at 213dpi is 1006 logical; the page's own padding is 48 a
    // side, so about 910 of usable width.
    const available = 910.0;

    double shareFor(int count) => (available - (count - 1) * gap) / count;

    test("the ef build's five cards fit without scrolling", () {
      expect(
        cardsNeedScroll(5, share: shareFor(5), floor: floor),
        isFalse,
        reason: 'the cards must fit, or the digest page eats the swipe gesture',
      );
    });

    test('the reduced build\'s two cards fit without scrolling', () {
      expect(cardsNeedScroll(2, share: shareFor(2), floor: floor), isFalse);
    });

    test('too many cards would have to scroll', () {
      // Eight cards at this width would give each 100px, below the floor.
      expect(cardsNeedScroll(8, share: shareFor(8), floor: floor), isTrue);
    });

    test('one card never needs to scroll', () {
      expect(cardsNeedScroll(1, share: shareFor(1), floor: floor), isFalse);
    });
  });

  group('the carousel gesture', () {
    test('a slow drag changes the page, not only a flick', () {
      // The handler passed the drag distance as zero, so only a fast flick
      // could move the carousel and a deliberate drag did nothing. This is
      // what made a synthetic swipe useless, and it is a real problem for a
      // person too: dragging across the screen should page.
      FeatureFlags.forTesting = reduced;
      final c = controller();
      addTearDown(c.dispose);
      c.goToPage(ShellPage.digest);

      // A slow drag: no velocity worth speaking of, but it travelled.
      //
      // The drag update comes first because that is what a real gesture does
      // — the carousel follows the finger, so the release reads a live
      // position rather than the page it started on.
      //
      // Rightward, not leftward: the reduced build is home, digest, and the
      // Home control page is disabled, so digest is the last page. A leftward
      // drag has nowhere to go and would pass without testing the threshold.
      c.onHorizontalDragUpdate(600, 1000);
      c.onHorizontalDragEnd(20, 600, 1000);
      expect(
        c.page,
        isNot(ShellPage.digest),
        reason: 'a drag past halfway commits to the previous page',
      );
    });

    test('a flick changes the page', () {
      FeatureFlags.forTesting = reduced;
      final c = controller();
      addTearDown(c.dispose);
      c.goToPage(ShellPage.digest);
      c.onHorizontalDragEnd(900, 0, 1000);
      expect(c.page, isNot(ShellPage.digest));
    });

    test('a small drag does not change the page', () {
      FeatureFlags.forTesting = reduced;
      final c = controller();
      addTearDown(c.dispose);
      c.goToPage(ShellPage.digest);
      c.onHorizontalDragEnd(10, 60, 1000);
      expect(c.page, ShellPage.digest);
    });
  });
}

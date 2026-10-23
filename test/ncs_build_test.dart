import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sn_launcher/src/services/feature_flags.dart';
import 'package:sn_launcher/src/state/shell_controller.dart';
import 'package:sn_launcher/src/theme/nest_metrics.dart';

/// The two builds differ only by a JSON file, and the music page has to obey
/// that the same way the weather page does.
///
/// The carousel indexes into `availablePages`, so a build without the page must
/// not have a hole in the middle of a swipe.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ShellController controller() => ShellController(
    metrics: NestMetrics.forSize(const Size(1280, 800)),
    vsync: const TestVSync(),
  );

  FeatureFlags flags(String json) => FeatureFlags.parse(json, 'test');

  tearDown(() => FeatureFlags.forTesting = FeatureFlags.empty);

  test('the ef build has the music page', () {
    FeatureFlags.forTesting = flags(
      '{"features":{"music":true,"ncsPlayer":true}}',
    );
    final c = controller();
    addTearDown(c.dispose);
    expect(c.availablePages, contains(ShellPage.music));
  });

  test('the reduced build has no music page', () {
    FeatureFlags.forTesting = flags(
      '{"features":{"music":false,"ncsPlayer":false}}',
    );
    final c = controller();
    addTearDown(c.dispose);
    expect(c.availablePages, isNot(contains(ShellPage.music)));
  });

  test('music without ncsPlayer is still no page', () {
    // The two flags are separate on purpose: `music` is the old card and
    // panel, `ncsPlayer` is the page that needs a player on the network. A
    // build can have one without the other, and this is the combination that
    // would otherwise put an empty page in the carousel.
    FeatureFlags.forTesting = flags('{"features":{"music":true}}');
    final c = controller();
    addTearDown(c.dispose);
    expect(c.availablePages, isNot(contains(ShellPage.music)));
  });

  test('discover is the sheet sentinel, not a carousel page', () {
    // It has no content (`_pageContent` returns a shrink): it only marks that
    // the launcher sheet is covering the carousel. In the reduced build it was
    // a blank fourth page after "Home" until the tablet showed it.
    FeatureFlags.forTesting = flags('{"features":{}}');
    final c = controller();
    addTearDown(c.dispose);
    expect(c.availablePages, isNot(contains(ShellPage.discover)));

    // The marker still has to take effect, or the dock stays visible under
    // the fully open sheet.
    c.goToPage(ShellPage.discover);
    expect(c.page, ShellPage.discover);
  });

  test('without digestPage the carousel drops the digest too', () {
    // `_pageContent` already returned a shrink for this case; the page list
    // was the other half of the same gate.
    FeatureFlags.forTesting = flags('{"features":{"digestPage":false}}');
    final c = controller();
    addTearDown(c.dispose);
    expect(c.availablePages, isNot(contains(ShellPage.digest)));
  });

  test('the page sits after the weather and before the home controls', () {
    FeatureFlags.forTesting = flags(
      '{"features":{"weather":true,"music":true,"ncsPlayer":true}}',
    );
    final c = controller();
    addTearDown(c.dispose);
    final pages = c.availablePages;
    expect(
      pages.indexOf(ShellPage.music),
      pages.indexOf(ShellPage.weather) + 1,
    );
    expect(
      pages.indexOf(ShellPage.music) + 1,
      pages.indexOf(ShellPage.homeControl),
    );
  });
}

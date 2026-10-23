import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/nest_action.dart';
import '../services/action_launcher.dart';
import '../services/feature_flags.dart';
import '../services/platform_bridge.dart';
import '../services/settings_store.dart';
import '../theme/ambient_palette.dart';
import '../theme/nest_metrics.dart';
import '../theme/nest_motion.dart';

/// Material 1 standard easing — the curve the Nest's Flutter UI uses.


/// The four top-level pages of the shell, in the device's carousel order.
enum ShellPage {
  /// Photo Frame / clock — far left.
  home,

  /// "Your morning / afternoon / evening" suggestion carousel.
  digest,

  /// The weather, on its own page.
  ///
  /// It used to be a card on the digest page, which was the wrong shape: the
  /// weather is the one thing on a Nest display that deserves the whole
  /// screen, and a card squeezed beside five others showed a temperature and
  /// two words.
  weather,

  /// Music, driven by NCS-SMLauncher.
  ///
  /// A page rather than the bottom-sheet panel the old music card opened: a
  /// remote control for a library needs a library's worth of room, and a panel
  /// that covers the launcher is the wrong shape for something that should
  /// stay playing while you look at the clock.
  music,

  /// Home control.
  homeControl,

  /// Discover / launcher grid.
  discover,
}

/// How far the bottom launcher sheet is dragged, 0 = closed, 1 = fully open.
class SheetState {
  const SheetState(this.progress);
  final double progress;

  static const SheetState closed = SheetState(0);
  static const SheetState open = SheetState(1);
  bool get isOpen => progress > 0.995;
  bool get isClosed => progress < 0.005;
}

/// Global shell state: page carousel, bottom sheet, brightness, volume,
/// theme and DND. Everything the gesture recogniser touches lives here so the
/// widget tree can stay declarative and cheap.
class ShellController extends ChangeNotifier {
  ShellController({
    required this.metrics,
    required TickerProvider vsync,
    PlatformBridge platform = const PlatformBridge(),
    SettingsStore? settings,
    // ignore: prefer_initializing_formals
  })  : _platform = platform,
        _settings = settings ?? SettingsStore() {
    _palette = AmbientPalette.of(_theme);

    // UNBOUNDED, and that is load-bearing.
    //
    // `AnimationController` defaults to `lowerBound: 0.0, upperBound: 1.0`.
    // `goToPage` animates to the *index* of the target page, so every page past
    // index 1 was silently clamped to 1.0: the animation ran, completed, and
    // reported success while parking the carousel on the digest page. The
    // weather page (index 2), home control (3) and discover (4) were all
    // unreachable by swipe or arrow key, with no exception anywhere — the only
    // symptom was that the page you selected never appeared.
    //
    // Bounds would need the page count, which the feature flags change at
    // runtime, so unbounded is both the smaller fix and the honest one: the
    // value is a page offset, not a 0..1 progress.
    _pageAnim = AnimationController.unbounded(vsync: vsync, duration: kNestSlow);
    _sheetAnim = AnimationController(vsync: vsync, duration: kNestMedium);
  }

  final NestMetrics metrics;

  final ActionLauncher _launcher = const ActionLauncher();

  /// Exposed so the quick-settings row can fall back to the plugin's URL path
  /// when the native one is unavailable (desktop, or an older Android build).
  ActionLauncher get actionLauncher => _launcher;
  /// Private with a public getter: the constructor takes a named parameter for
  /// testability but the field name must stay private.
  final PlatformBridge _platform;
  final SettingsStore _settings;

  /// Set by [attachClock] so the palette can drift with the wall clock.
  ClockTicker? _clockTicker;

  bool _disposed = false;

  /// Restore persisted settings, then match the real device state. Both are
  /// best-effort and must not delay the first frame — the launcher paints
  /// immediately and corrects itself a moment later if the platform answers.
  Future<void> restore() async {
    await _settings.load();
    _placePhotoEnabled =
        _settings.read(SettingKeys.placePhoto, false, (v) => v == 'true');
    if (_disposed) return;
    final stored = _settings.get(SettingKeys.theme);
    if (stored != null) {
      _theme = NestTheme.values.firstWhere(
        (t) => t.name == stored,
        orElse: () => NestTheme.dynamic,
      );
      // Re-check it against this build. The two variants have separate
      // settings stores, but a user who installs ef, picks Sun, then installs
      // the reduced build would otherwise be pinned to the one theme the
      // reduced build does not offer and does not show in its picker.
      final available = availableThemes(FeatureFlags.current);
      if (!available.contains(_theme)) {
        _theme = fallbackTheme(FeatureFlags.current);
      }
    }
    // The seconds flag has to be applied *after* the hook is attached, because
    // firing the hook is what re-schedules the clock service's timer — a
    // minute-resolution clock that is told to show seconds has to actually
    // start waking every second.
    final storedSeconds = _settings.get(SettingKeys.showSeconds);
    if (storedSeconds != null) {
      _showSeconds = storedSeconds == 'true';
      onShowSecondsChanged?.call(_showSeconds);
    }
    final storedZoom = _settings.get(SettingKeys.clockZoom);
    if (storedZoom != null) {
      _zoom = double.tryParse(storedZoom)?.clamp(1.0, 1.2) ?? 1.0;
    }
    _recomputePalette(force: true);
    notifyListeners();
    unawaited(syncWithDeviceState());
  }

  SettingsStore get settings => _settings;
  PlatformBridge get platform => _platform;

  late final AnimationController _pageAnim;
  late final AnimationController _sheetAnim;

  // ── Page carousel ────────────────────────────────────────────────────────
  ShellPage _page = ShellPage.home;
  ShellPage get page => _page;

  /// Live carousel offset in "pages", animated with a controller so swipes
  /// settle with the Material curve rather than snapping.
  Animation<double> get pageAnim => _pageAnim;

  // ── Bottom sheet ─────────────────────────────────────────────────────────
  Animation<double> get sheetAnim => _sheetAnim;
  double get sheetProgress => _sheetAnim.value;

  /// True while a finger is dragging the sheet, so release can decide snap.
  bool _draggingSheet = false;

  /// True once the finger has moved the carousel, so the release knows the
  /// animation's value is the live position rather than a value still catching
  /// up from the previous transition. Without this the release can read a
  /// stale value that is a whole page away from where the carousel is.
  bool _carouselDragged = false;
  double _dragStart = 0;

  // ── Settings ─────────────────────────────────────────────────────────────
  double _brightness = 0.8;
  double get brightness => _brightness;

  double _volume = 0.5;
  double get volume => _volume;

  NestTheme _theme = NestTheme.dynamic;
  NestTheme get theme => _theme;

  /// True when the current look came from the clock rather than a pinned
  /// choice — the theme picker labels this row "follows the sun".
  bool get themeIsDynamic => _theme == NestTheme.dynamic;

  bool get darkThemeEnabled => _palette.isDark;

  /// Whether the weather page's background photograph is wanted.
  bool _placePhotoEnabled = false;
  bool get placePhotoEnabled => _placePhotoEnabled;

  bool _doNotDisturb = false;
  bool get doNotDisturb => _doNotDisturb;

  bool _ambientEq = true;
  bool get ambientEq => _ambientEq;

  double _ambientLight = 0.5;
  double get ambientLight => _ambientLight;

  bool _use24Hour = true;
  bool get use24Hour => _use24Hour;

  bool _showSeconds = false;
  bool get showSeconds => _showSeconds;

  /// Called when the seconds display is turned on or off.
  ///
  /// The clock service owns the timer, and it only wakes on the *minute*
  /// boundary unless it is told to tick every second. So the flag has to
  /// reach the service and not just the display — otherwise the seconds are
  /// drawn and then frozen, which is exactly what happened.
  ValueChanged<bool>? onShowSecondsChanged;

  String _albumTitle = 'Recent highlights';
  String get albumTitle => _albumTitle;

  double _zoom = 1.0;
  double get zoom => _zoom;

  set zoom(double v) {
    final clamped = v.clamp(1.0, 1.2);
    if (_zoom == clamped) return;
    _zoom = clamped;
    unawaited(_settings.put(SettingKeys.clockZoom, '$_zoom'));
    notifyListeners();
  }

  // ── Ambient palette ──────────────────────────────────────────────────────
  late AmbientPalette _palette;
  AmbientPalette get palette => _palette;

  // ── Toast ────────────────────────────────────────────────────────────────
  String? _toast;
  Timer? _toastTimer;

  // ─────────────────────────────────────────────────────────────────────────
  void attachClock(ClockTicker ticker) {
    _clockTicker = ticker;
    _onClockTick();
    ticker.addListener(_onClockTick);
  }

  void _onClockTick() {
    _recomputePalette();
  }

  /// Recompute [palette] from the theme choice and the wall clock.
  ///
  /// A pinned theme ignores the clock entirely — that is the point of pinning
  /// it. Only [NestTheme.dynamic] drifts, and it only notifies when the colour
  /// actually moved, because this runs on every minute tick and a wall display
  /// must not wake up repainting when nothing changed.
  void _recomputePalette({bool force = false}) {
    final t = _clockTicker?.now ?? DateTime.now();
    final next = AmbientPalette.resolve(
      _theme,
      t.hour.toDouble() + t.minute / 60.0,
    );
    if (force ||
        next.top != _palette.top ||
        next.bottom != _palette.bottom ||
        next.surface != _palette.surface) {
      _palette = next;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _pageAnim.dispose();
    _sheetAnim.dispose();
    _toastTimer?.cancel();
    super.dispose();
  }

  // ── Page navigation ──────────────────────────────────────────────────────
  /// The pages this build actually has, in order.
  ///
  /// The carousel indexes into this list rather than into [ShellPage.values],
  /// so a build without the weather page has no hole in its carousel. Indexing
  /// the enum directly would leave a blank page in the middle of a swipe.
  List<ShellPage> get availablePages {
    final f = FeatureFlags.current;
    return [
      for (final p in ShellPage.values)
        if (_pageAvailable(p, f)) p,
    ];
  }

  /// Whether this build has a page at all.
  ///
  /// The carousel indexes into [availablePages] rather than the enum, so a
  /// build that drops a page has no hole where it used to be — which is the
  /// whole reason this is a predicate and not a `where` on the enum with the
  /// pages still present.
  bool _pageAvailable(ShellPage page, FeatureFlags f) => switch (page) {
        ShellPage.weather => f.isOn('weather'),
        ShellPage.music => f.isOn('music') && f.isOn('ncsPlayer'),
        _ => true,
      };

  /// Moves the carousel to [p].
  ///
  /// Springs rather than eases, and starts from wherever the animation happens
  /// to be rather than from a remembered position — see [nest_motion.dart] for
  /// why. [velocity] is the gesture's release velocity in pages/second; passing
  /// it is what makes a flick feel like it is throwing the carousel instead of
  /// asking it to go somewhere.
  ///
  /// [duration] forces the eased path and is used only where there is no
  /// gesture behind the motion (a tap on a page name, for instance).
  void goToPage(ShellPage p, {Duration? duration, double velocity = 0}) {
    final pages = availablePages;
    final index = pages.indexOf(p);
    if (index < 0) return;
    if (_page == p && _pageAnim.isAnimating) return;
    _page = p;
    final target = index.toDouble();
    if (duration != null) {
      _pageAnim.animateTo(target, duration: duration, curve: kNestEase);
    } else {
      _pageAnim.animateWith(nestSpring(kNestPageSpring, _pageAnim.value, target,
          clampNestVelocity(velocity, max: 3.0)));
    }
    notifyListeners();
  }

  /// Horizontal swipe moves the page carousel; small flicks advance one page.
  ///
  /// The base is the current *page*, not the animation's value. The animation
  /// is still catching up when a second gesture arrives, and a flick in that
  /// window computed its target from a stale position and went nowhere.
  /// The finger is moving the carousel.
  ///
  /// This is the thing that makes a swipe feel like a swipe. Without it the
  /// carousel sat still until you let go and then jumped — no amount of spring
  /// tuning fixes that, because the problem is not the spring, it is that
  /// nothing was moving while your finger was down.
  ///
  /// The animation's value is *set* rather than animated, so the page tracks
  /// the finger exactly, and the release springs from wherever it happens to
  /// be. That is the same reason the spring is there at all: it can start from
  /// any value, including a half-dragged one.
  ///
  /// [dx] is the total distance travelled, negative to the left.
  void onHorizontalDragUpdate(double dx, double width) {
    if (width <= 0) return;
    // Remember that the live value is authoritative from here on. Without
    // this the release would read a value that is still catching up from the
    // previous transition and decide the wrong thing — a stale value can be
    // a whole page away from where the carousel actually is.
    _carouselDragged = true;
    final pages = availablePages;
    if (pages.length < 2) return;
    final base = pages.indexOf(_page);
    if (base < 0) return;

    // A little resistance past the ends, so the edge of the list is felt
    // rather than simply stopping dead.
    const rubberBand = 0.35;
    final offset = dx / width;
    var target = base - offset;
    if (target < 0) target = -(-target) * rubberBand;
    if (target > pages.length - 1) {
      final over = target - (pages.length - 1);
      target = (pages.length - 1) + over * rubberBand;
    }
    _pageAnim.value = target;
  }

  void onHorizontalDragEnd(double velocity, double delta, double width) {
    if (width <= 0) return;
    final pages = availablePages;
    final base = pages.indexOf(_page);
    if (base < 0) return;
    // Decide from where the carousel *is*, not only from how far the finger
    // travelled. Now that the page follows the finger, the live position is
    // the honest answer: a drag that got 40% of the way and stopped is not a
    // page change, and the old threshold -- 18% of the width -- called that a
    // page change, so a small nudge sent you to the next page.
    final current = _carouselDragged ? _pageAnim.value : base.toDouble();
    _carouselDragged = false;
    var target = base.toDouble();
    if (velocity.abs() > 260) {
      // A flick decides on its own, and it throws the carousel.
      target = velocity > 0 ? target - 1 : target + 1;
    } else if ((current - base).abs() > 0.5) {
      // Past halfway: commit to the page it is closest to.
      target = current;
    }
    target = target.clamp(0, pages.length - 1);
    // Velocity arrives in px/s; the carousel counts pages. The sign is kept
    // because a flick to the left must throw it forwards, not backwards.
    goToPage(pages[target.round()], velocity: -velocity / width);
  }

  // ── Bottom sheet gesture ─────────────────────────────────────────────────
  /// Where the sheet settles when released: anything above this stays open.
  static const double sheetOpenThreshold = 0.45;

  /// Velocity (px/s, positive = downward) past which a fling wins over
  /// position, in either direction.
  static const double sheetFlingVelocity = 600;

  /// How much of a full sheet-height of travel a single frame of fling is
  /// projected to carry the sheet.
  static const double _flingProjection = 0.25;

  /// Begin a drag from a known starting [progress].
  ///
  /// Explicit rather than inferred lazily on the first move: inferring it let
  /// the widget layer and this layer disagree about whether a drag was
  /// happening, which froze the sheet mid-drag.
  void onSheetDragStart(double progress) {
    _draggingSheet = true;
    _dragStart = progress;
  }

  /// [dyFromStart] is finger travel since the drag began; [travelHeight] is the
  /// distance the sheet covers going 0 → 1, i.e. its own height — **not** the
  /// screen height.
  ///
  /// Dividing by the screen height made the sheet track the finger at half
  /// speed, which is the "it appears slowly" half of the report.
  void onSheetDragUpdate(double dyFromStart, double travelHeight) {
    if (!_draggingSheet) return;
    _sheetAnim.value =
        (_dragStart - dyFromStart / math.max(1.0, travelHeight)).clamp(0.0, 1.0);
  }

  /// Release settles the sheet. Called on pointer-up *and* pointer-cancel —
  /// Android claims bottom-edge drags for its own gesture, so a cancel is the
  /// normal way a drag ends here.
  void onSheetDragEnd(double velocity, double travelHeight, {required bool isDiscover}) {
    _draggingSheet = false;
    final travel = math.max(1.0, travelHeight);
    final projected =
        (_sheetAnim.value - velocity / travel * _flingProjection).clamp(0.0, 1.0);

    final bool shouldOpen;
    if (velocity < -sheetFlingVelocity) {
      shouldOpen = true; // flung upward
    } else if (velocity > sheetFlingVelocity) {
      shouldOpen = false; // flung downward
    } else {
      shouldOpen = projected > sheetOpenThreshold;
    }

    if (shouldOpen) {
      // No duration: the page springs too, rather than running the eased path
      // that only exists for taps. The velocity passed is the *sheet's*,
      // converted into page-widths per second — it is not the carousel's own
      // gesture, so this is a hint rather than a throw. The carousel clamp
      // inside goToPage keeps a hard fling from overshooting the page.
      final width = math.max(1.0, metrics.size.width);
      goToPage(isDiscover ? ShellPage.discover : _page, velocity: velocity / width);
      _springSheet(true, releaseVelocity: velocity);
    } else {
      _springSheet(false, releaseVelocity: velocity);
      // Match closeSheet(): leaving the drawer also returns to the first page.
      if (_page == ShellPage.discover) goToPage(ShellPage.home);
    }
  }

  /// Springs the sheet to [open], carrying the gesture's release velocity.
  ///
  /// The velocity is divided by a nominal travel so that "how hard was that
  /// flung" survives the trip from pixels to a 0..1 progress. It is the
  /// difference between a sheet that follows your finger and one that runs a
  /// fixed animation after letting go of it.
  void _springSheet(bool open, {double releaseVelocity = 0}) {
    final SpringDescription spring =
        open ? kNestSheetSpring : kNestSheetCloseSpring;
    _sheetAnim.animateWith(nestSpring(
      spring,
      _sheetAnim.value,
      open ? 1.0 : 0.0,
      clampNestVelocity(releaseVelocity / _nominalSheetTravel),
    ));
  }

  /// A full sheet height in logical pixels, used only to convert a gesture's
  /// px/s into progress-per-second. Exact value is unimportant; the ratio is
  /// what matters and any plausible number gives it.
  static const double _nominalSheetTravel = 900;

  void toggleSheet() {
    _springSheet(_sheetAnim.value <= sheetOpenThreshold);
  }

  void closeSheet() {
    _springSheet(false);
    if (_page == ShellPage.discover) {
      goToPage(ShellPage.home);
    }
  }

  // ── Quick settings ───────────────────────────────────────────────────────
  //
  // These drive the *hardware*, not just a number in this class. That is the
  // whole difference from the version that only mutated private fields and
  // told the user it had dimmed the screen: nothing on the panel changed.
  //
  // Each setter therefore (a) updates local state immediately so the UI is
  // responsive, and (b) pushes to the platform. The platform call is fire and
  // forget — a drag must never await a channel round trip, or the brightness
  // arc stutters. The resulting value is reconciled back when the platform
  // answers, because Android clamps to its own range.

  void setBrightness(double v, {bool notify = true}) {
    final next = v.clamp(0.0, 1.0);
    if ((next - _brightness).abs() < 0.001) return;
    _brightness = next;
    if (notify) notifyListeners();
    _platform.setBrightness(next).then((applied) {
      if (applied == null || _disposed) return;
      // Android quantises to its own steps; adopt what it really did rather
      // than showing the user a number the panel is not at.
      if ((applied - _brightness).abs() > 0.005) {
        _brightness = applied;
        notifyListeners();
      }
    });
  }

  void nudgeBrightness(double delta) => setBrightness(_brightness + delta);

  void setVolume(double v) {
    final next = v.clamp(0.0, 1.0);
    if ((next - _volume).abs() < 0.001) return;
    _volume = next;
    notifyListeners();
    _platform.setVolume(next);
  }

  void nudgeVolume(double delta) => setVolume(_volume + delta);

  /// Adopt the device's real brightness/volume on launch, so the launcher does
  /// not open showing 80% while the panel is actually at 40%.
  Future<void> syncWithDeviceState() async {
    final b = await _platform.getBrightness();
    final v = await _platform.getVolumeFraction();
    if (_disposed) return;
    if (b != null) _brightness = b.clamp(0.0, 1.0);
    if (v != null) _volume = v.clamp(0.0, 1.0);
    notifyListeners();
  }

  /// Switch the look. Persisted, because a wall display that forgets its theme
  /// every reboot is worse than one that never had themes.
  void setTheme(NestTheme t) {
    if (_theme == t) return;
    _theme = t;
    _recomputePalette(force: true);
    _settings.put(SettingKeys.theme, t.name);
    notifyListeners();
  }

  /// The theme picker walks the list, so a single button cycles rather than
  /// dead-ending on the last entry.
  ///
  /// Walks [availableThemes], not `NestTheme.values`: in the reduced build the
  /// Sun theme is compiled out, and cycling into a theme the picker cannot show
  /// would leave the user in a state with no way back out through the dock.
  void cycleTheme() {
    final values = availableThemes(FeatureFlags.current);
    if (values.length < 2) return;
    // A theme stored from a previous install may not exist in this build.
    final at = values.indexOf(_theme);
    setTheme(values[(at < 0 ? 0 : at + 1) % values.length]);
  }

  /// Turns the weather page's background photograph on or off.
  void togglePlacePhoto() {
    _placePhotoEnabled = !_placePhotoEnabled;
    _settings.put(SettingKeys.placePhoto, '$_placePhotoEnabled');
    showToast(_placePhotoEnabled
        ? 'Place photograph on'
        : 'Place photograph off');
    notifyListeners();
  }

  void toggleDoNotDisturb() {
    _doNotDisturb = !_doNotDisturb;
    showToast(_doNotDisturb ? 'Do Not Disturb on' : 'Do Not Disturb off');
    notifyListeners();
  }

  void toggleAmbientEq() {
    _ambientEq = !_ambientEq;
    _onClockTick();
    showToast(_ambientEq ? 'Ambient EQ on' : 'Ambient EQ off');
    notifyListeners();
  }

  void setAmbientLight(double v) {
    _ambientLight = v.clamp(0.0, 1.0);
    _onClockTick();
    notifyListeners();
  }

  void toggleUse24Hour() {
    _use24Hour = !_use24Hour;
    notifyListeners();
  }

  void toggleShowSeconds() => setShowSeconds(!_showSeconds);

  /// Sets the seconds display and tells the clock service, which changes the
  /// timer's granularity.
  void setShowSeconds(bool value) {
    if (_showSeconds == value) return;
    _showSeconds = value;
    onShowSecondsChanged?.call(value);
    unawaited(_settings.put(SettingKeys.showSeconds, '$_showSeconds'));
    notifyListeners();
  }

  void setAlbumTitle(String t) {
    _albumTitle = t;
    notifyListeners();
  }

  // ── Launching ────────────────────────────────────────────────────────────
  Future<void> openAction(NestAction action) async {
    closeSheet();
    final outcome = await _launcher.launch(action);
    if (outcome != LaunchOutcome.launched) {
      showToast(outcome == LaunchOutcome.notInstalled
          ? '${action.label} is not installed'
          : "Couldn't open ${action.label}");
    }
  }

  Future<void> openUrl(String url) async {
    final ok = await _launcher.openUrl(url);
    if (!ok) showToast("Couldn't open $url");
  }

  void showToast(String message) {
    _toast = message;
    _toastTimer?.cancel();
    _toastTimer = Timer(const Duration(seconds: 2), () {
      _toast = null;
      notifyListeners();
    });
    notifyListeners();
  }

  String? get toast => _toast;

  // ── Test hooks ───────────────────────────────────────────────────────────
  /// Forces the sheet position without animating (screenshot capture).
  @visibleForTesting
  void setSheetForTest(double v) {
    _sheetAnim.value = v;
    _page = v > 0.99 ? ShellPage.discover : _page;
  }

  /// Forces a specific ambient palette (deterministic screenshots).
  @visibleForTesting
  void setPaletteForTest(AmbientPalette p) {
    _palette = p;
    notifyListeners();
  }

  /// Pins the theme *and* its palette together.
  ///
  /// [setPaletteForTest] alone leaves `_theme` as `dynamic`, so the Digest
  /// page would report "follows the time of day" while rendering a pinned
  /// palette — a caption that contradicts what is on screen. Screenshots have
  /// already caught that once; keep the two in step.
  void setThemeForTest(NestTheme t) {
    _theme = t;
    _palette = AmbientPalette.of(t);
    notifyListeners();
  }
}

/// Minimal clock abstraction so the controller can be driven by tests without
/// a real timer.
class ClockTicker extends ChangeNotifier {
  ClockTicker(this._now);
  DateTime _now;
  DateTime get now => _now;
  void set(DateTime t) {
    _now = t;
    notifyListeners();
  }
}
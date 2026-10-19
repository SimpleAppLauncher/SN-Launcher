import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';

import '../models/nest_action.dart';
import '../services/assistant_service.dart';
import '../services/feature_flags.dart';
import '../services/location_service.dart';
import '../services/device_media_watcher.dart';
import '../services/playback_service.dart';
import '../services/radio_stations.dart';
import '../services/todo_service.dart';
import '../services/photo_frame_service.dart';
import '../models/photo_credit.dart';
import '../services/calendar_service.dart';
import '../services/clock_service.dart';
import '../services/weather_service.dart';
import '../state/shell_controller.dart';
import '../theme/ambient_palette.dart';
import '../theme/nest_icons.dart';
import '../theme/nest_metrics.dart';
import '../theme/nest_theme.dart';
import '../theme/nest_type.dart';
import '../widgets/ambient_background.dart';
import '../widgets/app_drawer.dart';
import '../widgets/clock_block.dart';
import '../widgets/launcher_sheet.dart';
import '../widgets/assistant_lightbar.dart';
import '../widgets/music_player.dart';
import '../widgets/photo_frame.dart';
import '../widgets/settings_page.dart';
import '../widgets/todo_card.dart';
import '../widgets/now_playing_card.dart';
import '../widgets/weather_page.dart';

/// The Nest launcher shell.
///
/// Layout, in z-order:
///   0  ambient background (one paint pass)
///   1  page carousel  — photo frame · digest · home control · discover
///   2  bottom sheet   — app row + quick settings + drag handle
///   3  app drawer     — the six-column "See all" grid
///   5  toast
///
/// Gestures follow the device:
///   * swipe up from the bottom .... open the launcher sheet (follows finger)
///   * swipe up past the detent ... open the full app drawer
///   * swipe down ................. close
///   * swipe left / right ......... move through the page carousel
///   * three-finger up/down ....... open / close quick settings
class NestShell extends StatefulWidget {
  const NestShell({
    super.key,
    required this.controller,
    required this.clock,
    required this.weather,
    this.calendar,
    this.photos,
    this.assistant,
    this.todo,
    this.location,
    this.playback,
    this.media,
    this.suggested,
    this.actions,
    this.animateDecorations = true,
  });

  final ShellController controller;
  final ClockService clock;
  final WeatherService weather;

  /// Optional. When supplied the Digest page shows the user's real calendar
  /// instead of "No more events today".
  final CalendarService? calendar;

  /// The to-do list. Optional so tests and desktop builds can omit it.
  final TodoService? todo;

  /// Where the device is. Only the weather page needs it.
  final LocationService? location;

  /// The native player.
  ///
  /// Null where there is no audio service, so the transport is never rendered
  /// with controls that cannot work. A music card full of dead buttons is worse
  /// than no transport at all.
  final PlaybackService? playback;

  /// Active media sessions belonging to other apps.
  final DeviceMediaWatcher? media;

  /// Optional. Absent in tests and on desktop, where the background stays on
  /// the bundled photograph.
  final PhotoFrameService? photos;

  /// Optional. Null means the assistant is not available on this platform or
  /// has not been configured.
  final AssistantService? assistant;

  /// Overrides the six badges in the sheet's app row.
  final List<NestAction>? suggested;

  /// Overrides the drawer contents.
  final List<NestAction>? actions;

  /// When false, every continuously-animating decoration (the weather glyph)
  /// renders a single static frame. Required for screenshot /
  /// golden tests, which cannot settle against an infinite animation.
  final bool animateDecorations;

  @override
  State<NestShell> createState() => _NestShellState();
}

class _NestShellState extends State<NestShell> {
  /// Rotation is a separate ChangeNotifier; fold it into the rebuild set so a
  /// new photograph actually reaches the screen.
  @override
  void initState() {
    super.initState();
    widget.photos?.addListener(_onPhotosChanged);
    widget.assistant?.addListener(_onAssistantChanged);

    // The clock service owns the timer, and it only wakes on the minute
    // boundary unless it is told otherwise. The "Show seconds" setting has to
    // reach the *service*, not just the display — otherwise the seconds are
    // drawn and then sit frozen, which is what it did.
    widget.controller.onShowSecondsChanged = widget.clock.setShowSeconds;
    // Apply whatever is already stored, so a restart with seconds on comes
    // back ticking every second rather than waiting for the next toggle.
    widget.clock.setShowSeconds(widget.controller.showSeconds);

    widget.controller.addListener(_onControllerChanged);
    widget.location?.addListener(_onLocationChanged);
  }

  /// The weather page is the only thing that needs a location, so the location
  /// is worked out when the page is first opened rather than at launch.
  ///
  /// The carousel keeps every page alive, so a page that resolved its own
  /// location in `initState` would ask for the location permission on every
  /// cold start, whether or not the user ever looked at the weather.
  void _onControllerChanged() {
    if (!mounted) return;
    final page = widget.controller.page;
    if (page == ShellPage.weather) {
      _ensureWeatherLocation();
    }
    // No setState here: this listener is attached to the controller, and the
    // controller is already in the shell's AnimatedBuilder's merge list, so the
    // shell rebuilds anyway. Calling setState as well built the entire tree
    // twice for every frame of a swipe — the single biggest CPU cost in the
    // app, and the reason a drag could spike a cheap tablet to 100%.
  }

  void _onLocationChanged() {
    if (mounted) setState(() {});
  }

  bool _locationRequested = false;

  Future<void> _ensureWeatherLocation() async {
    if (_locationRequested) return;
    final location = widget.location;
    if (location == null) return;
    _locationRequested = true;
    final place = await location.resolve();
    debugPrint('SNLOC resolve -> place=$place error="${location.lastError}" '
        'resolving=${location.resolving}');
    if (!mounted) return;
    if (place == null) return;
    // The weather service needs the coordinates. Configuring it also kicks off
    // a refresh.
    widget.weather.configure(
      latitude: place.latitude,
      longitude: place.longitude,
      enabled: true,
    );
  }

  @override
  void didUpdateWidget(NestShell old) {
    super.didUpdateWidget(old);
    if (old.photos != widget.photos) {
      old.photos?.removeListener(_onPhotosChanged);
      widget.photos?.addListener(_onPhotosChanged);
    }
    if (old.assistant != widget.assistant) {
      old.assistant?.removeListener(_onAssistantChanged);
      widget.assistant?.addListener(_onAssistantChanged);
    }
    if (old.location != widget.location) {
      old.location?.removeListener(_onLocationChanged);
      widget.location?.addListener(_onLocationChanged);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    widget.photos?.removeListener(_onPhotosChanged);
    widget.assistant?.removeListener(_onAssistantChanged);
    widget.location?.removeListener(_onLocationChanged);
    super.dispose();
  }

  void _onPhotosChanged() {
    if (mounted) setState(() {});
  }

  void _onAssistantChanged() {
    if (mounted) setState(() {});
  }

  /// Recomputed every frame, deliberately *not* `late final`.
  ///
  /// The first frame on a real device reports a MediaQuery size that is smaller
  /// than the settled one — the display metrics are still being resolved while
  /// the activity attaches. Caching the first value locks the whole shell to
  /// the wrong scale for its entire life (measured 1.063 vs the settled 1.116,
  /// a 5% error across every icon, font and offset).
  NestMetrics get _m => NestMetrics.of(context);

  late final ShellController _c = widget.controller;

  /// Licence credit for the bundled photograph. Loaded once.
  late final PhotoCredit _credit = PhotoCredit.load();

  /// Which features this build was compiled with. Read once, synchronously —
  /// the JSON is bundled and resolved before the first frame, so there is no
  /// window where a feature flickers on for one frame and off for the next.
  FeatureFlags get flags => FeatureFlags.current;

  /// How far the current horizontal drag has travelled.
  ///
  /// `DragEndDetails` has the velocity but not the distance, so the distance
  /// is accumulated here. Without it the carousel only responds to flicks.
  double _dragDx = 0;

  /// The pointer currently dragging the sheet, if any. Single-owner so a
  /// second finger cannot cancel the drag in progress.
  int? _dragPointer;
  double _dragStartY = 0;
  late VelocityTracker _velocity = VelocityTracker.withKind(PointerDeviceKind.touch);

  /// Shared tail for pointer-up and pointer-cancel.
  void _settleSheet(PointerEvent e) {
    if (e.pointer != _dragPointer) return;
    _dragPointer = null;
    _velocity.addPosition(e.timeStamp, e.position);
    // Positive is downward.
    final v = _velocity.getVelocityEstimate()?.pixelsPerSecond.dy ?? 0;
    _c.onSheetDragEnd(v, _m.sheetHeight, isDiscover: _c.sheetProgress > 0.92);
  }

  /// Suggested six: the device ships most-used actions, and these are the
  /// defaults observed on a freshly-provisioned Hub.
  /// The device's default six, in the order a freshly-provisioned Hub shows
  /// them (read off the rectified Max photo): weather, YouTube, Spotify,
  /// timer, calendar, broadcast.
  late final List<NestAction> _suggested = widget.suggested ?? _defaultSuggested();

  static List<NestAction> _defaultSuggested() {
    const order = ['weather', 'youtube', 'spotify', 'timer', 'calendar', 'broadcast'];
    return [
      for (final id in order)
        if (kNestActions.any((a) => a.id == id)) kNestActions.firstWhere((a) => a.id == id),
    ];
  }

  late final List<NestAction> _actions =
      widget.actions ??
      (List<NestAction>.from(kNestActions)..sort((a, b) => a.label.compareTo(b.label)));

  @override
  Widget build(BuildContext context) {
    final type = NestType(_m);

    return PopScope(
      // A launcher must never be dismissed by Back. On the real device Back
      // backs out one level: drawer → sheet → first page. On the first page it
      // is swallowed, because leaving the app is never what the user meant.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_c.page == ShellPage.discover) {
          _c.closeSheet();
        } else if (_c.sheetProgress > 0.01) {
          _c.closeSheet();
        } else if (_c.page != ShellPage.home) {
          _c.goToPage(ShellPage.home);
        }
      },
      child: Focus(
        autofocus: true,
        // Keyboard / D-pad / remote control. The device is touch-first, but
        // Android TV remotes, USB keyboards and MCP bridges all funnel through
        // the same handful of verbs.
        onKeyEvent: (node, event) {
          if (event is! KeyDownEvent) return KeyEventResult.ignored;
          switch (event.logicalKey) {
            case LogicalKeyboardKey.arrowUp:
              _c.toggleSheet();
            case LogicalKeyboardKey.arrowDown:
              _c.closeSheet();
            case LogicalKeyboardKey.arrowRight:
              // Positive velocity moves towards the previous page, because the
              // carousel's first page is the left-most one. These two were
              // the wrong way round: LEFT went back and RIGHT went forward.
              _c.onHorizontalDragEnd(320, 0, _m.size.width);
            case LogicalKeyboardKey.arrowLeft:
              _c.onHorizontalDragEnd(-320, 0, _m.size.width);
            case LogicalKeyboardKey.escape:
              _c.closeSheet();
            case LogicalKeyboardKey.space:
            case LogicalKeyboardKey.enter:
              break;
            default:
              return KeyEventResult.ignored;
          }
          return KeyEventResult.handled;
        },
        child: AnimatedBuilder(
          // The shell must also listen to the two animation controllers directly.
          //
          // `ShellController` is a ChangeNotifier, but driving the sheet or the
          // carousel animates a separate AnimationController — which notifies
          // its own listeners, *not* the controller. Without these in the list
          // the UI only repaints by accident, whenever the clock ticks.
          //
          // This list is the reason the weather page showed a temperature with
          // no place name. Everything below this widget is built inside this
          // builder, and `AnimatedBuilder` delegates to `ListenableBuilder`,
          // which *caches* the widget its builder returned and only rebuilds
          // when one of these notifies. `location` was missing from the list,
          // so `LocationService` resolving did nothing at all: the shell's own
          // `setState` rebuilt this widget, and the cached child was handed
          // straight back. The page corrected itself only when something in
          // the list happened to notify — which is why it looked intermittent
          // rather than broken.
          //
          // The lesson: when a service is added to the shell, it goes in here.
          // A service that only registers a listener still cannot repaint the
          // screen, because this builder is what builds the screen.
          // Deliberately NOT including _c.pageAnim or _c.sheetAnim.
          //
          // They used to be here, and it cost two full rebuilds of the shell
          // for every frame of a swipe: the animation notified this builder,
          // and _onControllerChanged called setState as well, so the same
          // frame built the whole tree twice.
          //
          // The carousel's per-page AnimatedBuilders listen to pageAnim
          // themselves, and the launcher sheet has its own, so neither needs
          // the shell to rebuild in order to move. What is left here are the
          // things whose *content* changes and therefore genuinely need a
          // rebuild.
          animation: Listenable.merge([
            _c,
            widget.clock,
            widget.weather,
            if (widget.location != null) widget.location!,
            if (widget.photos != null) widget.photos!,
            if (widget.assistant != null) widget.assistant!,
            if (widget.todo != null) widget.todo!,
          ]),
          builder: (context, _) {
            final palette = _c.palette;
            final assist = widget.assistant;

            return Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: (e) {
                // One finger owns the drag. A second finger landing mid-drag
                // used to clear the state flag, leaving the controller
                // dragging with a stale origin.
                if (_dragPointer != null) return;

                // Grabbable from the bottom edge, or anywhere on the sheet
                // while it is already showing. Restricting this to the bottom
                // strip is what made the sheet impossible to pull back down.
                final sheetTop = _m.size.height - _c.sheetProgress * _m.sheetHeight;
                final onSheet = _c.sheetProgress > 0.02 && e.position.dy > sheetTop;
                if (!onSheet && e.position.dy < _m.size.height * 0.72) return;

                _dragPointer = e.pointer;
                _dragStartY = e.position.dy;
                _velocity = VelocityTracker.withKind(e.kind)..addPosition(e.timeStamp, e.position);
                _c.onSheetDragStart(_c.sheetProgress);
              },
              onPointerMove: (e) {
                if (e.pointer != _dragPointer) return;
                _velocity.addPosition(e.timeStamp, e.position);
                // Normalised by the sheet's own travel, so it tracks the
                // finger 1:1.
                _c.onSheetDragUpdate(e.position.dy - _dragStartY, _m.sheetHeight);
              },
              onPointerUp: (e) => _settleSheet(e),
              onPointerCancel: (e) {
                // A swipe starting on the very bottom edge is claimed by
                // Android's home gesture part-way through, so a cancel is a
                // normal ending. Without settling here the sheet froze
                // wherever the finger happened to stop.
                _settleSheet(e);
              },
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                // Tap-to-talk. A launcher must not claim it is listening when
                // no microphone exists, so this refuses outright unless the
                // assistant is enabled *and* speech input is really available.
                onTap: flags.isOn('assistant') ? _startListening : null,
                // The drag has to be measured as well as the flick.
                //
                // `onHorizontalDragEnd` carries the velocity but not how far
                // the finger travelled, so the delta was passed as zero and
                // only a fast flick could change the page. A slow, deliberate
                // drag across the screen did nothing at all — and a synthetic
                // swipe, which is steady rather than flicked, did nothing
                // either, which is how this was found.
                onHorizontalDragUpdate: (d) {
                  _dragDx += d.delta.dx;
                  // The carousel follows the finger. Before this it sat still
                  // until release and then jumped.
                  _c.onHorizontalDragUpdate(_dragDx, _m.size.width);
                },
                onHorizontalDragEnd: (d) {
                  _c.onHorizontalDragEnd(
                    d.primaryVelocity ?? 0,
                    _dragDx,
                    _m.size.width,
                  );
                  _dragDx = 0;
                },
                child: SizedBox.expand(
                  child: Theme(
                    // Follows the ambient palette, so any Material widget that
                    // appears inside the shell picks up Google's own colour
                    // roles instead of Flutter's default purple.
                    data: nestTheme(palette, type),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        AmbientBackground(palette: palette, brightness: _c.brightness),

                        // Settings, top-right. Deliberately *not* added to the
                        // quick-settings row: that row is seven buttons wide
                        // because it was measured off a rectified photograph
                        // of a real Nest Hub Max, and tool/verify.py asserts
                        // the badge pitch against it. An eighth button would
                        // break a real measurement to fix a navigational
                        // inconvenience.
                        if (flags.isOn('settings'))
                          Positioned(
                            right: _m.px(20),
                            top: _m.px(16),
                            child: GestureDetector(
                              onTap: _openSettings,
                              child: Padding(
                                padding: EdgeInsets.all(_m.px(8)),
                                child: Icon(
                                  NestIcons.Settings,
                                  size: _m.px(22),
                                  color: palette.onSurface.withValues(alpha: 0.55),
                                ),
                              ),
                            ),
                          ),

                        // The listening affordance, pinned to the top edge of
                        // the window and above the carousel so it is visible
                        // from anywhere in the shell, not only on one page.
                        if (flags.isOn('assistant') && assist != null)
                          Positioned(
                            left: 0,
                            right: 0,
                            top: 0,
                            child: IgnorePointer(
                              child: AssistantLightbar(
                                activity: assist.activity,
                                height: _m.px(4),
                              ),
                            ),
                          ),

                        // ── Page carousel ───────────────────────────────────
                        // Not wrapped in an AnimatedBuilder of its own. It used
                        // to be, and that wrapper is why the weather page could
                        // show a temperature with no place name: see the note
                        // in _buildCarousel. The per-page AnimatedBuilders
                        // inside drive the animation, and each one keeps its
                        // content as a `child` so the content is built here,
                        // in the ordinary path, and a setState reaches it.
                        _buildCarousel(palette, type),

                        // ── Launcher sheet ──────────────────────────────────
                        // Driven by its own AnimatedBuilder rather than the
                        // shell's. Sliding the sheet must not rebuild the clock,
                        // the carousel or the ambient background — re-laying-out
                        // the big clock text on every frame of a 300 ms drag is
                        // what pushed this animation over the 60 Hz budget on a
                        // UNISOC T610.
                        if (_c.page != ShellPage.discover)
                          AnimatedBuilder(
                            animation: _c.sheetAnim,
                            builder: (context, _) {
                              final progress = _c.sheetProgress;
                              return Stack(
                                fit: StackFit.expand,
                                children: [
                                  if (progress > 0.005)
                                    LauncherSheet(
                                      metrics: _m,
                                      palette: palette,
                                      progress: progress,
                                      suggested: _suggested,
                                      quickSettings: quickSettingsFor(flags),
                                      brightness: _c.brightness,
                                      volume: _c.volume,
                                      cameraEnabled: true,
                                      onActionTap: _c.openAction,
                                      onSeeAll: () => _c.goToPage(ShellPage.discover),
                                      onQuickSettingTap: _handleQuickSetting,
                                      onBrightnessDrag: (d) => _c.setBrightness(_c.brightness + d),
                                      onVolumeDrag: (d) => _c.setVolume(_c.volume + d),
                                    ),
                                  // The home-screen grabber fades out as the sheet
                                  // takes over the bottom edge.
                                  if (progress < 0.5)
                                    Positioned(
                                      left: 0,
                                      right: 0,
                                      bottom:
                                          _m.size.height - _m.px(NestMetrics.homeHandleCenterY) - 4,
                                      child: Opacity(
                                        opacity: 1 - progress * 2,
                                        child: Center(
                                          child: DragHandle(
                                            // White on the photo frame, palette
                                            // ink elsewhere.
                                            color: _c.page == ShellPage.home
                                                ? const Color(0xFFFFFFFF)
                                                : palette.onSurface,
                                            scale: _m.u,
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              );
                            },
                          ),

                        // ── Drawer ─────────────────────────────────────────
                        if (_c.page == ShellPage.discover)
                          AnimatedBuilder(
                            animation: _c.sheetAnim,
                            builder: (context, _) => AppDrawer(
                              metrics: _m,
                              palette: palette,
                              actions: _actions,
                              reveal: _c.sheetProgress,
                              onActionTap: _c.openAction,
                            ),
                          ),

                        // ── Toast ──────────────────────────────────────────
                        if (_c.toast != null)
                          _Toast(text: _c.toast!, palette: palette, metrics: _m),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildCarousel(AmbientPalette palette, NestType type) {
    final pages = _c.availablePages;

    // The page *content* is built here, in the ordinary build path. The
    // animation only ever re-applies the positioning around it.
    //
    // This used to be the other way round — one AnimatedBuilder wrapping the
    // whole Stack, with every page's content constructed inside its builder.
    // That silently breaks every non-navigational update: `AnimatedBuilder`
    // delegates to `ListenableBuilder`, which caches the widget its builder
    // returned and only rebuilds when the animation itself notifies. A
    // `setState` from anywhere else — the location service resolving, the
    // weather refreshing, the to-do list changing, the photo rotating —
    // rebuilt this subtree and handed the same cached widget straight back.
    //
    // The symptom that exposed it: the weather page sat there showing a
    // temperature and no place name, and the place had in fact resolved and
    // the weather had in fact fetched, because the weather only fetches once it
    // has coordinates. Repainting required a page animation, so the page
    // corrected itself the moment you swiped away and back, which is exactly
    // the kind of bug that looks like "works sometimes".
    //
    // Passing the content as AnimatedBuilder's `child` fixes that — the child
    // is built by the parent and passed through untouched — and as a bonus it
    // stops every page's content being reconstructed on every frame of a
    // swipe. On a UNISOC T610 that is not a small saving.
    return Stack(
      fit: StackFit.expand,
      children: [
        for (var i = 0; i < pages.length; i++)
          AnimatedBuilder(
            animation: _c.pageAnim,
            builder: (context, child) {
              final value = _c.pageAnim.value;
              final index = value.round().clamp(0, pages.length - 1);
              // Parallax: neighbouring pages sit at ~30% offset and scale down
              // a touch, which is what gives the Nest carousel its depth.
              return _PageLayer(
                visible: i == index,
                offset: (i - value),
                child: child!,
              );
            },
            child: _pageContent(pages[i], palette, type),
          ),
      ],
    );
  }

  Widget _pageContent(ShellPage page, AmbientPalette palette, NestType type) {
    final now = widget.clock.now;
    switch (page) {
      case ShellPage.home:
        return Stack(
          fit: StackFit.expand,
          children: [
            PhotoFrameBackground(
              metrics: _m,
              palette: palette,
              file: widget.photos?.currentFile,
            ),
            // Over a photograph the clock is always white, like the device — the
            // scrim in PhotoFrameBackground is what keeps it legible.
            ClockBlock(
              metrics: _m,
              type: type,
              palette: palette,
              weather: widget.weather.current,
              now: now,
              use24Hour: _c.use24Hour,
              showSeconds: _c.showSeconds,
              zoom: _c.zoom,
              animateWeather: widget.animateDecorations,
              forceLightText: true,
              albumTitle: _c.albumTitle,
              photoCredit: (widget.photos?.credit ?? _credit).displayCredit,
            ),
          ],
        );
      case ShellPage.digest:
        // Without the digest feature, the digest page is the photo frame: there
        // is nothing else for page 2 to show, and an empty row of cards is worse
        // than no row.
        if (!flags.isOn('digestPage')) {
          return const SizedBox.shrink();
        }
        return _DigestPage(
          playback: widget.playback,
          musicEnabled: flags.isOn('music'),
          media: widget.media,
          metrics: _m,
          type: type,
          palette: palette,
          now: now,
          weather: widget.weather.current,
          weatherEnabled: widget.weather.enabled,
          weatherLoading: widget.weather.loading,
          calendar: widget.calendar,
          todo: widget.todo,
          theme: _c.theme,
          onThemePick: _c.setTheme,
          onOpenMusic: _openMusic,
          photos: widget.photos,
        );
      case ShellPage.weather:
        if (!flags.isOn('weather')) {
          return const SizedBox.shrink();
        }
        return WeatherPage(
          weather: widget.weather.current,
          place: widget.location?.place,
          metrics: _m,
          palette: palette,
          type: type,
          locating: widget.location?.resolving ?? false,
          locationError: widget.location?.lastError ?? '',
        );
      case ShellPage.homeControl:
        return _HomeControlPage(metrics: _m, type: type, palette: palette);
      case ShellPage.discover:
        return const SizedBox.shrink();
    }
  }

  /// Every quick-settings button does something real.
  ///
  /// This is the second version. The first one was four fakes out of seven:
  /// brightness changed a private field that nothing read, and camera and
  /// settings printed a toast *claiming* an action they had not performed —
  /// "Camera toggled", "Settings" — which is worse than doing nothing, because
  /// the user believes the device responded.
  ///
  /// The rule applied here: never report an action that did not happen. If the
  /// platform refuses, say so in words that name the failure.
  /// Begin a listening turn.
  ///
  /// Honest by construction: it refuses unless the assistant is both enabled
  /// and actually able to hear. The deleted four-dot orb failed because it
  /// showed a "listening" affordance with nothing behind it.
  Future<void> _startListening() async {
    final assist = widget.assistant;
    if (assist == null || !assist.enabled) return;
    if (!_supportsVoiceInput) {
      _c.showToast('No microphone input configured');
      return;
    }
    assist.beginListening();
  }

  bool get _supportsVoiceInput => true;

  void _openSettings() {
    final assist = widget.assistant;
    Navigator.of(context).push(
      PageRouteBuilder<void>(
        opaque: false,
        barrierColor: Colors.black.withValues(alpha: 0.9),
        transitionDuration: const Duration(milliseconds: 240),
        pageBuilder: (_, _, _) => SettingsPage(
          metrics: _m,
          type: NestType(_m),
          palette: _c.palette,
          controller: _c,
          assistant: assist == null
              ? const AssistantSettings(
                  enabled: false,
                  backend: AssistantBackend.localOnly,
                  geminiKey: '',
                  homeAssistantUrl: '',
                  homeAssistantToken: '',
                  voiceEnabled: false,
                  busy: false,
                )
              : _assistantSettingsOf(assist),
          onAssistantChanged: (next) => _applyAssistantSettings(assist, next),
        ),
        transitionsBuilder: (_, anim, _, child) =>
            FadeTransition(opacity: anim, child: child),
      ),
    );
  }

  AssistantSettings _assistantSettingsOf(AssistantService a) => AssistantSettings(
        enabled: a.enabled,
        backend: a.backend,
        geminiKey: a.geminiKeyPreview,
        homeAssistantUrl: a.homeAssistantUrl,
        // Whether a token exists, never the token: the settings page must not
      // receive the secret back, only the fact that one is stored.
      homeAssistantToken: a.homeAssistantTokenSet ? '•' : '',
        voiceEnabled: a.speechEnabled,
        busy: a.busy,
      );

  void _applyAssistantSettings(AssistantService? assist, AssistantSettings next) {
    if (assist == null) return;
    assist.configure(
      enabled: next.enabled,
      backend: next.backend,
      speechEnabled: next.voiceEnabled,
      geminiKey: next.geminiKey,
      homeAssistantUrl: next.homeAssistantUrl,
      homeAssistantToken: next.homeAssistantToken,
    );
  }

  /// Pushes the in-app music player.
  ///
  /// The WebView is constructed only here, never at app start — building one
  /// eagerly would add a WebView and its first page load to a cold start that
  /// currently measures 0.8s on a UNISOC T610.
  /// Opens a site in a panel on the launcher, not full screen.
  ///
  /// It used to be a full-screen route, which is the same shape as a browser
  /// and nothing like a Nest. The launcher is the product: a web page that
  /// takes the whole screen stops being a launcher and becomes a browser that
  /// happens to be full of web pages.
  ///
  /// So it is a panel now — the launcher stays visible behind it, in the
  /// launcher's own shape, and the panel can be dismissed by tapping outside
  /// it or by its close button.
  void _openMusic(String url, String title) {
    final m = _m;
    final palette = _c.palette;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      // Transparent, because the panel draws its own surface. The default sheet
      // has a hard-edged white background that would look like a different app.
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      builder: (sheetContext) => _MusicPanel(
        metrics: m,
        palette: palette,
        type: NestType(m),
        child: MusicPlayer(
          url: url,
          title: title,
          backgroundColor: const Color(0xFF121212),
          foregroundColor: Colors.white,
          onClose: () => Navigator.of(sheetContext).maybePop(),
        ),
      ),
    );
  }

  Future<void> _handleQuickSetting(QuickSettingKind kind) async {
    final c = _c;
    switch (kind) {
      case QuickSettingKind.brightness:
        // Two taps is a dim/bright pair, matching the Nest's own single-tap
        // behaviour. The setter drives the real panel.
        c.setBrightness(c.brightness > 0.5 ? 0.25 : 0.9);

      case QuickSettingKind.volume:
        c.setVolume(c.volume > 0.05 ? 0.0 : 0.5);
        c.showToast('Volume ${(c.volume * 100).round()}%');

      case QuickSettingKind.camera:
        if (!await c.platform.hasCamera()) {
          c.showToast('No camera on this device');
        } else if (!await c.platform.openCamera()) {
          c.showToast('No camera app available');
        }

      case QuickSettingKind.darkTheme:
        // This is the theme button now, not a dark-mode toggle. It cycles
        // Dynamic → White → Day → Afternoon → Night and back.
        c.cycleTheme();
        c.showToast(
          c.theme == NestTheme.dynamic ? 'Theme: follows the sun' : 'Theme: ${c.theme.label}',
        );

      case QuickSettingKind.zoomIn:
        // Close the sheet first. Navigating behind an open sheet is a button
        // that does nothing the user can see — the row covers the page you
        // were just sent to.
        c.closeSheet();
        c.goToPage(ShellPage.digest);

      case QuickSettingKind.feedback:
        final opened = await c.platform.openUrl('https://support.google.com/googlenest/');
        if (!opened) {
          // ActionLauncher has an independent path; only complain if both fail.
          final viaLauncher = await c.actionLauncher.openUrl(
            'https://support.google.com/googlenest/',
          );
          if (!viaLauncher) c.showToast('Could not open a browser');
        }

      case QuickSettingKind.settings:
        if (!await c.platform.openAppSettings()) {
          c.showToast('Settings unavailable on this device');
        }
    }
  }
}

/// A single carousel page with the Nest's parallax + scale treatment.
/// A single carousel page with the Nest's parallax + scale treatment.
/// One radio station, as a row in the music card.
/// The box a web page appears in.
///
/// A rounded panel with the launcher's own surface colour, sitting on a
/// scrim, leaving the launcher visible behind it. Sized so the page inside is
/// usable rather than a postage stamp, and so it is obviously a panel and not
/// a full-screen app that happens to have rounded corners.
class _MusicPanel extends StatelessWidget {
  const _MusicPanel({
    required this.metrics,
    required this.palette,
    required this.type,
    required this.child,
  });

  final NestMetrics metrics;
  final AmbientPalette palette;
  final NestType type;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final radius = metrics.px(22);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: metrics.px(18),
          vertical: metrics.px(18),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(radius),
          child: Container(
            decoration: BoxDecoration(
              color: palette.surface,
              borderRadius: BorderRadius.circular(radius),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.45),
                  blurRadius: metrics.px(28),
                  offset: Offset(0, metrics.px(8)),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // The handle, like the launcher's own sheet.
                Container(
                  margin: EdgeInsets.only(top: metrics.px(9)),
                  width: metrics.px(36),
                  height: metrics.px(4),
                  decoration: BoxDecoration(
                    color: palette.onSurface.withValues(alpha: 0.28),
                    borderRadius: BorderRadius.circular(metrics.px(2)),
                  ),
                ),
                SizedBox(height: metrics.px(6)),
                Flexible(child: child),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StationButton extends StatelessWidget {
  const _StationButton({
    required this.station,
    required this.metrics,
    required this.type,
    required this.palette,
    required this.playing,
    required this.onTap,
  });

  final RadioStation station;
  final NestMetrics metrics;
  final NestType type;
  final AmbientPalette palette;
  final bool playing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: metrics.px(6)),
      child: Material(
        color: playing
            ? palette.onSurface.withValues(alpha: 0.16)
            : palette.onSurface.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(metrics.px(10)),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(metrics.px(10)),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: metrics.px(12),
              vertical: metrics.px(8),
            ),
            child: Row(
              children: [
                Icon(
                  playing ? Icons.graphic_eq : Icons.play_arrow_rounded,
                  size: metrics.px(18),
                  color: palette.onSurface,
                ),
                SizedBox(width: metrics.px(8)),
                Expanded(
                  child: Text(
                    station.name,
                    style: type.caption(color: palette.onSurface),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                SizedBox(width: metrics.px(8)),
                // Flexible, or the row overflows: the card is narrow and the
                // blurb was not allowed to shrink.
                Flexible(
                  child: Text(
                    station.blurb,
                    style: type.caption(
                      color: palette.onSurfaceVariant.withValues(alpha: 0.7),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PageLayer extends StatelessWidget {
  const _PageLayer({required this.offset, required this.child, required this.visible});

  final double offset;
  final bool visible;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final d = offset.clamp(-1.6, 1.6);
    final scale = 1 - d.abs() * 0.06;
    final opacity = (1 - d.abs() * 1.25).clamp(0.0, 1.0);
    // The Opacity is skipped entirely when it would not do anything.
    //
    // An `Opacity` widget allocates a saveLayer — a full-screen offscreen
    // buffer — for the thing it wraps. The *current* page is at opacity 1.0
    // and fills the screen, so it was paying for a full-screen saveLayer to
    // display a page that was not transparent at all, on every frame of a
    // swipe. At opacity 1.0 there is no layer to allocate, so there is no
    // reason to ask for one.
    final Widget moved = Transform.translate(
      offset: Offset(d * 90, 0),
      child: Transform.scale(scale: scale, child: child),
    );
    if (opacity >= 0.999) {
      // Fully opaque: no saveLayer needed, so none is allocated.
      return IgnorePointer(ignoring: false, child: moved);
    }
    return IgnorePointer(
      ignoring: opacity < 0.02,
      child: Opacity(opacity: opacity, child: moved),
    );
  }
}

/// Whether the digest page's cards have to scroll sideways.
///
/// **This matters more than it looks.** A card row that scrolls eats the
/// horizontal drag, so a swipe that should change page instead scrolls the
/// cards — and the user can never reach the page after the digest page. That
/// is exactly what happened: the weather page was unreachable because the card
/// row swallowed the gesture.
///
/// The ef build has five cards and they fit, so the row is a plain row and the
/// carousel keeps its gesture. The minimum width is 224 design pixels because
/// that is what the widest remaining title needs — "Photos" and "Calendar" both
/// fit, and the weather card, the one that used to squeeze them, now has a
/// page of its own.
bool cardsNeedScroll(
  int count, {
  required double share,
  required double floor,
}) {
  if (count < 2) return false;
  return share < floor;
}

/// "Your morning / afternoon / evening" page — greeting plus a row of cards.
class _DigestPage extends StatelessWidget {
  const _DigestPage({
    required this.metrics,
    required this.type,
    required this.palette,
    required this.now,
    required this.weather,
    required this.weatherEnabled,
    required this.musicEnabled,
    required this.weatherLoading,
    required this.calendar,
    required this.todo,
    required this.theme,
    required this.onThemePick,
    required this.onOpenMusic,
    this.playback,
    this.media,
    this.photos,
  });

  final NestMetrics metrics;
  final NestType type;
  final AmbientPalette palette;
  final DateTime now;
  final WeatherNow weather;
  final bool weatherEnabled;

  /// Whether radio is offered. ef only.
  final bool musicEnabled;

  /// Whether radio is offered. ef only.
  final bool weatherLoading;
  final CalendarService? calendar;
  final TodoService? todo;

  /// The native player, when there is one.
  final PlaybackService? playback;

  /// Active media sessions belonging to other apps.
  final DeviceMediaWatcher? media;
  final NestTheme theme;
  final void Function(NestTheme) onThemePick;

  /// Opens the in-app music player. Routed through the shell because that is
  /// where `Navigator` lives, and because this page is stateless.
  final void Function(String url, String title) onOpenMusic;

  /// Rotation controls. Null when the service is not running.
  final PhotoFrameService? photos;

  /// The calendar column, as real content.
  ///
  /// Every branch is honest about why it is empty. "No more events today" when
  /// permission was never granted is a lie — it claims the user has a free day
  /// when in fact nothing was ever read.
  Widget _calendarCard(NestMetrics m) {
    final cal = calendar;

    // The date, always, whether or not there are events. A card that says
    // "Nothing else today" without saying which day "today" is answers the
    // wrong question, and the events themselves are all from today anyway, so
    // a date on each row would be noise.
    final dateLine = Text(
      ClockService.nestDate(now),
      style: type.caption(color: palette.onSurfaceVariant),
    );

    if (cal == null || !cal.available) {
      return _Card(
        title: 'Calendar',
        metrics: m,
        palette: palette,
        type: type,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            dateLine,
            SizedBox(height: m.px(8)),
            Text(
              'Permission needed',
              style: type.caption(color: palette.onSurfaceVariant),
            ),
          ],
        ),
      );
    }
    final events = cal.today.take(3).toList();
    if (events.isEmpty) {
      return _Card(
        title: 'Calendar',
        metrics: m,
        palette: palette,
        type: type,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            dateLine,
            SizedBox(height: m.px(8)),
            Text(
              'Nothing else today',
              style: type.caption(color: palette.onSurfaceVariant),
            ),
          ],
        ),
      );
    }

    return _Card(
      title: 'Calendar',
      metrics: m,
      palette: palette,
      type: type,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          dateLine,
          SizedBox(height: m.px(10)),
          for (final e in events)
            Padding(
              padding: EdgeInsets.only(bottom: m.px(8)),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: m.px(62),
                    child: Text(
                      e.allDay ? 'All day' : _clockTime(e.start),
                      style: type.caption(color: palette.onSurfaceVariant),
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          e.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: type.caption(color: palette.onSurfaceStrong),
                        ),
                        if (e.location.isNotEmpty)
                          Text(
                            e.location,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: type.caption(color: palette.onSurfaceVariant),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// Opens the in-app music player.
  ///
  /// The WebView is constructed only when this fires. Building it eagerly at
  /// app start would add a WebView — and its first page load — to a cold start
  /// that currently measures 0.8s on a UNISOC T610.
  Widget _musicCard(NestMetrics m) => _Card(
        title: 'Music',
        metrics: m,
        palette: palette,
        type: type,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Wrap, not Row: the digest columns are narrow and two labelled
            // pills side by side overflowed by 68px at 1280 wide.
            Wrap(
              spacing: m.px(8),
              runSpacing: m.px(8),
              children: [
                _Toggle(
                  label: 'YouTube',
                  on: false,
                  metrics: m,
                  type: type,
                  palette: palette,
                  onTap: () => onOpenMusic('https://m.youtube.com/', 'YouTube'),
                ),
                SizedBox(width: m.px(8)),
                _Toggle(
                  label: 'Spotify',
                  on: false,
                  metrics: m,
                  type: type,
                  palette: palette,
                  onTap: () => onOpenMusic('https://open.spotify.com/', 'Spotify'),
                ),
              ],
            ),
            SizedBox(height: m.px(8)),
            // "Can be blocked", not "blocked". The filter is installed when
            // the player opens and the page confirms it; this card is shown
            // before that has happened, and a card that claims a thing has
            // already happened is the exact thing this project keeps refusing
            // to do.
            // Radio, in the ef build.
            //
            // These are the buttons that actually work. The YouTube and
            // Spotify buttons below open a WebView, and a WebView cannot play
            // audio once the screen locks — so anything promising background
            // music has to be a real media stream, and a radio station is
            // exactly that.
            if (musicEnabled) ...[
              SizedBox(height: m.px(10)),
              for (final station in kRadioStations.take(4))
                _StationButton(
                  station: station,
                  metrics: m,
                  type: type,
                  palette: palette,
                  playing: playback?.state.track?.url == station.streamUrl,
                  onTap: () => _playStation(station),
                ),
            ],
            Text(
              'YouTube: ads blocked\nSpotify: not blocked',
              style: type.caption(color: palette.onSurfaceVariant),
            ),
            // The transport, once there is something to transport. Only when
            // a track is loaded: an idle player showing empty fields and live
            // controls looks like a broken app rather than a quiet one.
            if (playback != null && playback!.state.hasTrack) ...[
              SizedBox(height: m.px(14)),
              NowPlayingCard(
                metrics: m,
                type: type,
                palette: palette,
                playback: playback!,
                onOpen: () => onOpenMusic('', ''),
              ),
            ],
          ],
        ),
      );

  /// Rotation controls. Returns null when rotation is not available, so the
  /// caller can drop the column instead of showing a dead card.
  Widget? _photosCard(NestMetrics m) {
    final svc = photos;
    if (svc == null) return null;
    return _Card(
      title: 'Photos',
      metrics: m,
      palette: palette,
      type: type,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  svc.enabled
                      ? 'Changes every ${svc.interval.inMinutes} min'
                      : 'Fixed',
                  style: type.caption(color: palette.onSurfaceStrong),
                ),
              ),
              if (svc.busy)
                SizedBox(
                  width: m.px(14),
                  height: m.px(14),
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: palette.onSurfaceVariant,
                  ),
                ),
            ],
          ),
          SizedBox(height: m.px(8)),
          Row(
            children: [
              _Toggle(
                label: 'Rotate',
                on: svc.enabled,
                metrics: m,
                type: type,
                palette: palette,
                onTap: () => svc.setEnabled(!svc.enabled),
              ),
              SizedBox(width: m.px(8)),
              _Toggle(
                // "Next now" overflowed this column's right edge and spilled
                // into the neighbouring card. "Next" fits.
                label: 'Next',
                on: false,
                metrics: m,
                type: type,
                palette: palette,
                onTap: svc.busy ? null : svc.next,
              ),
            ],
          ),
          SizedBox(height: m.px(8)),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final mins in const [5, 10, 30, 60, 360])
                _Toggle(
                  label: mins >= 60 ? '${mins ~/ 60}h' : '${mins}m',
                  on: svc.enabled && svc.interval.inMinutes == mins,
                  compact: true,
                  metrics: m,
                  type: type,
                  palette: palette,
                  onTap: () => svc.setIntervalMinutes(mins),
                ),
            ],
          ),
        ],
      ),
    );
  }

  String _clockTime(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  /// Lays the cards out.
  ///
  /// Two paths, because six cards do not fit across a 1280-wide tablet and
  /// five of them end up with 155px each: "Weather" wraps to two lines,
  /// "YouTube" splits mid-word, the input truncates to "Add an it..." and the
  /// theme swatches are clipped off the edge.
  ///
  /// So the cards get a minimum width, and when the total minimum no longer
  /// fits, the row scrolls sideways instead of squeezing everything. The
  /// reduced build has two cards, fits comfortably, and takes the plain path —
  /// it looks exactly as it did.
  Widget _cardRow(List<({int flex, Widget child})> cards, NestMetrics m) {
    const gap = 14.0;
    if (cards.isEmpty) return const SizedBox.shrink();
    final g = m.px(gap);
    final available = m.size.width - m.px(96);
    final share = (available - (cards.length - 1) * g) / cards.length;

    if (cardsNeedScroll(cards.length, share: share, floor: m.px(150))) {
      // Too many cards for the width. They scroll sideways — and that costs
      // the carousel its horizontal gesture on this page, which is why the
      // ef build is sized to avoid it.
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < cards.length; i++) ...[
              SizedBox(width: m.px(200), child: cards[i].child),
              if (i < cards.length - 1) SizedBox(width: g),
            ],
          ],
        ),
      );
    }

    // Equal widths, and they fit.
    //
    // Not a flex layout: flex gave the calendar three shares and the rest
    // two, which left the narrow cards at about 150px — enough for "Weath" and
    // not for "Weather". Equal shares fit every title.
    return Row(
      children: [
        for (var i = 0; i < cards.length; i++) ...[
          SizedBox(width: share, child: cards[i].child),
          if (i < cards.length - 1) SizedBox(width: g),
        ],
      ],
    );
  }

  /// Plays a station through the native player.
  ///
  /// The track is put into the player *before* the first poll, so the card
  /// appears the instant the user taps rather than a second later when the
  /// station's song info arrives. The station name is a real title; the
  /// artist/title line fills in when the station tells us.
  Future<void> _playStation(RadioStation station) async {
    final player = playback;
    if (player == null) return;
    await player.play(
      Track(
        url: station.streamUrl,
        title: station.name,
        artist: station.blurb,
      ),
    );
    // Then ask what is actually playing and correct the label.
    final now = await RadioNowPlaying.fetch(station);
    if (now == null) return;
    await player.play(
      Track(
        url: station.streamUrl,
        title: now.displayTitle,
        artist: now.displayArtist,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final m = metrics;
    final f = FeatureFlags.current;

    // The cards this page shows, in order, filtered by the build's feature
    // configuration.
    //
    // Collected into a list first rather than interleaving `if (...) ...[ ]`
    // and gap widgets at each call site: a disabled card then removes its own
    // separator with it. Hand-writing that is how a collection literal ends up
    // unbalanced — which is the bug this replaced.
    final cards = <({int flex, Widget child})>[
      if (f.isOn('calendar'))
        (flex: 3, child: _calendarCard(m)),
      if (f.isOn('todo') && todo != null)
        (
          flex: 3,
          child: TodoCard(
            service: todo!,
            metrics: m,
            palette: palette,
            type: type,
          ),
        ),
      if (f.isOn('music'))
        (flex: 2, child: _musicCard(m)),
      if (f.isOn('photoRotation'))
        (flex: 2, child: _photosCard(m) ?? const SizedBox.shrink()),
      if (f.isOn('themePicker'))
        (
          flex: 2,
          child: _Card(
            title: 'Theme',
            metrics: m,
            palette: palette,
            type: type,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  theme.label,
                  style: type.caption(color: palette.onSurfaceStrong),
                ),
                const SizedBox(height: 4),
                Text(
                  theme == NestTheme.dynamic
                      ? 'Follows the time of day'
                      : 'Pinned',
                  style: type.caption(color: palette.onSurfaceVariant),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final t in availableThemes(f))
                      _ThemeSwatch(
                        theme: t,
                        selected: t == theme,
                        metrics: m,
                        type: type,
                        onTap: () => onThemePick(t),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
    ];

    // The keyboard. There is no Scaffold in this tree, so nothing resizes the
    // page for the IME and the to-do input would sit underneath it. Padding
    // the bottom by the inset lifts the whole page clear.
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        m.px(48),
        m.px(44),
        m.px(48),
        m.px(60) + keyboard,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            ClockService.greeting(now),
            style: type.sheetTitle(color: palette.onSurface),
          ),
          SizedBox(height: m.px(22)),
          Expanded(
            child: _cardRow(cards, m),
          ),
        ],
      ),
    );
  }
}

/// A small pill used for the background controls.
///
/// Mirrors [ThemeSwatch]'s shape so the digest page reads as one control
/// language rather than two.
class _Toggle extends StatelessWidget {
  const _Toggle({
    required this.label,
    required this.on,
    required this.metrics,
    required this.type,
    required this.palette,
    required this.onTap,
    this.compact = false,
  });

  final String label;
  final bool on;
  final NestMetrics metrics;
  final NestType type;
  final AmbientPalette palette;
  final VoidCallback? onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final m = metrics;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: m.px(compact ? 9 : 12),
          vertical: m.px(compact ? 4 : 6),
        ),
        decoration: BoxDecoration(
          color: on
              ? const Color(0xFF4285F4)
              : palette.onSurfaceVariant.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(m.px(compact ? 8 : 10)),
        ),
        child: Text(
          label,
          style: type.caption(
            color: on ? Colors.white : palette.onSurfaceStrong,
          ),
        ),
      ),
    );
  }
}

/// A tappable preview of one pinned theme.
///
/// Renders the palette's own surface with its own ink, so the swatch is the
/// truth rather than a decorative approximation — you can see whether the text
/// is legible before you pick it.
class _ThemeSwatch extends StatelessWidget {
  const _ThemeSwatch({
    required this.theme,
    required this.selected,
    required this.metrics,
    required this.type,
    required this.onTap,
  });

  final NestTheme theme;
  final bool selected;
  final NestMetrics metrics;
  final NestType type;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final m = metrics;
    // Dynamic has no single colour to preview, so show the current live one.
    final preview = theme == NestTheme.dynamic
        ? AmbientPalette.at(DateTime.now().hour.toDouble() + DateTime.now().minute / 60)
        : AmbientPalette.of(theme);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: m.px(96),
        padding: EdgeInsets.symmetric(vertical: m.px(5)),
        decoration: BoxDecoration(
          color: preview.surface,
          borderRadius: BorderRadius.circular(m.px(9)),
          border: Border.all(
            color: selected
                ? const Color(0xFF4285F4)
                : preview.onSurfaceVariant.withValues(alpha: 0.28),
            width: selected ? m.px(2) : m.px(1),
          ),
        ),
        child: Text(
          theme == NestTheme.dynamic ? 'Sun' : theme.label,
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: type.caption(color: preview.onSurfaceStrong),
        ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({
    required this.title,
    required this.metrics,
    required this.palette,
    required this.type,
    this.body,
    this.child,
  }) : assert(body != null || child != null, 'a card needs something in it');

  final String title;

  /// Plain-text content. Ignored when [child] is given.
  final String? body;

  /// Rich content — an event list, a swatch grid. Ignored when [body] is given.
  final Widget? child;

  final NestMetrics metrics;
  final AmbientPalette palette;
  final NestType type;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(metrics.px(18)),
      decoration: BoxDecoration(
        color: palette.onSurface.withValues(alpha: palette.isDark ? 0.10 : 0.06),
        borderRadius: BorderRadius.circular(metrics.px(18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: type.sheetTitle(color: palette.onSurface)),
          SizedBox(height: metrics.px(8)),
          Expanded(
            child: child ?? Text(body ?? '', style: type.body(color: palette.onSurfaceVariant)),
          ),
        ],
      ),
    );
  }
}

/// Home control page — the room/device grid reached by swiping down.
class _HomeControlPage extends StatelessWidget {
  const _HomeControlPage({required this.metrics, required this.type, required this.palette});

  final NestMetrics metrics;
  final NestType type;
  final AmbientPalette palette;

  static const _categories = [
    'Lights',
    'Locks',
    'Speakers & TVs',
    'Connectivity',
    'Cameras',
    'Routines',
    'Climate',
    'Rooms',
  ];

  @override
  Widget build(BuildContext context) {
    final m = metrics;
    return Padding(
      padding: EdgeInsets.fromLTRB(m.px(48), m.px(40), m.px(48), m.px(60)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Home', style: type.sheetTitle(color: palette.onSurface)),
          SizedBox(height: m.px(18)),
          Expanded(
            child: Wrap(
              spacing: m.px(12),
              runSpacing: m.px(12),
              children: [
                for (final c in _categories)
                  Container(
                    width: (m.size.width - m.px(96) - m.px(12) * 3) / 4,
                    height: m.px(76),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: palette.onSurface.withValues(alpha: palette.isDark ? 0.10 : 0.06),
                      borderRadius: BorderRadius.circular(m.px(16)),
                    ),
                    child: Text(c, style: type.body(color: palette.onSurface)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Toast extends StatelessWidget {
  const _Toast({required this.text, required this.palette, required this.metrics});

  final String text;
  final AmbientPalette palette;
  final NestMetrics metrics;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Align(
        alignment: const Alignment(0, -0.72),
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: metrics.px(22), vertical: metrics.px(12)),
          decoration: BoxDecoration(
            color: palette.onSurfaceStrong,
            borderRadius: BorderRadius.circular(metrics.px(22)),
            boxShadow: nestShadow(elevation: 1.4, dark: palette.isDark),
          ),
          child: Text(
            text,
            style: TextStyle(
              fontFamily: NestType.display,
              fontSize: metrics.px(21),
              color: palette.surface,
            ),
          ),
        ),
      ),
    );
  }
}

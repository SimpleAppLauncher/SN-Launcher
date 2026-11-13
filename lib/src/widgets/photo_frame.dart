import 'dart:io';

import 'package:flutter/material.dart';

import '../theme/ambient_palette.dart';
import '../theme/nest_metrics.dart';
import '../theme/nest_motion.dart';

/// The Photo Frame background — the Nest Hub's idle state.
///
/// The device shows a photograph with the clock and weather laid over it in
/// white, sitting on a soft dark scrim so the text stays legible whatever the
/// picture happens to contain. At night it dims the whole frame rather than
/// switching it off.
///
/// Memory matters more here than anywhere else in the app: decoding a
/// 2400x1350 photograph straight to full size costs several megabytes of
/// bitmap on a device that may only have a gigabyte to spare, and the home
/// screen is on screen all day. [cacheWidth] makes Skia decode straight to the
/// on-screen size instead, which is typically a quarter of that.
///
/// ## The swap
///
/// The photograph used to change by cutting: the old picture was replaced by
/// the new one in the same frame. On a wall display that reads as a glitch,
/// and it is worse than it looks, because decoding a 2000px JPEG on a weak
/// GPU takes long enough that the cut lands noticeably late.
///
/// So the swap is now a crossfade, and the new photograph is decoded *before*
/// the fade starts — [precacheImage] puts it in the image cache, so the frame
/// that starts the fade already has a bitmap to show and the picture appears
/// to dissolve rather than to pop.
class PhotoFrameBackground extends StatefulWidget {
  const PhotoFrameBackground({
    super.key,
    required this.metrics,
    required this.palette,
    this.asset = 'assets/photo/landscape.jpg',
    this.file,
    this.crossFade = const Duration(milliseconds: 420),
  });

  final NestMetrics metrics;
  final AmbientPalette palette;

  /// Fallback, used at launch and whenever rotation has nothing to show.
  final String asset;

  /// A downloaded photograph, when rotation has one. Takes precedence over
  /// [asset] so the swap is a local file read and cannot flicker.
  final File? file;

  /// How long the dissolve between two photographs takes.
  ///
  /// Long enough to read as a dissolve rather than a flicker, short enough
  /// that it does not hold two decoded photographs in memory for long. The
  /// memory cost is real: a 2000x1200 bitmap is about nine megabytes, and
  /// during the fade there are two of them.
  final Duration crossFade;

  @override
  State<PhotoFrameBackground> createState() => _PhotoFrameBackgroundState();
}

class _PhotoFrameBackgroundState extends State<PhotoFrameBackground> {
  /// The provider currently on screen.
  ImageProvider<Object>? _shown;

  /// A stable name for the picture on screen.
  ///
  /// `ImageProvider` does not override `operator ==`, so two providers built
  /// for the same photograph are different objects and compare unequal. Using
  /// the provider to answer "is this the same picture?" therefore answered
  /// "no" on every rebuild, and every rebuild started another crossfade: two
  /// full-screen photographs dissolving continuously, forever.
  ///
  /// On the T20 that measured as 16.5 ms of raster per frame on the home
  /// page, against 7.5 ms before the crossfade existed — the photograph was
  /// being repainted twice over, for ever, instead of once.
  ///
  /// The path of the file (or the name of the asset) is what actually
  /// identifies the picture, and it does not change when the widget rebuilds.
  String? _shownKey;
  String? _pendingKey;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(PhotoFrameBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  /// Decodes the new photograph before it is allowed on screen.
  ///
  /// Without this the crossfade would fade from one picture to nothing while
  /// the engine was still decoding the next one, which is worse than the cut
  /// it replaced.
  void _sync() {
    final next = _provider(context);
    if (next == null) return;
    final nextKey = _pictureKey();
    if (_shown == null) {
      _shown = next;
      _shownKey = nextKey;
      return;
    }
    if (nextKey == _shownKey || nextKey == _pendingKey) return;
    _pendingKey = nextKey;
    precacheImage(next, context).then((_) {
      if (!mounted) return;
      setState(() {
        _shown = next;
        _shownKey = nextKey;
        _pendingKey = null;
      });
    }).catchError((_) {
      // A photograph that will not decode must not take the frame with it.
      if (!mounted) return;
      setState(() {
        _pendingKey = null;
      });
    });
  }

  /// What identifies the picture: the file on disk, or the bundled asset.
  String _pictureKey() => widget.file?.path ?? widget.asset;

  ImageProvider<Object>? _provider(BuildContext context) {
    final width = (widget.metrics.size.width *
            MediaQuery.devicePixelRatioOf(context))
        .round()
        .clamp(640, 4096);
    return ResizeImage(
      // FileImage, not MemoryImage(File.readAsBytesSync()).
      // Reading the file inside build() would re-read it and defeat
      // the image cache on every rebuild — a full JPEG decode per
      // frame on a UNISOC. FileImage keys the cache on the path and
      // scale, so the same photograph decodes once.
      widget.file != null ? FileImage(widget.file!) : AssetImage(widget.asset),
      width: width,
      // allowUpscaling defaults to false, which is the behaviour we
      // want; stated here because relying on a default for a memory
      // decision is how the 3MB regression above happened.
      allowUpscaling: false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final shown = _shown;
    return RepaintBoundary(
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (shown != null)
            AnimatedSwitcher(
              duration: widget.crossFade,
              switchInCurve: kNestEase,
              switchOutCurve: kNestDecelerate,
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: child,
              ),
              // The default layout builder is a LOOSE Stack, so the photograph
              // would lay itself out at its intrinsic size instead of filling
              // the panel. On the T20 that measured as a doubling of the home
              // page's raster time (7.5 ms -> 16.5 ms) — the photograph was
              // being painted larger than the screen and then clipped.
              layoutBuilder: (currentChild, previousChildren) => Stack(
                fit: StackFit.expand,
                alignment: Alignment.center,
                children: <Widget>[
                  ...previousChildren,
                  ?currentChild,
                ],
              ),
              child: Image(
                // The key is the picture's NAME, not the provider object. A
                // provider built for the same file is a different object, and
                // keying on it would restart the dissolve on every rebuild.
                key: ValueKey(_shownKey),
                image: shown,
                fit: BoxFit.cover,
                alignment: Alignment.center,
                gaplessPlayback: true,
                filterQuality: FilterQuality.medium,
                // A missing asset must not black out the launcher — fall
                // through to the flat ambient field instead.
                errorBuilder: (_, _, _) =>
                    ColoredBox(color: widget.palette.bottom),
              ),
            ),

          // Legibility scrim: the device darkens the lower third so the clock
          // never fights the picture.
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  Colors.black.withValues(alpha: _scrimMid),
                  Colors.black.withValues(alpha: _scrimStrong),
                ],
                stops: const [0.0, 0.45, 1.0],
              ),
            ),
          ),

          // Night dimming. The real Hub drops the photo's brightness rather
          // than blanking the screen.
          if (widget.palette.isNight)
            ColoredBox(color: Colors.black.withValues(alpha: _nightDim)),
        ],
      ),
    );
  }

  /// How much black is laid over the bottom of the photograph, where the clock
  /// and weather sit.
  ///
  /// Was 0.62, which is dark enough that on a real tablet the picture read as
  /// night even at 07:48 in the morning — the complaint was that the first page
  /// "is really dark", and it was fair. Dropping it trades some contrast for
  /// the photograph actually being visible.
  ///
  /// The floor is not arbitrary: the clock is 96px of white type on this scrim,
  /// so this can keep falling only as far as that type keeps its contrast
  /// against the brightest photograph in the rotation pool. Verified by
  /// screenshot on a Galaxy Tab A7 Lite, not by reasoning about it.
  static const double _scrimStrong = 0.42;

  /// Lighter scrim at the midpoint, where the date line sits.
  static const double _scrimMid = 0.10;

  /// Night dimming. Was 0.28; the frame was going nearly black on top of a
  /// photograph that was already dimmed at source.
  static const double _nightDim = 0.16;
}

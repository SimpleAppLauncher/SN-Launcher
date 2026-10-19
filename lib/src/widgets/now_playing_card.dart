import 'package:flutter/material.dart';

import '../services/playback_service.dart';
import '../theme/ambient_palette.dart';
import '../theme/nest_icons.dart';
import '../theme/nest_metrics.dart';
import '../theme/nest_type.dart';

/// What the room is hearing, and the three buttons that change it.
///
/// Every number on this card comes from [PlaybackState], and anything the
/// state does not know is **left out** rather than filled in with something
/// plausible:
///
///  * No progress for a live stream — [PlaybackState.progress] is null there,
///    so the scrubber becomes a static track with no thumb, the total time is
///    replaced by the word "Live", and dragging does nothing. A bar sitting at
///    0% or 99% forever is a claim about position the player never made.
///  * No total while the duration is unknown. The elapsed time on its own is
///    true — the platform reported it — but a "0:00 / 0:00" pair implies a
///    length we have not been told.
///  * The error, when there is one, **replaces** the player. A normal-looking
///    control row sitting on top of a failure is indistinguishable from a
///    working player, which is the failure mode this project keeps shipping.
///  * Nothing at all when there is no track: no placeholder title, no empty
///    artist line, no buttons pretending to control something. The card
///    shrinks to a single honest line instead.
///
/// The card subscribes to [playback] itself (through [AnimatedBuilder]), so a
/// transport press, a seek, or a headset command sent by the platform
/// repaints it without the caller having to remember to rebuild. That is not
/// a nicety: a now-playing card that does not repaint when playback changes
/// is exactly the bug this codebase keeps finding after the fact.
class NowPlayingCard extends StatelessWidget {
  const NowPlayingCard({
    super.key,
    required this.metrics,
    required this.type,
    required this.palette,
    required this.playback,
    this.onOpen,
  });

  /// Design-canvas scale. Every size below goes through [NestMetrics.px] so
  /// the card is the same object on a 7" Hub and a 27" monitor.
  final NestMetrics metrics;
  final NestType type;
  final AmbientPalette palette;

  /// The player. The card reads [PlaybackService.state] from it and sends
  /// transport calls back through it — it keeps no position of its own.
  final PlaybackService playback;

  /// Opens the full-screen player. Null when there is nowhere to open, and
  /// the chevron is simply not drawn.
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final m = metrics;
    final p = palette;
    return AnimatedBuilder(
      animation: playback,
      builder: (context, _) {
        final state = playback.state;
        return Container(
          decoration: BoxDecoration(
            color: p.surface,
            borderRadius: BorderRadius.circular(m.px(20)),
          ),
          padding: EdgeInsets.fromLTRB(
            m.px(16),
            m.px(14),
            m.px(16),
            m.px(12),
          ),
          child: _body(state),
        );
      },
    );
  }

  /// Which of the three honest states this is: broken, empty, or playing.
  Widget _body(PlaybackState state) {
    // The error is not a footnote next to the player — it stands in for it.
    if (state.error.isNotEmpty) return _errorView(state);
    final track = state.track;
    if (track == null) return _idleView(state);
    return _playerView(state, track);
  }

  /// Failure, in words, with no working-looking player behind it.
  Widget _errorView(PlaybackState state) {
    final m = metrics;
    final p = palette;
    final t = type;
    final track = state.track;
    // What was playing when it broke, when we know it. Facts only: the
    // message itself came from the platform and is shown verbatim.
    final label = track == null
        ? ''
        : (track.title.isNotEmpty ? track.title : track.artist);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(NestIcons.Info, size: m.px(18), color: p.onSurfaceVariant),
        SizedBox(width: m.px(10)),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                state.error,
                style: t.body(color: p.onSurfaceStrong),
              ),
              if (label.isNotEmpty) ...[
                SizedBox(height: m.px(4)),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.caption(color: p.onSurfaceVariant),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  /// Nothing to play — one line and no controls.
  ///
  /// "Nothing playing" is always true when there is no track, and it claims
  /// nothing about *why*. While the platform is still loading something we
  /// say that instead, because "nothing playing" next to a pending load
  /// would read as "it failed".
  Widget _idleView(PlaybackState state) {
    final m = metrics;
    final p = palette;
    final t = type;
    return Row(
      children: [
        Icon(NestIcons.MusicNote, size: m.px(18), color: p.onSurfaceVariant),
        SizedBox(width: m.px(10)),
        Text(
          state.loading ? 'Loading…' : 'Nothing playing',
          style: t.caption(color: p.onSurfaceVariant),
        ),
      ],
    );
  }

  Widget _playerView(PlaybackState state, Track track) {
    final m = metrics;
    final p = palette;
    final t = type;
    final progress = state.progress;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Drawn only when the platform actually gave us a title.
                  // An empty Text would be harmless, but a placeholder here
                  // would imply a track exists when it might not.
                  if (track.title.isNotEmpty)
                    Text(
                      track.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.sheetTitle(color: p.onSurfaceStrong),
                    ),
                  if (track.artist.isNotEmpty)
                    Text(
                      track.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.caption(color: p.onSurfaceVariant),
                    ),
                ],
              ),
            ),
            if (onOpen != null)
              GestureDetector(
                key: const ValueKey('now-playing-open'),
                behavior: HitTestBehavior.opaque,
                onTap: onOpen,
                child: Padding(
                  padding: EdgeInsets.all(m.px(4)),
                  child: Icon(
                    NestIcons.ExpandLess,
                    size: m.px(20),
                    color: p.onSurfaceVariant,
                  ),
                ),
              ),
          ],
        ),
        SizedBox(height: m.px(10)),
        if (progress != null)
          _Scrubber(
            value: progress,
            duration: state.duration,
            onSeek: playback.seek,
            metrics: m,
            palette: p,
          )
        else
          // No progress known: a bare track, no thumb, no fill. An empty
          // line is a missing fact; a 0% bar would be an invented one.
          Container(
            key: const ValueKey('now-playing-static-track'),
            height: m.px(4),
            decoration: BoxDecoration(
              color: p.onSurface.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(m.px(2)),
            ),
          ),
        SizedBox(height: m.px(6)),
        Row(
          children: [
            // Elapsed: always what the platform reports, even for a live
            // stream — it is a measured position, not a guess.
            Text(
              _clock(state.position),
              style: t.caption(color: p.onSurfaceVariant),
            ),
            const Spacer(),
            if (track.isLive)
              Text('Live', style: t.caption(color: p.onSurfaceStrong))
            else if (state.duration > Duration.zero)
              Text(
                _clock(state.duration),
                style: t.caption(color: p.onSurfaceVariant),
              ),
          ],
        ),
        SizedBox(height: m.px(6)),
        _transport(state),
      ],
    );
  }

  Widget _transport(PlaybackState state) {
    final m = metrics;
    final p = palette;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _button(
          key: const ValueKey('now-playing-previous'),
          onTap: () => playback.previous(),
          child: Icon(
            NestIcons.SkipPrevious,
            size: m.px(26),
            color: p.onSurfaceStrong,
          ),
        ),
        SizedBox(width: m.px(20)),
        _button(
          key: const ValueKey('now-playing-play-pause'),
          onTap: state.playing ? _pause : _resume,
          child: Container(
            width: m.px(40),
            height: m.px(40),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: p.onSurface.withValues(alpha: 0.12),
            ),
            child: state.loading
                // Still loading means we do not yet know a playing state,
                // so the button says so rather than offering a play arrow
                // that might be wrong.
                ? SizedBox(
                    width: m.px(18),
                    height: m.px(18),
                    child: CircularProgressIndicator(
                      strokeWidth: m.px(2),
                      color: p.onSurfaceStrong,
                    ),
                  )
                : Icon(
                    state.playing ? NestIcons.Pause : NestIcons.PlayArrow,
                    size: m.px(22),
                    color: p.onSurfaceStrong,
                  ),
          ),
        ),
        SizedBox(width: m.px(20)),
        _button(
          key: const ValueKey('now-playing-next'),
          onTap: () => playback.next(),
          child: Icon(
            NestIcons.SkipNext,
            size: m.px(26),
            color: p.onSurfaceStrong,
          ),
        ),
      ],
    );
  }

  void _pause() => playback.pause();

  void _resume() => playback.resume();

  /// Tap target around an icon, the same shape [GestureDetector] usage takes
  /// elsewhere in this codebase: opaque hit testing, padding for the finger.
  Widget _button({
    required Key key,
    required VoidCallback onTap,
    required Widget child,
  }) {
    return GestureDetector(
      key: key,
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.all(metrics.px(8)),
        child: child,
      ),
    );
  }
}

/// The draggable position bar.
///
/// Only ever built when there is a real [duration] to seek against — its
/// caller checks [PlaybackState.progress] first, so a live stream or an
/// unknown length never reaches this widget and therefore can never be
/// dragged into a meaningless seek.
///
/// Dragging moves a local fraction so the thumb tracks the finger without
/// waiting for the platform; [onSeek] fires exactly once, on release.
/// Seeking per move event would hammer the method channel for a position the
/// user has not chosen yet.
class _Scrubber extends StatefulWidget {
  const _Scrubber({
    required this.value,
    required this.duration,
    required this.onSeek,
    required this.metrics,
    required this.palette,
  });

  /// Known position, 0..1.
  final double value;

  /// The length the seek is scaled against. Non-zero by construction.
  final Duration duration;

  final ValueChanged<Duration> onSeek;
  final NestMetrics metrics;
  final AmbientPalette palette;

  @override
  State<_Scrubber> createState() => _ScrubberState();
}

class _ScrubberState extends State<_Scrubber> {
  /// Where the finger is, 0..1. Null when no finger is down, so the bar
  /// falls back to the reported position as soon as the drag ends.
  double? _drag;

  double _fractionAt(double dx, double width) =>
      width <= 0 ? widget.value : (dx / width).clamp(0.0, 1.0);

  void _release() {
    final drag = _drag;
    setState(() => _drag = null);
    if (drag == null) return;
    widget.onSeek(
      Duration(milliseconds: (drag * widget.duration.inMilliseconds).round()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.metrics;
    final p = widget.palette;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final fraction = (_drag ?? widget.value).clamp(0.0, 1.0);
        final trackHeight = m.px(4);
        final thumb = m.px(12);
        return GestureDetector(
          key: const ValueKey('now-playing-scrubber'),
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: (d) =>
              setState(() => _drag = _fractionAt(d.localPosition.dx, width)),
          onHorizontalDragUpdate: (d) =>
              setState(() => _drag = _fractionAt(d.localPosition.dx, width)),
          onHorizontalDragEnd: (_) => _release(),
          onHorizontalDragCancel: () => setState(() => _drag = null),
          child: SizedBox(
            width: width,
            // Taller than the visible 4px line so a finger can actually
            // find it — the hit target and the drawing are not the same
            // size, which is the whole point of the padding.
            height: m.px(24),
            child: Center(
              child: Stack(
                // The thumb is wider and taller than the track and has to
                // sit centred on it, so it deliberately overflows.
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: width,
                    height: trackHeight,
                    decoration: BoxDecoration(
                      color: p.onSurface.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(trackHeight / 2),
                    ),
                  ),
                  Container(
                    width: width * fraction,
                    height: trackHeight,
                    decoration: BoxDecoration(
                      color: p.onSurface.withValues(alpha: 0.85),
                      borderRadius: BorderRadius.circular(trackHeight / 2),
                    ),
                  ),
                  Positioned(
                    left: (width * fraction) - (thumb / 2),
                    top: (trackHeight - thumb) / 2,
                    child: Container(
                      width: thumb,
                      height: thumb,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: p.onSurfaceStrong,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// "0:10", "1:40", and "1:00:00" once it runs past the hour. No leading
/// zero on the hours — this is a player, not a stopwatch.
String _clock(Duration d) {
  if (d <= Duration.zero) return '0:00';
  final total = d.inSeconds;
  final hours = total ~/ 3600;
  final minutes = (total % 3600) ~/ 60;
  final seconds = (total % 60).toString().padLeft(2, '0');
  if (hours > 0) {
    return '$hours:${minutes.toString().padLeft(2, '0')}:$seconds';
  }
  return '$minutes:$seconds';
}

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/ncs_client.dart';
import '../theme/nest_icons.dart';
import '../theme/nest_metrics.dart';
import '../theme/nest_type.dart';

/// The launcher's music page, driven by NCS-SMLauncher.
///
/// The shape is the one every streaming app on a phone has settled on — a feed
/// of square artwork, a section of "what comes next", and a player that stays
/// at the bottom of the screen so the music is never more than one tap away.
/// It is the shape YouTube Music uses; the colours and the type are the
/// launcher's own, and nothing here is Google's artwork or branding.
///
/// What this page is *not*: a player. It decodes nothing and owns no audio. It
/// draws what the other application reports and sends button presses back over
/// HTTP, so restarting the launcher does not stop the music — the reason a wall
/// panel is useful in the first place.
class NcsMusicPage extends StatefulWidget {
  const NcsMusicPage({
    super.key,
    required this.client,
    required this.metrics,
    required this.type,
    this.isCurrent = true,
    this.onBaseUrlChanged,
  });

  final NcsClient client;
  final NestMetrics metrics;
  final NestType type;

  /// Whether this page is the one on screen.
  ///
  /// The carousel keeps every page alive, so a page that fetches on a timer has
  /// to know whether anyone is looking at it.
  final bool isCurrent;

  /// Called when the user types a new address, so it can be remembered.
  final ValueChanged<String>? onBaseUrlChanged;

  @override
  State<NcsMusicPage> createState() => _NcsMusicPageState();
}

class _NcsMusicPageState extends State<NcsMusicPage> {
  /// The library, once the server has offered one.
  List<NcsTrack> _library = const [];

  bool _loadingLibrary = false;

  @override
  void initState() {
    super.initState();
    widget.client.addListener(_onClient);
    if (widget.isCurrent) {
      widget.client.start();
      if (widget.client.connected) unawaited(_loadLibrary());
    }
  }

  @override
  void didUpdateWidget(NcsMusicPage old) {
    super.didUpdateWidget(old);
    if (old.client != widget.client) {
      old.client.removeListener(_onClient);
      widget.client.addListener(_onClient);
    }
    if (widget.isCurrent && !old.isCurrent) widget.client.start();
    if (!widget.isCurrent && old.isCurrent) widget.client.stop();
  }

  @override
  void dispose() {
    widget.client.removeListener(_onClient);
    // The page is gone; nothing is watching the player any more. Without this
    // the two-second poll would keep running for the life of the process.
    widget.client.stop();
    super.dispose();
  }

  void _onClient() {
    if (!widget.isCurrent) return;
    if (widget.client.connected && _library.isEmpty && !_loadingLibrary) {
      unawaited(_loadLibrary());
    }
  }

  Future<void> _loadLibrary() async {
    _loadingLibrary = true;
    final tracks = await widget.client.browse();
    _loadingLibrary = false;
    if (!mounted || tracks.isEmpty) return;
    setState(() => _library = tracks);
  }

  /// What to show in the feed, preferring the real library and falling back to
  /// the queue the server sent with its state.
  ///
  /// A player that does not implement `/browse` still gets a full-looking page,
  /// because the queue is part of the state it already sends.
  List<NcsTrack> get _quickPicks {
    final seen = <String>{};
    return [
      for (final track in [..._library, ...?widget.client.snapshot?.queue])
        if (track.title.isNotEmpty &&
            seen.add(track.id.isEmpty ? track.title : track.id))
          track,
    ].take(24).toList();
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.metrics;
    final type = widget.type;

    return Material(
      color: _bg,
      child: SafeArea(
        child: ListenableBuilder(
          listenable: widget.client,
          builder: (context, _) {
            final client = widget.client;
            final snapshot = client.snapshot;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Header(
                  metrics: m,
                  type: type,
                  connected: client.connected,
                  serverName: snapshot?.serverName ?? '',
                  address: client.baseUrl,
                  onSettings: () => _editAddress(context),
                ),
                Expanded(
                  child: !client.configured
                      ? _ConnectCard(
                          metrics: m,
                          type: type,
                          error: '',
                          initial: '',
                          onSubmit: (value) => _connect(context, value),
                        )
                      : !client.connected
                      ? _ConnectCard(
                          metrics: m,
                          type: type,
                          error: client.error,
                          initial: client.baseUrl,
                          onSubmit: (value) => _connect(context, value),
                        )
                      : _Feed(
                          metrics: m,
                          type: type,
                          client: client,
                          snapshot: snapshot!,
                          quickPicks: _quickPicks,
                        ),
                ),
                if (snapshot?.current != null)
                  _MiniPlayer(
                    metrics: m,
                    type: type,
                    client: client,
                    snapshot: snapshot!,
                    onOpen: () => _openFullPlayer(context),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  Future<void> _connect(BuildContext context, String value) async {
    final next = value.trim();
    if (next.isEmpty) return;
    // Resolved before the await: the context may be gone by the time the
    // player answers, and a snack bar is not worth a lint suppression.
    final messenger = ScaffoldMessenger.maybeOf(context);
    widget.onBaseUrlChanged?.call(next);
    await widget.client.configure(next);
    await widget.client.refresh();
    widget.client.start();
    if (!mounted) return;
    if (!widget.client.connected) {
      messenger?.showSnackBar(
        SnackBar(
          content: Text(
            widget.client.error.isEmpty
                ? 'Could not reach the player'
                : widget.client.error,
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _editAddress(BuildContext context) async {
    final controller = TextEditingController(text: widget.client.baseUrl);
    final value = await showDialog<String>(
      context: context,
      builder: (dialog) => AlertDialog(
        backgroundColor: _surface,
        title: Text(
          'Player address',
          style: widget.type.sheetTitle(color: _onSurface),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.url,
          style: widget.type.body(color: _onSurface),
          decoration: InputDecoration(
            hintText: NcsClient.exampleAddress,
            hintStyle: widget.type.caption(color: _muted),
          ),
          onSubmitted: (v) => Navigator.of(dialog).pop(v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialog).pop(),
            child: Text('Cancel', style: widget.type.caption(color: _muted)),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialog).pop(controller.text),
            child: Text('Save', style: widget.type.caption(color: _onSurface)),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value == null || value.trim().isEmpty) return;
    widget.onBaseUrlChanged?.call(value.trim());
    await widget.client.configure(value.trim());
    await widget.client.refresh();
    if (mounted && widget.client.connected) widget.client.start();
  }

  void _openFullPlayer(BuildContext context) {
    final snapshot = widget.client.snapshot;
    if (snapshot?.current == null) return;
    Navigator.of(context).push(
      PageRouteBuilder<void>(
        opaque: true,
        transitionDuration: const Duration(milliseconds: 240),
        pageBuilder: (routeContext, animation, secondary) => _FullPlayer(
          metrics: widget.metrics,
          type: widget.type,
          client: widget.client,
        ),
        transitionsBuilder: (route, animation, secondary, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────── palette

const _bg = Color(0xFF030303);
const _surface = Color(0xFF1A1A1A);
const _onSurface = Colors.white;
const _muted = Color(0xFFAAAAAA);
const _hairline = Color(0xFF2A2A2A);

// ──────────────────────────────────────────────────────────────────── header

class _Header extends StatelessWidget {
  const _Header({
    required this.metrics,
    required this.type,
    required this.connected,
    required this.serverName,
    required this.address,
    required this.onSettings,
  });

  final NestMetrics metrics;
  final NestType type;
  final bool connected;
  final String serverName;
  final String address;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final m = metrics;
    return Padding(
      padding: EdgeInsets.fromLTRB(m.px(24), m.px(18), m.px(16), m.px(10)),
      child: Row(
        children: [
          Text(
            'Music',
            style: type
                .sheetTitle(color: _onSurface)
                .copyWith(fontSize: m.px(36), fontWeight: FontWeight.w600),
          ),
          const Spacer(),
          _ConnectionChip(
            metrics: m,
            type: type,
            connected: connected,
            label: connected
                ? (serverName.isEmpty ? 'Player' : serverName)
                : 'Not connected',
            address: address,
          ),
          SizedBox(width: m.px(4)),
          IconButton(
            onPressed: onSettings,
            icon: Icon(NestIcons.Settings, size: m.px(24), color: _muted),
            tooltip: 'Player address',
          ),
        ],
      ),
    );
  }
}

class _ConnectionChip extends StatelessWidget {
  const _ConnectionChip({
    required this.metrics,
    required this.type,
    required this.connected,
    required this.label,
    required this.address,
  });

  final NestMetrics metrics;
  final NestType type;
  final bool connected;
  final String label;
  final String address;

  @override
  Widget build(BuildContext context) {
    final m = metrics;
    return Tooltip(
      message: address.isEmpty ? 'No player configured' : address,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: m.px(12), vertical: m.px(7)),
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(m.px(20)),
          border: Border.all(color: _hairline),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _Dot(color: connected ? const Color(0xFF3DDC84) : _muted),
            SizedBox(width: m.px(8)),
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: metrics.px(220)),
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: type.caption(color: _onSurface),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A seven-pixel dot. Small enough to be a detail, which is the point: it says
/// "connected" without taking a line of the screen.
class _Dot extends StatelessWidget {
  const _Dot({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: 7,
    height: 7,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}

// ────────────────────────────────────────────────────────────────────── feed

class _Feed extends StatelessWidget {
  const _Feed({
    required this.metrics,
    required this.type,
    required this.client,
    required this.snapshot,
    required this.quickPicks,
  });

  final NestMetrics metrics;
  final NestType type;
  final NcsClient client;
  final NcsSnapshot snapshot;
  final List<NcsTrack> quickPicks;

  @override
  Widget build(BuildContext context) {
    final m = metrics;
    // The queue without whatever is playing right now: a list headed "Up next"
    // that starts with the track already playing is a lie.
    final upNext = [
      for (final track in snapshot.queue)
        if (track.title != snapshot.current?.title) track,
    ];

    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        if (quickPicks.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: _SectionHeader(metrics: m, type: type, title: 'Quick picks'),
          ),
          SliverPadding(
            padding: EdgeInsets.symmetric(horizontal: m.px(24)),
            sliver: SliverGrid(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: m.size.width >= m.px(900) ? 3 : 2,
                mainAxisSpacing: m.px(18),
                crossAxisSpacing: m.px(16),
                childAspectRatio: 0.78,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, i) => _AlbumCard(
                  metrics: m,
                  type: type,
                  track: quickPicks[i],
                  baseUrl: client.baseUrl,
                  playing:
                      snapshot.playing &&
                      snapshot.current?.title == quickPicks[i].title,
                  onTap: () => client.control('play', id: quickPicks[i].id),
                ),
                childCount: quickPicks.length,
              ),
            ),
          ),
        ],
        if (upNext.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: _SectionHeader(
              metrics: m,
              type: type,
              title: 'Up next',
              top: m.px(28),
            ),
          ),
          SliverPadding(
            padding: EdgeInsets.symmetric(horizontal: m.px(16)),
            sliver: SliverList.builder(
              itemCount: upNext.length,
              itemBuilder: (context, i) => _QueueRow(
                metrics: m,
                type: type,
                track: upNext[i],
                index: i + 1,
                baseUrl: client.baseUrl,
                onTap: () => client.control('play', id: upNext[i].id),
              ),
            ),
          ),
        ],
        // Room for the player and the system gesture bar, so the last row can
        // still be scrolled clear of both.
        SliverToBoxAdapter(
          child: SizedBox(height: m.px(snapshot.current == null ? 24 : 104)),
        ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.metrics,
    required this.type,
    required this.title,
    this.top = 0,
  });

  final NestMetrics metrics;
  final NestType type;
  final String title;
  final double top;

  @override
  Widget build(BuildContext context) {
    final m = metrics;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        m.px(24),
        m.px(14) + top,
        m.px(24),
        m.px(12),
      ),
      child: Text(
        title,
        style: type
            .sheetTitle(color: _onSurface)
            .copyWith(fontSize: m.px(26), fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _AlbumCard extends StatelessWidget {
  const _AlbumCard({
    required this.metrics,
    required this.type,
    required this.track,
    required this.baseUrl,
    required this.playing,
    required this.onTap,
  });

  final NestMetrics metrics;
  final NestType type;
  final NcsTrack track;
  final String baseUrl;
  final bool playing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final m = metrics;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(m.px(10)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 1,
            child: Stack(
              fit: StackFit.expand,
              children: [
                _Artwork(
                  track: track,
                  baseUrl: baseUrl,
                  metrics: m,
                  radius: m.px(8),
                ),
                if (playing)
                  Positioned(
                    right: m.px(8),
                    bottom: m.px(8),
                    child: Container(
                      padding: EdgeInsets.all(m.px(6)),
                      decoration: const BoxDecoration(
                        color: Colors.black54,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        NestIcons.GraphicEq,
                        size: m.px(16),
                        color: _onSurface,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          SizedBox(height: m.px(8)),
          Text(
            track.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: type.body(color: _onSurface),
          ),
          SizedBox(height: m.px(2)),
          Text(
            track.artist.isEmpty ? track.album : track.artist,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: type.caption(color: _muted),
          ),
        ],
      ),
    );
  }
}

class _QueueRow extends StatelessWidget {
  const _QueueRow({
    required this.metrics,
    required this.type,
    required this.track,
    required this.index,
    required this.baseUrl,
    required this.onTap,
  });

  final NestMetrics metrics;
  final NestType type;
  final NcsTrack track;
  final int index;
  final String baseUrl;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final m = metrics;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(m.px(8)),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: m.px(8), vertical: m.px(8)),
        child: Row(
          children: [
            _Artwork(
              track: track,
              baseUrl: baseUrl,
              metrics: m,
              radius: m.px(6),
              size: m.px(52),
            ),
            SizedBox(width: m.px(14)),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    track.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: type.body(color: _onSurface),
                  ),
                  SizedBox(height: m.px(2)),
                  Text(
                    track.artist.isEmpty ? track.album : track.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: type.caption(color: _muted),
                  ),
                ],
              ),
            ),
            if (track.duration > Duration.zero) ...[
              SizedBox(width: m.px(10)),
              Text(
                formatDuration(track.duration),
                style: type.caption(color: _muted),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Square artwork, or a deterministic gradient when there is none.
///
/// The gradient is derived from the title, so the same track is always the same
/// colour — a placeholder that changes every rebuild looks like a bug.
class _Artwork extends StatelessWidget {
  const _Artwork({
    required this.track,
    required this.baseUrl,
    required this.metrics,
    required this.radius,
    this.size,
  });

  final NcsTrack track;
  final String baseUrl;
  final NestMetrics metrics;
  final double radius;
  final double? size;

  @override
  Widget build(BuildContext context) {
    final url = track.artworkUrl(baseUrl);
    final fallback = _GradientTile(
      seed: track.title,
      iconSize: (size ?? metrics.px(140)) * 0.28,
    );
    final child = ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: url == null
          ? fallback
          : Image.network(
              url,
              fit: BoxFit.cover,
              // A server that promises artwork and cannot deliver it is a
              // gradient, not a broken image icon.
              errorBuilder: (context, error, stack) => fallback,
              loadingBuilder: (context, child, progress) =>
                  progress == null ? child : fallback,
            ),
    );
    return size == null
        ? child
        : SizedBox(width: size, height: size, child: child);
  }
}

class _GradientTile extends StatelessWidget {
  const _GradientTile({required this.seed, required this.iconSize});

  final String seed;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final hue = (seed.hashCode.abs() % 360).toDouble();
    final start = HSLColor.fromAHSL(1, hue, 0.45, 0.32).toColor();
    final end = HSLColor.fromAHSL(1, (hue + 40) % 360, 0.5, 0.16).toColor();
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [start, end],
        ),
      ),
      child: Center(
        child: Icon(NestIcons.MusicNote, size: iconSize, color: Colors.white24),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────── mini player

class _MiniPlayer extends StatelessWidget {
  const _MiniPlayer({
    required this.metrics,
    required this.type,
    required this.client,
    required this.snapshot,
    required this.onOpen,
  });

  final NestMetrics metrics;
  final NestType type;
  final NcsClient client;
  final NcsSnapshot snapshot;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final m = metrics;
    final track = snapshot.current!;
    return Container(
      decoration: const BoxDecoration(
        color: _surface,
        border: Border(top: BorderSide(color: _hairline)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _LiveProgress(
            snapshot: snapshot,
            color: _onSurface,
            height: 2,
            onSeek: (position) => client.control(
              'seek',
              value: position.inMilliseconds.toDouble(),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              m.px(14),
              m.px(10),
              m.px(10),
              m.px(10),
            ),
            child: Row(
              children: [
                _Artwork(
                  track: track,
                  baseUrl: client.baseUrl,
                  metrics: m,
                  radius: m.px(4),
                  size: m.px(46),
                ),
                SizedBox(width: m.px(12)),
                Expanded(
                  child: InkWell(
                    onTap: onOpen,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          track.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: type.body(color: _onSurface),
                        ),
                        Text(
                          track.artist.isEmpty ? track.album : track.artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: type.caption(color: _muted),
                        ),
                      ],
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () =>
                      client.control(snapshot.playing ? 'pause' : 'play'),
                  icon: Icon(
                    snapshot.playing ? NestIcons.Pause : NestIcons.PlayArrow,
                    size: m.px(30),
                    color: _onSurface,
                  ),
                ),
                IconButton(
                  onPressed: () => client.control('next'),
                  icon: Icon(
                    NestIcons.SkipNext,
                    size: m.px(30),
                    color: _onSurface,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A progress line that moves between polls.
///
/// The snapshot's position is a photograph taken when the poll landed. Without
/// interpolating from it the bar would sit still for two seconds and then jump,
/// which reads as a broken connection rather than as a progress bar.
class _LiveProgress extends StatefulWidget {
  const _LiveProgress({
    required this.snapshot,
    required this.color,
    required this.height,
    this.onSeek,
  });

  final NcsSnapshot snapshot;
  final Color color;
  final double height;
  final ValueChanged<Duration>? onSeek;

  @override
  State<_LiveProgress> createState() => _LiveProgressState();
}

class _LiveProgressState extends State<_LiveProgress> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(_LiveProgress old) {
    super.didUpdateWidget(old);
    _sync();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  /// Ticks only while something is playing. A paused track does not need a
  /// repaint twice a second.
  void _sync() {
    if (widget.snapshot.playing && _ticker == null) {
      _ticker = Timer.periodic(const Duration(milliseconds: 500), (_) {
        if (mounted) setState(() {});
      });
    } else if (!widget.snapshot.playing) {
      _ticker?.cancel();
      _ticker = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = widget.snapshot;
    final total = snapshot.duration.inMilliseconds;
    final position = snapshot.positionAt(DateTime.now()).inMilliseconds;
    final fraction = total <= 0 ? 0.0 : (position / total).clamp(0.0, 1.0);

    final bar = Stack(
      children: [
        Container(height: widget.height, color: _hairline),
        FractionallySizedBox(
          widthFactor: fraction,
          child: Container(height: widget.height, color: widget.color),
        ),
      ],
    );

    final onSeek = widget.onSeek;
    if (onSeek == null) return bar;

    // Tapping a thin line is unpleasant; the tap target is the line plus
    // sixteen pixels above and below it.
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (details) {
        if (total <= 0) return;
        final box = context.findRenderObject() as RenderBox?;
        if (box == null || !box.hasSize) return;
        final x = details.localPosition.dx.clamp(0.0, box.size.width);
        onSeek(Duration(milliseconds: (total * (x / box.size.width)).round()));
      },
      child: SizedBox(
        height: widget.height + 16,
        child: Center(child: bar),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────── full player

class _FullPlayer extends StatelessWidget {
  const _FullPlayer({
    required this.metrics,
    required this.type,
    required this.client,
  });

  final NestMetrics metrics;
  final NestType type;
  final NcsClient client;

  @override
  Widget build(BuildContext context) {
    final m = metrics;
    return Scaffold(
      backgroundColor: _bg,
      body: ListenableBuilder(
        listenable: client,
        builder: (context, _) {
          final snapshot = client.snapshot;
          final track = snapshot?.current;
          if (snapshot == null || track == null) {
            return const Center(
              child: Text('Nothing playing', style: TextStyle(color: _muted)),
            );
          }
          // As large as the screen allows: on a wall panel the cover is the
          // point, and a 360 px square floating in the top third of a 1340 px
          // screen looks like a phone app that gave up.
          final art = math.max(
            m.px(160),
            math.min(m.size.width - m.px(96), m.size.height * 0.42),
          );

          // A tint behind the cover, the way the real player does it. Derived
          // from the title, so it is stable, and only when there is no cover:
          // a real photograph's colour is not something a hash can guess, and
          // a guessed tint under a real cover looks wrong rather than rich.
          final hue = (track.title.hashCode.abs() % 360).toDouble();
          final background = track.artworkUrl(client.baseUrl) != null
              ? _bg
              : HSLColor.fromAHSL(1, hue, 0.35, 0.10).toColor();

          return DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.center,
                colors: [background, _bg],
              ),
            ),
            child: SafeArea(
              child: Column(
                children: [
                  _FullPlayerBar(
                    metrics: m,
                    type: type,
                    subtitle: snapshot.serverName.isEmpty
                        ? 'Playing from your player'
                        : 'Playing from ${snapshot.serverName}',
                  ),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) => SingleChildScrollView(
                        padding: EdgeInsets.symmetric(horizontal: m.px(48)),
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            minHeight: constraints.maxHeight,
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              SizedBox(height: m.px(10)),
                              SizedBox(
                                width: art,
                                height: art,
                                child: _Artwork(
                                  track: track,
                                  baseUrl: client.baseUrl,
                                  metrics: m,
                                  radius: m.px(12),
                                ),
                              ),
                              SizedBox(height: m.px(24)),
                              // Everything under the cover is as wide as the cover
                              // and sits directly under it, rather than stretching to
                              // the screen edges while the cover floats in the
                              // middle. That misalignment is the difference between a
                              // player and a page with a picture on it.
                              SizedBox(
                                width: art,
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Text(
                                      track.title,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: type
                                          .sheetTitle(color: _onSurface)
                                          .copyWith(
                                            fontSize: m.px(30),
                                            fontWeight: FontWeight.w600,
                                          ),
                                    ),
                                    SizedBox(height: m.px(4)),
                                    Text(
                                      track.artist.isEmpty
                                          ? track.album
                                          : track.artist,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: type.body(color: _muted),
                                    ),
                                    SizedBox(height: m.px(18)),
                                    _ProgressRow(
                                      metrics: m,
                                      type: type,
                                      snapshot: snapshot,
                                      onSeek: (position) => client.control(
                                        'seek',
                                        value: position.inMilliseconds
                                            .toDouble(),
                                      ),
                                    ),
                                    SizedBox(height: m.px(10)),
                                    _Transport(
                                      metrics: m,
                                      client: client,
                                      snapshot: snapshot,
                                    ),
                                    SizedBox(height: m.px(24)),
                                    _VolumeRow(
                                      metrics: m,
                                      type: type,
                                      client: client,
                                      volume: snapshot.volume,
                                    ),
                                  ],
                                ),
                              ),
                              SizedBox(height: m.px(24)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _FullPlayerBar extends StatelessWidget {
  const _FullPlayerBar({
    required this.metrics,
    required this.type,
    required this.subtitle,
  });

  final NestMetrics metrics;
  final NestType type;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final m = metrics;
    return Padding(
      padding: EdgeInsets.fromLTRB(m.px(8), m.px(8), m.px(16), m.px(4)),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).maybePop(),
            icon: Icon(NestIcons.ArrowBack, size: m.px(26), color: _onSurface),
            tooltip: 'Back',
          ),
          const Spacer(),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'NOW PLAYING',
                style: type
                    .caption(color: _muted)
                    .copyWith(letterSpacing: m.px(1.6)),
              ),
              SizedBox(height: m.px(2)),
              Text(subtitle, style: type.caption(color: _onSurface)),
            ],
          ),
          const Spacer(),
          IconButton(
            onPressed: () {},
            icon: Icon(NestIcons.MoreVert, size: m.px(24), color: _muted),
          ),
        ],
      ),
    );
  }
}

class _ProgressRow extends StatelessWidget {
  const _ProgressRow({
    required this.metrics,
    required this.type,
    required this.snapshot,
    required this.onSeek,
  });

  final NestMetrics metrics;
  final NestType type;
  final NcsSnapshot snapshot;
  final ValueChanged<Duration> onSeek;

  @override
  Widget build(BuildContext context) {
    final m = metrics;
    return Column(
      children: [
        _LiveProgress(
          snapshot: snapshot,
          color: _onSurface,
          height: 3,
          onSeek: onSeek,
        ),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: m.px(2)),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _TickingTime(
                snapshot: snapshot,
                style: type.caption(color: _muted),
              ),
              Text(
                formatDuration(snapshot.duration),
                style: type.caption(color: _muted),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The elapsed time, which has to tick between polls like the bar does.
class _TickingTime extends StatefulWidget {
  const _TickingTime({required this.snapshot, required this.style});
  final NcsSnapshot snapshot;
  final TextStyle style;

  @override
  State<_TickingTime> createState() => _TickingTimeState();
}

class _TickingTimeState extends State<_TickingTime> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(_TickingTime old) {
    super.didUpdateWidget(old);
    _sync();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _sync() {
    if (widget.snapshot.playing && _timer == null) {
      _timer = Timer.periodic(const Duration(milliseconds: 500), (_) {
        if (mounted) setState(() {});
      });
    } else if (!widget.snapshot.playing) {
      _timer?.cancel();
      _timer = null;
    }
  }

  @override
  Widget build(BuildContext context) => Text(
    formatDuration(widget.snapshot.positionAt(DateTime.now())),
    style: widget.style,
  );
}

class _Transport extends StatelessWidget {
  const _Transport({
    required this.metrics,
    required this.client,
    required this.snapshot,
  });

  final NestMetrics metrics;
  final NcsClient client;
  final NcsSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final m = metrics;
    // Only the controls whose effect the snapshot can confirm: play and pause
    // move `playing`, next and previous move the track, seek moves the
    // position, volume comes back as a value. Shuffle and repeat are
    // deliberately absent — the protocol carries no state for them, so a
    // toggle could not show whether it was on, and a button that gives no
    // feedback is the four-dead-buttons mistake with better icons. They go
    // back in when /state can say what they are doing.
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        IconButton(
          onPressed: () => client.control('previous'),
          icon: Icon(NestIcons.SkipPrevious, size: m.px(38), color: _onSurface),
          tooltip: 'Previous',
        ),
        _PlayButton(
          metrics: m,
          playing: snapshot.playing,
          onTap: () => client.control(snapshot.playing ? 'pause' : 'play'),
        ),
        IconButton(
          onPressed: () => client.control('next'),
          icon: Icon(NestIcons.SkipNext, size: m.px(38), color: _onSurface),
          tooltip: 'Next',
        ),
      ],
    );
  }
}

class _PlayButton extends StatelessWidget {
  const _PlayButton({
    required this.metrics,
    required this.playing,
    required this.onTap,
  });

  final NestMetrics metrics;
  final bool playing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final m = metrics;
    return Material(
      color: _onSurface,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: m.px(68),
          height: m.px(68),
          child: Icon(
            playing ? NestIcons.Pause : NestIcons.PlayArrow,
            size: m.px(34),
            color: Colors.black,
          ),
        ),
      ),
    );
  }
}

class _VolumeRow extends StatelessWidget {
  const _VolumeRow({
    required this.metrics,
    required this.type,
    required this.client,
    required this.volume,
  });

  final NestMetrics metrics;
  final NestType type;
  final NcsClient client;
  final double volume;

  @override
  Widget build(BuildContext context) {
    final m = metrics;
    return Row(
      children: [
        Icon(NestIcons.VolumeUp, size: m.px(20), color: _muted),
        SizedBox(width: m.px(10)),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: m.px(2),
              thumbShape: RoundSliderThumbShape(enabledThumbRadius: m.px(6)),
              overlayShape: RoundSliderOverlayShape(overlayRadius: m.px(14)),
              activeTrackColor: _onSurface,
              inactiveTrackColor: _hairline,
              thumbColor: _onSurface,
            ),
            child: Slider(
              value: volume.clamp(0.0, 1.0),
              onChanged: (value) => client.control('volume', value: value),
            ),
          ),
        ),
        SizedBox(width: m.px(4)),
        Text('${(volume * 100).round()}%', style: type.caption(color: _muted)),
      ],
    );
  }
}

// ────────────────────────────────────────────────────────────────── connect

class _ConnectCard extends StatefulWidget {
  const _ConnectCard({
    required this.metrics,
    required this.type,
    required this.error,
    required this.initial,
    required this.onSubmit,
  });

  final NestMetrics metrics;
  final NestType type;
  final String error;
  final String initial;
  final ValueChanged<String> onSubmit;

  @override
  State<_ConnectCard> createState() => _ConnectCardState();
}

class _ConnectCardState extends State<_ConnectCard> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initial,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.metrics;
    final type = widget.type;
    return Center(
      child: SingleChildScrollView(
        padding: EdgeInsets.all(m.px(32)),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: m.px(520)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(NestIcons.Headphones, size: m.px(52), color: _muted),
              SizedBox(height: m.px(14)),
              Text(
                'Connect NCS-SMLauncher',
                textAlign: TextAlign.center,
                style: type
                    .sheetTitle(color: _onSurface)
                    .copyWith(fontSize: m.px(28), fontWeight: FontWeight.w600),
              ),
              SizedBox(height: m.px(8)),
              Text(
                'Your music player does the playing; this screen is the remote. '
                'Enter the address it is listening on.',
                textAlign: TextAlign.center,
                style: type.caption(color: _muted),
              ),
              SizedBox(height: m.px(20)),
              TextField(
                controller: _controller,
                keyboardType: TextInputType.url,
                autocorrect: false,
                style: type.body(color: _onSurface),
                onSubmitted: widget.onSubmit,
                decoration: InputDecoration(
                  hintText: NcsClient.exampleAddress,
                  hintStyle: type.caption(color: _muted),
                  filled: true,
                  fillColor: _surface,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(m.px(10)),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              if (widget.error.isNotEmpty) ...[
                SizedBox(height: m.px(10)),
                Text(
                  widget.error,
                  textAlign: TextAlign.center,
                  style: type.caption(color: const Color(0xFFFF8A80)),
                ),
              ],
              SizedBox(height: m.px(16)),
              FilledButton(
                onPressed: () => widget.onSubmit(_controller.text),
                style: FilledButton.styleFrom(
                  backgroundColor: _onSurface,
                  foregroundColor: Colors.black,
                  padding: EdgeInsets.symmetric(vertical: m.px(14)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(m.px(24)),
                  ),
                ),
                child: Text('Connect', style: type.body(color: Colors.black)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────── helpers

/// `3:07`, or `1:02:07` for anything over an hour.
String formatDuration(Duration duration) {
  if (duration <= Duration.zero) return '0:00';
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60);
  final seconds = duration.inSeconds.remainder(60);
  final two = seconds.toString().padLeft(2, '0');
  if (hours > 0) {
    return '$hours:${minutes.toString().padLeft(2, '0')}:$two';
  }
  return '$minutes:$two';
}

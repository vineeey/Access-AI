import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/glass.dart';
import '../core/motion.dart';
import '../core/tokens.dart';
import '../core/ui.dart';
import '../state/providers.dart';
import '../widgets/mjpeg_view.dart';

/// Live view — the doorbell camera's MJPEG feed from GET /video. [MjpegView]
/// (our own lightweight decoder) handles the multipart stream; a changing [Key]
/// forces a fresh connection when the user taps Reconnect (or when the server
/// URL changes). A friendly panel is shown while loading or on error rather than
/// a blank frame.
class LiveScreen extends ConsumerStatefulWidget {
  const LiveScreen({super.key});

  @override
  ConsumerState<LiveScreen> createState() => _LiveScreenState();
}

class _LiveScreenState extends ConsumerState<LiveScreen> {
  int _reconnectNonce = 0;

  void _reconnect() => setState(() => _reconnectNonce++);

  @override
  Widget build(BuildContext context) {
    final api = ref.watch(apiProvider);
    final url = api.videoUrl;
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('Live view'),
        actions: [
          IconButton(
            onPressed: _reconnect,
            icon: const Icon(Icons.refresh),
            tooltip: 'Reconnect the camera',
          ),
        ],
      ),
      body: MeshScaffoldBody(
        child: SafeArea(
          bottom: false,
          child: Padding(
            // 120 bottom clears the floating glass nav pill (extendBody).
            padding: const EdgeInsets.fromLTRB(T.s16, T.s16, T.s16, 120),
            child: Column(
              children: [
                Expanded(
                  child: Entrance(
                    index: 0,
                    child: Stack(
                      children: [
                        // Specular hairline frame around the video glass.
                        Positioned.fill(
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(T.rLg),
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  Colors.white.withValues(alpha: 0.22),
                                  Colors.white.withValues(alpha: 0.04),
                                  T.jarvis2.withValues(alpha: 0.16),
                                ],
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.5),
                                  blurRadius: 40,
                                  offset: const Offset(0, 18),
                                ),
                              ],
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(1.2),
                              child: ClipRRect(
                                borderRadius:
                                    BorderRadius.circular(T.rLg - 1.2),
                                child: Container(
                                  color: const Color(0xFF060B16),
                                  width: double.infinity,
                                  child: Semantics(
                                    label: 'Live camera feed from the door',
                                    image: true,
                                    // Key ties the stream to the URL + reconnect
                                    // counter so a change tears down and rebuilds
                                    // the connection cleanly.
                                    child: MjpegView(
                                      key: ValueKey('$url#$_reconnectNonce'),
                                      stream: url,
                                      fit: BoxFit.contain,
                                      timeout: const Duration(seconds: 8),
                                      loadingBuilder: (context) =>
                                          const _LoadingPanel(),
                                      errorBuilder: (context, error) =>
                                          _ErrorPanel(
                                        message:
                                            'Camera stream unavailable.\nMake '
                                            'sure the server is running and '
                                            'reachable, then Reconnect.',
                                        onRetry: _reconnect,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const Positioned(
                          top: T.s12,
                          left: T.s12,
                          child: _LiveBadge(),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: T.s12),
                Entrance(
                  index: 1,
                  child: GlassCard(
                    padding: const EdgeInsets.symmetric(
                        horizontal: T.s16, vertical: T.s8),
                    radius: T.rSm,
                    child: Row(
                      children: [
                        Icon(Icons.info_outline,
                            size: 18,
                            color: cs.onSurface.withValues(alpha: 0.6)),
                        const SizedBox(width: T.s8),
                        Expanded(
                          child: Text(
                            'Streaming from $url',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(
                                    color:
                                        cs.onSurface.withValues(alpha: 0.6)),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        TextButton.icon(
                          onPressed: () {
                            _reconnect();
                            showSnack(context, 'Reconnecting…');
                          },
                          icon: const Icon(Icons.refresh),
                          label: const Text('Reconnect'),
                        ),
                      ],
                    ),
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

/// Small "LIVE" pill floating over the video with a breathing red dot.
class _LiveBadge extends StatefulWidget {
  const _LiveBadge();

  @override
  State<_LiveBadge> createState() => _LiveBadgeState();
}

class _LiveBadgeState extends State<_LiveBadge>
    with SingleTickerProviderStateMixin {
  AnimationController? _c;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (context.reduceMotion) {
      _c?.stop();
    } else {
      _c ??= AnimationController(vsync: this, duration: T.xslow)
        ..repeat(reverse: true);
      if (!_c!.isAnimating) _c!.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final dot = _c == null
        ? _dot(1.0)
        : AnimatedBuilder(
            animation: _c!,
            builder: (_, _) => _dot(0.55 + 0.45 * _c!.value),
          );
    return Semantics(
      label: 'Live stream indicator',
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: T.s12, vertical: T.s6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(T.rPill),
          color: Colors.black.withValues(alpha: 0.45),
          border:
              Border.all(color: T.danger.withValues(alpha: 0.5), width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            dot,
            const SizedBox(width: T.s8),
            Text(
              'LIVE',
              style: text.labelSmall?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.6,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dot(double opacity) => Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: T.danger.withValues(alpha: opacity),
          boxShadow: [
            BoxShadow(
              color: T.danger.withValues(alpha: 0.6 * opacity),
              blurRadius: 8,
            ),
          ],
        ),
      );
}

class _LoadingPanel extends StatelessWidget {
  const _LoadingPanel();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: T.s12),
          Text('Connecting to the camera…',
              style: TextStyle(color: Colors.white70)),
        ],
      ),
    );
  }
}

class _ErrorPanel extends StatelessWidget {
  const _ErrorPanel({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(T.s24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: T.danger.withValues(alpha: 0.12),
                border: Border.all(
                    color: T.danger.withValues(alpha: 0.35), width: 1.5),
              ),
              child: const Icon(Icons.videocam_off,
                  color: Colors.white70, size: 40),
            ),
            const SizedBox(height: T.s16),
            Text(message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70)),
            const SizedBox(height: T.s16),
            SizedBox(
              height: T.minTouch,
              child: FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Reconnect'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

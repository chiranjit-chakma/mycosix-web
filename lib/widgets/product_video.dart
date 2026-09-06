import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../config/mx_colors.dart';
import '../config/mx_type.dart';
import '../models/product.dart';

/// Normalises an optional product video link: trims it and only keeps it when
/// it is a real http(s) web URL. Blank/garbage values are treated as "no
/// video", so the UI hides the video control when there is nothing playable.
String? cleanProductVideo(String? videoUrl) {
  final v = videoUrl?.trim() ?? '';
  if (v.isEmpty) return null;
  final uri = Uri.tryParse(v);
  if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
    return null;
  }
  return uri.toString();
}

/// True when [videoUrl] is a playable web link.
bool hasProductVideo(String? videoUrl) => cleanProductVideo(videoUrl) != null;

/// "Watch product video" button that appears ONLY when the product carries a
/// playable video link, and otherwise renders nothing (hidden when none).
class ProductVideoButton extends StatelessWidget {
  const ProductVideoButton({super.key, required this.product});

  final Product product;

  @override
  Widget build(BuildContext context) {
    final url = cleanProductVideo(product.videoUrl);
    if (url == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 22),
      child: Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          onPressed: () => showDialog<void>(
            context: context,
            builder: (_) => ProductVideoDialog(url: url),
          ),
          icon: const Icon(Icons.play_circle_outline_rounded, size: 20),
          label: const Text('Watch product video'),
        ),
      ),
    );
  }
}

/// Full-screen dialog that plays a product's video. The video is loaded but
/// never auto-plays (no autoplay); the customer presses play. Controls are
/// provided, and the dialog is fully dismissible.
class ProductVideoDialog extends StatefulWidget {
  const ProductVideoDialog({super.key, required this.url});

  final String url;

  @override
  State<ProductVideoDialog> createState() => _ProductVideoDialogState();
}

class _ProductVideoDialogState extends State<ProductVideoDialog> {
  VideoPlayerController? _controller;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    _controller!.initialize().then((_) {
      if (mounted) setState(() {});
    }).catchError((Object _) {
      if (mounted) setState(() => _failed = true);
    });
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  void _togglePlay() {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    setState(() => c.value.isPlaying ? c.pause() : c.play());
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context).size;
    final c = _controller;
    final init = c != null && c.value.isInitialized && !_failed;

    return Dialog(
      insetPadding: const EdgeInsets.all(20),
      backgroundColor: MxColors.forest,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 820,
          maxHeight: mq.height - 40,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 8, 6),
              child: Row(
                children: [
                  const Icon(
                    Icons.play_circle_fill_rounded,
                    size: 18,
                    color: MxColors.mossSoft,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Product video',
                    style: MxType.bodySm(
                      color: Colors.white,
                      weight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Close video',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded, color: Colors.white),
                  ),
                ],
              ),
            ),
            Flexible(
              child: _failed
                  ? _Message(
                      icon: Icons.error_outline_rounded,
                      label: 'The video could not be loaded.',
                    )
                  : !init
                      ? const SizedBox(
                          height: 360,
                          child: Center(
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: MxColors.mossSoft,
                            ),
                          ),
                        )
                      : GestureDetector(
                          onTap: _togglePlay,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              AspectRatio(
                                aspectRatio: c.value.aspectRatio,
                                child: VideoPlayer(c),
                              ),
                              if (!c.value.isPlaying)
                                Container(
                                  width: 64,
                                  height: 64,
                                  decoration: BoxDecoration(
                                    color: MxColors.forest.withValues(
                                      alpha: 0.55,
                                    ),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.play_arrow_rounded,
                                    size: 36,
                                    color: Colors.white,
                                  ),
                                ),
                            ],
                          ),
                        ),
            ),
            if (init) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
                child: ValueListenableBuilder<VideoPlayerValue>(
                  valueListenable: c,
                  builder: (context, value, _) {
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            IconButton(
                              tooltip: value.isPlaying ? 'Pause' : 'Play',
                              onPressed: _togglePlay,
                              icon: Icon(
                                value.isPlaying
                                    ? Icons.pause_rounded
                                    : Icons.play_arrow_rounded,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              _clock(value.position),
                              style: MxType.bodyXs(color: Colors.white70),
                            ),
                            Expanded(
                              child: VideoProgressIndicator(
                                c,
                                allowScrubbing: true,
                                padding: const EdgeInsets.only(
                                  left: 12,
                                  right: 12,
                                ),
                                colors: const VideoProgressColors(
                                  playedColor: MxColors.mossSoft,
                                  bufferedColor: Colors.white24,
                                  backgroundColor: Colors.white12,
                                ),
                              ),
                            ),
                            Text(
                              _clock(value.duration),
                              style: MxType.bodyXs(color: Colors.white70),
                            ),
                          ],
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static String _clock(Duration d) {
    String two(int v) => v.toString().padLeft(2, '0');
    final m = two(d.inMinutes.remainder(60));
    final s = two(d.inSeconds.remainder(60));
    return '$m:$s';
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 180,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: MxColors.stoneLight, size: 30),
            const SizedBox(height: 10),
            Text(label, style: MxType.bodySm(color: Colors.white70)),
          ],
        ),
      ),
    );
  }
}

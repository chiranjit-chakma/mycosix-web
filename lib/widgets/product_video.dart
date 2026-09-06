import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../config/mx_colors.dart';
import '../config/mx_type.dart';
import '../models/product.dart';
import 'youtube_embed_view.dart';

/// How a product's video link is played.
enum ProductVideoKind {
  /// A direct media-file web link (.mp4/.webm) played by the in-app player.
  direct,

  /// A YouTube link, embedded as a privacy-friendly youtube-nocookie iframe
  /// with YouTube's own controls.
  youtube,
}

/// A resolved, playable video reference for a product's [Product.videoUrl].
class ProductVideoRef {
  const ProductVideoRef({required this.kind, required this.url});

  /// [kind] says which player to use, and [url] is the concrete playable
  /// address: the media-file link for [ProductVideoKind.direct], or the
  /// youtube-nocookie embed address for [ProductVideoKind.youtube].
  final ProductVideoKind kind;
  final String url;

  bool get isYoutube => kind == ProductVideoKind.youtube;
}

final RegExp _youtubeIdPattern = RegExp(r'^[A-Za-z0-9_-]{11}$');

/// Resolves an optional product video link to something playable.
///
/// Trims it and accepts only real http(s) web links. A YouTube watch / shorts /
/// youtu.be / embed link becomes its embed reference; any other http(s) link
/// is treated as a direct media-file link. Blank, non-web, local or garbage
/// values are treated as "no video", so the UI hides the video control when
/// there is nothing playable.
ProductVideoRef? resolveProductVideo(String? videoUrl) {
  final v = videoUrl?.trim() ?? '';
  if (v.isEmpty) return null;
  final uri = Uri.tryParse(v);
  if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
    return null;
  }
  final host = uri.host.toLowerCase();
  final isYouTubeHost = host == 'youtu.be' ||
      host == 'youtube.com' ||
      host.endsWith('.youtube.com');
  if (isYouTubeHost) {
    final id = _youtubeVideoId(uri);
    if (id == null) return null; // a YouTube page without a real video id
    return ProductVideoRef(
      kind: ProductVideoKind.youtube,
      url: 'https://www.youtube-nocookie.com/embed/$id?playsinline=1&rel=0',
    );
  }
  return ProductVideoRef(kind: ProductVideoKind.direct, url: uri.toString());
}

/// True when [videoUrl] carries a playable web video.
bool hasProductVideo(String? videoUrl) =>
    resolveProductVideo(videoUrl) != null;

/// Validation message for the admin "Video link (optional)" field: empty is
/// fine (no video), anything else must resolve to a playable web link.
String? videoLinkFieldError(String? value) {
  final t = value?.trim() ?? '';
  if (t.isEmpty) return null;
  return resolveProductVideo(t) == null
      ? 'Paste a YouTube link or a direct .mp4/.webm web link.'
      : null;
}

String? _validId(String? raw) =>
    (raw != null && _youtubeIdPattern.hasMatch(raw)) ? raw : null;

/// Pulls an 11-character YouTube video id out of the supported URL shapes.
String? _youtubeVideoId(Uri uri) {
  final host = uri.host.toLowerCase();
  final segs = uri.pathSegments;
  if (host == 'youtu.be') {
    return segs.isEmpty ? null : _validId(segs.first);
  }
  if (segs.isNotEmpty && segs.first == 'watch') {
    return _validId(uri.queryParameters['v']);
  }
  const shortHosts = {'shorts', 'embed', 'live', 'v'};
  if (segs.isNotEmpty &&
      shortHosts.contains(segs.first) &&
      segs.length > 1) {
    return _validId(segs[1]);
  }
  return null;
}

/// "Watch product video" button that appears ONLY when the product carries a
/// playable video link (a direct .mp4/.webm link or a YouTube link), and
/// otherwise renders nothing (hidden when none).
class ProductVideoButton extends StatelessWidget {
  const ProductVideoButton({super.key, required this.product});

  final Product product;

  @override
  Widget build(BuildContext context) {
    final ref = resolveProductVideo(product.videoUrl);
    if (ref == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 22),
      child: Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          onPressed: () => showDialog<void>(
            context: context,
            builder: (_) => ProductVideoDialog(ref: ref),
          ),
          icon: const Icon(Icons.play_circle_outline_rounded, size: 20),
          label: const Text('Watch product video'),
        ),
      ),
    );
  }
}

/// Full-screen dialog that plays a product's video. A direct media file is
/// loaded into the in-app player; a YouTube link is embedded. Nothing
/// auto-plays (no autoplay); the customer presses play. Controls are provided
/// (in-app for direct files, YouTube's own for embeds), and the dialog is
/// fully dismissible.
class ProductVideoDialog extends StatefulWidget {
  const ProductVideoDialog({super.key, required this.ref});

  final ProductVideoRef ref;

  @override
  State<ProductVideoDialog> createState() => _ProductVideoDialogState();
}

class _ProductVideoDialogState extends State<ProductVideoDialog> {
  VideoPlayerController? _controller;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    if (widget.ref.isYoutube) return; // embeds carry their own player
    _controller =
        VideoPlayerController.networkUrl(Uri.parse(widget.ref.url));
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
    final isYoutube = widget.ref.isYoutube;
    final c = _controller;
    final init =
        !isYoutube && c != null && c.value.isInitialized && !_failed;

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
            if (isYoutube)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 2, 14, 14),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: AspectRatio(
                    aspectRatio: 16 / 9,
                    child: YoutubeEmbedView(
                      embedUrl: widget.ref.url,
                    ),
                  ),
                ),
              )
            else
              Flexible(
                child: _failed
                    ? const _Message(
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

import 'dart:ui_web' as ui_web;

import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

/// Real web YouTube player: a full-size <iframe> of the privacy-friendly
/// youtube-nocookie embed for one product's video. Each instance registers its
/// own platform-view type so the iframe always points at exactly this video,
/// regardless of how many products are shown over a session.
///
/// The embed carries YouTube's own controls and does NOT autoplay; the
/// customer presses play. Imported only when compiling for the web, so the
/// browser-only `dart:ui_web` / `package:web` code never reaches the VM test
/// runner (which gets [youtube_embed_stub.dart] instead).
class YoutubeEmbedView extends StatefulWidget {
  const YoutubeEmbedView({super.key, required this.embedUrl});

  final String embedUrl;

  @override
  State<YoutubeEmbedView> createState() => _YoutubeEmbedViewState();
}

class _YoutubeEmbedViewState extends State<YoutubeEmbedView> {
  static int _seq = 0;

  late final String _viewType;

  @override
  void initState() {
    super.initState();
    _viewType = 'mycosix-youtube-${_seq++}';
    ui_web.platformViewRegistry.registerViewFactory(_viewType, (int viewId) {
      return web.HTMLIFrameElement()
        ..src = widget.embedUrl
        ..style.width = '100%'
        ..style.height = '100%'
        ..style.border = 'none'
        ..allowFullscreen = true
        ..allow =
            'accelerometer; autoplay; clipboard-write; encrypted-media; '
            'gyroscope; picture-in-picture; web-share';
    });
  }

  @override
  Widget build(BuildContext context) {
    return HtmlElementView(viewType: _viewType);
  }
}

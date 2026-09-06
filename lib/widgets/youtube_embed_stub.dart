import 'package:flutter/material.dart';

/// Non-web stand-in for the YouTube player. On the VM test runner (and any
/// future non-web target) there is no browser iframe to host, so this renders
/// a quiet placeholder instead of crashing. The real browser implementation
/// lives in [youtube_embed_web.dart] and is only ever compiled for the web.
class YoutubeEmbedView extends StatelessWidget {
  const YoutubeEmbedView({super.key, required this.embedUrl});

  final String embedUrl;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(16),
      child: const Text(
        'Video playback is available on the website.',
        textAlign: TextAlign.center,
        style: TextStyle(color: Colors.white70),
      ),
    );
  }
}

import 'dart:convert';

import 'package:flutter/material.dart';

import '../config/mx_colors.dart';
import '../config/mx_type.dart';
import '../util/product_image.dart';

/// Product / editorial image with a graceful loading placeholder and error
/// state.
///
/// Accepts any source a product can carry:
///  * a bundled asset path (the marketing/editorial images and the seeded
///    catalogue),
///  * an inline `data:image/...` URL (a photo the admin uploaded onto the
///    product document itself - see `util/product_image.dart`), or
///  * a normal http(s) URL.
class MxImage extends StatelessWidget {
  const MxImage({
    super.key,
    required this.asset,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    this.borderRadius,
  });

  final String asset;
  final BoxFit fit;
  final double? width;
  final double? height;
  final BorderRadius? borderRadius;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: borderRadius ?? BorderRadius.zero,
      child: _image(),
    );
  }

  ImageProvider _provider() {
    if (isInlineImage(asset)) {
      final comma = asset.indexOf(',');
      final b64 = comma >= 0 ? asset.substring(comma + 1) : '';
      try {
        return MemoryImage(base64Decode(b64));
      } catch (_) {
        // Fall through to the asset path below so the error tile renders.
      }
    } else if (isHttpImage(asset)) {
      return NetworkImage(asset);
    }
    return AssetImage(asset);
  }

  Widget _image() {
    final image = Image(
      image: _provider(),
      fit: fit,
      width: width,
      height: height,
      gaplessPlayback: true,
      errorBuilder: (context, error, stack) {
        return _Fallback(borderRadius: borderRadius);
      },
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
        if (wasSynchronouslyLoaded || frame != null) return child;
        return _Loading(borderRadius: borderRadius);
      },
    );
    return image;
  }
}

class _Loading extends StatelessWidget {
  const _Loading({this.borderRadius});

  final BorderRadius? borderRadius;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: MxColors.creamDeep,
        borderRadius: borderRadius,
      ),
      child: const Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: MxColors.moss,
          ),
        ),
      ),
    );
  }
}

class _Fallback extends StatelessWidget {
  const _Fallback({this.borderRadius});

  final BorderRadius? borderRadius;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: MxColors.creamDeep,
        borderRadius: borderRadius,
      ),
      padding: const EdgeInsets.all(16),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.spa_outlined, size: 30, color: MxColors.moss),
            const SizedBox(height: 8),
            Text(
              'Image unavailable',
              style: MxType.bodyXs(color: MxColors.stone),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

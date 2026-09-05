import 'package:flutter/material.dart';

import '../config/mx_colors.dart';
import '../config/mx_type.dart';

/// Network/file image with a graceful loading placeholder and error state.
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
    final child = ClipRRect(
      borderRadius: borderRadius ?? BorderRadius.zero,
      child: Image.asset(
        asset,
        fit: fit,
        width: width,
        height: height,
        gaplessPlayback: true,
        errorBuilder: (context, error, stack) {
          return _Fallback(
            asset: asset,
            borderRadius: borderRadius,
          );
        },
        frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
          if (wasSynchronouslyLoaded || frame != null) return child;
          return _Loading(borderRadius: borderRadius);
        },
      ),
    );
    return child;
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
  const _Fallback({required this.asset, this.borderRadius});

  final String asset;
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

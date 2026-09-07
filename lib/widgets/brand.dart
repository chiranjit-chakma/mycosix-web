import 'package:flutter/material.dart';

import '../config/mx_colors.dart';

/// The MYCOSIX wordmark, marked with the real MYCOSIX brand seal (the same
/// cream-tile emblem used by the app icon and footer) instead of a generic
/// mushroom glyph.
class MxLogo extends StatelessWidget {
  const MxLogo({
    super.key,
    this.dark = false,
    this.size = 20,
    this.showFull = false,
  });

  final bool dark;
  final double size;
  final bool showFull;

  @override
  Widget build(BuildContext context) {
    final color = dark ? MxColors.cream : MxColors.forest;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Image.asset(
          'assets/brand/mycosix-tile.webp',
          width: size,
          height: size,
          fit: BoxFit.cover,
          filterQuality: FilterQuality.medium,
        ),
        SizedBox(width: size * 0.45),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'MYCOSIX',
              style: TextStyle(
                fontFamily: 'Fraunces',
                fontSize: size,
                height: 1,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.08,
                color: color,
              ),
            ),
            if (showFull) ...[
              const SizedBox(height: 2),
              Text(
                'MUSHROOMS',
                style: TextStyle(
                  fontFamily: 'Manrope',
                  fontSize: size * 0.42,
                  height: 1,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.44,
                  color: dark
                      ? MxColors.cream.withValues(alpha: 0.72)
                      : MxColors.earth,
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

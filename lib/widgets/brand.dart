import 'package:flutter/material.dart';

import '../config/mx_colors.dart';

/// The MYCOSIX wordmark. A plain brand lockup with no hidden gestures.
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
        _Mark(size: size * 0.9, dark: dark),
        SizedBox(width: size * 0.5),
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

/// A small mushroom-cap mark.
class _Mark extends StatelessWidget {
  const _Mark({required this.size, required this.dark});

  final double size;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(size, size),
      painter: _MarkPainter(dark: dark),
    );
  }
}

class _MarkPainter extends CustomPainter {
  _MarkPainter({required this.dark});

  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final cap = Paint()..color = dark ? MxColors.mossSoft : MxColors.moss;
    final rim = Paint()
      ..color = dark
          ? MxColors.mossSoft.withValues(alpha: 0.6)
          : MxColors.forest;
    final stem = Paint()..color = dark ? MxColors.mossSoft : MxColors.earth;

    // cap (fan)
    final capPath = Path()
      ..moveTo(s * 0.5, s * 0.14)
      ..quadraticBezierTo(s * 0.92, s * 0.2, s * 0.9, s * 0.56)
      ..quadraticBezierTo(s * 0.78, s * 0.5, s * 0.68, s * 0.54)
      ..quadraticBezierTo(s * 0.56, s * 0.62, s * 0.5, s * 0.62)
      ..quadraticBezierTo(s * 0.44, s * 0.62, s * 0.32, s * 0.54)
      ..quadraticBezierTo(s * 0.22, s * 0.5, s * 0.1, s * 0.56)
      ..quadraticBezierTo(s * 0.08, s * 0.2, s * 0.5, s * 0.14)
      ..close();
    canvas.drawPath(capPath, cap);
    canvas.drawPath(capPath, rim..style = PaintingStyle.stroke);

    // stem
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(s * 0.42, s * 0.56, s * 0.16, s * 0.34),
        Radius.circular(s * 0.08),
      ),
      stem,
    );
  }

  @override
  bool shouldRepaint(covariant _MarkPainter oldDelegate) =>
      oldDelegate.dark != dark;
}

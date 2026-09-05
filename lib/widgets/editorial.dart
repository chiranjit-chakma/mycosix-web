import 'package:flutter/material.dart';

import '../config/mx_colors.dart';
import '../config/mx_type.dart';
import 'mx_image.dart';
import 'page.dart';

/// Full-bleed page hero: an image with a dark editorial scrim and copy.
///
/// Height is fixed per breakpoint (never unbounded) so it scrolls safely
/// inside [MxShell]'s single scroll view.
class MxPageHero extends StatelessWidget {
  const MxPageHero({
    super.key,
    required this.overline,
    required this.title,
    required this.body,
    required this.image,
  });

  final String overline;
  final String title;
  final String body;
  final String image;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final desktop = width >= 1024;
    final height = (desktop ? 400.0 : 330.0).clamp(280.0, 480.0);

    return SizedBox(
      height: height + 30,
      child: Stack(
        fit: StackFit.expand,
        children: [
          MxImage(asset: image, fit: BoxFit.cover),
          // Scrim, strongest on the left where the copy sits.
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  MxColors.forest.withValues(alpha: 0.94),
                  MxColors.forest.withValues(alpha: 0.72),
                  MxColors.forest.withValues(alpha: 0.2),
                ],
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            child: MxPage(
              padding: const EdgeInsets.only(top: 132),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 30,
                        height: 1.5,
                        color: MxColors.mossSoft,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        overline.toUpperCase(),
                        style: MxType.overline(color: MxColors.mossSoft),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 720),
                    child: Text(
                      title,
                      style: MxType.h1(width, color: Colors.white),
                    ),
                  ),
                  const SizedBox(height: 14),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 620),
                    child: Text(
                      body,
                      style: MxType.body(
                        width,
                        color: Colors.white.withValues(alpha: 0.88),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Editorial two-column feature: large image beside kicker/title/body.
///
/// Stacks vertically below 900 px. Use [mediaFirst] to alternate the layout.
class MxFeature extends StatelessWidget {
  const MxFeature({
    super.key,
    required this.image,
    required this.overline,
    required this.title,
    required this.body,
    this.bodyExtra,
    this.mediaFirst = true,
    this.imageHeight = 380,
  });

  final String image;
  final String overline;
  final String title;
  final String body;
  final String? bodyExtra;
  final bool mediaFirst;
  final double imageHeight;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;

    final media = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(MxRadius.lg),
          child: MxImage(asset: image, fit: BoxFit.cover, height: imageHeight),
        ),
      ],
    );

    final copy = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(overline.toUpperCase(), style: MxType.overline()),
        const SizedBox(height: 14),
        Text(title, style: MxType.h1(width)),
        const SizedBox(height: 18),
        Text(body, style: MxType.body(width)),
        if (bodyExtra != null) ...[
          const SizedBox(height: 12),
          Text(bodyExtra!, style: MxType.body(width)),
        ],
      ],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 900) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [media, const SizedBox(height: 28), copy],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(flex: 5, child: mediaFirst ? media : copy),
            const SizedBox(width: 56),
            Expanded(flex: 6, child: mediaFirst ? copy : media),
          ],
        );
      },
    );
  }
}

/// A soft highlighted band with a heading and supporting text.
class MxBand extends StatelessWidget {
  const MxBand({
    super.key,
    required this.overline,
    required this.title,
    required this.body,
    this.tone = 'tint', // 'tint' | 'dark' | 'cream'
  });

  final String overline;
  final String title;
  final String body;
  final String tone;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isDark = tone == 'dark';
    final bg = isDark
        ? MxColors.forest
        : (tone == 'cream'
              ? MxColors.creamDeep.withValues(alpha: 0.5)
              : MxColors.mossTint);
    final overlineColor = isDark ? MxColors.mossSoft : MxColors.earth;
    final titleColor = isDark ? MxColors.cream : MxColors.charcoal;
    final bodyColor = isDark
        ? MxColors.cream.withValues(alpha: 0.8)
        : MxColors.charcoalSoft;

    return Container(
      color: bg,
      child: MxPage(
        padding: const EdgeInsets.symmetric(vertical: 72),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              overline.toUpperCase(),
              style: MxType.overline(color: overlineColor),
            ),
            const SizedBox(height: 14),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 820),
              child: Text(title, style: MxType.h1(width, color: titleColor)),
            ),
            const SizedBox(height: 16),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: Text(body, style: MxType.body(width, color: bodyColor)),
            ),
          ],
        ),
      ),
    );
  }
}

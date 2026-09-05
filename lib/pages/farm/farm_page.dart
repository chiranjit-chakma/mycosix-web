import 'package:flutter/material.dart';

import '../../config/mx_colors.dart';
import '../../config/mx_type.dart';
import '../../router/routes.dart';
import '../../widgets/editorial.dart';
import '../../widgets/mx_cta.dart';
import '../../widgets/mx_image.dart';
import '../../widgets/page.dart';
import '../../widgets/shell.dart';

class FarmPage extends StatelessWidget {
  const FarmPage({super.key});

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;

    return MxShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const MxPageHero(
            overline: 'Our Farm',
            title: 'Where the mushrooms grow',
            body:
                'A small, climate-tuned grow room where six students tend oyster '
                'mushrooms from spawn to harvest — every single week.',
            image: 'assets/images/shelf.jpg',
          ),
          MxPage(
            padding: const EdgeInsets.symmetric(vertical: 84),
            child: const MxFeature(
              mediaFirst: true,
              image: 'assets/images/moss_close.jpg',
              overline: 'The Grow Room',
              title: 'Indoors, on purpose',
              body:
                  'Oyster mushrooms do not need sunlight — they need the right '
                  'humidity, airflow and temperature. Our grow room gives them '
                  'exactly that, so we can grow consistently through the year, '
                  'stacked on shelves instead of fields.',
              bodyExtra:
                  'Because the room is enclosed and the substrate is pasteurised '
                  'before spawning, everything the mushrooms touch is kept clean '
                  'and controlled from start to finish.',
            ),
          ),
          const MxBand(
            overline: 'The Substrate',
            title: 'Straw and sawdust, given a second life',
            body:
                'We grow on agricultural waste — paddy straw and sawdust that '
                'would otherwise be burned. After two or three flushes the '
                'spent substrate leaves the room as rich compost, so nothing '
                'goes to waste.',
            tone: 'dark',
          ),
          MxPage(
            padding: const EdgeInsets.symmetric(vertical: 84),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('A WEEK AT THE FARM'.toUpperCase(), style: MxType.overline()),
                const SizedBox(height: 14),
                Text('Small daily rituals', style: MxType.h1(width)),
                const SizedBox(height: 18),
                Text(
                  'Mushroom farming is mostly patience. The work is quiet, '
                  'repetitive and honest.',
                  style: MxType.body(width),
                ),
                const SizedBox(height: 36),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final desktop = constraints.maxWidth >= 900;
                    final cards = <Widget>[
                      _FarmStep(
                        icon: Icons.water_drop_outlined,
                        title: 'Mist & fresh air',
                        body:
                            'The room is misted and ventilated several times a '
                            'day to keep humidity high and carbon dioxide low.',
                      ),
                      _FarmStep(
                        icon: Icons.visibility_outlined,
                        title: 'Watch & adjust',
                        body:
                            'We check each shelf daily, watching for pinning and '
                            'catching any issue before it spreads.',
                      ),
                      _FarmStep(
                        icon: Icons.front_hand_outlined,
                        title: 'Hand-pick at peak',
                        body:
                            'Clusters are picked by hand at their freshest, '
                            'trimmed and packed the same day.',
                      ),
                    ];
                    return desktop
                        ? Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              for (var i = 0; i < cards.length; i++) ...[
                                Expanded(child: cards[i]),
                                if (i < cards.length - 1)
                                  const SizedBox(width: 20),
                              ],
                            ],
                          )
                        : Column(
                            children: [
                              for (final c in cards) ...[
                                c,
                                const SizedBox(height: 16),
                              ],
                            ],
                          );
                  },
                ),
              ],
            ),
          ),
          // Photo strip.
          MxPage(
            padding: const EdgeInsets.only(bottom: 84),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final desktop = constraints.maxWidth >= 900;
                final imgs = [
                  'assets/images/moss_close.jpg',
                  'assets/images/harvest_hands.jpg',
                  'assets/images/packaging.jpg',
                ];
                final children = <Widget>[
                  for (final a in imgs)
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(MxRadius.lg),
                        child: MxImage(
                          asset: a,
                          fit: BoxFit.cover,
                          height: desktop ? 280 : 200,
                        ),
                      ),
                    ),
                ];
                return desktop
                    ? Row(
                        children: [
                          for (var i = 0; i < children.length; i++) ...[
                            children[i],
                            if (i < children.length - 1)
                              const SizedBox(width: 18),
                          ],
                        ],
                      )
                    : Column(
                        children: [
                          for (var i = 0; i < children.length; i++) ...[
                            children[i],
                            if (i < children.length - 1)
                              const SizedBox(height: 14),
                          ],
                        ],
                      );
              },
            ),
          ),
          // CTA band.
          MxPage(
            padding: const EdgeInsets.only(bottom: 84),
            child: Container(
              padding: EdgeInsets.all(width >= 768 ? 48 : 28),
              decoration: BoxDecoration(
                color: MxColors.moss,
                borderRadius: BorderRadius.circular(MxRadius.xl),
              ),
              child: Column(
                children: [
                  Text(
                    'Taste what the room grows',
                    textAlign: TextAlign.center,
                    style: MxType.h1(width, color: Colors.white),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Fresh harvests go into the shop each week. Order yours '
                    'before it is gone.',
                    textAlign: TextAlign.center,
                    style: MxType.body(width, color: Colors.white.withValues(alpha: 0.85)),
                  ),
                  const SizedBox(height: 26),
                  MxCta(
                    label: 'Shop Fresh Mushrooms',
                    tone: 'light',
                    icon: Icons.shopping_bag_outlined,
                    onTap: () => Navigator.of(context).pushNamed(Routes.shop),
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

class _FarmStep extends StatelessWidget {
  const _FarmStep({required this.icon, required this.title, required this.body});

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: MxColors.creamSoft,
        borderRadius: BorderRadius.circular(MxRadius.lg),
        border: Border.all(color: MxColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 22, color: MxColors.moss),
          const SizedBox(height: 14),
          Text(title, style: MxType.h4(color: MxColors.charcoal)),
          const SizedBox(height: 8),
          Text(body, style: MxType.bodySm(color: MxColors.charcoalSoft)),
        ],
      ),
    );
  }
}
